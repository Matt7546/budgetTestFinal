const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const express = require("express");
const { createJsonPlaidItemStore } = require("../jsonPlaidItemStore");
const { createAuthMiddleware } = require("../authMiddleware");
const {
  exchangePublicTokenForUser,
  createExchangePublicTokenHandler, createDisconnectHandler,
  createDeleteAccountHandler,
} = require("../itemLifecycleRoutes");

function barrier() {
  let release;
  let reached;
  const waiting = new Promise((resolve) => { release = resolve; });
  const entered = new Promise((resolve) => { reached = resolve; });
  return { waiting, entered, release, reached };
}

async function run() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "caldera-item-race-"));
  const storePath = path.join(directory, "items.json");
  const store = createJsonPlaidItemStore({ tokenStorePath: storePath });
  const otherStore = createJsonPlaidItemStore({ tokenStorePath: storePath });
  const sessions = new Map([["session-a", "owner-a"], ["session-b", "owner-b"]]);
  const sessionStore = {
    async getSessionByToken(token) {
      const id = sessions.get(token);
      return id ? { user: { id }, session: { id: token } } : null;
    },
    async finalizeAccountDeletion(userId) {
      let count = 0;
      for (const [token, owner] of sessions) {
        if (owner === userId) { sessions.delete(token); count += 1; }
      }
      return { userDeleted: true, sessionsRevoked: count };
    },
  };
  const auth = createAuthMiddleware({ authMode: "required",
    personalUserID: "unused", sessionStore });
  const exchangeBarrier = barrier();
  const removalBarrier = barrier();
  let waitForExchange = false;
  let waitForRemoval = false;
  const calls = { exchange: [], remove: [] };
  let removalFails = false;
  const client = {
    async itemPublicTokenExchange({ public_token }) {
      calls.exchange.push(public_token);
      if (waitForExchange) {
        exchangeBarrier.reached();
        await exchangeBarrier.waiting;
      }
      return { data: { access_token: `access-${public_token}`,
        item_id: `item-${public_token}` } };
    },
    async itemRemove({ access_token }) {
      calls.remove.push(access_token);
      if (waitForRemoval) {
        removalBarrier.reached();
        await removalBarrier.waiting;
      }
      if (removalFails) throw new Error("intercepted provider failure");
      return { data: { request_id: `remove-${access_token}` } };
    },
  };
  const app = express();
  app.use(express.json());
  const apiKey = (req, res, next) => req.get("x-app-api-key") === "test-key"
    ? next() : res.sendStatus(401);
  app.post("/api/exchange_public_token", apiKey, auth.resolvePlaidAuth,
    createExchangePublicTokenHandler({ getRequestUserID: auth.getRequestUserID,
      plaidItemStore: store, plaidClient: client }));
  app.post("/api/disconnect", apiKey, auth.resolvePlaidAuth,
    createDisconnectHandler({ getRequestUserID: auth.getRequestUserID,
      plaidItemStore: store, plaidClient: client }));
  app.delete("/api/account", apiKey, auth.requireSessionAuth,
    createDeleteAccountHandler({ sessionStore, plaidItemStore: store,
      plaidClient: client }));
  const server = app.listen(0, "127.0.0.1");
  await new Promise((resolve) => server.once("listening", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  async function request(route, token = "session-a", method = "POST", body = {}) {
    const response = await fetch(`${base}${route}`, { method,
      headers: { "x-app-api-key": "test-key", authorization: `Bearer ${token}`,
        "content-type": "application/json" },
      body: method === "DELETE" ? undefined : JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  }
  const link = (name, token = "session-a") => request(
    "/api/exchange_public_token", token, "POST", { public_token: name });
  const disconnect = () => request("/api/disconnect");
  const deletion = () => request("/api/account", "session-a", "DELETE");

  try {
    // Healthy links and another owner remain independent.
    const healthyLink = await link("a1");
    assert.equal(healthyLink.status, 200);
    assert.deepEqual(healthyLink.body, { success: true, item_id: "item-a1",
      linked_items: 1 });
    assert.equal((await link("b1", "session-b")).status, 200);
    assert.deepEqual((await otherStore.getUserItems("owner-a"))
      .map((item) => item.itemId), ["item-a1"]);

    // Link completed before removal starts: it belongs to the snapshot.
    assert.equal((await link("a2")).status, 200);
    assert.equal((await disconnect()).body.removed_items, 2);
    assert.equal((await otherStore.getUserItems("owner-a")).length, 0);

    // Provider removal is suspended: no new exchange may reach Plaid.
    assert.equal((await link("a3")).status, 200);
    waitForRemoval = true;
    const pendingDisconnect = disconnect();
    await removalBarrier.entered;
    const previousExchanges = calls.exchange.length;
    assert.equal((await link("blocked")).status, 500);
    assert.equal(calls.exchange.length, previousExchanges);
    await assert.rejects(store.saveUserItem("owner-a",
      { itemId: "direct-bypass", accessToken: "direct-bypass-token" }),
    /item_lifecycle_unavailable/);
    assert.equal((await otherStore.getUserItems("owner-a")).length, 1);
    removalBarrier.release();
    assert.equal((await pendingDisconnect).body.success, true);
    waitForRemoval = false;
    assert.equal((await otherStore.getUserItems("owner-a")).length, 0);

    // An authenticated exchange already waiting on Plaid blocks deletion;
    // neither deletion nor provider removal may claim completion.
    waitForExchange = true;
    const pendingLink = link("late");
    await exchangeBarrier.entered;
    const blockedDeletion = await deletion();
    assert.equal(blockedDeletion.body.success, false);
    assert.equal(blockedDeletion.status, 500);
    assert.equal(sessions.has("session-a"), true);
    exchangeBarrier.release();
    assert.equal((await pendingLink).body.success, true);
    waitForExchange = false;
    assert.equal((await deletion()).body.success, true);
    assert.equal((await link("after-delete")).status, 401);
    assert.equal((await otherStore.getUserItems("owner-a")).length, 0);
    assert.equal((await otherStore.getUserItems("owner-b"))[0].itemId, "item-b1");
    assert.equal(sessions.has("session-b"), true);
    await otherStore.removeAllUserItems("owner-a");
    await otherStore.ensureUser("owner-a");
    await assert.rejects(otherStore.saveUserItem("owner-a",
      { itemId: "resurrect", accessToken: "resurrect-token" }),
    /item_lifecycle_unavailable/);

    // Exact compare cannot remove a replacement record after a stale result.
    const before = (await otherStore.getUserItems("owner-b"))[0];
    await otherStore.saveUserItem("owner-b", { itemId: before.itemId,
      accessToken: "replacement-token" });
    assert.equal(await otherStore.removeUserItemIfMatching("owner-b", before), false);
    assert.equal((await otherStore.getUserItems("owner-b"))[0].accessToken,
      "replacement-token");
    removalFails = true;
    const failedRemoval = await request("/api/disconnect", "session-b");
    assert.equal(failedRemoval.status, 502);
    assert.equal(failedRemoval.body.success, false);
    assert.equal((await otherStore.getUserItems("owner-b"))[0].accessToken,
      "replacement-token");
    removalFails = false;
    assert.equal((await request("/api/disconnect", "session-b")).body.success,
      true);
    const repeated = await request("/api/disconnect", "session-b");
    assert.equal(repeated.body.success, true);
    assert.equal(repeated.body.removed_items, 0);
    assert.equal((await link("b2", "session-b")).status, 200);
    const originalExactRemoval = store.removeUserItemIfMatching;
    store.removeUserItemIfMatching = async () => {
      throw new Error("intercepted store write failure");
    };
    const failedStoreRemoval = await request("/api/disconnect", "session-b");
    assert.equal(failedStoreRemoval.status, 502);
    assert.equal(failedStoreRemoval.body.failed_items, 1);
    assert.equal((await otherStore.getUserItems("owner-b"))[0].itemId, "item-b2");
    store.removeUserItemIfMatching = originalExactRemoval;

    // A rejected post-exchange save with uncertain provider cleanup retains
    // the exact token in owner-scoped persisted recovery storage.
    const freshStore = createJsonPlaidItemStore({
      tokenStorePath: path.join(directory, "recovery.json") });
    const originalSave = freshStore.saveUserItem;
    freshStore.saveUserItem = async () => { throw new Error("intercepted store failure"); };
    removalFails = true;
    sessions.set("session-recovery", "recovery-owner");
    const recoveryApp = express();
    recoveryApp.use(express.json());
    recoveryApp.post("/link", createExchangePublicTokenHandler({
      getRequestUserID: () => "recovery-owner", plaidItemStore: freshStore,
      plaidClient: client }));
    recoveryApp.delete("/account", apiKey, auth.requireSessionAuth,
      createDeleteAccountHandler({ sessionStore, plaidItemStore: freshStore,
        plaidClient: client }));
    const recoveryServer = recoveryApp.listen(0, "127.0.0.1");
    await new Promise((resolve) => recoveryServer.once("listening", resolve));
    try {
      const response = await fetch(
        `http://127.0.0.1:${recoveryServer.address().port}/link`, {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ public_token: "orphan" }),
        });
      assert.equal(response.status, 500);
      const reopened = createJsonPlaidItemStore({
        tokenStorePath: path.join(directory, "recovery.json") });
      assert.equal((await reopened.getRemovalRecoveries("recovery-owner"))[0]
        .accessToken, "access-orphan");
      assert.equal(fs.readFileSync(path.join(directory, "recovery.json"), "utf8")
        .includes("access-orphan"), false);
      const recoveryKeyPath = path.join(directory, "recovery.json.recovery-key");
      fs.renameSync(recoveryKeyPath, `${recoveryKeyPath}.held`);
      await assert.rejects(reopened.getRemovalRecoveries("recovery-owner"),
        /key is missing/);
      await assert.rejects(reopened.beginItemExchange("recovery-owner",
        { publicToken: "must-not-dispatch" }), /key is missing/);
      await assert.rejects(reopened.recordRemovalRecovery("recovery-owner",
        { itemId: "another", accessToken: "another-token" }), /key is missing/);
      fs.renameSync(`${recoveryKeyPath}.held`, recoveryKeyPath);
      assert.equal((await reopened.getRemovalRecoveries("recovery-owner"))
        .length, 1);
      assert.deepEqual(await reopened.getItemLifecycleObligations("recovery-owner"),
        { pendingExchanges: 0, removalRecoveries: 1 });
      await assert.rejects(reopened.beginItemRemoval("recovery-owner", "deleting"));
      const blockedRecoveryDeletion = await fetch(
        `http://127.0.0.1:${recoveryServer.address().port}/account`, {
          method: "DELETE", headers: { "x-app-api-key": "test-key",
            authorization: "Bearer session-recovery" },
        });
      assert.equal((await blockedRecoveryDeletion.json()).success, false);
      assert.equal(sessions.has("session-recovery"), true);
      freshStore.saveUserItem = originalSave;
    } finally { recoveryServer.close(); }

    // A functioning lifecycle store must retain its fence if BOTH recovery
    // persistence and provider compensation fail after exchange succeeds.
    const doublePath = path.join(directory, "double-failure.json");
    const doubleStore = createJsonPlaidItemStore({ tokenStorePath: doublePath });
    doubleStore.saveUserItem = async () => { throw new Error("save failed"); };
    doubleStore.recordRemovalRecovery = async () => {
      throw new Error("recovery write failed");
    };
    sessions.set("session-double", "owner-double");
    const doubleApp = express();
    doubleApp.use(express.json());
    doubleApp.post("/link", apiKey, auth.resolvePlaidAuth,
      createExchangePublicTokenHandler({
        getRequestUserID: auth.getRequestUserID,
        plaidItemStore: doubleStore, plaidClient: client,
      }));
    doubleApp.delete("/account", apiKey, auth.requireSessionAuth,
      createDeleteAccountHandler({ sessionStore, plaidItemStore: doubleStore,
        plaidClient: client }));
    const doubleServer = doubleApp.listen(0, "127.0.0.1");
    await new Promise((resolve) => doubleServer.once("listening", resolve));
    try {
      const doubleBase = `http://127.0.0.1:${doubleServer.address().port}`;
      const headers = { "x-app-api-key": "test-key",
        authorization: "Bearer session-double", "content-type": "application/json" };
      const exchange = await fetch(`${doubleBase}/link`, { method: "POST",
        headers, body: JSON.stringify({ public_token: "double" }) });
      assert.equal(exchange.status, 500);
      const deletionResponse = await fetch(`${doubleBase}/account`, {
        method: "DELETE", headers });
      const deletionBody = await deletionResponse.json();
      assert.equal(deletionBody.success, false,
        "double failure must not authorize completed account deletion");
      assert.equal(sessions.has("session-double"), true);
      const reopenedDouble = createJsonPlaidItemStore({ tokenStorePath: doublePath });
      assert.equal((await reopenedDouble.getItemLifecycleObligations("owner-double"))
        .pendingExchanges, 1);
      const [pending] = await reopenedDouble.getItemExchangeLeases("owner-double");
      assert.equal(pending.state, "result_recorded");
      assert.equal(pending.itemId, "item-double");
      assert.equal(pending.accessToken, "access-double");
      assert.equal(fs.readFileSync(doublePath, "utf8").includes("access-double"), false);
      const exactItem = { itemId: pending.itemId, accessToken: pending.accessToken };
      await assert.rejects(reopenedDouble.finishItemExchange("other-owner", pending,
        { kind: "removed", item: exactItem }),
      /item_exchange_lease_changed/);
      await assert.rejects(reopenedDouble.finishItemExchange("owner-double",
        { ...pending, generation: pending.generation + 1 },
        { kind: "removed", item: exactItem }),
      /item_exchange_lease_changed/);
      await assert.rejects(reopenedDouble.finishItemExchange("owner-double", pending,
        { kind: "removed", item: exactItem }),
      /item_exchange_resolution_unverified/);
      assert.equal((await reopenedDouble.getItemLifecycleObligations("owner-double"))
        .pendingExchanges, 1);
      removalFails = false;
      const removal = await client.itemRemove({ access_token: pending.accessToken });
      await reopenedDouble.markItemExchangeRemovalConfirmed("owner-double", pending,
        exactItem, removal.data.request_id);
      const [confirmed] = await reopenedDouble.getItemExchangeLeases("owner-double");
      assert.equal(confirmed.state, "removal_confirmed");
      assert.equal(confirmed.removalRequestId, removal.data.request_id);
      await reopenedDouble.finishItemExchange("owner-double", pending,
        { kind: "removed", item: exactItem });
      await assert.rejects(reopenedDouble.finishItemExchange("owner-double", pending,
        { kind: "removed", item: exactItem }),
      /item_exchange_lease_changed/);
      assert.equal((await reopenedDouble.getItemLifecycleObligations("owner-double"))
        .pendingExchanges, 0);
      assert.equal((await reopenedDouble.beginItemRemoval("owner-double", "deleting")),
        pending.generation + 1);
    } finally { doubleServer.close(); }

    // A prepared lease and a dispatched request with no durable provider
    // response are distinct after reopening; neither permits deletion.
    const interruptedPath = path.join(directory, "interrupted.json");
    const interrupted = createJsonPlaidItemStore({ tokenStorePath: interruptedPath });
    const prepared = await interrupted.beginItemExchange("interrupted-owner",
      { publicToken: "ephemeral-public", linkSessionId: "link-interrupted" });
    const reopenedInterrupted = createJsonPlaidItemStore({
      tokenStorePath: interruptedPath });
    assert.equal((await reopenedInterrupted.getItemExchangeLeases(
      "interrupted-owner"))[0].state, "prepared");
    await reopenedInterrupted.markItemExchangeDispatched("interrupted-owner", prepared);
    const [unknown] = await interrupted.getItemExchangeLeases("interrupted-owner");
    assert.equal(unknown.state, "dispatch_uncertain");
    assert.equal(unknown.linkSessionId, "link-interrupted");
    assert.equal(unknown.accessToken, null);
    assert.equal(fs.readFileSync(interruptedPath, "utf8")
      .includes("ephemeral-public"), false);
    await assert.rejects(interrupted.beginItemRemoval(
      "interrupted-owner", "deleting"), /item_lifecycle_busy/);

    // A resolved transport call with an invalid removal body is still
    // uncertain; it cannot stand in for Plaid's documented request ID.
    const malformedPath = path.join(directory, "malformed-removal.json");
    const malformedStore = createJsonPlaidItemStore({ tokenStorePath: malformedPath });
    malformedStore.saveUserItem = async () => { throw new Error("save failed"); };
    malformedStore.recordRemovalRecovery = async () => {
      throw new Error("recovery write failed");
    };
    await assert.rejects(exchangePublicTokenForUser({ userId: "malformed-owner",
      publicToken: "malformed-public", plaidItemStore: malformedStore,
      plaidClient: { itemPublicTokenExchange: client.itemPublicTokenExchange,
        itemRemove: async () => ({ data: {} }) } }),
    /Exchange cleanup and recovery persistence failed/);
    assert.equal((await createJsonPlaidItemStore({ tokenStorePath: malformedPath })
      .getItemLifecycleObligations("malformed-owner")).pendingExchanges, 1);

    // If the result write fails but the exact recovery record succeeds, a
    // confirmed provider removal can durably adopt that encrypted token and
    // request ID before both obligations are cleared.
    const fallbackPath = path.join(directory, "result-write-failure.json");
    const fallbackStore = createJsonPlaidItemStore({ tokenStorePath: fallbackPath });
    fallbackStore.recordItemExchangeResult = async () => {
      throw new Error("result write failed");
    };
    fallbackStore.saveUserItem = async () => { throw new Error("save failed"); };
    await assert.rejects(exchangePublicTokenForUser({ userId: "fallback-owner",
      publicToken: "fallback-public", plaidItemStore: fallbackStore,
      plaidClient: client }), /Exchanged Item was not saved/);
    const reopenedFallback = createJsonPlaidItemStore({
      tokenStorePath: fallbackPath });
    assert.deepEqual(await reopenedFallback.getItemLifecycleObligations(
      "fallback-owner"), { pendingExchanges: 0, removalRecoveries: 0 });
    assert.equal(fs.readFileSync(fallbackPath, "utf8")
      .includes("access-fallback-public"), false);

    // A saved Item is still safe if local lease acknowledgment fails. The
    // provider must not be removed as compensation for an already saved Item.
    const ackPath = path.join(directory, "ack-failure.json");
    const ackStore = createJsonPlaidItemStore({ tokenStorePath: ackPath });
    const originalFinish = ackStore.finishItemExchange;
    ackStore.finishItemExchange = async () => { throw new Error("ack failed"); };
    const removesBeforeAck = calls.remove.length;
    const ackApp = express();
    ackApp.use(express.json());
    ackApp.post("/link", createExchangePublicTokenHandler({
      getRequestUserID: () => "ack-owner", plaidItemStore: ackStore,
      plaidClient: client }));
    const ackServer = ackApp.listen(0, "127.0.0.1");
    await new Promise((resolve) => ackServer.once("listening", resolve));
    try {
      const response = await fetch(
        `http://127.0.0.1:${ackServer.address().port}/link`, {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ public_token: "ack",
            link_session_id: "link-session-ack" }),
        });
      assert.equal(response.status, 500);
      assert.equal(calls.remove.length, removesBeforeAck);
      const reopenedAck = createJsonPlaidItemStore({ tokenStorePath: ackPath });
      const [saved] = await reopenedAck.getUserItems("ack-owner");
      const [ackLease] = await reopenedAck.getItemExchangeLeases("ack-owner");
      assert.equal(ackLease.linkSessionId, "link-session-ack");
      assert.equal(ackLease.state, "item_saved");
      await reopenedAck.finishItemExchange("ack-owner", ackLease,
        { kind: "saved", item: saved });
      assert.equal((await reopenedAck.getItemLifecycleObligations("ack-owner"))
        .pendingExchanges, 0);
    } finally { ackServer.close(); ackStore.finishItemExchange = originalFinish; }

    // The real Item write succeeds, but a later acknowledgment fails. The
    // handler must classify the durable save, not compensate it away.
    const committedPath = path.join(directory, "post-commit.json");
    const committedStore = createJsonPlaidItemStore({ tokenStorePath: committedPath });
    const committedSave = committedStore.saveUserItem;
    committedStore.saveUserItem = async (...args) => {
      await committedSave(...args);
      throw new Error("post-commit response failed");
    };
    const committedApp = express();
    committedApp.use(express.json());
    committedApp.post("/link", createExchangePublicTokenHandler({
      getRequestUserID: () => "committed-owner", plaidItemStore: committedStore,
      plaidClient: client }));
    const committedServer = committedApp.listen(0, "127.0.0.1");
    await new Promise((resolve) => committedServer.once("listening", resolve));
    try {
      const removesBeforeCommit = calls.remove.length;
      const response = await fetch(
        `http://127.0.0.1:${committedServer.address().port}/link`, {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ public_token: "committed" }),
        });
      assert.equal(response.status, 200,
        "post-commit response failure must not remove a saved Item");
      assert.equal((await response.json()).linked_items, 1);
      assert.equal(calls.remove.length, removesBeforeCommit);
      const reopenedCommitted = createJsonPlaidItemStore({
        tokenStorePath: committedPath });
      const [item] = await reopenedCommitted.getUserItems("committed-owner");
      assert.equal(item.itemId, "item-committed");
      assert.equal(item.accessToken, "access-committed");
      assert.deepEqual(await reopenedCommitted.getItemLifecycleObligations(
        "committed-owner"), { pendingExchanges: 0, removalRecoveries: 0 });
    } finally { committedServer.close(); }

    // A committed save whose verification read fails must retain its lease,
    // preserve the Item, and block the authenticated deletion route.
    const unknownPath = path.join(directory, "verification-failure.json");
    const unknownStore = createJsonPlaidItemStore({ tokenStorePath: unknownPath });
    const unknownSave = unknownStore.saveUserItem;
    unknownStore.saveUserItem = async (...args) => {
      await unknownSave(...args);
      throw new Error("post-commit response failed");
    };
    unknownStore.inspectItemExchangeSave = async () => {
      throw new Error("verification unavailable");
    };
    sessions.set("session-unknown", "unknown-owner");
    const unknownApp = express();
    unknownApp.use(express.json());
    unknownApp.post("/link", apiKey, auth.resolvePlaidAuth,
      createExchangePublicTokenHandler({ getRequestUserID: auth.getRequestUserID,
        plaidItemStore: unknownStore, plaidClient: client }));
    unknownApp.delete("/account", apiKey, auth.requireSessionAuth,
      createDeleteAccountHandler({ sessionStore, plaidItemStore: unknownStore,
        plaidClient: client }));
    const unknownServer = unknownApp.listen(0, "127.0.0.1");
    await new Promise((resolve) => unknownServer.once("listening", resolve));
    try {
      const unknownBase = `http://127.0.0.1:${unknownServer.address().port}`;
      const headers = { "x-app-api-key": "test-key",
        authorization: "Bearer session-unknown", "content-type": "application/json" };
      const removesBeforeUnknown = calls.remove.length;
      const response = await fetch(`${unknownBase}/link`, { method: "POST",
        headers, body: JSON.stringify({ public_token: "unknown" }) });
      assert.equal(response.status, 500);
      assert.equal(calls.remove.length, removesBeforeUnknown);
      const reopenedUnknown = createJsonPlaidItemStore({ tokenStorePath: unknownPath });
      assert.equal((await reopenedUnknown.getUserItems("unknown-owner"))[0]
        .accessToken, "access-unknown");
      assert.equal((await reopenedUnknown.getItemExchangeLeases("unknown-owner"))[0]
        .state, "item_saved");
      assert.equal((await reopenedUnknown.getItemLifecycleObligations("unknown-owner"))
        .pendingExchanges, 1);
      const deletionResponse = await fetch(`${unknownBase}/account`, {
        method: "DELETE", headers });
      assert.equal((await deletionResponse.json()).success, false);
      assert.equal(sessions.has("session-unknown"), true);
    } finally { unknownServer.close(); }

    // An unrelated row with the same provider identity is not proof that
    // this lease saved it. A conflicting token is likewise indeterminate.
    for (const [label, existingToken] of [
      ["unrelated", "access-unrelated"], ["conflict", "different-token"],
    ]) {
      const pathForCase = path.join(directory, `${label}-identity.json`);
      const identityStore = createJsonPlaidItemStore({ tokenStorePath: pathForCase });
      await identityStore.saveUserItem(`${label}-owner`, {
        itemId: `item-${label}`, accessToken: existingToken });
      identityStore.saveUserItem = async () => { throw new Error("pre-commit failure"); };
      const removesBeforeIdentity = calls.remove.length;
      await assert.rejects(exchangePublicTokenForUser({
        userId: `${label}-owner`, publicToken: label,
        plaidItemStore: identityStore, plaidClient: client,
      }), /save outcome is uncertain/);
      assert.equal(calls.remove.length, removesBeforeIdentity);
      const reopenedIdentity = createJsonPlaidItemStore({
        tokenStorePath: pathForCase });
      assert.equal((await reopenedIdentity.getUserItems(`${label}-owner`))[0]
        .accessToken, existingToken);
      assert.equal((await reopenedIdentity.getItemLifecycleObligations(
        `${label}-owner`)).pendingExchanges, 1);
      await assert.rejects(reopenedIdentity.beginItemRemoval(
        `${label}-owner`, "deleting"), /item_lifecycle_busy/);
    }

    // A definite pre-commit failure retains the existing compensation path.
    const beforePath = path.join(directory, "before-commit.json");
    const beforeStore = createJsonPlaidItemStore({ tokenStorePath: beforePath });
    beforeStore.saveUserItem = async () => { throw new Error("pre-commit failure"); };
    const removesBeforeFailure = calls.remove.length;
    await assert.rejects(exchangePublicTokenForUser({ userId: "before-owner",
      publicToken: "before", plaidItemStore: beforeStore, plaidClient: client }),
    /Exchanged Item was not saved/);
    assert.equal(calls.remove.length, removesBeforeFailure + 1);
    const reopenedBefore = createJsonPlaidItemStore({ tokenStorePath: beforePath });
    assert.equal((await reopenedBefore.getUserItems("before-owner")).length, 0);
    assert.deepEqual(await reopenedBefore.getItemLifecycleObligations("before-owner"),
      { pendingExchanges: 0, removalRecoveries: 0 });
    console.log("Item lifecycle Express/JSON race check passed.");
  } finally {
    server.close();
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

run().catch((error) => {
  console.error(`Item lifecycle race check failed: ${error.message}`);
  process.exit(1);
});
