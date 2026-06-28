const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { createJsonPlaidItemStore } = require("../jsonPlaidItemStore");

async function run() {
  const tokenStorePath = path.join(
    os.tmpdir(),
    `caldera-user-scope-${process.pid}-${Date.now()}.json`
  );
  const store = createJsonPlaidItemStore({ tokenStorePath });

  try {
    await store.saveUserItem("userA", {
      accessToken: "token-a1",
      itemId: "item-a1",
      institutionName: "Institution A",
    });

    await store.saveUserItem("userB", {
      accessToken: "token-b1",
      itemId: "item-b1",
      institutionName: "Institution B",
    });

    assert.deepEqual(
      (await store.getUserItems("userA")).map((item) => item.itemId),
      ["item-a1"]
    );
    assert.deepEqual(
      (await store.getUserItems("userB")).map((item) => item.itemId),
      ["item-b1"]
    );

    await store.saveUserItem("userA", {
      accessToken: "token-a1-updated",
      itemId: "item-a1",
      institutionName: "Institution A Updated",
    });

    assert.equal(await store.getUserItemCount("userA"), 1);
    assert.equal((await store.getUserItems("userA"))[0].accessToken, "token-a1-updated");
    assert.equal(await store.getUserItemCount("userB"), 1);
    assert.equal((await store.getUserItems("userB"))[0].accessToken, "token-b1");

    await store.removeAllUserItems("userA");

    assert.equal(await store.getUserItemCount("userA"), 0);
    assert.equal(await store.getUserItemCount("userB"), 1);
    assert.deepEqual(
      (await store.getUserItems("userB")).map((item) => item.itemId),
      ["item-b1"]
    );

    console.log("User-scoped Plaid item store check passed.");
  } finally {
    fs.rmSync(tokenStorePath, { force: true });
  }
}

run().catch((error) => {
  console.error(`User-scoped Plaid item store check failed: ${error.message}`);
  process.exit(1);
});
