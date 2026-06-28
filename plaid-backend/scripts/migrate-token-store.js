const dotenv = require("dotenv");
const path = require("path");
const { createPostgresPlaidItemStore } = require("../postgresPlaidItemStore");
const { importJsonTokenStoreToPostgres } = require("../tokenStoreMigration");

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

async function run() {
  const postgresStore = createPostgresPlaidItemStore();

  try {
    await postgresStore.ensureSchema();
    await importJsonTokenStoreToPostgres({
      sourcePath: tokenStorePath(),
      postgresStore,
    });
    console.log("JSON token store was left unchanged.");
  } finally {
    await postgresStore.close?.();
  }
}

run().catch((error) => {
  console.error(`Token store migration failed: ${error.message}`);
  process.exit(1);
});
