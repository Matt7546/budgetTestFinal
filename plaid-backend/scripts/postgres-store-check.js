const assert = require("node:assert/strict");
const crypto = require("crypto");
const express = require("express");
const { createAuthMiddleware } = require("../authMiddleware");
const { exchangePublicTokenForUser, createExchangePublicTokenHandler,
  createDeleteAccountHandler } = require("../itemLifecycleRoutes");
const {
  requireDisposableTarget,
  assertDisposableTarget,
} = require("./postgres-test-target");

async function run() {
  // This preflight must complete before opening a connection or running schema SQL.
  const target = requireDisposableTarget();
  const { createPool } = require("../db");
  const { createPostgresPlaidItemStore } = require("../postgresPlaidItemStore");
  const { createSessionStore } = require("../sessionStore");
  const pool = createPool(target.databaseUrl);
  let store;
  let schemaAttempted = false;

  const suffix = crypto.randomBytes(6).toString("hex");
  const userA = `check-user-a-${suffix}`;
  const userB = `check-user-b-${suffix}`;

  try {
    // Read-only server identity and empty-database checks precede all writes.
    await assertDisposableTarget(pool, target);
    store = createPostgresPlaidItemStore({
      pool,
      databaseUrl: target.databaseUrl,
      tokenEncryptionKey: process.env.TOKEN_ENCRYPTION_KEY,
    });
    schemaAttempted = true;
    await store.ensureSchema();
    const authStore = createSessionStore({ pool });
    await authStore.ensureSchema();

    await store.saveUserItem(userA, {
      accessToken: "token-a1",
      itemId: "item-a1",
      institutionName: "Institution A",
    });

    await store.saveUserItem(userB, {
      accessToken: "token-b1",
      itemId: "item-b1",
      institutionName: "Institution B",
    });

    assert.deepEqual(
      (await store.getUserItems(userA)).map((item) => item.itemId),
      ["item-a1"]
    );
    assert.deepEqual(
      (await store.getUserItems(userB)).map((item) => item.itemId),
      ["item-b1"]
    );

    await store.saveUserItem(userA, {
      accessToken: "token-a1-updated",
      itemId: "item-a1",
      institutionName: "Institution A Updated",
    });

    assert.equal(await store.getUserItemCount(userA), 1);
    assert.equal((await store.getUserItems(userA))[0].accessToken, "token-a1-updated");
    assert.equal(await store.getUserItemCount(userB), 1);

    // A second store instance represents a separate database writer. The
    // owner row lock and persisted lease/state govern both instances.
    const otherWriter = createPostgresPlaidItemStore({ pool,
      tokenEncryptionKey: process.env.TOKEN_ENCRYPTION_KEY });
    const raceUser = `race-user-${suffix}`;
    const lease = await store.beginItemExchange(raceUser,
      { publicToken: "race-public-token", linkSessionId: "race-link-session" });
    assert.equal((await otherWriter.getItemExchangeLeases(raceUser))[0].state,
      "prepared");
    await assert.rejects(otherWriter.beginItemRemoval(raceUser, "deleting"),
      /item_lifecycle_busy/);
    await store.markItemExchangeDispatched(raceUser, lease);
    const [dispatched] = await otherWriter.getItemExchangeLeases(raceUser);
    assert.equal(dispatched.state, "dispatch_uncertain");
    assert.equal(dispatched.linkSessionId, "race-link-session");
    assert.equal(dispatched.accessToken, null);
    await store.recordItemExchangeResult(raceUser, lease,
      { itemId: "race-item", accessToken: "race-token" }, "request-race");
    await store.saveUserItem(raceUser,
      { itemId: "race-item", accessToken: "race-token" }, lease);
    await store.finishItemExchange(raceUser, lease,
      { kind: "saved", item: { itemId: "race-item", accessToken: "race-token" } });
    const generation = await otherWriter.beginItemRemoval(raceUser, "disconnecting");
    await assert.rejects(store.beginItemExchange(raceUser),
      /item_lifecycle_unavailable/);
    await assert.rejects(store.saveUserItem(raceUser,
      { itemId: "blocked", accessToken: "blocked-token" }),
      /item_lifecycle_unavailable/);
    const exactSnapshot = (await store.getUserItems(raceUser))[0];
    assert.equal(await otherWriter.removeUserItemIfMatching(raceUser,
      exactSnapshot), true);
    await otherWriter.finishItemRemoval(raceUser, generation, "disconnecting");
    await store.saveUserItem(raceUser,
      { itemId: "race-item", accessToken: "replacement-token" });
    assert.equal(await otherWriter.removeUserItemIfMatching(raceUser,
      exactSnapshot), false);
    assert.equal((await store.getUserItems(raceUser))[0].accessToken,
      "replacement-token");

    const recoveryId = await store.recordRemovalRecovery(raceUser,
      { itemId: "orphan", accessToken: "orphan-secret-token" });
    const encrypted = await pool.query(
      `SELECT encrypted_access_token FROM plaid_item_removal_recoveries
        WHERE id = $1`, [recoveryId]);
    assert.notEqual(encrypted.rows[0].encrypted_access_token,
      "orphan-secret-token");
    assert.equal((await otherWriter.getRemovalRecoveries(raceUser))[0]
      .accessToken, "orphan-secret-token");
    await assert.rejects(otherWriter.beginItemRemoval(raceUser, "deleting"),
      /item_lifecycle_busy/);
    await store.clearRemovalRecovery(raceUser, recoveryId);

    const deleteGeneration = await otherWriter.beginItemRemoval(
      raceUser, "deleting");
    await otherWriter.removeUserItemIfMatching(raceUser,
      (await store.getUserItems(raceUser))[0]);
    const finalization = await authStore.finalizeAccountDeletion(raceUser);
    assert.equal(finalization.userDeleted, true);
    await otherWriter.finishItemRemoval(raceUser, deleteGeneration,
      "deleting", true);
    await store.ensureUser(raceUser);
    await assert.rejects(store.beginItemExchange(raceUser),
      /item_lifecycle_unavailable/);
    await assert.rejects(store.saveUserItem(raceUser,
      { itemId: "resurrection", accessToken: "resurrection-token" }),
      /item_lifecycle_unavailable/);
    assert.equal(await store.getUserItemCount(raceUser), 0);

    // The real Express exchange and deletion handlers use the same durable
    // Postgres gate across store instances. Recovery-write failure is
    // independent of otherwise functioning lifecycle storage.
    const doubleUser = `double-user-${suffix}`;
    const sessions = new Map([["test-double", doubleUser]]);
    const routeSessionStore = {
      async getSessionByToken(token) {
        const id = sessions.get(token);
        return id ? { user: { id }, session: { id: token } } : null;
      },
      async finalizeAccountDeletion(id) {
        for (const [token, owner] of sessions) {
          if (owner === id) sessions.delete(token);
        }
        return { userDeleted: true, sessionsRevoked: 1 };
      },
    };
    const brokenStore = createPostgresPlaidItemStore({ pool,
      tokenEncryptionKey: process.env.TOKEN_ENCRYPTION_KEY });
    brokenStore.saveUserItem = async () => { throw new Error("save failed"); };
    brokenStore.recordRemovalRecovery = async () => {
      throw new Error("recovery write failed");
    };
    let removalFails = true;
    const interceptedPlaid = {
      async itemPublicTokenExchange() {
        return { data: { item_id: "double-item", access_token: "double-token",
          request_id: "double-request" } };
      },
      async itemRemove() {
        if (removalFails) throw new Error("removal uncertain");
        return { data: { request_id: "confirmed-removal" } };
      },
    };
    const auth = createAuthMiddleware({ authMode: "required",
      personalUserID: "unused", sessionStore: routeSessionStore });
    const app = express();
    app.use(express.json());
    const apiKey = (req, res, next) => req.get("x-app-api-key") === "test-key"
      ? next() : res.sendStatus(401);
    app.post("/link", apiKey, auth.resolvePlaidAuth,
      createExchangePublicTokenHandler({ getRequestUserID: auth.getRequestUserID,
        plaidItemStore: brokenStore, plaidClient: interceptedPlaid }));
    app.delete("/account", apiKey, auth.requireSessionAuth,
      createDeleteAccountHandler({ sessionStore: routeSessionStore,
        plaidItemStore: brokenStore, plaidClient: interceptedPlaid }));
    const server = app.listen(0, "127.0.0.1");
    await new Promise((resolve) => server.once("listening", resolve));
    try {
      const base = `http://127.0.0.1:${server.address().port}`;
      const headers = { "x-app-api-key": "test-key",
        authorization: "Bearer test-double", "content-type": "application/json" };
      const linked = await fetch(`${base}/link`, { method: "POST", headers,
        body: JSON.stringify({ public_token: "public-double",
          link_session_id: "link-double" }) });
      assert.equal(linked.status, 500);
      const deleted = await fetch(`${base}/account`, { method: "DELETE", headers });
      assert.equal((await deleted.json()).success, false);
      assert.equal(sessions.has("test-double"), true);
      assert.equal((await otherWriter.getItemLifecycleObligations(doubleUser))
        .pendingExchanges, 1);
      const [pending] = await otherWriter.getItemExchangeLeases(doubleUser);
      assert.equal(pending.state, "result_recorded");
      assert.equal(pending.linkSessionId, "link-double");
      assert.equal(pending.providerRequestId, "double-request");
      assert.equal(pending.accessToken, "double-token");
      const raw = await pool.query(
        `SELECT encrypted_access_token FROM plaid_item_exchange_leases
          WHERE id = $1`, [pending.id]);
      assert.notEqual(raw.rows[0].encrypted_access_token, "double-token");
      const item = { itemId: pending.itemId, accessToken: pending.accessToken };
      await assert.rejects(otherWriter.finishItemExchange(userB, pending,
        { kind: "removed", item }),
      /item_exchange_lease_changed/);
      await assert.rejects(otherWriter.finishItemExchange(doubleUser,
        { ...pending, generation: pending.generation + 1 },
        { kind: "removed", item }),
      /item_exchange_lease_changed/);
      await assert.rejects(otherWriter.finishItemExchange(doubleUser, pending,
        { kind: "removed", item }), /item_exchange_resolution_unverified/);
      removalFails = false;
      const removal = await interceptedPlaid.itemRemove({
        access_token: pending.accessToken });
      await otherWriter.markItemExchangeRemovalConfirmed(doubleUser, pending,
        item, removal.data.request_id);
      const [confirmed] = await otherWriter.getItemExchangeLeases(doubleUser);
      assert.equal(confirmed.state, "removal_confirmed");
      assert.equal(confirmed.removalRequestId, removal.data.request_id);
      await otherWriter.finishItemExchange(doubleUser, pending,
        { kind: "removed", item });
      await assert.rejects(otherWriter.finishItemExchange(doubleUser, pending,
        { kind: "removed", item }),
      /item_exchange_lease_changed/);
      assert.equal((await otherWriter.getItemLifecycleObligations(doubleUser))
        .pendingExchanges, 0);
    } finally { server.close(); }

    const ackUser = `ack-user-${suffix}`;
    const ackStore = createPostgresPlaidItemStore({ pool,
      tokenEncryptionKey: process.env.TOKEN_ENCRYPTION_KEY });
    ackStore.finishItemExchange = async () => { throw new Error("ack failed"); };
    let ackRemovalCalls = 0;
    const ackClient = {
      async itemPublicTokenExchange() {
        return { data: { item_id: "ack-item", access_token: "ack-token",
          request_id: "ack-exchange-request" } };
      },
      async itemRemove() { ackRemovalCalls += 1; return { data: {} }; },
    };
    const ackApp = express();
    ackApp.use(express.json());
    ackApp.post("/link", createExchangePublicTokenHandler({
      getRequestUserID: () => ackUser, plaidItemStore: ackStore,
      plaidClient: ackClient }));
    const ackServer = ackApp.listen(0, "127.0.0.1");
    await new Promise((resolve) => ackServer.once("listening", resolve));
    try {
      const response = await fetch(
        `http://127.0.0.1:${ackServer.address().port}/link`, {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ public_token: "ack-public",
            link_session_id: "ack-link" }) });
      assert.equal(response.status, 500);
      assert.equal(ackRemovalCalls, 0);
      const [saved] = await otherWriter.getUserItems(ackUser);
      const [ackLease] = await otherWriter.getItemExchangeLeases(ackUser);
      assert.equal(saved.itemId, "ack-item");
      assert.equal(ackLease.state, "item_saved");
      await assert.rejects(otherWriter.beginItemRemoval(ackUser, "deleting"),
        /item_lifecycle_busy/);
      await otherWriter.finishItemExchange(ackUser, ackLease,
        { kind: "saved", item: saved });
      assert.equal((await otherWriter.getItemLifecycleObligations(ackUser))
        .pendingExchanges, 0);
    } finally { ackServer.close(); }

    // Fault the actual COMMIT acknowledgment, after the database committed the
    // Item, marker, and count. The production store method itself is untouched.
    const committedUser = `committed-user-${suffix}`;
    let committedAckFailures = 0;
    const commitFaultPool = {
      query: (...args) => pool.query(...args),
      async connect() {
        const connection = await pool.connect();
        let savedMarkerWritten = false;
        return {
          async query(...args) {
            const command = String(args[0]);
            const result = await connection.query(...args);
            if (command.includes("SET state = 'item_saved'")) {
              savedMarkerWritten = true;
            }
            if (command === "COMMIT" && savedMarkerWritten) {
              savedMarkerWritten = false;
              committedAckFailures += 1;
              throw new Error("commit acknowledgment lost");
            }
            return result;
          },
          release: () => connection.release(),
        };
      },
    };
    const committedStore = createPostgresPlaidItemStore({ pool: commitFaultPool,
      tokenEncryptionKey: process.env.TOKEN_ENCRYPTION_KEY });
    let committedRemovals = 0;
    const committedClient = {
      async itemPublicTokenExchange() {
        return { data: { item_id: "committed-item", access_token: "committed-token",
          request_id: "committed-exchange-request" } };
      },
      async itemRemove() { committedRemovals += 1;
        return { data: { request_id: "unexpected-removal" } }; },
    };
    const committedApp = express();
    committedApp.use(express.json());
    committedApp.post("/link", createExchangePublicTokenHandler({
      getRequestUserID: () => committedUser, plaidItemStore: committedStore,
      plaidClient: committedClient }));
    const committedServer = committedApp.listen(0, "127.0.0.1");
    await new Promise((resolve) => committedServer.once("listening", resolve));
    try {
      const response = await fetch(
        `http://127.0.0.1:${committedServer.address().port}/link`, {
          method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify({ public_token: "committed-public" }) });
      assert.equal(response.status, 200);
      assert.equal((await response.json()).linked_items, 1);
      assert.equal(committedAckFailures, 1);
      assert.equal(committedRemovals, 0);
      assert.equal((await otherWriter.getUserItems(committedUser))[0].accessToken,
        "committed-token");
      assert.deepEqual(await otherWriter.getItemLifecycleObligations(committedUser),
        { pendingExchanges: 0, removalRecoveries: 0 });
    } finally { committedServer.close(); }

    const unknownUser = `unknown-user-${suffix}`;
    const unknownStore = createPostgresPlaidItemStore({ pool,
      tokenEncryptionKey: process.env.TOKEN_ENCRYPTION_KEY });
    const unknownSave = unknownStore.saveUserItem;
    unknownStore.saveUserItem = async (...args) => {
      await unknownSave(...args);
      throw new Error("post-commit response failed");
    };
    unknownStore.inspectItemExchangeSave = async () => {
      throw new Error("verification unavailable");
    };
    sessions.set("test-unknown", unknownUser);
    const unknownClient = {
      async itemPublicTokenExchange() {
        return { data: { item_id: "unknown-item", access_token: "unknown-token",
          request_id: "unknown-exchange-request" } };
      },
      async itemRemove() { committedRemovals += 1;
        return { data: { request_id: "unexpected-removal" } }; },
    };
    const unknownApp = express();
    unknownApp.use(express.json());
    unknownApp.post("/link", apiKey, auth.resolvePlaidAuth,
      createExchangePublicTokenHandler({ getRequestUserID: auth.getRequestUserID,
        plaidItemStore: unknownStore, plaidClient: unknownClient }));
    unknownApp.delete("/account", apiKey, auth.requireSessionAuth,
      createDeleteAccountHandler({ sessionStore: routeSessionStore,
        plaidItemStore: unknownStore, plaidClient: unknownClient }));
    const unknownServer = unknownApp.listen(0, "127.0.0.1");
    await new Promise((resolve) => unknownServer.once("listening", resolve));
    try {
      const base = `http://127.0.0.1:${unknownServer.address().port}`;
      const headers = { "x-app-api-key": "test-key",
        authorization: "Bearer test-unknown", "content-type": "application/json" };
      const linked = await fetch(`${base}/link`, { method: "POST", headers,
        body: JSON.stringify({ public_token: "unknown-public" }) });
      assert.equal(linked.status, 500);
      assert.equal(committedRemovals, 0);
      assert.equal((await otherWriter.getUserItems(unknownUser))[0].accessToken,
        "unknown-token");
      assert.equal((await otherWriter.getItemExchangeLeases(unknownUser))[0]
        .state, "item_saved");
      assert.equal((await otherWriter.getItemLifecycleObligations(unknownUser))
        .pendingExchanges, 1);
      const deleted = await fetch(`${base}/account`, { method: "DELETE", headers });
      assert.equal((await deleted.json()).success, false);
      assert.equal(sessions.has("test-unknown"), true);
    } finally { unknownServer.close(); }

    const conflictUser = `conflict-user-${suffix}`;
    await store.saveUserItem(conflictUser,
      { itemId: "conflict-item", accessToken: "old-token" });
    const conflictStore = createPostgresPlaidItemStore({ pool,
      tokenEncryptionKey: process.env.TOKEN_ENCRYPTION_KEY });
    conflictStore.saveUserItem = async () => { throw new Error("pre-commit failure"); };
    let conflictRemovals = 0;
    await assert.rejects(exchangePublicTokenForUser({ userId: conflictUser,
      publicToken: "conflict-public", plaidItemStore: conflictStore,
      plaidClient: { itemPublicTokenExchange: async () => ({ data: {
        item_id: "conflict-item", access_token: "new-token",
        request_id: "conflict-exchange-request" } }),
      itemRemove: async () => { conflictRemovals += 1;
        return { data: { request_id: "unexpected-removal" } }; } } }),
    /save outcome is uncertain/);
    assert.equal(conflictRemovals, 0);
    assert.equal((await otherWriter.getUserItems(conflictUser))[0].accessToken,
      "old-token");
    assert.equal((await otherWriter.getItemLifecycleObligations(conflictUser))
      .pendingExchanges, 1);

    const beforeUser = `before-user-${suffix}`;
    const beforeStore = createPostgresPlaidItemStore({ pool,
      tokenEncryptionKey: process.env.TOKEN_ENCRYPTION_KEY });
    beforeStore.saveUserItem = async () => { throw new Error("pre-commit failure"); };
    let beforeRemovals = 0;
    await assert.rejects(exchangePublicTokenForUser({ userId: beforeUser,
      publicToken: "before-public", plaidItemStore: beforeStore,
      plaidClient: { itemPublicTokenExchange: async () => ({ data: {
        item_id: "before-item", access_token: "before-token",
        request_id: "before-exchange-request" } }),
      itemRemove: async () => { beforeRemovals += 1;
        return { data: { request_id: "before-removal-request" } }; } } }),
    /Exchanged Item was not saved/);
    assert.equal(beforeRemovals, 1);
    assert.equal((await otherWriter.getUserItems(beforeUser)).length, 0);
    assert.deepEqual(await otherWriter.getItemLifecycleObligations(beforeUser),
      { pendingExchanges: 0, removalRecoveries: 0 });

    const fallbackUser = `fallback-user-${suffix}`;
    const fallbackLease = await store.beginItemExchange(fallbackUser,
      { publicToken: "fallback-public", linkSessionId: "fallback-link" });
    await store.markItemExchangeDispatched(fallbackUser, fallbackLease);
    const fallbackItem = { itemId: "fallback-item", accessToken: "fallback-token" };
    const fallbackRecovery = await store.recordRemovalRecovery(fallbackUser,
      fallbackItem, fallbackLease);
    await assert.rejects(otherWriter.finishItemExchange(fallbackUser,
      fallbackLease, { kind: "removed", item: fallbackItem }),
    /item_exchange_resolution_unverified/);
    await otherWriter.markItemExchangeRemovalConfirmed(fallbackUser,
      fallbackLease, fallbackItem, "fallback-removal-request", fallbackRecovery);
    assert.equal((await store.getItemExchangeLeases(fallbackUser))[0].state,
      "removal_confirmed");
    await otherWriter.finishItemExchange(fallbackUser, fallbackLease,
      { kind: "removed", item: fallbackItem });
    assert.equal((await store.getItemLifecycleObligations(fallbackUser))
      .removalRecoveries, 1);
    await store.clearRemovalRecovery(fallbackUser, fallbackRecovery);
    assert.deepEqual(await store.getItemLifecycleObligations(fallbackUser),
      { pendingExchanges: 0, removalRecoveries: 0 });

    const exactItem = (await store.getUserItems(userA))[0];
    const readinessAt = new Date(Date.now() + 1000).toISOString();
    assert.equal(await store.markHistoricalReadyForUserItem(
      userB, exactItem, readinessAt
    ), null);
    assert.equal((await store.getUserItemReadiness(userA, "item-a1"))
      .historicalReadyAt, null);
    assert.equal(await store.markHistoricalReadyForUserItem(
      userA, exactItem, readinessAt
    ), readinessAt);
    assert.equal(await store.markHistoricalReadyByItemID("item-a1", readinessAt), true);
    assert.equal((await store.getUserItemReadiness(userA, "item-a1"))
      .historicalReadyAt, readinessAt);
    assert.equal((await store.getUserItemReadiness(userB, "item-b1"))
      .historicalReadyAt, null);
    assert.equal(await store.markHistoricalRecoveryStarted(
      userA, "item-a1", readinessAt
    ), true);
    assert.equal((await store.getUserItemReadiness(userA, "item-a1"))
      .historicalRecoveryStartedAt, readinessAt);

    // An active duplicate Item ID is ambiguous: no owner may receive proof.
    await store.saveUserItem(userB, {
      accessToken: "token-b2", itemId: "item-a1",
    });
    const later = new Date(Date.now() + 2000).toISOString();
    assert.equal(await store.markHistoricalReadyByItemID("item-a1", later), false);
    assert.equal(await store.markHistoricalReadyForUserItem(
      userA, exactItem, later
    ), null);
    assert.equal((await store.getUserItemReadiness(userB, "item-a1"))
      .historicalReadyAt, null);
    assert.equal((await store.getUserItemReadiness(userA, "item-a1"))
      .historicalReadyAt, readinessAt);
    await store.removeUserItem(userB, "item-a1");

    await store.removeUserItem(userA, "item-a1");
    await store.saveUserItem(userA, {
      accessToken: "token-a1-relinked", itemId: "item-a1",
    });
    assert.equal((await store.getUserItemReadiness(userA, "item-a1"))
      .historicalReadyAt, null);
    assert.equal((await store.getUserItemReadiness(userA, "item-a1"))
      .historicalRecoveryStartedAt, null);
    assert.equal(await store.markHistoricalReadyForUserItem(
      userA, exactItem, later
    ), null);

    await store.removeAllUserItems(userA);

    assert.equal(await store.getUserItemCount(userA), 0);
    assert.equal(await store.getUserItemCount(userB), 1);

    console.log("Postgres Plaid item store check passed.");
  } finally {
    if (schemaAttempted) {
      await store.removeAllUserItems(userA).catch(() => {});
      await store.removeAllUserItems(userB).catch(() => {});
    }
    await pool.end();
  }
}

run().catch((error) => {
  const details = String(error.message || "unknown error");
  const safeDetails = [process.env.DATABASE_URL, process.env.TOKEN_ENCRYPTION_KEY]
    .filter(Boolean)
    .reduce((message, secret) => message.replaceAll(secret, "[redacted]"), details);
  console.error(`Postgres Plaid item store check failed: ${safeDetails}`);
  process.exit(1);
});
