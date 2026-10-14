const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const DISPOSABLE_CONFIRMATION = "disposable-loopback-cluster";

function requireDisposableTarget(env = process.env) {
  if (env.CALDERA_POSTGRES_TEST_CONFIRM !== DISPOSABLE_CONFIRMATION) {
    throw new Error("Explicit disposable Postgres test authorization is required.");
  }
  if (!env.DATABASE_URL || !env.TOKEN_ENCRYPTION_KEY ||
      !env.CALDERA_POSTGRES_TEST_DATABASE ||
      !env.CALDERA_POSTGRES_TEST_CLUSTER_DIR) {
    throw new Error("Postgres test URL, encryption key, database, and cluster directory are required.");
  }

  let url;
  try {
    url = new URL(env.DATABASE_URL);
  } catch {
    throw new Error("Postgres test URL is invalid.");
  }
  const databaseName = url.pathname.slice(1);
  const port = Number(url.port);
  if (!["postgres:", "postgresql:"].includes(url.protocol) ||
      url.hostname !== "127.0.0.1" ||
      !Number.isInteger(port) || port <= 1024 || port === 5432 ||
      port > 65535 || url.search || url.hash ||
      !/^caldera_validation_[a-f0-9]{8,}$/.test(databaseName) ||
      databaseName !== env.CALDERA_POSTGRES_TEST_DATABASE) {
    throw new Error("Postgres test target must be an exact named database on an explicit loopback port.");
  }

  let clusterRoot;
  let dataDirectory;
  try {
    clusterRoot = fs.realpathSync(env.CALDERA_POSTGRES_TEST_CLUSTER_DIR);
    dataDirectory = fs.realpathSync(path.join(clusterRoot, "data"));
    const allowedParents = new Set([
      fs.realpathSync(os.tmpdir()),
      fs.realpathSync("/tmp"),
    ]);
    if (!allowedParents.has(path.dirname(clusterRoot)) ||
        !path.basename(clusterRoot).startsWith("caldera-pg-test-") ||
        path.dirname(dataDirectory) !== clusterRoot ||
        !fs.statSync(clusterRoot).isDirectory() ||
        !fs.statSync(dataDirectory).isDirectory() ||
        !fs.statSync(path.join(dataDirectory, "PG_VERSION")).isFile() ||
        (process.getuid &&
          (fs.statSync(clusterRoot).uid !== process.getuid() ||
           fs.statSync(dataDirectory).uid !== process.getuid()))) {
      throw new Error("Postgres test cluster is not a user-owned disposable temp cluster.");
    }
  } catch {
    throw new Error("Postgres test cluster is not a user-owned disposable temp cluster.");
  }

  return {
    databaseUrl: env.DATABASE_URL,
    databaseName,
    dataDirectory,
  };
}

async function assertDisposableTarget(pool, target) {
  const identity = await pool.query(`
    SELECT current_database() AS database_name,
           current_setting('data_directory') AS data_directory,
           current_setting('listen_addresses') AS listen_addresses,
           host(inet_server_addr()) AS server_address
  `);
  const row = identity.rows[0];
  if (identity.rows.length !== 1 ||
      !row ||
      row.database_name !== target.databaseName ||
      row.server_address !== "127.0.0.1" ||
      row.listen_addresses !== "127.0.0.1" ||
      fs.realpathSync(row.data_directory) !== target.dataDirectory) {
    throw new Error("Connected Postgres server does not match the disposable loopback cluster.");
  }

  const relations = await pool.query(`
    SELECT count(*)::integer AS count
      FROM pg_class AS relation
      JOIN pg_namespace AS namespace ON namespace.oid = relation.relnamespace
     WHERE namespace.nspname NOT IN ('pg_catalog', 'information_schema')
       AND namespace.nspname NOT LIKE 'pg_toast%'
       AND relation.relkind IN ('r', 'p', 'm', 'f')
  `);
  if (relations.rows.length !== 1 || relations.rows[0].count !== 0) {
    throw new Error("Postgres test database must be newly created and empty.");
  }
}

module.exports = {
  DISPOSABLE_CONFIRMATION,
  requireDisposableTarget,
  assertDisposableTarget,
};
