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
