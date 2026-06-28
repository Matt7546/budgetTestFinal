const { Pool } = require("pg");

function createPool(databaseUrl = process.env.DATABASE_URL) {
  if (!databaseUrl) {
    throw new Error("DATABASE_URL is required for Postgres token storage.");
  }

  return new Pool({
    connectionString: databaseUrl,
  });
}

module.exports = {
  createPool,
};
