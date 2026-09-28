const assert = require("node:assert/strict");
const crypto = require("crypto");
const {
  requireDisposableTarget,
  assertDisposableTarget,
} = require("./postgres-test-target");

async function run() {
  // This preflight must complete before opening a connection or running schema SQL.
  const target = requireDisposableTarget();
  const { createPool } = require("../db");
  const { createPostgresPlaidItemStore } = require("../postgresPlaidItemStore");
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
