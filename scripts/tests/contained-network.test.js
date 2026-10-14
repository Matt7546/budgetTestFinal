const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");
const guard = path.resolve(__dirname, "../validation/contained-network.cjs");
const confirmation = "disposable-loopback-cluster";

function target(t, tempRoot = os.tmpdir()) {
  const selected = fs.realpathSync(tempRoot);
  const root = fs.mkdtempSync(path.join(selected, "caldera-pg-test-"));
  fs.mkdirSync(path.join(root, "data"));
  fs.writeFileSync(path.join(root, "data/PG_VERSION"), "17\n");
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return { TMPDIR: selected, CALDERA_POSTGRES_TEST_CONFIRM: confirmation,
    CALDERA_POSTGRES_TEST_CLUSTER_DIR: root,
    CALDERA_POSTGRES_TEST_DATABASE: "caldera_validation_12345678",
    TOKEN_ENCRYPTION_KEY: "synthetic-key",
    DATABASE_URL: "postgresql://127.0.0.1:55439/caldera_validation_12345678" };
}
function probe(env, action = "") {
  // Spies are installed BEFORE the production preload. An allowed call reaches
  // the spy; a rejected call must never reach any real socket/DNS implementation.
  return spawnSync(process.execPath, ["-e", `const net=require('node:net'),dns=require('node:dns');
let sockets=0,lookups=0;
net.Socket.prototype.connect=function(){sockets++;return this;};
dns.lookup=function(){lookups++;};
process.on('exit',()=>process.stdout.write(JSON.stringify({sockets,lookups})));
require(${JSON.stringify(guard)});
${action}`], { env: { PATH: process.env.PATH, ...env }, encoding: "utf8" });
}
function denied(result, counts = { sockets: 0, lookups: 0 }) {
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Validation blocked/);
  assert.doesNotMatch(result.stderr, /ERR_INVALID_URL/);
  assert.deepEqual(JSON.parse(result.stdout), counts);
}
test("no DB authorization initializes safely and denies original socket/DNS attempts before dispatch", () => {
  const empty = probe({});
  assert.equal(empty.status, 0);
  assert.deepEqual(JSON.parse(empty.stdout), { sockets: 0, lookups: 0 });
  for (const action of ["new net.Socket().connect({host:'example.invalid',port:443});",
    "dns.lookup('example.invalid',()=>{});", "new net.Socket().connect({host:'127.0.0.1',port:5432});"]) denied(probe({}, action));
});
test("DB authorization with missing URL fails safely before any network call", () => {
  denied(probe({ CALDERA_POSTGRES_TEST_CONFIRM: confirmation }));
});
test("malformed credential-bearing DB URLs never escape diagnostics", (t) => {
  const env = target(t);
  for (const url of ["synthetic-sensitive-url", "postgresql://synthetic-user:synthetic-password@["]) {
    const result = probe({ ...env, DATABASE_URL: url });
    denied(result);
    assert.doesNotMatch(result.stderr + result.stdout, /synthetic-sensitive-url|synthetic-user|synthetic-password/);
  }
});
test("a DB URL without exact authorization cannot permit a database socket", (t) => {
  const env = target(t);
  delete env.CALDERA_POSTGRES_TEST_CONFIRM;
  for (const confirmation of [undefined, "not-authorized"]) {
    denied(probe({ ...env, ...(confirmation ? { CALDERA_POSTGRES_TEST_CONFIRM: confirmation } : {}) },
      "new net.Socket().connect({host:'127.0.0.1',port:55439});"));
  }
});
test("guarded exact loopback target alone reaches the connection implementation", (t) => {
  const result = probe(target(t), "new net.Socket().connect({host:'127.0.0.1',port:55439});");
  assert.equal(result.status, 0);
  assert.equal(result.stderr, "");
  assert.deepEqual(JSON.parse(result.stdout), { sockets: 1, lookups: 0 });
});
test("guarded DB target still rejects external socket/DNS and unrelated loopback ports", (t) => {
  const env = target(t);
  for (const action of ["new net.Socket().connect({host:'example.invalid',port:55439});",
    "dns.lookup('example.invalid',()=>{});", "new net.Socket().connect({host:'127.0.0.1',port:55440});",
    "new net.Socket().connect({host:'localhost',port:55439});"]) denied(probe(env, action));
});
test("authorization cannot bypass exact URL, database, or owned temp-cluster guards", (t) => {
  const env = target(t);
  for (const changes of [
    { DATABASE_URL: "postgresql://localhost:55439/caldera_validation_12345678" },
    { DATABASE_URL: "postgresql://127.0.0.1:5432/caldera_validation_12345678" },
    { DATABASE_URL: "postgresql://127.0.0.1:55439/caldera_validation_12345678?host=example.invalid" },
    { CALDERA_POSTGRES_TEST_DATABASE: "caldera_validation_87654321" },
    { CALDERA_POSTGRES_TEST_CLUSTER_DIR: path.dirname(env.CALDERA_POSTGRES_TEST_CLUSTER_DIR) },
    { TOKEN_ENCRYPTION_KEY: "" },
  ]) denied(probe({ ...env, ...changes }));
});
function customTemp(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "caldera custom tmp "));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return fs.realpathSync(root);
}
test("custom TMPDIR with spaces shares one canonical root and still fences unrelated ports", (t) => {
  const selected = customTemp(t);
  const env = target(t, selected);
  assert.equal(env.TMPDIR, selected);
  const allowed = probe(env, "new net.Socket().connect({host:'127.0.0.1',port:55439});");
  assert.equal(allowed.status, 0);
  assert.deepEqual(JSON.parse(allowed.stdout), { sockets: 1, lookups: 0 });
  denied(probe(env, "new net.Socket().connect({host:'127.0.0.1',port:55440});"));
});
test("a different or missing custom TMPDIR cannot authorize a target outside the child's allowed roots", (t) => {
  const env = target(t, customTemp(t));
  denied(probe({ ...env, TMPDIR: customTemp(t) }));
  const missing = { ...env }; delete missing.TMPDIR;
  denied(probe(missing));
});
test("missing TMPDIR uses the documented /tmp fallback; unusable roots fail without credential echo", (t) => {
  const env = target(t, "/tmp");
  delete env.TMPDIR;
  assert.equal(probe(env, "new net.Socket().connect({host:'127.0.0.1',port:55439});").status, 0);
  const custom = target(t, customTemp(t));
  for (const TMPDIR of ["/path-that-does-not-exist-for-caldera-validation", custom.CALDERA_POSTGRES_TEST_CLUSTER_DIR + "/data/PG_VERSION"]) {
    const result = probe({ ...custom, TMPDIR, DATABASE_URL: "postgresql://synthetic-user:synthetic-password@127.0.0.1:55439/caldera_validation_12345678" });
    denied(result);
    assert.doesNotMatch(result.stdout + result.stderr, /synthetic-user|synthetic-password/);
  }
});
