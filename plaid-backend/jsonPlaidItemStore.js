const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { normalizeLinkedItem } = require("./plaidItemUtils");

function createJsonPlaidItemStore({ tokenStorePath }) {
  function readTokenStore() {
    try {
      if (!fs.existsSync(tokenStorePath)) {
        return {};
      }

      return JSON.parse(fs.readFileSync(tokenStorePath, "utf8"));
    } catch (error) {
      throw new Error("Token store read failed.", { cause: error });
    }
  }

  function writeTokenStore(store) {
    const temporaryPath = `${tokenStorePath}.${process.pid}.${crypto.randomUUID()}.tmp`;
    const directory = path.dirname(tokenStorePath);
    let descriptor;
    try {
      descriptor = fs.openSync(temporaryPath, "wx", 0o600);
      fs.writeFileSync(descriptor, JSON.stringify(store, null, 2));
      fs.fsyncSync(descriptor);
      fs.closeSync(descriptor);
      descriptor = undefined;
      fs.renameSync(temporaryPath, tokenStorePath);
      const directoryDescriptor = fs.openSync(directory, "r");
      try {
        fs.fsyncSync(directoryDescriptor);
      } finally {
        fs.closeSync(directoryDescriptor);
      }
    } finally {
      if (descriptor !== undefined) {
        fs.closeSync(descriptor);
      }
      if (fs.existsSync(temporaryPath)) {
        fs.unlinkSync(temporaryPath);
      }
    }
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
      normalizedItem.historicalReadyAt = items[existingIndex].historicalReadyAt;
      normalizedItem.historicalRecoveryStartedAt =
        items[existingIndex].historicalRecoveryStartedAt;
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

  async function getUserItemReadiness(userId, itemId) {
    const item = getItemsFromStore(readTokenStore(), userId).find(
      (candidate) => candidate.itemId === itemId
    );
    return item ? {
      historicalReadyAt: item.historicalReadyAt,
      historicalRecoveryStartedAt: item.historicalRecoveryStartedAt,
    } : null;
  }

  async function markHistoricalReadyByItemID(itemId, at) {
    const store = readTokenStore();
    const matches = Object.entries(store).flatMap(([userId, bucket]) =>
      getItemsFromStore(store, userId)
        .filter((item) => item.itemId === itemId)
        .map(() => userId)
    );
    if (matches.length !== 1) {
      return false;
    }
    const userId = matches[0];
    const items = getItemsFromStore(store, userId);
    const item = items.find((candidate) => candidate.itemId === itemId);
    if (!Number.isFinite(Date.parse(item.linkedAt)) ||
        !Number.isFinite(Date.parse(at)) ||
        Date.parse(item.linkedAt) > Date.parse(at)) {
      return false;
    }
    if (item.historicalReadyAt) {
      return true;
    }
    item.historicalReadyAt = at;
    saveItemsToStore(store, userId, items);
    writeTokenStore(store);
    return true;
  }

  async function markHistoricalRecoveryStarted(userId, itemId, at) {
    const store = readTokenStore();
    const items = getItemsFromStore(store, userId);
    const item = items.find((candidate) => candidate.itemId === itemId);
    if (!item) {
      return false;
    }
    item.historicalRecoveryStartedAt = at;
    saveItemsToStore(store, userId, items);
    writeTokenStore(store);
    return true;
  }

  return {
    driver: "json",
    ensureUser,
    getUserItems,
    saveUserItem,
    removeUserItem,
    removeAllUserItems,
    getUserItemCount,
    getUserItemReadiness,
    markHistoricalReadyByItemID,
    markHistoricalRecoveryStarted,
  };
}

module.exports = {
  createJsonPlaidItemStore,
};
