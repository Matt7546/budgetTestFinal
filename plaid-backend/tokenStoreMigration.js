const fs = require("fs");
const { normalizeLinkedItem } = require("./plaidItemUtils");

function itemsForRecord(record) {
  if (!record) {
    return [];
  }

  if (Array.isArray(record.items)) {
    return record.items.map(normalizeLinkedItem).filter(Boolean);
  }

  const legacyItem = normalizeLinkedItem(record);

  return legacyItem ? [legacyItem] : [];
}

async function importJsonTokenStoreToPostgres({
  sourcePath,
  postgresStore,
  log = console.log,
}) {
  if (!fs.existsSync(sourcePath)) {
    log("JSON token store import skipped: source file not found.");
    return {
      users: 0,
      items: 0,
      skipped: true,
    };
  }

  const jsonStore = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
  let userCount = 0;
  let itemCount = 0;

  for (const [userId, userRecord] of Object.entries(jsonStore)) {
    const items = itemsForRecord(userRecord);

    if (items.length === 0) {
      continue;
    }

    userCount += 1;

    for (const item of items) {
      await postgresStore.saveUserItem(userId, item);
      itemCount += 1;
    }
  }

  log(`Imported ${userCount} user${userCount === 1 ? "" : "s"} and ${itemCount} Plaid item${itemCount === 1 ? "" : "s"}.`);

  return {
    users: userCount,
    items: itemCount,
    skipped: false,
  };
}

module.exports = {
  importJsonTokenStoreToPostgres,
  itemsForRecord,
};
