const dotenv = require("dotenv");
const fs = require("fs");
const path = require("path");
const { createPostgresPlaidItemStore } = require("../postgresPlaidItemStore");
const { normalizeLinkedItem } = require("../plaidItemUtils");

dotenv.config();

function tokenStorePath() {
  const configuredPath = process.env.PLAID_TOKEN_STORE_PATH;

  if (configuredPath) {
    return path.isAbsolute(configuredPath)
      ? configuredPath
      : path.join(__dirname, "..", configuredPath);
  }

  return path.join(__dirname, "..", ".plaid-token-store.json");
}

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

async function run() {
  const sourcePath = tokenStorePath();

  if (!fs.existsSync(sourcePath)) {
    console.log("No JSON token store found; nothing to migrate.");
    return;
  }

  const jsonStore = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
  const postgresStore = createPostgresPlaidItemStore();
  let userCount = 0;
  let itemCount = 0;

  try {
    await postgresStore.ensureSchema();

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

    console.log(`Migrated Plaid item namespaces: users=${userCount} items=${itemCount}`);
    console.log("JSON token store was left unchanged.");
  } finally {
    await postgresStore.close?.();
  }
}

run().catch((error) => {
  console.error(`Token store migration failed: ${error.message}`);
  process.exit(1);
});
