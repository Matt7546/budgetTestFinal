const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const {
  deleteAccountForUser,
  removePlaidItemsForUser,
} = require("../accountLifecycle");

class FakePlaidItemStore {
  constructor(itemsByUser) {
    this.itemsByUser = new Map(
      Object.entries(itemsByUser).map(([userId, items]) => [
        userId,
        items.map((item) => ({ ...item })),
      ])
    );
  }

  async getUserItems(userId) {
    return (this.itemsByUser.get(userId) || [])
      .filter((item) => !item.disconnected)
      .map((item) => ({ ...item }));
  }

  async removeUserItem(userId, itemId) {
    const items = this.itemsByUser.get(userId) || [];

    items.forEach((item) => {
      if (item.itemId === itemId) {
        item.disconnected = true;
      }
    });

    return this.getUserItems(userId).then((activeItems) => activeItems.length);
  }

  async removeAllUserItems(userId) {
    const items = this.itemsByUser.get(userId) || [];

    items.forEach((item) => {
      item.disconnected = true;
    });
  }

  async activeItemIds(userId) {
    return (await this.getUserItems(userId)).map((item) => item.itemId);
  }
}

class FakePlaidClient {
  constructor({ failingTokens = [] } = {}) {
    this.failingTokens = new Set(failingTokens);
    this.removedTokens = [];
  }

  async itemRemove({ access_token }) {
    if (this.failingTokens.has(access_token)) {
      const error = new Error("Plaid item remove failed");
      error.response = {
        status: 400,
        data: {
          error_type: "ITEM_ERROR",
          error_code: "ITEM_REMOVE_FAILED",
          request_id: "request-id-is-not-returned",
        },
      };
      throw error;
    }

    this.removedTokens.push(access_token);
  }
}

class FakeSessionStore {
  constructor() {
    this.users = new Map([
      [
        "userA",
        {
          id: "userA",
          appleSub: "apple-a",
          email: "a@example.com",
          fullName: "User A",
          deleted: false,
        },
      ],
      [
        "userB",
        {
          id: "userB",
          appleSub: "apple-b",
          email: "b@example.com",
          fullName: "User B",
          deleted: false,
        },
      ],
    ]);
    this.sessions = [
      { id: "session-a1", userId: "userA", revoked: false },
      { id: "session-a2", userId: "userA", revoked: false },
      { id: "session-b1", userId: "userB", revoked: false },
    ];
    this.nextUserNumber = 1;
  }

  async revokeAllSessionsForUser(userId) {
    let revokedCount = 0;

    this.sessions.forEach((session) => {
      if (session.userId === userId && !session.revoked) {
        session.revoked = true;
        revokedCount += 1;
      }
    });

    return revokedCount;
  }

  async softDeleteUser(userId) {
    const user = this.users.get(userId);

    if (!user || user.deleted) {
      return false;
    }

    user.deleted = true;
    user.appleSub = null;
    user.email = null;
    user.fullName = null;

    return true;
  }

  async findOrCreateAppleUser({ appleSub, email = null, fullName = null }) {
    for (const user of this.users.values()) {
      if (!user.deleted && user.appleSub === appleSub) {
        return user;
      }
    }

    const user = {
      id: `new-user-${this.nextUserNumber}`,
      appleSub,
      email,
      fullName,
      deleted: false,
    };
    this.nextUserNumber += 1;
    this.users.set(user.id, user);

    return user;
  }

  activeSessionIds(userId) {
    return this.sessions
      .filter((session) => session.userId === userId && !session.revoked)
      .map((session) => session.id);
  }

  user(userId) {
    return this.users.get(userId);
  }
}

function seededItemStore() {
  return new FakePlaidItemStore({
    userA: [
      {
        accessToken: "token-a1",
        itemId: "item-a1",
        institutionName: "Institution A1",
      },
      {
        accessToken: "token-a2",
        itemId: "item-a2",
        institutionName: "Institution A2",
      },
    ],
    userB: [
      {
        accessToken: "token-b1",
        itemId: "item-b1",
        institutionName: "Institution B1",
      },
    ],
  });
}

