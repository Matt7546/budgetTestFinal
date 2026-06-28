const { createJsonPlaidItemStore } = require("./jsonPlaidItemStore");

const supportedDrivers = new Set(["json", "postgres"]);

function resolveTokenStoreDriver(env = process.env) {
  const driver = (env.TOKEN_STORE_DRIVER || "json").toLowerCase();

  if (!supportedDrivers.has(driver)) {
    throw new Error("TOKEN_STORE_DRIVER must be json or postgres.");
  }

  return driver;
}

function createPlaidItemStore({ tokenStorePath, env = process.env } = {}) {
  const driver = resolveTokenStoreDriver(env);

  if (driver === "postgres") {
    if (!env.DATABASE_URL) {
      throw new Error("DATABASE_URL is required when TOKEN_STORE_DRIVER=postgres.");
    }

    if (!env.TOKEN_ENCRYPTION_KEY) {
      throw new Error("TOKEN_ENCRYPTION_KEY is required when TOKEN_STORE_DRIVER=postgres.");
    }

    const { createPostgresPlaidItemStore } = require("./postgresPlaidItemStore");

    return createPostgresPlaidItemStore({
      databaseUrl: env.DATABASE_URL,
      tokenEncryptionKey: env.TOKEN_ENCRYPTION_KEY,
    });
  }

  return createJsonPlaidItemStore({
    tokenStorePath,
  });
}

module.exports = {
  createPlaidItemStore,
  resolveTokenStoreDriver,
};
