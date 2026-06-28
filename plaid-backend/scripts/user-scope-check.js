const assert = require("node:assert/strict");
const {
  getUserItems,
  saveUserItem,
  removeAllUserItems,
  getUserItemCount,
} = require("../userItemStore");

const store = {};

saveUserItem(store, "userA", {
  accessToken: "token-a1",
  itemId: "item-a1",
  institutionName: "Institution A",
});

saveUserItem(store, "userB", {
  accessToken: "token-b1",
  itemId: "item-b1",
  institutionName: "Institution B",
});

assert.deepEqual(
  getUserItems(store, "userA").map((item) => item.itemId),
  ["item-a1"]
);
assert.deepEqual(
  getUserItems(store, "userB").map((item) => item.itemId),
  ["item-b1"]
);

saveUserItem(store, "userA", {
  accessToken: "token-a1-updated",
  itemId: "item-a1",
  institutionName: "Institution A Updated",
});

assert.equal(getUserItemCount(store, "userA"), 1);
assert.equal(getUserItems(store, "userA")[0].accessToken, "token-a1-updated");
assert.equal(getUserItemCount(store, "userB"), 1);
assert.equal(getUserItems(store, "userB")[0].accessToken, "token-b1");

removeAllUserItems(store, "userA");

assert.equal(getUserItemCount(store, "userA"), 0);
assert.equal(getUserItemCount(store, "userB"), 1);
assert.deepEqual(
  getUserItems(store, "userB").map((item) => item.itemId),
  ["item-b1"]
);

console.log("User-scoped Plaid item store check passed.");
