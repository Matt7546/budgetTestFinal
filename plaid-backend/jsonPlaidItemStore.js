const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { normalizeLinkedItem } = require("./plaidItemUtils");
const { encryptToken, decryptToken, decodeEncryptionKey } = require("./tokenCrypto");

function createJsonPlaidItemStore({ tokenStorePath }) {
  const recoveryKeyPath = `${tokenStorePath}.recovery-key`;

  function recoveryKey(createIfMissing = false) {
    if (fs.existsSync(recoveryKeyPath)) {
      const key = fs.readFileSync(recoveryKeyPath, "utf8");
      decodeEncryptionKey(key);
      return key;
    }
    if (!createIfMissing) {
      throw new Error("Removal recovery key is missing.");
    }
    const key = crypto.randomBytes(32).toString("base64");
    const descriptor = fs.openSync(recoveryKeyPath, "wx", 0o600);
    try {
      fs.writeFileSync(descriptor, key);
      fs.fsyncSync(descriptor);
    } finally {
      fs.closeSync(descriptor);
    }
    const directoryDescriptor = fs.openSync(path.dirname(recoveryKeyPath), "r");
    try { fs.fsyncSync(directoryDescriptor); }
    finally { fs.closeSync(directoryDescriptor); }
    return key;
  }

  function checkedRecoveryKey(store) {
    const encryptedRecords = Object.values(store).flatMap((bucket) => [
      ...(bucket?.exchangeLeases || []), ...(bucket?.removalRecoveries || []),
    ]).filter((entry) => entry.encryptedAccessToken);
    const key = recoveryKey(encryptedRecords.length === 0);
    for (const record of encryptedRecords) {
      decryptToken(record.encryptedAccessToken, key);
    }
    return key;
  }
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
        itemLifecycleGeneration: 0,
        itemLifecycleState: "active",
        exchangeLeases: [],
        removalRecoveries: [],
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

  // The JSON driver supports one writer process. Synchronous read/modify/write
  // sections are atomic within that process, not across independent processes.
  async function beginItemExchange(userId, context = {}) {
    const store = readTokenStore();
    // Establish the key prerequisite before an external exchange. Never
    // generate a replacement key over existing encrypted obligations.
    checkedRecoveryKey(store);
    const bucket = ensureUserBucket(store, userId);
    if ((bucket.itemLifecycleState || "active") !== "active") {
      throw new Error("item_lifecycle_unavailable");
    }
    const lease = {
      id: crypto.randomUUID(),
      generation: bucket.itemLifecycleGeneration || 0,
      state: "prepared",
      publicTokenSHA256: context.publicToken
        ? crypto.createHash("sha256").update(context.publicToken).digest("hex") : null,
      linkSessionId: context.linkSessionId || null,
      createdAt: new Date().toISOString(),
    };
    bucket.exchangeLeases = bucket.exchangeLeases || [];
    bucket.exchangeLeases.push(lease);
    writeTokenStore(store);
    return lease;
  }

  function exactLease(bucket, lease) {
    const entry = (bucket?.exchangeLeases || []).find((candidate) =>
      candidate.id === lease.id && candidate.generation === lease.generation);
    if (!entry || (bucket.itemLifecycleGeneration || 0) !== lease.generation ||
        (bucket.itemLifecycleState || "active") !== "active") {
      throw new Error("item_exchange_lease_changed");
    }
    return entry;
  }

  async function markItemExchangeDispatched(userId, lease) {
    const store = readTokenStore();
    const entry = exactLease(store[userId], lease);
    if (entry.state !== "prepared") throw new Error("item_exchange_lease_changed");
    entry.state = "dispatch_uncertain";
    writeTokenStore(store);
  }

  async function recordItemExchangeResult(userId, lease, item, requestId = null) {
    const store = readTokenStore();
    const entry = exactLease(store[userId], lease);
    if (entry.state !== "dispatch_uncertain" || !item.itemId || !item.accessToken) {
      throw new Error("item_exchange_lease_changed");
    }
    entry.state = "result_recorded";
    entry.itemId = item.itemId;
    entry.encryptedAccessToken = encryptToken(item.accessToken, recoveryKey());
    entry.providerRequestId = requestId;
    writeTokenStore(store);
  }

  async function markItemExchangeRemovalConfirmed(userId, lease, item,
    removalRequestId, recoveryId = null) {
    const store = readTokenStore();
    const bucket = store[userId];
    const entry = exactLease(bucket, lease);
    if (!removalRequestId) {
      throw new Error("item_exchange_resolution_unverified");
    }
    if (entry.state === "dispatch_uncertain" && recoveryId) {
      const recovery = (bucket.removalRecoveries || []).find((candidate) =>
        candidate.id === recoveryId && candidate.exchangeLeaseId === lease.id &&
        candidate.itemId === item.itemId);
      if (!recovery || decryptToken(recovery.encryptedAccessToken,
        recoveryKey()) !== item.accessToken) {
        throw new Error("item_exchange_resolution_unverified");
      }
      entry.itemId = recovery.itemId;
      entry.encryptedAccessToken = recovery.encryptedAccessToken;
    } else if (entry.state !== "result_recorded" ||
        entry.itemId !== item.itemId ||
        decryptToken(entry.encryptedAccessToken, recoveryKey()) !== item.accessToken) {
      throw new Error("item_exchange_resolution_unverified");
    }
    entry.state = "removal_confirmed";
    entry.removalRequestId = removalRequestId;
    writeTokenStore(store);
  }

  async function getItemExchangeLeases(userId) {
    const entries = readTokenStore()[userId]?.exchangeLeases || [];
    const key = entries.some((entry) => entry.encryptedAccessToken)
      ? recoveryKey() : null;
    return entries.map((entry) => ({ ...entry,
      accessToken: entry.encryptedAccessToken
        ? decryptToken(entry.encryptedAccessToken, key) : null,
      encryptedAccessToken: undefined }));
  }

  async function finishItemExchange(userId, lease, resolution) {
    const store = readTokenStore();
    const bucket = store[userId];
    const entry = exactLease(bucket, lease);
    const item = resolution?.item;
    if (!item?.itemId || !item?.accessToken ||
        (entry.itemId && entry.itemId !== item.itemId) ||
        (entry.encryptedAccessToken &&
          decryptToken(entry.encryptedAccessToken, recoveryKey()) !== item.accessToken)) {
      throw new Error("item_exchange_resolution_unverified");
    }
    if (resolution.kind === "saved") {
      if (entry.state !== "item_saved" ||
          !getItemsFromStore(store, userId).some((candidate) =>
        candidate.itemId === item.itemId &&
        candidate.accessToken === item.accessToken)) {
        throw new Error("item_exchange_resolution_unverified");
      }
    } else if (resolution.kind === "recovery") {
      const recovery = (bucket.removalRecoveries || []).find((candidate) =>
        candidate.id === resolution.recoveryId && candidate.itemId === item.itemId &&
        candidate.exchangeLeaseId === lease.id);
      if (!recovery || decryptToken(recovery.encryptedAccessToken,
        recoveryKey()) !== item.accessToken) {
        throw new Error("item_exchange_resolution_unverified");
      }
    } else if (resolution.kind === "removed") {
      if (entry.state !== "removal_confirmed" || !entry.removalRequestId) {
        throw new Error("item_exchange_resolution_unverified");
      }
    } else {
      throw new Error("item_exchange_resolution_unverified");
    }
    bucket.exchangeLeases = bucket.exchangeLeases.filter((candidate) =>
      candidate.id !== lease.id);
    writeTokenStore(store);
  }

  async function beginItemRemoval(userId, purpose) {
    if (!["disconnecting", "deleting"].includes(purpose)) {
      throw new Error("Invalid Item removal purpose.");
    }
    const store = readTokenStore();
    const bucket = ensureUserBucket(store, userId);
    if ((bucket.itemLifecycleState || "active") !== "active") {
      throw new Error("item_lifecycle_unavailable");
    }
    if ((bucket.exchangeLeases || []).length ||
        (bucket.removalRecoveries || []).length) {
      throw new Error("item_lifecycle_busy");
    }
    bucket.itemLifecycleGeneration = (bucket.itemLifecycleGeneration || 0) + 1;
    bucket.itemLifecycleState = purpose;
    writeTokenStore(store);
    return bucket.itemLifecycleGeneration;
  }

  async function finishItemRemoval(userId, generation, purpose, deleted = false) {
    const store = readTokenStore();
    const bucket = store[userId];
    if (!bucket || bucket.itemLifecycleGeneration !== generation ||
        bucket.itemLifecycleState !== purpose) {
      throw new Error("item_lifecycle_changed");
    }
    bucket.itemLifecycleState = deleted ? "deleted" : "active";
    writeTokenStore(store);
  }

  async function getItemLifecycleObligations(userId) {
    const bucket = readTokenStore()[userId];
    return {
      pendingExchanges: bucket?.exchangeLeases?.length || 0,
      removalRecoveries: bucket?.removalRecoveries?.length || 0,
    };
  }

  async function recordRemovalRecovery(userId, item, lease = null) {
    const store = readTokenStore();
    const bucket = ensureUserBucket(store, userId);
    if (lease) {
      const entry = exactLease(bucket, lease);
      if (entry.itemId && entry.itemId !== item.itemId) {
        throw new Error("item_exchange_lease_changed");
      }
    }
    const id = crypto.randomUUID();
    const encrypted = encryptToken(item.accessToken, checkedRecoveryKey(store));
    bucket.removalRecoveries = bucket.removalRecoveries || [];
    bucket.removalRecoveries.push({ id, itemId: item.itemId,
      encryptedAccessToken: encrypted,
      exchangeLeaseId: lease?.id || null,
      createdAt: new Date().toISOString() });
    writeTokenStore(store);
    return id;
  }

  async function clearRemovalRecovery(userId, id) {
    const store = readTokenStore();
    const bucket = store[userId];
    if (!bucket) return;
    bucket.removalRecoveries = (bucket.removalRecoveries || [])
      .filter((entry) => entry.id !== id);
    writeTokenStore(store);
  }

  async function getRemovalRecoveries(userId) {
    const entries = readTokenStore()[userId]?.removalRecoveries || [];
    if (!entries.length) return [];
    const key = recoveryKey();
    return entries.map((entry) => ({ id: entry.id, itemId: entry.itemId,
      accessToken: decryptToken(entry.encryptedAccessToken, key),
      exchangeLeaseId: entry.exchangeLeaseId || null,
      createdAt: entry.createdAt }));
  }

  async function saveUserItem(userId, item, lease = null) {
    const store = readTokenStore();
    const bucket = ensureUserBucket(store, userId);
    if ((bucket.itemLifecycleState || "active") !== "active" ||
        (lease && (lease.generation !== (bucket.itemLifecycleGeneration || 0) ||
          !(bucket.exchangeLeases || []).some((entry) => entry.id === lease.id &&
            entry.generation === lease.generation)))) {
      throw new Error("item_lifecycle_unavailable");
    }
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
    if (lease) {
      const entry = exactLease(bucket, lease);
      if (!["dispatch_uncertain", "result_recorded"].includes(entry.state) ||
          (entry.itemId && entry.itemId !== normalizedItem.itemId) ||
          (entry.encryptedAccessToken &&
            decryptToken(entry.encryptedAccessToken, recoveryKey()) !==
              normalizedItem.accessToken)) {
        throw new Error("item_exchange_lease_changed");
      }
      entry.state = "item_saved";
      entry.itemId = normalizedItem.itemId;
      entry.encryptedAccessToken = encryptToken(normalizedItem.accessToken,
        checkedRecoveryKey(store));
    }
    writeTokenStore(store);

    return count;
  }

  async function inspectItemExchangeSave(userId, lease, item) {
    const store = readTokenStore();
    const bucket = store[userId];
    const entry = exactLease(bucket, lease);
    if (!item?.itemId || !item?.accessToken ||
        (entry.itemId && entry.itemId !== item.itemId) ||
        (entry.encryptedAccessToken &&
          decryptToken(entry.encryptedAccessToken, recoveryKey()) !== item.accessToken)) {
      return { outcome: "unknown" };
    }
    const items = getItemsFromStore(store, userId);
    const current = items.find((candidate) => candidate.itemId === item.itemId);
    if (entry.state === "item_saved") {
      return current?.accessToken === item.accessToken
        ? { outcome: "saved", linkedItemCount: items.length }
        : { outcome: "unknown" };
    }
    if (current || !["dispatch_uncertain", "result_recorded"].includes(entry.state)) {
      return { outcome: "unknown" };
    }
    return { outcome: "not_saved" };
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

  async function removeUserItemIfMatching(userId, expectedItem) {
    const store = readTokenStore();
    const items = getItemsFromStore(store, userId);
    const current = items.find((item) => item.itemId === expectedItem.itemId);
    if (!current || current.accessToken !== expectedItem.accessToken ||
        current.linkedAt !== expectedItem.linkedAt) return false;
    saveItemsToStore(store, userId,
      items.filter((item) => item !== current));
    writeTokenStore(store);
    return true;
  }

  async function removeAllUserItems(userId) {
    const store = readTokenStore();

    if (store[userId]) {
      // Preserve a deletion tombstone/generation even for administrative
      // clearing; otherwise a later ensureUser could re-open this owner.
      const bucket = ensureUserBucket(store, userId);
      bucket.items = [];
      bucket.updatedAt = new Date().toISOString();
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

  async function markHistoricalReadyForUserItem(userId, expectedItem, at) {
    const store = readTokenStore();
    const matches = Object.entries(store).flatMap(([owner, bucket]) =>
      getItemsFromStore(store, owner)
        .filter((item) => item.itemId === expectedItem?.itemId)
        .map((item) => ({ owner, item }))
    );
    if (matches.length !== 1 || matches[0].owner !== userId) {
      return null;
    }
    const currentItem = matches[0].item;
    if (!expectedItem?.itemId ||
        currentItem.accessToken !== expectedItem.accessToken ||
        currentItem.linkedAt !== expectedItem.linkedAt ||
        !Number.isFinite(Date.parse(at)) ||
        (currentItem.linkedAt !== null &&
          (!Number.isFinite(Date.parse(currentItem.linkedAt)) ||
            Date.parse(currentItem.linkedAt) > Date.parse(at)))) {
      return null;
    }
    if (currentItem.historicalReadyAt) {
      return currentItem.historicalReadyAt;
    }
    currentItem.historicalReadyAt = at;
    const items = getItemsFromStore(store, userId);
    const index = items.findIndex((item) => item.itemId === expectedItem.itemId);
    items[index] = currentItem;
    saveItemsToStore(store, userId, items);
    writeTokenStore(store);
    return at;
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
    beginItemExchange,
    markItemExchangeDispatched,
    recordItemExchangeResult,
    markItemExchangeRemovalConfirmed,
    getItemExchangeLeases,
    finishItemExchange,
    beginItemRemoval,
    finishItemRemoval,
    getItemLifecycleObligations,
    recordRemovalRecovery,
    clearRemovalRecovery,
    getRemovalRecoveries,
    saveUserItem,
    inspectItemExchangeSave,
    removeUserItem,
    removeUserItemIfMatching,
    removeAllUserItems,
    getUserItemCount,
    getUserItemReadiness,
    markHistoricalReadyByItemID,
    markHistoricalReadyForUserItem,
    markHistoricalRecoveryStarted,
  };
}

module.exports = {
  createJsonPlaidItemStore,
};
