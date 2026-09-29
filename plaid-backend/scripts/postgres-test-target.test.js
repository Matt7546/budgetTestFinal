const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const {
  DISPOSABLE_CONFIRMATION,
  requireDisposableTarget,
  assertDisposableTarget,
} = require("./postgres-test-target");

function fixture(t) {
  const clusterRoot = fs.mkdtempSync(path.join(os.tmpdir(), "caldera-pg-test-"));
  const dataDirectory = path.join(clusterRoot, "data");
  fs.mkdirSync(dataDirectory);
  fs.writeFileSync(path.join(dataDirectory, "PG_VERSION"), "17\n");
  t.after(() => fs.rmSync(clusterRoot, { recursive: true, force: true }));
  const databaseName = "caldera_validation_12345678";
  return {
    clusterRoot,
    dataDirectory,
    env: {
      CALDERA_POSTGRES_TEST_CONFIRM: DISPOSABLE_CONFIRMATION,
      CALDERA_POSTGRES_TEST_CLUSTER_DIR: clusterRoot,
      CALDERA_POSTGRES_TEST_DATABASE: databaseName,
      DATABASE_URL: `postgresql://127.0.0.1:55439/${databaseName}`,
      TOKEN_ENCRYPTION_KEY: "test-key-placeholder",
    },
  };
}

test("a disposable loopback target requires every explicit prerequisite", (t) => {
  const { env } = fixture(t);
  assert.equal(requireDisposableTarget(env).databaseName, env.CALDERA_POSTGRES_TEST_DATABASE);
  for (const key of Object.keys(env)) {
    const missing = { ...env };
    delete missing[key];
    assert.throws(() => requireDisposableTarget(missing), Error, key);
  }
});

test("a matching database name does not authorize a remote or ambiguous URL", (t) => {
  const { env } = fixture(t);
  for (const databaseUrl of [
    "postgresql://production.example:55439/caldera_validation_12345678",
    "postgresql://localhost:55439/caldera_validation_12345678",
    "postgresql://127.0.0.1:5432/caldera_validation_12345678",
    "postgresql://127.0.0.1:55439/caldera_validation_12345678?host=production.example",
    "postgresql://127.0.0.1:55439/application_data",
  ]) {
    assert.throws(() => requireDisposableTarget({ ...env, DATABASE_URL: databaseUrl }));
  }
  assert.throws(() => requireDisposableTarget({
    ...env,
    CALDERA_POSTGRES_TEST_DATABASE: "caldera_validation_different",
  }));
});

test("a missing or unowned cluster proof fails before database use", (t) => {
  const { env } = fixture(t);
  assert.throws(() => requireDisposableTarget({
    ...env,
    CALDERA_POSTGRES_TEST_CLUSTER_DIR: path.dirname(env.CALDERA_POSTGRES_TEST_CLUSTER_DIR),
  }));
});

test("server identity and empty-database checks issue read-only SQL first", async (t) => {
  const { env, dataDirectory } = fixture(t);
  const target = requireDisposableTarget(env);
  const commands = [];
  const pool = {
    async query(sql) {
      commands.push(sql.trim());
      if (commands.length === 1) {
        return { rows: [{
          database_name: target.databaseName,
          data_directory: dataDirectory,
          listen_addresses: "127.0.0.1",
          server_address: "127.0.0.1",
        }] };
      }
      return { rows: [{ count: 0 }] };
    },
  };
  await assertDisposableTarget(pool, target);
  assert.equal(commands.length, 2);
  assert(commands.every((sql) => /^SELECT\b/.test(sql)));
});

test("server mismatch and existing relations reject before mutation", async (t) => {
  const { env, dataDirectory } = fixture(t);
  const target = requireDisposableTarget(env);
  const identity = {
    database_name: target.databaseName,
    data_directory: dataDirectory,
    listen_addresses: "127.0.0.1",
    server_address: "127.0.0.1",
  };
  await assert.rejects(assertDisposableTarget({
    query: async () => ({ rows: [{ ...identity, data_directory: "/var/lib/postgresql" }] }),
  }, target));
  const commands = [];
  await assert.rejects(assertDisposableTarget({
    async query(sql) {
      commands.push(sql.trim());
      return { rows: commands.length === 1 ? [identity] : [{ count: 1 }] };
    },
  }, target));
  assert(commands.every((sql) => /^SELECT\b/.test(sql)));
});

test("the executable fails closed without authorization before loading database modules", (t) => {
  const { env } = fixture(t);
  const result = spawnSync(process.execPath, [path.join(__dirname, "postgres-store-check.js")], {
    encoding: "utf8",
    env: { PATH: process.env.PATH, ...env, CALDERA_POSTGRES_TEST_CONFIRM: "" },
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Explicit disposable Postgres test authorization is required/);
  assert.doesNotMatch(result.stdout + result.stderr, /Skipping|DATABASE_URL=.*postgresql/i);
});
