const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { spawnSync } = require("node:child_process");
const test = require("node:test");
const { declaredTests } = require("../validation/backend-test-chain");
const source = path.resolve(__dirname, "../..");
const pkg = JSON.parse(fs.readFileSync(path.join(source, "plaid-backend/package.json")));

test("every declared npm test suite is retained in order with Postgres last", () => {
  assert.deepEqual(declaredTests(pkg), pkg.scripts.test.split(" && ").map((s) => s.slice("npm run ".length)));
  assert.equal(declaredTests(pkg).length, 13);
  assert.equal(declaredTests(pkg).at(-1), "test:postgres-store");
});
test("unsupported, missing, duplicate, or reordered required suites fail closed", () => {
  for (const chain of ["npm run test:auth; npm run test:postgres-store", "npm run test:missing && npm run test:postgres-store",
    "npm run test:auth && npm run test:auth && npm run test:postgres-store",
    "npm run test:postgres-store && npm run test:auth", "npm run test:auth", ""]) {
    assert.throws(() => declaredTests({ scripts: { ...pkg.scripts, test: chain } }));
  }
});
test("actual chain dispatcher runs all non-DB npm suites without a database exception and preserves failure exit", (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "caldera-chain-test-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const repo = path.join(root, "repo");
  fs.mkdirSync(path.join(repo, "scripts/validation"), { recursive: true });
  fs.mkdirSync(path.join(repo, "plaid-backend"));
  for (const name of ["backend-test-chain.js", "backend-suite-result.js", "node-test-reporter.cjs"]) {
    fs.copyFileSync(path.join(source, "scripts/validation", name), path.join(repo, "scripts/validation", name));
  }
  const fixturePackage = { scripts: { ...pkg.scripts } };
  const log = path.join(root, "calls.jsonl");
  fs.mkdirSync(path.join(repo, "plaid-backend/scripts"));
  for (const suite of declaredTests(pkg)) {
    const file = `scripts/${suite.replace(":", "-")}.js`;
    fixturePackage.scripts[suite] = `node ${file}`;
    fs.writeFileSync(path.join(repo, "plaid-backend", file), `
const fs=require('node:fs');
fs.appendFileSync(${JSON.stringify(log)},JSON.stringify({suite:${JSON.stringify(suite)},db:process.env.DATABASE_URL,auth:process.env.CALDERA_POSTGRES_TEST_CONFIRM,key:process.env.TOKEN_ENCRYPTION_KEY})+'\\n');
if(${JSON.stringify(suite)}===process.env.SYNTHETIC_FAIL_SUITE)process.exit(17);
`);
  }
  fs.writeFileSync(path.join(repo, "plaid-backend/package.json"), JSON.stringify(fixturePackage));
  const command = path.join(repo, "scripts/validation/backend-test-chain.js");
  const env = { PATH: process.env.PATH };
  assert.equal(spawnSync(process.execPath, [command], { env }).status, 0);
  const calls = fs.readFileSync(log, "utf8").trim().split("\n").map(JSON.parse);
  assert.deepEqual(calls.map((c) => c.suite), declaredTests(pkg).slice(0, -1));
  assert.ok(calls.every((c) => c.db === undefined && c.auth === undefined && c.key === undefined));
  fs.writeFileSync(log, "");
  assert.notEqual(spawnSync(process.execPath, [command], { env: { ...env, SYNTHETIC_FAIL_SUITE: "test:crypto" } }).status, 0);
  assert.equal(fs.readFileSync(log, "utf8").trim().split("\n").length, 3);
  fs.writeFileSync(log, "");
  assert.equal(spawnSync(process.execPath, [command], { env: { ...env, CALDERA_POSTGRES_TEST_CONFIRM: "disposable-loopback-cluster" } }).status, 1);
  assert.equal(fs.readFileSync(log, "utf8"), "");
});