async function run() {
  const indexSource = fs.readFileSync(
    path.join(__dirname, "..", "index.js"),
    "utf8"
  );
  assert.match(
    indexSource,
    /app\.delete\("\/api\/account", requireAppApiKey, requireSessionAuth/
  );

  const sessionStoreSource = fs.readFileSync(
    path.join(__dirname, "..", "sessionStore.js"),
    "utf8"
  );
  assert.match(sessionStoreSource, /revokeAllSessionsForUser/);
  assert.match(sessionStoreSource, /softDeleteUser/);
  assert.match(sessionStoreSource, /apple_sub = NULL/);

  let plaidItemStore = seededItemStore();
  let plaidClient = new FakePlaidClient();
  let result = await removePlaidItemsForUser({
    userId: "userA",
    plaidItemStore,
    plaidClient,
  });

  assert.equal(result.total_items, 2);
  assert.equal(result.removed_items, 2);
  assert.equal(result.failed_items, 0);
  assert.deepEqual(await plaidItemStore.activeItemIds("userA"), []);
  assert.deepEqual(await plaidItemStore.activeItemIds("userB"), ["item-b1"]);

  plaidItemStore = seededItemStore();
  plaidClient = new FakePlaidClient({ failingTokens: ["token-a2"] });
  result = await removePlaidItemsForUser({
    userId: "userA",
    plaidItemStore,
    plaidClient,
  });

  assert.equal(result.total_items, 2);
  assert.equal(result.removed_items, 1);
  assert.equal(result.failed_items, 1);
  assert.deepEqual(await plaidItemStore.activeItemIds("userA"), ["item-a2"]);
  assert.deepEqual(await plaidItemStore.activeItemIds("userB"), ["item-b1"]);
  assert.doesNotMatch(JSON.stringify(result), /token-a2/);
  assert.doesNotMatch(JSON.stringify(result), /request-id-is-not-returned/);

  plaidItemStore = seededItemStore();
  plaidClient = new FakePlaidClient();
  const sessionStore = new FakeSessionStore();
  result = await deleteAccountForUser({
    userId: "userA",
    plaidItemStore,
    plaidClient,
    sessionStore,
  });

  assert.equal(result.success, true);
  assert.equal(result.removed_items, 2);
  assert.equal(result.failed_items, 0);
  assert.equal(result.sessions_revoked, 2);
  assert.equal(result.user_deleted, true);
  assert.deepEqual(sessionStore.activeSessionIds("userA"), []);
  assert.deepEqual(sessionStore.activeSessionIds("userB"), ["session-b1"]);
  assert.equal(sessionStore.user("userA").appleSub, null);
  assert.equal(sessionStore.user("userA").email, null);
  assert.equal(sessionStore.user("userA").fullName, null);
  assert.deepEqual(await plaidItemStore.activeItemIds("userB"), ["item-b1"]);

  const recreatedUser = await sessionStore.findOrCreateAppleUser({
    appleSub: "apple-a",
    email: "new-a@example.com",
    fullName: "New User A",
  });
  assert.notEqual(recreatedUser.id, "userA");

  plaidItemStore = seededItemStore();
  plaidClient = new FakePlaidClient({ failingTokens: ["token-a2"] });
  const partialSessionStore = new FakeSessionStore();
  result = await deleteAccountForUser({
    userId: "userA",
    plaidItemStore,
    plaidClient,
    sessionStore: partialSessionStore,
  });

  assert.equal(result.success, false);
  assert.equal(result.retryable, true);
  assert.equal(result.removed_items, 1);
  assert.equal(result.failed_items, 1);
  assert.equal(result.sessions_revoked, 0);
  assert.equal(result.user_deleted, false);
  assert.deepEqual(partialSessionStore.activeSessionIds("userA"), [
    "session-a1",
    "session-a2",
  ]);
  assert.equal(partialSessionStore.user("userA").deleted, false);
  assert.deepEqual(await plaidItemStore.activeItemIds("userA"), ["item-a2"]);
  assert.deepEqual(await plaidItemStore.activeItemIds("userB"), ["item-b1"]);

  console.log("Delete account and disconnect hardening check passed.");
}

run().catch((error) => {
  console.error(`Delete account hardening check failed: ${error.message}`);
  process.exit(1);
});
