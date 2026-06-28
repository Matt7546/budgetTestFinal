const fs = require("fs");
const { normalizeLinkedItem } = require("./plaidItemUtils");

function createJsonPlaidItemStore({ tokenStorePath }) {
  function readTokenStore() {
    try {
      if (!fs.existsSync(tokenStorePath)) {
        return {};
      }

      return JSON.parse(fs.readFileSync(tokenStorePath, "utf8"));
    } catch {
      console.error("Token store read failed.");
      return {};
    }
  }

  function writeTokenStore(store) {
    fs.writeFileSync(
      tokenStorePath,
      JSON.stringify(store, null, 2),
      {
        mode: 0o600,
      }
    );
  }

  function ensureUserBucket(store, userId) {
    if (!userId) {
      throw new Error("userId is required for Plaid item storage.");
    }

    const existingBucket = store[userId];

    if (!existingBucket) {
      store[userId] = {
        items: [],
        updatedAt: new Date().toISOString(),
      };

      return store[userId];
    }

    if (Array.isArray(existingBucket.items)) {
      existingBucket.items = existingBucket.items
        .map(normalizeLinkedItem)
        .filter(Boolean);
      existingBucket.updatedAt = existingBucket.updatedAt || new Date().toISOString();
      return existingBucket;
    }

    const legacyItem = normalizeLinkedItem(existingBucket);
    store[userId] = {
      items: legacyItem ? [legacyItem] : [],
      updatedAt: existingBucket.updatedAt || new Date().toISOString(),
    };

    return store[userId];
  }

  function getItemsFromStore(store, userId) {
    const userBucket = store[userId];

    if (!userBucket) {
      return [];
    }

    if (Array.isArray(userBucket.items)) {
      return userBucket.items
        .map(normalizeLinkedItem)
        .filter(Boolean);
    }

    const legacyItem = normalizeLinkedItem(userBucket);

    return legacyItem ? [legacyItem] : [];
  }

  function saveItemsToStore(store, userId, items) {
    const bucket = ensureUserBucket(store, userId);

    bucket.items = items
      .map(normalizeLinkedItem)
      .filter(Boolean);
    bucket.updatedAt = new Date().toISOString();

    return bucket.items.length;
  }

  async function ensureUser(userId) {
    const store = readTokenStore();
    ensureUserBucket(store, userId);
    writeTokenStore(store);
  }

  async function getUserItems(userId) {
    return getItemsFromStore(readTokenStore(), userId);
  }

  async function saveUserItem(userId, item) {
    const store = readTokenStore();
    const now = new Date().toISOString();
    const items = getItemsFromStore(store, userId);
    const normalizedItem = normalizeLinkedItem({
      ...item,
      linkedAt: item.linkedAt || now,
      updatedAt: now,
    });

    if (!normalizedItem) {
      return items.length;
    }

    const existingIndex = normalizedItem.itemId
      ? items.findIndex((existingItem) => existingItem.itemId === normalizedItem.itemId)
      : -1;

    if (existingIndex >= 0) {
      normalizedItem.linkedAt = items[existingIndex].linkedAt;
      items[existingIndex] = normalizedItem;
    } else {
      items.push(normalizedItem);
    }

    const count = saveItemsToStore(store, userId, items);
    writeTokenStore(store);

    return count;
  }

  async function removeUserItem(userId, itemId) {
    if (!itemId) {
      return getUserItemCount(userId);
    }

    const store = readTokenStore();
    const nextItems = getItemsFromStore(store, userId).filter(
      (item) => item.itemId !== itemId
    );
    const count = saveItemsToStore(store, userId, nextItems);
    writeTokenStore(store);

    return count;
  }

  async function removeAllUserItems(userId) {
    const store = readTokenStore();

    if (store[userId]) {
      delete store[userId];
      writeTokenStore(store);
    }
  }

  async function getUserItemCount(userId) {
    return getItemsFromStore(readTokenStore(), userId).length;
  }

  return {
    driver: "json",
    ensureUser,
    getUserItems,
    saveUserItem,
    removeUserItem,
    removeAllUserItems,
    getUserItemCount,
  };
}

module.exports = {
  createJsonPlaidItemStore,
};
