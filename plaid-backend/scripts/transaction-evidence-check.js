const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const express = require("express");
const { createJsonPlaidItemStore } = require("../jsonPlaidItemStore");
const { createPlaidWebhookHandler } = require("../plaidWebhook");
const { createItemEvidenceProvider } = require("../transactionEvidence");
const {
  fetchTransactionSnapshot,
  createTransactionsHandler,
} = require("../transactionSnapshot");

const now = new Date("2026-09-28T12:00:00.000Z");
const webhookURL = "https://example.test/api/plaid/webhook";

function signedWebhook(privateKey, body, issuedAt = now) {
  const header = Buffer.from(JSON.stringify({
    alg: "ES256", kid: "test-key", typ: "JWT",
  })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({
    iat: Math.floor(issuedAt.getTime() / 1000),
    request_body_sha256: crypto.createHash("sha256")
      .update(body).digest("hex"),
  })).toString("base64url");
  const input = `${header}.${payload}`;
  const signature = crypto.sign(
    "sha256", Buffer.from(input),
    { key: privateKey, dsaEncoding: "ieee-p1363" }
  ).toString("base64url");
  return `${input}.${signature}`;
}

async function run() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "caldera-evidence-"));
  const store = createJsonPlaidItemStore({
    tokenStorePath: path.join(directory, "items.json"),
  });
  const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
  });
  const verificationKey = {
    ...publicKey.export({ format: "jwk" }),
    alg: "ES256", kid: "test-key", use: "sig",
  };
  const plaidCalls = [];
  let lastProviderUpdate = "2026-09-28T11:00:00Z";
  let itemWebhook = null;
  const client = {
    async webhookVerificationKeyGet({ key_id }) {
      assert.equal(key_id, "test-key");
      return { data: { key: verificationKey } };
    },
    async itemGet({ access_token }) {
      plaidCalls.push("itemGet");
      return { data: {
        item: { item_id: access_token === "token-a" ? "item-a" : "item-b",
          webhook: itemWebhook },
        status: { transactions: {
          last_successful_update: lastProviderUpdate,
        } },
      } };
    },
    async itemWebhookUpdate({ access_token, webhook }) {
      assert.equal(access_token, "token-a");
      assert.equal(webhook, webhookURL);
      plaidCalls.push("itemWebhookUpdate");
      itemWebhook = webhook;
      return { data: {} };
    },
    async transactionsSync({ access_token, cursor, count }) {
      assert.equal(access_token, "token-a");
      assert.equal(cursor, "now");
      assert.equal(count, 1);
      plaidCalls.push("transactionsSync");
      return { data: { added: [], has_more: false, next_cursor: "unused" } };
    },
    async transactionsGet() {
      plaidCalls.push("transactionsGet");
      return { data: {
        transactions: [{ transaction_id: "posted-a", account_id: "account-a",
          name: "Rent", amount: 100, date: "2026-09-01", pending: false }],
        accounts: [{ account_id: "account-a" }],
        total_transactions: 1,
      } };
    },
  };
  const app = express();
  app.post(
    "/api/plaid/webhook",
    express.raw({ type: "application/json" }),
    createPlaidWebhookHandler({
      client, plaidItemStore: store, environment: "sandbox",
      now: () => now,
    })
  );
  app.get("/api/transactions", createTransactionsHandler({
    client,
    plaidItemStore: store,
    getRequestUserID: (req) => req.get("X-Test-Owner"),
    transactionsEnabled: true,
    lookbackDays: 90,
    capabilitiesResponse: () => ({}),
    logStoreError: () => {},
    logPlaidError: () => {},
    now: () => now,
    itemEvidenceFor: (owner, item) => createItemEvidenceProvider({
      client, plaidItemStore: store, webhookURL, now: () => now,
    })(owner, item),
  }));
  const server = app.listen(0, "127.0.0.1");

  try {
    await new Promise((resolve) => server.once("listening", resolve));
    const url = `http://127.0.0.1:${server.address().port}/api/plaid/webhook`;
    await store.saveUserItem("owner-a", {
      itemId: "item-a", accessToken: "token-a",
      linkedAt: "2026-09-01T00:00:00Z",
    });
    await store.saveUserItem("owner-b", {
      itemId: "item-b", accessToken: "token-b",
      linkedAt: "2026-09-01T00:00:00Z",
    });
    const itemA = (await store.getUserItems("owner-a"))[0];
    const evidenceFor = createItemEvidenceProvider({
      client, plaidItemStore: store, webhookURL, now: () => now,
    });

    const initial = await evidenceFor("owner-a", itemA);
    assert.equal(initial.historical_ready, false);
    assert.equal(initial.provider_last_successful_update,
      "2026-09-28T11:00:00.000Z");
    assert.deepEqual(plaidCalls.slice(0, 3), [
      "itemGet", "itemWebhookUpdate", "transactionsSync",
    ]);
    assert.ok((await store.getUserItemReadiness(
      "owner-a", "item-a"
    )).historicalRecoveryStartedAt);
    await evidenceFor("owner-a", itemA);
    assert.equal(plaidCalls.filter((call) => call === "transactionsSync").length, 1);

    const event = {
      webhook_type: "TRANSACTIONS", webhook_code: "HISTORICAL_UPDATE",
      environment: "sandbox", item_id: "item-a", error: null,
    };
    async function send(bodyObject, signatureBody = bodyObject, issuedAt = now) {
      const body = Buffer.from(JSON.stringify(bodyObject));
      const signedBody = Buffer.from(JSON.stringify(signatureBody));
      return fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json",
          "Plaid-Verification": signedWebhook(privateKey, signedBody, issuedAt) },
        body,
      });
    }
    assert.equal((await send(event, { ...event, item_id: "tampered" })).status, 401);
    assert.equal((await send(event, event,
      new Date(now.getTime() - 301000))).status, 401);
    assert.equal((await send({ ...event, error: { error_code: "FAIL" } })).status, 204);
    assert.equal((await send({ ...event,
      webhook_code: "INITIAL_UPDATE" })).status, 204);
    assert.equal((await send({ ...event,
      environment: "production" })).status, 204);
    assert.equal((await send({ ...event,
      webhook_code: "SYNC_UPDATES_AVAILABLE",
      historical_update_complete: false })).status, 204);
    assert.equal((await send({ ...event,
      webhook_code: "SYNC_UPDATES_AVAILABLE",
      historical_update_complete: true,
      error: { error_code: "NOT_READY" } })).status, 204);
    assert.equal((await store.getUserItemReadiness(
      "owner-a", "item-a"
    )).historicalReadyAt, null);
    assert.equal((await send({ ...event,
      webhook_code: "SYNC_UPDATES_AVAILABLE",
      historical_update_complete: true })).status, 204);
    assert.equal((await send(event)).status, 204);
    assert.equal((await send(event)).status, 204);
    assert.equal((await store.getUserItemReadiness(
      "owner-a", "item-a"
    )).historicalReadyAt, now.toISOString());
    assert.equal((await store.getUserItemReadiness(
      "owner-b", "item-b"
    )).historicalReadyAt, null);

    const ready = await evidenceFor("owner-a", itemA);
    assert.equal(ready.historical_ready, true);
    assert.equal(ready.provider_last_successful_update,
      "2026-09-28T11:00:00.000Z");
    lastProviderUpdate = null;
    assert.equal((await evidenceFor("owner-a", itemA))
      .provider_last_successful_update, null);
    lastProviderUpdate = "not-a-date";
    assert.equal((await evidenceFor("owner-a", itemA))
      .provider_last_successful_update, null);
    lastProviderUpdate = "2026-02-30T11:00:00Z";
    assert.equal((await evidenceFor("owner-a", itemA))
      .provider_last_successful_update, null);
    lastProviderUpdate = "2026-09-29T11:00:00Z";
    assert.equal((await evidenceFor("owner-a", itemA))
      .provider_last_successful_update, null);
    lastProviderUpdate = "2026-09-20T11:00:00Z";
    assert.equal((await evidenceFor("owner-a", itemA))
      .provider_last_successful_update,
      "2026-09-20T11:00:00.000Z");

    lastProviderUpdate = "2026-09-28T11:00:00Z";
    const snapshot = await fetchTransactionSnapshot({
      client, items: [itemA], startDate: "2026-06-28",
      endDate: "2026-09-28", now: () => now,
      itemEvidenceFor: (item) => evidenceFor("owner-a", item),
    });
    assert.equal(snapshot.complete, true);
    assert.equal(snapshot.itemEvidence[0].historical_ready, true);
    assert.deepEqual(snapshot.evaluatedItemIDs, ["item-a"]);
    assert.ok(plaidCalls.lastIndexOf("itemGet") <
      plaidCalls.lastIndexOf("transactionsGet"));

    const ownerResponse = await fetch(`${url.replace("/api/plaid/webhook", "/api/transactions")}`, {
      headers: { "X-Test-Owner": "owner-a" },
    });
    assert.equal(ownerResponse.status, 200);
    const ownerSnapshot = await ownerResponse.json();
    assert.equal(ownerSnapshot.complete, true);
    assert.deepEqual(ownerSnapshot.evaluated_item_ids, ["item-a"]);
    assert.equal(ownerSnapshot.item_evidence[0].historical_ready, true);
    assert.equal(ownerSnapshot.item_evidence[0].item_id, "item-a");
    assert.equal(ownerSnapshot.item_evidence[0].provider_last_successful_update,
      "2026-09-28T11:00:00.000Z");

    const otherResponse = await fetch(`${url.replace("/api/plaid/webhook", "/api/transactions")}`, {
      headers: { "X-Test-Owner": "owner-b" },
    });
    assert.equal(otherResponse.status, 200);
    const otherSnapshot = await otherResponse.json();
    assert.deepEqual(otherSnapshot.evaluated_item_ids, ["item-b"]);
    assert.equal(otherSnapshot.item_evidence[0].historical_ready, false);

    await store.removeUserItem("owner-a", "item-a");
    await store.saveUserItem("owner-a", {
      itemId: "item-a", accessToken: "token-a",
    });
    assert.equal((await store.getUserItemReadiness(
      "owner-a", "item-a"
    )).historicalReadyAt, null);
    const tokenStorePath = path.join(directory, "items.json");
    fs.writeFileSync(tokenStorePath, "{corrupt", { mode: 0o600 });
    await assert.rejects(store.getUserItemReadiness("owner-a", "item-a"));
    await assert.rejects(store.markHistoricalReadyByItemID(
      "item-a", now.toISOString()
    ));
    assert.equal(fs.readFileSync(tokenStorePath, "utf8"), "{corrupt");
  } finally {
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(directory, { recursive: true, force: true });
  }
  console.log("Transaction provider evidence checks passed.");
}

run().catch((error) => {
  console.error(`Transaction provider evidence check failed: ${error.message}`);
  process.exit(1);
});
