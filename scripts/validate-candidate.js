#!/usr/bin/env node
// Platform checks share this exact-source/evidence contract. No deployment code.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawnSync } = require("node:child_process");
const { failureReport, unavailableReport, prepareFailurePublication } = require("./validation/backend-failure-evidence");
const { declaredTests } = require("./validation/backend-test-chain");
const { readResults, recordValid, passed, resultFile } = require("./validation/backend-suite-result");

const VERSION = 1;
const BLOCKERS = ["F15", "PHYSICAL_IOS_26_1"];
const GATES = {
  backend: ["static", "backend-chain", "postgres-startup"],
  ios: ["debug-build", "rc-build", "ios-contract", "ios-stable", "ios-hold", "ios-mounted", "ios-production"],
};
const digest = (data) => crypto.createHash("sha256").update(data).digest("hex");
function git(repo, args) {
  const result = spawnSync("git", args, { cwd: repo, encoding: "utf8" });
  if (result.status !== 0) throw new Error("Required Git identity check failed.");
  return result.stdout.trim();
}
function identity(repo, env = process.env) {
  const commit = git(repo, ["rev-parse", "HEAD"]);
  const dirty = git(repo, ["status", "--porcelain=v1", "--untracked-files=all"]) !== "";
  if (!/^[a-f0-9]{40}$/.test(commit)) throw new Error("Invalid candidate SHA.");
  if (env.GITHUB_ACTIONS === "true" && env.GITHUB_SHA !== commit) {
    throw new Error("Checked-out SHA does not match GITHUB_SHA.");
  }
  return { commit, ref: env.GITHUB_REF || git(repo, ["branch", "--show-current"]) || "detached", dirty };
}
function policy(repo) {
  const bytes = fs.readFileSync(path.join(repo, "scripts/release-gates.json"));
  const config = JSON.parse(bytes);
  if (config.version !== VERSION || !Array.isArray(config.blockers) ||
      JSON.stringify(config.blockers.map((b) => b.id).sort()) !== JSON.stringify(BLOCKERS) ||
      config.blockers.some((b) => !["open", "closed"].includes(b.status) ||
        typeof b.reason !== "string" || !b.reason.trim())) {
    throw new Error("Release-blocker configuration is missing, incomplete, or unsupported.");
  }
  for (const name of ["contract", "stable", "hold", "mounted", "production"]) {
    const suite = config.ios?.[name];
    if (!suite || !Number.isInteger(suite.total) || suite.total <= 0 ||
        !Number.isInteger(suite.passed) || !Number.isInteger(suite.expectedFailures) ||
        suite.passed < 0 || suite.expectedFailures < 0 ||
        suite.passed + suite.expectedFailures !== suite.total ||
        !Array.isArray(suite.selection) || !suite.selection.length ||
        new Set(suite.selection).size !== suite.selection.length ||
        suite.selection.some((s) => typeof s !== "string" || !/^[A-Za-z0-9_/]+$/.test(s))) {
      throw new Error("Contained iOS gate configuration is invalid.");
    }
    // Whole-target and diagnostic selections cannot become release evidence.
    // Only the named transport contracts and accepted auth group are whole classes.
    const accepted = /^(?:AuthEnvironmentSessionTests|(?:BankDataRequestCacheIsolationTests|CardPaymentDetailsSessionIsolationTests|CorePlanningUserIsolationTests|KeychainEnvironmentSessionTests|HostedHoldLifecycleTests|OrdinaryProductionCompatibilityTests|MountedPlanningValidationTests)\/test[A-Za-z0-9_]+)$/;
    if (name === "contract" ? JSON.stringify(suite.selection) !== '["ContainedTestTransportTests"]'
      : suite.selection.some((s) => !accepted.test(s))) {
      throw new Error("Stable iOS selection includes an unaccepted or diagnostic test.");
    }
  }
  return { config, hash: digest(bytes) };
}
function hasSkip(log) {
  return /^(?:#\s*(?:skipped|todo|cancelled)\s+[1-9]\d*\b|\s*SKIP(?:PED)?\b|(?:not ok|ok)\s+\d+[^\n]*#\s*(?:SKIP|TODO)\b)/mi.test(log);
}
function testSummary(value, expected) {
  if (value.result !== "Passed" || value.totalTestCount !== expected.total ||
      value.passedTests !== expected.passed || value.expectedFailures !== expected.expectedFailures ||
      value.failedTests !== 0 || value.skippedTests !== 0) {
    throw new Error("Contained XCTest counts did not match the required zero-skip selection.");
  }
  // Never publish testFailures, diagnostics, or financial/provider payloads.
  return Object.fromEntries(["totalTestCount", "passedTests", "expectedFailures", "failedTests", "skippedTests"]
    .map((key) => [key, value[key]]));
}
function commands(repo, mode, options, config) {
  if (mode === "backend") return [
    ["static", "node", [path.join(repo, "scripts/validation/static-check.js")]],
    ["backend-chain", "bash", [path.join(repo, "scripts/validation/disposable-postgres.sh"), "chain"]],
    ["postgres-startup", "bash", [path.join(repo, "scripts/validation/disposable-postgres.sh"), "startup"]],
  ];
  if (!options.packages || !options.simulator || !/^[A-Fa-f0-9-]{36}$/.test(options.simulator)) {
    throw new Error("iOS gate requires an offline package directory and disposable simulator UUID.");
  }
  const common = ["-derivedDataPath", path.join(options.evidence, "BuildData"),
    "-clonedSourcePackagesDirPath", path.resolve(options.packages), "-disableAutomaticPackageResolution",
    "-skipPackageUpdates", "-onlyUsePackageVersionsFromResolvedFile", "APP_API_KEY="];
  return [
    ["debug-build", "bash", [path.join(repo, "scripts/build-debug.sh"), ...common]],
    ["rc-build", "bash", [path.join(repo, "scripts/build-release.sh"), ...common]],
    ...["contract", "stable", "hold", "mounted", "production"].map((suite) => [`ios-${suite}`, "bash", [
      path.join(repo, "scripts/test-contained-ios.sh"), options.simulator,
      path.join(options.evidence, suite), path.resolve(options.packages), ...config.ios[suite].selection,
    ]]),
  ];
}
function run(command, args, options) {
  const fd = fs.openSync(options.log, "w", 0o600);
  try {
    const result = spawnSync(command, args, { cwd: options.repo, env: options.env, stdio: ["ignore", fd, fd] });
    return result.status ?? 1;
  } finally { fs.closeSync(fd); }
}
function backendEnvironment(id, env) {
  // Git/SHA attribution uses the original environment above; test children
  // receive no application credentials or inherited database exception.
  const child = {};
  for (const key of ["PATH", "TMPDIR"]) if (env[key] !== undefined) child[key] = env[key];
  if (id !== "static") for (const key of ["CALDERA_DISPOSABLE_POSTGRES_CONFIRM", "CALDERA_POSTGRES_BIN"]) {
    if (env[key] !== undefined) child[key] = env[key];
  }
  return child;
}
function backendSuites(repo, id) {
  if (id === "static") return ["static"];
  if (id === "postgres-startup") return ["test:startup-postgres"];
  return declaredTests(JSON.parse(fs.readFileSync(path.join(repo, "plaid-backend/package.json"))));
}
function summarize(manifest) {
  const required = manifest.mode === "aggregate" ? Object.values(GATES).flat() : GATES[manifest.mode];
  const checksPassed = manifest.finalized === true &&
    JSON.stringify(manifest.gates.map((g) => g.id)) === JSON.stringify(required) &&
    manifest.gates.every((gate) => gate.status === "passed");
  const open = manifest.blockers.filter((b) => b.status === "open");
  manifest.checksPassed = checksPassed;
  manifest.releaseReady = manifest.mode === "aggregate" && checksPassed && open.length === 0;
  manifest.summary = checksPassed ? "VALIDATION CHECKS PASSED" : "VALIDATION CHECKS FAILED";
  if (open.length) manifest.summary += `\nBUT RELEASE READINESS BLOCKED BY: ${open.map((b) => b.id).join(", ")}`;
  else if (manifest.mode !== "aggregate") manifest.summary += "\nRelease decision requires both platform manifests.";
  else if (checksPassed) manifest.summary += "\nConfigured candidate gates cleared; archive/provider/deployment approval is separate.";
}
function safeLog(id, exitCode, raw) {
  // Raw output stays private. Safe failure fields live in a separate bounded
  // backend failure report; this log retains only fixed milestones/counts.
  const milestones = ["Rate limit checks passed.", "User-scoped Plaid item store check passed.",
    "Token crypto check passed.", "Auth scaffolding check passed.",
    "Delete account and disconnect hardening check passed.", "Item lifecycle Express/JSON race check passed.",
    "Card payment details checks passed.", "Bank Sync Item recovery checks passed.",
    "Transaction snapshot checks passed.", "Transaction provider evidence checks passed.",
    "Static and validation-contract checks passed.", "Postgres Plaid item store check passed.",
    "Guarded real backend Postgres startup passed: migrations, required auth, disabled dev auth, no provider requests.",
    "** BUILD SUCCEEDED **", "** TEST SUCCEEDED **"];
  const lines = raw.split(/\r?\n/).filter((line) => milestones.includes(line) ||
    /^# (tests|pass|fail|cancelled|skipped|todo) \d+$/.test(line));
  return `Gate: ${id}\nExit: ${exitCode}\n${lines.join("\n")}\n`;
}
function freshEvidence(repo, value) {
  const requested = path.resolve(value);
  const resolved = path.join(fs.realpathSync(path.dirname(requested)), path.basename(requested));
  const root = fs.realpathSync(repo);
  if (resolved === root || resolved.startsWith(root + path.sep) || fs.existsSync(resolved)) {
    throw new Error("Evidence must be a fresh directory outside the repository.");
  }
  return resolved;
}
function writeManifest(file, value) {
  writeJSONBytes(file, JSON.stringify(value, null, 2) + "\n");
}
function writeJSONBytes(file, serialized) {
  // Readers see the previous complete JSON or the new complete JSON, never a
  // partially replaced final manifest. An abandoned temporary file is not input.
  const temporary = path.join(path.dirname(file), `.${path.basename(file)}.${crypto.randomUUID()}.tmp`);
  let fd;
  try {
    fd = fs.openSync(temporary, "wx", 0o600);
    fs.writeFileSync(fd, serialized);
    fs.fsyncSync(fd);
    fs.closeSync(fd);
    fd = undefined;
    fs.renameSync(temporary, file);
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
    if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
  }
}
function dependencyResults(env) {
  const keys = ["CALDERA_BACKEND_JOB_RESULT", "CALDERA_IOS_JOB_RESULT", "CALDERA_ARTIFACT_DOWNLOAD_RESULT"];
  if (env.GITHUB_ACTIONS !== "true" && keys.every((key) => env[key] === undefined)) return undefined;
  const normalize = (value) => ["success", "failure", "skipped", "cancelled"].includes(value)
    ? value : value === undefined || value === "" ? "missing" : "unexpected";
  return { backend: normalize(env[keys[0]]), ios: normalize(env[keys[1]]),
    artifactDownload: normalize(env[keys[2]]) };
}
function execute(options, deps = {}) {
  const repo = path.resolve(options.repo);
  const source = identity(repo, deps.env || process.env);
  const { config, hash } = policy(repo); // Missing blockers fail before any gate.
  if (source.dirty) throw new Error("Dirty working tree: exact-candidate validation refused.");
  const evidence = freshEvidence(repo, options.evidence);
  fs.mkdirSync(path.join(evidence, "publish"), { recursive: true, mode: 0o700 });
  const manifest = { version: VERSION, command: "node scripts/validate-candidate.js", mode: options.mode,
    ...source, timestamp: new Date().toISOString(), nodeVersion: process.version, platform: process.platform,
    policyHash: hash, blockers: config.blockers, finalized: false, gates: [] };
  const persist = () => {
    summarize(manifest);
    writeManifest(path.join(evidence, "publish", `${options.mode}.json`), manifest);
  };
  persist();
  for (const [id, command, args] of commands(repo, options.mode, { ...options, evidence }, config)) {
    if (id.startsWith("ios-")) fs.mkdirSync(path.join(evidence, id.slice(4)));
    const log = path.join(evidence, `${id}.raw.log`);
    const environment = deps.env || process.env;
    const childEnvironment = options.mode === "backend" ? backendEnvironment(id, environment) : environment;
    let suiteDirectory, suiteRunID;
    if (options.mode === "backend") {
      suiteDirectory = path.join(evidence, "structured", id);
      fs.mkdirSync(suiteDirectory, { recursive: true, mode: 0o700 });
      suiteRunID = crypto.randomUUID();
      Object.assign(childEnvironment, { CALDERA_SUITE_REPORT_DIR: suiteDirectory, CALDERA_SUITE_RUN_ID: suiteRunID });
    }
    const exitCode = (deps.run || run)(command, args, { repo, log,
      env: childEnvironment });
    const raw = fs.readFileSync(log, "utf8");
    const gate = { id, exitCode, status: exitCode === 0 && !hasSkip(raw) ? "passed" : "failed" };
    let failureReason = exitCode !== 0 ? "command-failed" : "required-tests-skipped";
    if (options.mode === "backend") {
      const expected = backendSuites(repo, id);
      const suites = [];
      // Publish ONLY schema-checked controller records, never raw reporter data.
      for (const suite of expected) {
        try {
          const value = JSON.parse(fs.readFileSync(resultFile(suiteDirectory, suite), "utf8"));
          if (recordValid(value, suite, suiteRunID)) suites.push(value);
        } catch { /* Missing/unsafe detail is explicit below, never echoed. */ }
      }
      gate.suiteRunID = suiteRunID;
      gate.suites = suites;
      try { readResults(suiteDirectory, expected, suiteRunID); }
      catch {
        gate.status = "failed";
        gate.structuredEvidence = "unavailable-or-failed";
        if (exitCode === 0) failureReason = "structured-suite-evidence-invalid";
      }
      const file = `${id}.suites.json`;
      const suitePath = path.join(evidence, "publish", file);
      writeManifest(suitePath, { version: 1, gate: id, runID: suiteRunID, suites });
      gate.suiteEvidence = { file, hash: digest(fs.readFileSync(suitePath)) };
    }
    if (gate.status === "passed" && id === "backend-chain" &&
        !raw.includes("Postgres Plaid item store check passed.")) {
      gate.status = "failed";
      failureReason = "required-postgres-execution-marker-missing";
    }
    if (gate.status === "passed" && id === "postgres-startup" &&
        !raw.includes("Guarded real backend Postgres startup passed:")) {
      gate.status = "failed";
      failureReason = "required-postgres-startup-marker-missing";
    }
    if (gate.status === "passed" && id.startsWith("ios-")) {
      const suite = id.slice(4);
      const result = spawnSync("xcrun", ["xcresulttool", "get", "test-results", "summary", "--path",
        path.join(evidence, suite, "Contained.xcresult")], { encoding: "utf8" });
      try {
        if (result.status !== 0) throw new Error("Cannot read XCTest result.");
        gate.tests = testSummary(JSON.parse(result.stdout), config.ios[suite]);
      } catch { gate.status = "failed"; }
    }
    if (options.mode === "backend" && gate.status === "failed") {
      const file = `${id}.failure.json`;
      const context = { gate: id, exitCode, repo, reason: failureReason };
      let report;
      try { report = failureReport({ ...context, raw }); }
      catch {
        // A sanitizer failure is explicit missing evidence, never publication
        // of raw error/log contents or conversion of the gate into a pass.
        report = unavailableReport(context, "Safe failure evidence generation failed; raw output was not published.");
      }
      const publication = prepareFailurePublication(report, context);
      const reportPath = path.join(evidence, "publish", file);
      writeJSONBytes(reportPath, publication.serialized);
      gate.failureEvidence = { file, hash: digest(fs.readFileSync(reportPath)), availability: publication.report.availability,
        publicationSafety: publication.report.publicationSafety };
    }
    const published = safeLog(id, exitCode, raw);
    fs.writeFileSync(path.join(evidence, "publish", `${id}.log`), published);
    gate.logHash = digest(published);
    manifest.gates.push(gate);
    persist();
    if (gate.status !== "passed") break;
  }
  // Test-only fault boundary: progress is already persisted but source verification
  // has not happened. There is no CLI option that bypasses this final check.
  deps.beforeFinalSourceCheck?.();
  const finalSource = identity(repo, deps.env || process.env);
  if (finalSource.commit !== source.commit || finalSource.dirty) {
    manifest.gates.push({ id: "source-changed", status: "failed", exitCode: 1 });
  } else if (JSON.stringify(manifest.gates.map((g) => g.id)) === JSON.stringify(GATES[options.mode]) &&
      manifest.gates.every((g) => g.status === "passed" && g.exitCode === 0)) {
    manifest.finalized = true;
  }
  persist();
  return manifest;
}
function aggregate(repo, inputs, env = process.env) {
  const source = identity(repo, env);
  const { config, hash } = policy(repo);
  if (source.dirty) throw new Error("Dirty working tree: exact-candidate validation refused.");
  const dependencies = dependencyResults(env);
  if (dependencies && Object.values(dependencies).some((result) => result !== "success")) {
    throw new Error("Required CI jobs or artifact retrieval did not succeed.");
  }
  const manifests = inputs.map((file) => ({ file, value: JSON.parse(fs.readFileSync(file)) }));
  if (manifests.length !== 2 || new Set(manifests.map((m) => m.value.mode)).size !== 2) {
    throw new Error("Both exact backend and iOS manifests are required.");
  }
  manifests.sort((a, b) => Object.keys(GATES).indexOf(a.value.mode) - Object.keys(GATES).indexOf(b.value.mode));
  for (const { file, value } of manifests) {
    const required = GATES[value.mode];
    if (value.finalized !== true) throw new Error("Manifest was not successfully finalized.");
    if (!required || value.version !== VERSION || value.commit !== source.commit || value.dirty !== false ||
        value.policyHash !== hash || !Array.isArray(value.gates) ||
        JSON.stringify(value.gates.map((g) => g.id)) !== JSON.stringify(required)) {
      throw new Error("Manifest is incomplete or belongs to a different candidate/policy.");
    }
    for (const gate of value.gates) {
      if (gate.status !== "passed" || gate.exitCode !== 0 ||
          digest(fs.readFileSync(path.join(path.dirname(file), `${gate.id}.log`))) !== gate.logHash) {
        throw new Error("A required gate failed or its retained evidence changed.");
      }
      if (gate.id.startsWith("ios-")) {
        testSummary({ ...gate.tests, result: "Passed" }, config.ios[gate.id.slice(4)]);
      }
      if (value.mode === "backend") {
        const expected = backendSuites(repo, gate.id);
        if (!Array.isArray(gate.suites) || JSON.stringify(gate.suites.map(s => s.suite)) !== JSON.stringify(expected) ||
            gate.suites.some(s => !recordValid(s, s.suite, gate.suiteRunID) || !passed(s)) ||
            gate.suiteEvidence?.file !== `${gate.id}.suites.json`) throw new Error("Required structured backend evidence did not pass.");
        const bytes = fs.readFileSync(path.join(path.dirname(file), gate.suiteEvidence.file));
        if (digest(bytes) !== gate.suiteEvidence.hash ||
            bytes.toString() !== JSON.stringify({ version: 1, gate: gate.id, runID: gate.suiteRunID, suites: gate.suites }, null, 2) + "\n") {
          throw new Error("Structured backend evidence changed.");
        }
      }
    }
  }
  const finalSource = identity(repo, env);
  if (finalSource.commit !== source.commit || finalSource.dirty) {
    throw new Error("Candidate source changed during aggregation.");
  }
  const result = { version: VERSION, command: "node scripts/validate-candidate.js release|summary", mode: "aggregate",
    ...source, timestamp: new Date().toISOString(), policyHash: hash, blockers: config.blockers,
    finalized: true, ...(dependencies ? { dependencies } : {}),
    gates: manifests.flatMap((m) => m.value.gates) };
  summarize(result);
  return result;
}
function aggregateReport(repo, inputs, env = process.env) {
  try { return aggregate(repo, inputs, env); }
  catch {
    // Diagnostic reporting cannot authorize anything. Fixed messages and
    // normalized states avoid publishing filesystem/configuration error data.
    let source = { commit: null, ref: null, dirty: null };
    let currentPolicy = { hash: null, config: { blockers: BLOCKERS.map((id) =>
      ({ id, status: "open", reason: "Release policy could not be verified." })) } };
    try { source = identity(repo, env); } catch { /* Unverified identity stays null. */ }
    try { currentPolicy = policy(repo); } catch { /* Unverified policy stays blocked. */ }
    const dependencies = dependencyResults(env);
    const result = { version: VERSION, command: "node scripts/validate-candidate.js release|summary", mode: "aggregate",
      ...source, timestamp: new Date().toISOString(), policyHash: currentPolicy.hash,
      blockers: currentPolicy.config.blockers, finalized: false, gates: [],
      ...(dependencies ? { dependencies } : {}),
      failure: "Required dependency, finalized evidence, or candidate/policy verification failed." };
    summarize(result);
    return result;
  }
}
if (require.main === module) {
  try {
    const [mode, ...args] = process.argv.slice(2);
    const options = { mode, repo: path.resolve(__dirname, "..") };
    for (let i = 0; i < args.length; i += 2) {
      if (!["--evidence", "--packages", "--simulator", "--backend", "--ios"].includes(args[i]) || !args[i + 1]) {
        throw new Error("Invalid arguments. See docs/VALIDATION_GUIDE.md.");
      }
      options[args[i].slice(2)] = args[i + 1];
    }
    let result;
    if (["release", "summary"].includes(mode)) {
      if (!options.backend || !options.ios || !options.evidence) throw new Error("Both manifests and fresh evidence directory are required.");
      result = aggregateReport(options.repo, [options.backend, options.ios]);
      const out = freshEvidence(options.repo, options.evidence);
      fs.mkdirSync(out, { recursive: true });
      writeManifest(path.join(out, "aggregate.json"), result);
      process.exitCode = !result.checksPassed ? 1 : mode === "release" && !result.releaseReady ? 2 : 0;
    } else if (GATES[mode] && options.evidence) {
      result = execute(options);
      process.exitCode = result.checksPassed ? 0 : 1;
    } else throw new Error("Use backend, ios, summary, or release with the documented arguments.");
    console.log(result.summary);
  } catch (error) {
    // Do not echo driver/command output or supplied configuration.
    console.error(`Candidate validation refused/failed: ${error instanceof SyntaxError ? "Unreadable manifest/policy." : error.message}`);
    process.exitCode = 1;
  }
}
module.exports = { VERSION, GATES, identity, policy, hasSkip, testSummary, commands, execute, aggregate, backendSuites,
  aggregateReport, dependencyResults, digest };
