function normalizeLinkedItem(item) {
  if (!item) {
    return null;
  }

  const accessToken = item.accessToken || item.access_token;

  if (!accessToken) {
    return null;
  }

  return {
    accessToken,
    itemId: item.itemId || item.item_id || null,
    institutionName: item.institutionName || item.institution_name || null,
    institutionId: item.institutionId || item.institution_id || null,
    linkedAt: item.linkedAt || item.createdAt || new Date().toISOString(),
    updatedAt: item.updatedAt || new Date().toISOString(),
  };
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

function getUserItems(store, userId) {
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

function saveUserItems(store, userId, items) {
  const bucket = ensureUserBucket(store, userId);

  bucket.items = items
    .map(normalizeLinkedItem)
    .filter(Boolean);
  bucket.updatedAt = new Date().toISOString();

  return bucket.items.length;
}

function saveUserItem(store, userId, item) {
  const now = new Date().toISOString();
  const items = getUserItems(store, userId);
  const normalizedItem = normalizeLinkedItem({
    ...item,
    linkedAt: item.linkedAt || now,
    updatedAt: now,
  });

  if (!normalizedItem) {
    return getUserItemCount(store, userId);
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

  return saveUserItems(store, userId, items);
}

function removeUserItem(store, userId, itemId) {
  if (!itemId) {
    return getUserItemCount(store, userId);
  }

  const nextItems = getUserItems(store, userId).filter(
    (item) => item.itemId !== itemId
  );

  return saveUserItems(store, userId, nextItems);
}

function removeAllUserItems(store, userId) {
  if (store[userId]) {
    delete store[userId];
  }
}

function getUserItemCount(store, userId) {
  return getUserItems(store, userId).length;
}

module.exports = {
  ensureUserBucket,
  getUserItems,
  saveUserItem,
  removeUserItem,
  removeAllUserItems,
  getUserItemCount,
  normalizeLinkedItem,
};
