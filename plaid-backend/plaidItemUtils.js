const crypto = require("crypto");

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

function stableLegacyItemID(item) {
  const normalizedItem = normalizeLinkedItem(item);

  if (!normalizedItem) {
    return null;
  }

  if (normalizedItem.itemId) {
    return normalizedItem.itemId;
  }

  const digest = crypto
    .createHash("sha256")
    .update(normalizedItem.accessToken)
    .digest("hex");

  return `legacy-${digest.slice(0, 32)}`;
}

function stablePlaidItemRowID(userId, plaidItemId) {
  return crypto
    .createHash("sha256")
    .update(`${userId}:${plaidItemId}`)
    .digest("hex");
}

module.exports = {
  normalizeLinkedItem,
  stableLegacyItemID,
  stablePlaidItemRowID,
};
