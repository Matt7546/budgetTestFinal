const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const test = require("node:test");
const api = require("../validation/backend-suite-result");
const { spawnSync } = require("node:child_process");
const source = path.resolve(__dirname, "../..");
function fixture(t, body) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "caldera-structured-suite-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.writeFileSync(path.join(root, "case.test.js"), body);
  fs.mkdirSync(path.join(root, "results"));
  return { root, suite: "test:auth", files: ["case.test.js"], cwd: root,
    env: { PATH: process.env.PATH }, directory: path.join(root, "results"), runID: crypto.randomUUID() };
}
test("real passing Node test produces finalized exact-suite/process counts", (t) => {
  const f = fixture(t, "require('node:test').test('ordinary pass',()=>{});\n");
  const result = api.runFiles(f);
  assert.equal(result.exitCode, 0);
  assert.equal(result.record.childExitCode, 0);
  assert.equal(result.record.finalized, true);
  assert.deepEqual(result.record.counts, { total: 1, pass: 1, fail: 0, skip: 0, cancel: 0, todo: 0 });
  assert.deepEqual(api.readResults(f.directory, [f.suite], f.runID), [result.record]);
});
test("real skipped required test has child exit zero but structured skip rejects dispatch", (t) => {
  const f = fixture(t, "require('node:test').test('must not skip',{skip:true},()=>{});\n");
  const result = api.runFiles(f);
  assert.equal(result.record.childExitCode, 0);
  assert.equal(result.record.finalized, true);
  assert.equal(result.record.counts.skip, 1);
  assert.equal(result.exitCode, 1);
  assert.throws(() => api.readResults(f.directory, [f.suite], f.runID));
});
test("real cancelled, todo and failed tests cannot pass required validation", (t) => {
  for (const [kind, body] of [
    ["cancel", "require('node:test').test('cancelled',{timeout:10},()=>new Promise(resolve=>setTimeout(resolve,40)));"],
    ["todo", "require('node:test').test('todo',{todo:true},()=>{});"],
    ["fail", "require('node:test').test('failed',()=>{throw new Error('synthetic failure');});"],
  ]) {
    const f = fixture(t, body);
    const result = api.runFiles(f);
    assert.notEqual(result.exitCode, 0);
    assert.equal(result.record.finalized, true);
    assert.equal(result.record.counts[kind], 1);
  }
});
test("missing, malformed, unfinished and mismatched reports fail after a real zero-exit test", (t) => {
  for (const kind of ["missing", "malformed", "unfinished", "suite", "operation", "pid"]) {
    const f = fixture(t, "require('node:test').test('ordinary pass',()=>{});");
    const reporter = path.join(f.root, "reporter.cjs");
    const mutation = kind === "missing" ? "return;" : kind === "malformed" ? "yield '{'; return;" :
      `const r={version:1,suite:process.env.CALDERA_SUITE_ID,runID:process.env.CALDERA_SUITE_RUN_ID,operation:process.env.CALDERA_SUITE_OPERATION,pid:process.pid,nodeVersion:process.version,counts:{total:1,pass:1,fail:0,skip:0,cancel:0,todo:0},success:true,finalized:true};
${kind === "unfinished" ? "r.finalized=false;" : kind === "suite" ? "r.suite='test:crypto';" : kind === "operation" ? "r.operation='wrong-operation';" : "r.pid++;"}
yield JSON.stringify(r);`;
    fs.writeFileSync(reporter, `module.exports=async function*(source){for await(const e of source){} ${mutation}};`);
    const result = api.runFiles(f, { reporter });
    assert.equal(result.record.childExitCode, 0, kind);
    assert.equal(result.exitCode, 1, kind);
    assert.equal(result.record.finalized, false);
    assert.equal(result.record.counts, null);
  }
});
test("reporter exception and nonzero child with successful-looking data remain failures", (t) => {
  const f = fixture(t, "require('node:test').test('ordinary pass',()=>{});");
  const reporter = path.join(f.root, "throw.cjs");
  fs.writeFileSync(reporter, "module.exports=async function*(){throw new Error('controlled reporter failure');};");
  const result = api.runFiles(f, { reporter });
  assert.notEqual(result.exitCode, 0);
  assert.equal(result.record.finalized, false);
  const g = fixture(t, "");
  const fake = api.runFiles(g, { spawn(command, args, options) {
    const data = { version: 1, suite: g.suite, runID: g.runID, operation: options.env.CALDERA_SUITE_OPERATION,
      pid: 12345, nodeVersion: process.version, counts: { total: 1, pass: 1, fail: 0, skip: 0, cancel: 0, todo: 0 }, success: true, finalized: true };
    fs.writeFileSync(args.find(a => a.startsWith("--test-reporter-destination=") && !a.endsWith("stdout")).split("=").slice(1).join("="), JSON.stringify(data));
    return { status: 17, pid: 12345 };
  } });
  assert.equal(fake.exitCode, 17);
  assert.equal(fake.record.decision, "failed");
});
test("Node 22/24 summary fixtures have identical semantics and discard all sensitive event payloads", async () => {
  for (const nodeVersion of ["v22.23.3", "v24.19.0"]) {
    for (const skipped of [0, 1]) {
      const context = { suite: "test:auth", runID: crypto.randomUUID(), operation: crypto.randomUUID(), pid: 1234, nodeVersion };
      async function* events() {
        yield { type: "test:stdout", data: { message: "Bearer synthetic-sentinel" } };
        yield { type: "test:pass", data: { name: "PASSWORD=synthetic-sentinel", skip: skipped > 0 } };
        yield { type: "test:summary", data: { file: "/private/source", counts: { tests: 1 }, success: true } };
        yield { type: "test:summary", data: { counts: { tests: 1, passed: 1 - skipped, failed: 0, skipped, cancelled: 0, todo: 0 }, success: true } };
      }
      const report = await api.summarizeEvents(events(), context);
      assert.equal(report.finalized, true);
      assert.equal(report.counts.skip, skipped);
      assert.doesNotMatch(JSON.stringify(report), /synthetic-sentinel|private\/source|PASSWORD|Bearer/);
    }
  }
  async function* incomplete() { yield { type: "test:pass", data: {} }; }
  await assert.rejects(api.summarizeEvents(incomplete(), { suite: "test:auth", runID: crypto.randomUUID(), operation: crypto.randomUUID(), pid: 1234, nodeVersion: process.version }));
});
test("real dispatcher rejects a skipped suite before starting the next declared suite", (t) => {
  const f = fixture(t, "");
  const repo = path.join(f.root, "repo");
  fs.mkdirSync(path.join(repo, "scripts/validation"), { recursive: true });
  fs.mkdirSync(path.join(repo, "plaid-backend/scripts"), { recursive: true });
  for (const name of ["backend-test-chain.js", "backend-suite-result.js", "node-test-reporter.cjs"]) {
    fs.copyFileSync(path.join(source, "scripts/validation", name), path.join(repo, "scripts/validation", name));
  }
  fs.writeFileSync(path.join(repo, "plaid-backend/package.json"), JSON.stringify({ scripts: {
    test: "npm run test:auth && npm run test:crypto && npm run test:postgres-store",
    "test:auth": "node --test scripts/skip.js", "test:crypto": "node scripts/later.js", "test:postgres-store": "node scripts/db.js",
  } }));
  fs.writeFileSync(path.join(repo, "plaid-backend/scripts/skip.js"), "require('node:test').test('required skip',{skip:true},()=>{});");
  fs.writeFileSync(path.join(repo, "plaid-backend/scripts/later.js"), "require('node:fs').writeFileSync('must-not-exist','');");
  const result = spawnSync(process.execPath, [path.join(repo, "scripts/validation/backend-test-chain.js")], {
    env: { PATH: process.env.PATH, CALDERA_SUITE_REPORT_DIR: f.directory, CALDERA_SUITE_RUN_ID: f.runID }, encoding: "utf8" });
  assert.equal(result.status, 1);
  assert.equal(fs.existsSync(path.join(repo, "plaid-backend/must-not-exist")), false);
  const record = JSON.parse(fs.readFileSync(api.resultFile(f.directory, "test:auth")));
  assert.equal(record.childExitCode, 0);
  assert.equal(record.counts.skip, 1);
  assert.equal(record.finalized, true);
  assert.equal(record.decision, "failed");
});
