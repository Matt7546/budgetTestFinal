const assert = require("node:assert/strict");
const crypto = require("crypto");
const { createPostgresPlaidItemStore } = require("../postgresPlaidItemStore");

async function run() {
  if (!process.env.DATABASE_URL || !process.env.TOKEN_ENCRYPTION_KEY) {
    console.log("Skipping Postgres store check: DATABASE_URL and TOKEN_ENCRYPTION_KEY are required.");
    return;
  }

  const store = createPostgresPlaidItemStore();
  const suffix = crypto.randomBytes(6).toString("hex");
  const userA = `check-user-a-${suffix}`;
  const userB = `check-user-b-${suffix}`;

  try {
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
    await store.removeAllUserItems(userA).catch(() => {});
    await store.removeAllUserItems(userB).catch(() => {});
    await store.close?.();
  }
}

run().catch((error) => {
  console.error(`Postgres Plaid item store check failed: ${error.message}`);
  process.exit(1);
});
