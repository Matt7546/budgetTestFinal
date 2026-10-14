const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawnSync } = require("node:child_process");
const COUNT_KEYS = ["total", "pass", "fail", "skip", "cancel", "todo"];
const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const SUITE = /^(?:static|test:[a-z0-9-]+)$/;
const exact = (v, keys) => v && typeof v === "object" && !Array.isArray(v) &&
  Object.keys(v).length === keys.length && keys.every(k => Object.hasOwn(v, k));
function countsValid(v) {
  return exact(v, COUNT_KEYS) && COUNT_KEYS.every(k => Number.isSafeInteger(v[k]) && v[k] >= 0) &&
    v.total > 0 && v.total === v.pass + v.fail + v.skip + v.cancel + v.todo;
}
function contextValid(c) {
  return SUITE.test(c.suite) && UUID.test(c.runID) && UUID.test(c.operation) &&
    Number.isSafeInteger(c.pid) && c.pid > 0 && /^v\d+\.\d+\.\d+$/.test(c.nodeVersion);
}
async function summarizeEvents(source, context) {
  if (!contextValid(context)) throw new Error("Structured reporter context is invalid.");
  let summary;
  let interrupted = false;
  for await (const event of source) {
    if (event.type === "test:interrupted") interrupted = true;
    if (event.type === "test:summary" && event.data.file === undefined) {
      if (summary) throw new Error("Structured reporter received duplicate final summaries.");
      const c = event.data.counts;
      summary = { counts: { total: c.tests, pass: c.passed, fail: c.failed,
        skip: c.skipped, cancel: c.cancelled, todo: c.todo }, success: event.data.success };
    }
  }
  if (!summary || !countsValid(summary.counts) || typeof summary.success !== "boolean" || interrupted) {
    throw new Error("Structured reporter did not receive a valid completed run.");
  }
  // Finalization occurs only AFTER the event stream ends normally.
  return { version: 1, ...context, ...summary, finalized: true };
}
function rawValid(raw, context) {
  return exact(raw, ["version", "suite", "runID", "operation", "pid", "nodeVersion", "counts", "success", "finalized"]) &&
    raw.version === 1 && raw.finalized === true && typeof raw.success === "boolean" &&
    contextValid(raw) && ["suite", "runID", "operation", "pid", "nodeVersion"].every(k => raw[k] === context[k]) && countsValid(raw.counts);
}
function passed(record) {
  return record.finalized === true && record.childExitCode === 0 && record.success === true &&
    countsValid(record.counts) && ["fail", "skip", "cancel", "todo"].every(k => record.counts[k] === 0);
}
function recordValid(v, suite, runID) {
  return exact(v, ["version", "suite", "runID", "operation", "pid", "nodeVersion", "counts", "success", "finalized", "childExitCode", "decision"]) &&
    v.version === 1 && v.suite === suite && v.runID === runID && contextValid(v) &&
    Number.isInteger(v.childExitCode) && typeof v.finalized === "boolean" && typeof v.success === "boolean" &&
    (v.finalized ? countsValid(v.counts) : v.counts === null && v.success === false) &&
    v.decision === (passed(v) ? "passed" : "failed");
}
function resultFile(directory, suite) { return path.join(directory, suite.replace(":", "-") + ".json"); }
function writeRecord(directory, record) {
  if (!recordValid(record, record.suite, record.runID)) throw new Error("Structured suite record is invalid.");
  fs.writeFileSync(resultFile(directory, record.suite), JSON.stringify(record, null, 2) + "\n", { flag: "wx", mode: 0o600 });
}
function readResults(directory, suites, runID) {
  if (!UUID.test(runID)) throw new Error("Structured gate identity is invalid.");
  return suites.map(suite => {
    const record = JSON.parse(fs.readFileSync(resultFile(directory, suite), "utf8"));
    if (!recordValid(record, suite, runID) || !passed(record)) throw new Error("Required structured suite evidence did not pass.");
    return record;
  });
}
function runFiles({ suite, files, cwd, env = process.env, directory = env.CALDERA_SUITE_REPORT_DIR, runID = env.CALDERA_SUITE_RUN_ID }, deps = {}) {
  let owned;
  if (!directory) { owned = fs.mkdtempSync(path.join(os.tmpdir(), "caldera-suite-results-")); directory = owned; }
  runID ||= crypto.randomUUID();
  const operation = crypto.randomUUID();
  if (!SUITE.test(suite) || !UUID.test(runID)) throw new Error("Structured suite invocation is invalid.");
  const rawFile = path.join(directory, `.${suite.replace(":", "-")}.${operation}.raw.json`);
  try {
    // Reserve a fresh private file. Stale evidence cannot satisfy this invocation.
    fs.writeFileSync(rawFile, "", { flag: "wx", mode: 0o600 });
    const childEnv = { ...env, CALDERA_SUITE_ID: suite, CALDERA_SUITE_RUN_ID: runID, CALDERA_SUITE_OPERATION: operation };
    const child = (deps.spawn || spawnSync)(process.execPath, ["--test",
      "--test-reporter=tap", "--test-reporter-destination=stdout",
      `--test-reporter=${deps.reporter || path.join(__dirname, "node-test-reporter.cjs")}`,
      `--test-reporter-destination=${rawFile}`, ...files], { cwd, env: childEnv, stdio: "inherit", timeout: 120_000 });
    const context = { suite, runID, operation, pid: child.pid, nodeVersion: process.version };
    let raw;
    try { raw = JSON.parse(fs.readFileSync(rawFile, "utf8")); } catch { /* Never echo rejected evidence. */ }
    const valid = Boolean(rawValid(raw, context));
    const record = { version: 1, ...context, counts: valid ? raw.counts : null,
      success: valid ? raw.success : false, finalized: valid,
      childExitCode: child.status ?? 1 };
    record.decision = passed(record) ? "passed" : "failed";
    if (contextValid(context)) writeRecord(directory, record);
    const exitCode = child.status !== 0 ? child.status || 1 : record.decision === "passed" ? 0 : 1;
    if (exitCode !== 0) console.error(`Required structured suite failed: ${suite}.`);
    return { exitCode, record };
  } finally {
    if (owned) fs.rmSync(owned, { recursive: true, force: true });
  }
}
module.exports = { COUNT_KEYS, summarizeEvents, countsValid, rawValid, recordValid, passed,
  resultFile, writeRecord, readResults, runFiles };
