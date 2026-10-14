const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");
const gate = require("../validate-candidate");
const source = path.resolve(__dirname, "../..");

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "caldera-candidate-test-"));
  const repo = path.join(root, "repo");
  fs.mkdirSync(path.join(repo, "scripts"), { recursive: true });
  for (const name of ["validate-candidate.js", "release-gates.json"]) {
    fs.copyFileSync(path.join(source, "scripts", name), path.join(repo, "scripts", name));
  }
  fs.mkdirSync(path.join(repo, "scripts/validation"));
  fs.copyFileSync(path.join(source, "scripts/validation/backend-failure-evidence.js"),
    path.join(repo, "scripts/validation/backend-failure-evidence.js"));
  fs.copyFileSync(path.join(source, "scripts/validation/disposable-postgres.sh"),
    path.join(repo, "scripts/validation/disposable-postgres.sh"));
  for (const name of ["backend-test-chain.js", "backend-suite-result.js", "node-test-reporter.cjs"]) {
    fs.copyFileSync(path.join(source, "scripts/validation", name), path.join(repo, "scripts/validation", name));
  }
  fs.mkdirSync(path.join(repo, "plaid-backend"));
  fs.copyFileSync(path.join(source, "plaid-backend/package.json"), path.join(repo, "plaid-backend/package.json"));
  // Only the static gate is substituted for this temporary CLI fixture. The
  // required database command below executes the actual production wrapper.
  fs.writeFileSync(path.join(repo, "scripts/static-fixture.test.js"), "require('node:test').test('static fixture',()=>{});\n");
  fs.writeFileSync(path.join(repo, "scripts/validation/static-check.js"),
    "process.exitCode=require('./backend-suite-result').runFiles({suite:'static',files:['scripts/static-fixture.test.js'],cwd:process.cwd()}).exitCode;\n");
  for (const args of [["init", "-q"], ["add", "scripts", "plaid-backend/package.json"],
    ["-c", "user.name=Validation Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "Synthetic candidate"]]) {
    assert.equal(spawnSync("git", args, { cwd: repo }).status, 0);
  }
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return { root, repo, env: { PATH: process.env.PATH }, evidence: path.join(root, "evidence") };
}
function passingRun(command, args, options) {
  let log = "";
  if (args.at(-1) === "chain") log = "Postgres Plaid item store check passed.\n# skipped 0\n";
  if (args.at(-1) === "startup") log = "Guarded real backend Postgres startup passed: migrations, required auth, disabled dev auth, no provider requests.\n";
  fs.writeFileSync(options.log, log);
  const id = args.at(-1) === "chain" ? "backend-chain" : args.at(-1) === "startup" ? "postgres-startup" : "static";
  for (const suite of gate.backendSuites(options.repo, id)) {
    require("../validation/backend-suite-result").writeRecord(options.env.CALDERA_SUITE_REPORT_DIR, {
      version: 1, suite, runID: options.env.CALDERA_SUITE_RUN_ID, operation: require("node:crypto").randomUUID(),
      pid: process.pid, nodeVersion: process.version, counts: { total: 1, pass: 1, fail: 0, skip: 0, cancel: 0, todo: 0 },
      success: true, finalized: true, childExitCode: 0, decision: "passed",
    });
  }
  return 0;
}
function backend(f, run = passingRun, faults = {}) {
  return gate.execute({ ...f, mode: "backend" }, { ...faults, run, env: f.env });
}
function writeIOS(f, backendManifest) {
  const out = path.join(f.root, "ios");
  fs.mkdirSync(out);
  const config = gate.policy(f.repo).config;
  const value = { ...backendManifest, mode: "ios", gates: gate.GATES.ios.map((id) => {
    const text = `Gate: ${id}\nExit: 0\n`;
    fs.writeFileSync(path.join(out, `${id}.log`), text);
    const result = { id, status: "passed", exitCode: 0, logHash: gate.digest(text) };
    if (id.startsWith("ios-")) {
      const e = config.ios[id.slice(4)];
      result.tests = { totalTestCount: e.total, passedTests: e.passed, expectedFailures: e.expectedFailures, failedTests: 0, skippedTests: 0 };
    }
    return result;
  }) };
  fs.writeFileSync(path.join(out, "ios.json"), JSON.stringify(value));
  return [path.join(f.evidence, "publish/backend.json"), path.join(out, "ios.json")];
}
test("clean candidate records real Git SHA, cleanliness, version, time and every backend result", (t) => {
  const f = fixture(t);
  const manifest = backend(f);
  assert.equal(manifest.commit, spawnSync("git", ["rev-parse", "HEAD"], { cwd: f.repo, encoding: "utf8" }).stdout.trim());
  assert.equal(manifest.dirty, false);
  assert.equal(manifest.version, 1);
  assert.ok(Date.parse(manifest.timestamp));
  assert.equal(manifest.checksPassed, true);
  assert.equal(manifest.finalized, true);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.evidence, "publish/backend.json"))), manifest);
  assert.equal(fs.readdirSync(path.join(f.evidence, "publish")).some((name) => name.endsWith(".tmp")), false);
  assert.equal(manifest.releaseReady, false);
  assert.match(manifest.summary, /RELEASE READINESS BLOCKED BY: F15, PHYSICAL_IOS_26_1/);
});
test("candidate scopes creation permission to the wrapper and never leaks DB configuration to static or non-DB children", (t) => {
  const f = fixture(t);
  Object.assign(f.env, { CALDERA_DISPOSABLE_POSTGRES_CONFIRM: "disposable-loopback-cluster",
    CALDERA_POSTGRES_BIN: "/synthetic/postgres/bin", CALDERA_POSTGRES_TEST_CONFIRM: "disposable-loopback-cluster",
    DATABASE_URL: "synthetic-credential-url", TOKEN_ENCRYPTION_KEY: "synthetic-key", PGUSER: "synthetic-owner",
    NODE_OPTIONS: "synthetic-preload", APP_API_KEY: "synthetic-app-secret" });
  const result = backend(f, (command, args, options) => {
    assert.deepEqual(Object.keys(options.env).sort(), args.at(-1) === "chain" || args.at(-1) === "startup"
      ? ["CALDERA_DISPOSABLE_POSTGRES_CONFIRM", "CALDERA_POSTGRES_BIN", "CALDERA_SUITE_REPORT_DIR", "CALDERA_SUITE_RUN_ID", "PATH"]
      : ["CALDERA_SUITE_REPORT_DIR", "CALDERA_SUITE_RUN_ID", "PATH"]);
    return passingRun(command, args, options);
  });
  assert.equal(result.finalized, true);
});
test("actual CLI refuses dirty source before creating evidence or running a gate", (t) => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.repo, "dirty.swift"), "uncommitted");
  const result = spawnSync(process.execPath, [path.join(f.repo, "scripts/validate-candidate.js"),
    "backend", "--evidence", f.evidence], { env: f.env, encoding: "utf8" });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Dirty working tree/);
  assert.equal(fs.existsSync(f.evidence), false);
});
test("required backend failure is non-green, retains actual exit and stops subsequent gates", (t) => {
  const f = fixture(t);
  const result = backend(f, (command, args, options) => {
    passingRun(command, args, options);
    return args.at(-1) === "chain" ? 17 : 0;
  });
  assert.equal(result.checksPassed, false);
  assert.equal(result.gates.at(-1).exitCode, 17);
  assert.equal(result.gates.length, 2);
  assert.doesNotMatch(result.summary, /VALIDATION CHECKS PASSED/);
});
test("Postgres skip, absent execution marker, and skipped required tests fail aggregation", (t) => {
  for (const log of ["SKIP: Postgres missing configuration\n", "# skipped 1\nPostgres Plaid item store check passed.\n",
    "# todo 1\nPostgres Plaid item store check passed.\n", "ok 1 - required test # SKIP\n", "no database executed\n"]) {
    const f = fixture(t);
    const result = backend(f, (command, args, options) => {
      const exit = passingRun(command, args, options);
      if (args.at(-1) === "chain") fs.writeFileSync(options.log, log);
      return exit;
    });
    assert.equal(result.checksPassed, false);
    assert.equal(result.gates.at(-1).status, "failed");
  }
});
test("structured skips, cancelled/todo coverage and missing or invalid reports reject a zero-exit gate", (t) => {
  for (const fault of ["skip", "cancel", "todo", "missing", "malformed", "unfinished", "suite", "runID"]) {
    const f = fixture(t);
    const result = backend(f, (command, args, options) => {
      passingRun(command, args, options);
      if (args.at(-1) !== "chain") return 0;
      const api = require("../validation/backend-suite-result");
      const file = api.resultFile(options.env.CALDERA_SUITE_REPORT_DIR, "test:auth");
      const value = JSON.parse(fs.readFileSync(file));
      if (["skip", "cancel", "todo"].includes(fault)) {
        value.counts.pass = 0; value.counts[fault] = 1; value.decision = "failed";
      } else if (fault === "unfinished") value.finalized = false;
      else if (fault === "suite") value.suite = "test:crypto";
      else if (fault === "runID") value.runID = require("node:crypto").randomUUID();
      if (fault === "missing") fs.unlinkSync(file);
      else fs.writeFileSync(file, fault === "malformed" ? '{"secret":"synthetic-sentinel"' : JSON.stringify(value));
      // Deliberately successful-looking human output cannot override the report.
      fs.writeFileSync(options.log, "# skipped 0\nPostgres Plaid item store check passed.\n");
      return 0;
    });
    assert.equal(result.checksPassed, false, fault);
    assert.equal(result.finalized, false);
    assert.equal(result.releaseReady, false);
    assert.equal(result.gates.at(-1).status, "failed");
    assert.doesNotMatch(JSON.stringify(result), /synthetic-sentinel/);
  }
});
test("real skipped static child keeps actual candidate CLI and aggregate nonzero with finalized skipped counts", (t) => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.repo, "scripts/static-fixture.test.js"), "require('node:test').test('required skip',{skip:true},()=>{});\n");
  assert.equal(spawnSync("git", ["-c", "user.name=Validation Fixture", "-c", "user.email=fixture@example.invalid",
    "commit", "-am", "Synthetic skipped fixture"], { cwd: f.repo }).status, 0);
  const child = spawnSync(process.execPath, [path.join(f.repo, "scripts/validate-candidate.js"), "backend", "--evidence", f.evidence], { env: f.env, encoding: "utf8" });
  assert.equal(child.status, 1);
  const manifest = JSON.parse(fs.readFileSync(path.join(f.evidence, "publish/backend.json")));
  assert.equal(manifest.finalized, false);
  assert.equal(manifest.releaseReady, false);
  assert.equal(manifest.gates[0].exitCode, 1);
  assert.equal(manifest.gates[0].suites[0].childExitCode, 0);
  assert.equal(manifest.gates[0].suites[0].counts.skip, 1);
  assert.equal(manifest.gates[0].suites[0].finalized, true);
  const aggregate = spawnSync(process.execPath, [path.join(f.repo, "scripts/validate-candidate.js"), "summary",
    "--backend", path.join(f.evidence, "publish/backend.json"), "--ios", path.join(f.root, "missing-ios.json"),
    "--evidence", path.join(f.root, "summary")], { env: f.env, encoding: "utf8" });
  assert.equal(aggregate.status, 1);
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.root, "summary/aggregate.json"))).checksPassed, false);
});
test("actual disposable wrapper rejects missing authorization before cluster creation", () => {
  const result = spawnSync("bash", [path.join(source, "scripts/validation/disposable-postgres.sh"), "chain"], {
    env: { PATH: process.env.PATH }, encoding: "utf8",
  });
  assert.equal(result.status, 64);
  assert.match(result.stderr, /Explicit disposable Postgres test authorization/);
});
test("real missing-authorization outcome makes the production orchestrator non-green", (t) => {
  const f = fixture(t);
  const result = backend(f, (command, args, options) => {
    if (args.at(-1) !== "chain") return passingRun(command, args, options);
    const child = spawnSync("bash", [path.join(source, "scripts/validation/disposable-postgres.sh"), "chain"], {
      env: { PATH: process.env.PATH }, encoding: "utf8",
    });
    fs.writeFileSync(options.log, child.stdout + child.stderr);
    return child.status;
  });
  assert.equal(result.checksPassed, false);
  assert.equal(result.gates.at(-1).exitCode, 64);
  assert.equal(result.gates.at(-1).status, "failed");
});
test("actual clean-candidate CLI exits nonzero on real missing Postgres authorization", (t) => {
  const f = fixture(t);
  const result = spawnSync(process.execPath, [path.join(f.repo, "scripts/validate-candidate.js"),
    "backend", "--evidence", f.evidence], { env: f.env, encoding: "utf8" });
  assert.equal(result.status, 1);
  const manifest = JSON.parse(fs.readFileSync(path.join(f.evidence, "publish/backend.json")));
  assert.equal(manifest.checksPassed, false);
  assert.equal(manifest.gates.at(-1).id, "backend-chain");
  assert.equal(manifest.gates.at(-1).exitCode, 64);
  assert.doesNotMatch(result.stdout, /VALIDATION CHECKS PASSED/);
});
test("missing or omitted blocker config fails closed before any command", (t) => {
  for (const mutation of ["absent", "omit", "version", "corrupt", "status", "reason", "duplicate", "stale-runtime"]) {
    const f = fixture(t);
    const file = path.join(f.repo, "scripts/release-gates.json");
    if (mutation === "absent") fs.unlinkSync(file);
    else if (mutation === "corrupt") fs.writeFileSync(file, "{bad-json");
    else {
      const config = JSON.parse(fs.readFileSync(file));
      if (mutation === "omit") config.blockers.pop();
      else if (mutation === "version") config.version = 99;
      else if (mutation === "status") config.blockers[0].status = "accepted";
      else if (mutation === "reason") config.blockers[0].reason = "";
      else if (mutation === "duplicate") config.blockers[1] = config.blockers[0];
      else config.blockers.push({ id: "F11", status: "open", reason: "Stale runtime blocker" });
      fs.writeFileSync(file, JSON.stringify(config));
    }
    assert.throws(() => backend(f, () => assert.fail("No command may run")));
    assert.equal(fs.existsSync(f.evidence), false);
  }
});
test("all required gates passing still makes actual release CLI exit 2 for open blockers", (t) => {
  const f = fixture(t);
  const paths = writeIOS(f, backend(f));
  const output = path.join(f.root, "aggregate");
  const result = spawnSync(process.execPath, [path.join(f.repo, "scripts/validate-candidate.js"), "release",
    "--backend", paths[0], "--ios", paths[1], "--evidence", output], { env: f.env, encoding: "utf8" });
  assert.equal(result.status, 2);
  assert.match(result.stdout, /VALIDATION CHECKS PASSED\nBUT RELEASE READINESS BLOCKED BY: F15, PHYSICAL_IOS_26_1/);
  const value = JSON.parse(fs.readFileSync(path.join(output, "aggregate.json")));
  assert.equal(value.checksPassed, true);
  assert.equal(value.releaseReady, false);
});
test("CI summary keeps release blocked even when its validation-only exit is zero", (t) => {
  const f = fixture(t);
  const paths = writeIOS(f, backend(f));
  const result = spawnSync(process.execPath, [path.join(f.repo, "scripts/validate-candidate.js"), "summary",
    "--backend", paths[0], "--ios", paths[1], "--evidence", path.join(f.root, "summary")], { env: f.env, encoding: "utf8" });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /RELEASE READINESS BLOCKED/);
});
test("complete passing gates without explicit successful finalization cannot aggregate", (t) => {
  for (const state of [undefined, false, "true"]) {
    const f = fixture(t);
    const paths = writeIOS(f, backend(f));
    const value = JSON.parse(fs.readFileSync(paths[0]));
    if (state === undefined) delete value.finalized;
    else value.finalized = state;
    fs.writeFileSync(paths[0], JSON.stringify(value));
    assert.throws(() => gate.aggregate(f.repo, paths, f.env), /not successfully finalized/);
  }
});
test("interruption after all passing gates are persisted leaves only rejected unfinished evidence", (t) => {
  const f = fixture(t);
  assert.throws(() => backend(f, passingRun, { beforeFinalSourceCheck() {
    const progress = JSON.parse(fs.readFileSync(path.join(f.evidence, "publish/backend.json")));
    assert.deepEqual(progress.gates.map((g) => g.id), gate.GATES.backend);
    assert.ok(progress.gates.every((g) => g.status === "passed"));
    assert.equal(progress.finalized, false);
    assert.equal(progress.checksPassed, false);
    throw new Error("Controlled interruption before source verification");
  } }), /Controlled interruption/);
  const unfinished = JSON.parse(fs.readFileSync(path.join(f.evidence, "publish/backend.json")));
  const paths = writeIOS(f, { ...unfinished, finalized: true });
  assert.throws(() => gate.aggregate(f.repo, paths, f.env), /not successfully finalized/);
  assert.equal(gate.aggregateReport(f.repo, paths, f.env).releaseReady, false);
});
test("failed final source verification cannot finalize otherwise passing gates", (t) => {
  const f = fixture(t);
  const changed = path.join(f.repo, "changed.swift");
  const result = backend(f, passingRun, { beforeFinalSourceCheck() {
    fs.writeFileSync(changed, "Source changed after gates");
  } });
  assert.equal(result.finalized, false);
  assert.equal(result.checksPassed, false);
  assert.equal(result.gates.at(-1).id, "source-changed");
  const persisted = JSON.parse(fs.readFileSync(path.join(f.evidence, "publish/backend.json")));
  assert.equal(persisted.finalized, false);
  // Even after the fixture becomes clean again, failed evidence stays rejected.
  fs.unlinkSync(changed);
  assert.throws(() => gate.aggregate(f.repo, writeIOS(f, { ...persisted, finalized: true }), f.env),
    /not successfully finalized/);
});
function ciEnvironment(f, backendResult = "success", iosResult = "success", downloadResult = "success") {
  return { ...f.env, GITHUB_ACTIONS: "true", GITHUB_SHA: gate.identity(f.repo, f.env).commit,
    CALDERA_BACKEND_JOB_RESULT: backendResult, CALDERA_IOS_JOB_RESULT: iosResult,
    CALDERA_ARTIFACT_DOWNLOAD_RESULT: downloadResult };
}
test("actual summary CLI retains a failed report for every non-success required dependency", (t) => {
  for (const job of ["backend", "ios"]) for (const state of ["failure", "skipped", "cancelled", "", "unknown"]) {
    const f = fixture(t);
    const paths = writeIOS(f, backend(f));
    const env = ciEnvironment(f);
    env[job === "backend" ? "CALDERA_BACKEND_JOB_RESULT" : "CALDERA_IOS_JOB_RESULT"] = state;
    const output = path.join(f.root, "failed-summary");
    const result = spawnSync(process.execPath, [path.join(f.repo, "scripts/validate-candidate.js"), "summary",
      "--backend", paths[0], "--ios", paths[1], "--evidence", output], { env, encoding: "utf8" });
    assert.equal(result.status, 1, `${job}: ${state}`);
    const report = JSON.parse(fs.readFileSync(path.join(output, "aggregate.json")));
    assert.equal(report.dependencies[job], state === "" ? "missing" : state === "unknown" ? "unexpected" : state);
    assert.equal(report.finalized, false);
    assert.equal(report.checksPassed, false);
    assert.equal(report.releaseReady, false);
    assert.match(result.stdout, /VALIDATION CHECKS FAILED/);
  }
});
test("CI cannot bypass missing dependency results or failed artifact retrieval with valid manifests", (t) => {
  const f = fixture(t);
  const paths = writeIOS(f, backend(f));
  for (const env of [{ ...f.env, GITHUB_ACTIONS: "true", GITHUB_SHA: gate.identity(f.repo, f.env).commit },
    ciEnvironment(f, "success", "success", "failure"), ciEnvironment(f, "success", "success", "skipped"),
    ciEnvironment(f, "success", "success", "cancelled")]) {
    assert.throws(() => gate.aggregate(f.repo, paths, env), /did not succeed/);
    const report = gate.aggregateReport(f.repo, paths, env);
    assert.equal(report.checksPassed, false);
    assert.equal(report.releaseReady, false);
  }
});
test("actual summary CLI publishes non-success diagnostics for missing corrupt or incomplete evidence", (t) => {
  for (const mutation of ["missing", "corrupt", "incomplete", "unfinalized", "cancelled-gate", "failed-gate", "skipped-gate", "policy"]) {
    const f = fixture(t);
    const paths = writeIOS(f, backend(f));
    const value = JSON.parse(fs.readFileSync(paths[1]));
    if (mutation === "missing") fs.unlinkSync(paths[1]);
    else if (mutation === "corrupt") fs.writeFileSync(paths[1], "{invalid-json");
    else {
      if (mutation === "incomplete") value.gates.pop();
      if (mutation === "unfinalized") value.finalized = false;
      if (mutation.endsWith("-gate")) value.gates.at(-1).status = mutation.split("-")[0];
      if (mutation === "policy") value.policyHash = "0".repeat(64);
      fs.writeFileSync(paths[1], JSON.stringify(value));
    }
    const output = path.join(f.root, "failed-summary");
    const result = spawnSync(process.execPath, [path.join(f.repo, "scripts/validate-candidate.js"), "summary",
      "--backend", paths[0], "--ios", paths[1], "--evidence", output], {
      env: ciEnvironment(f), encoding: "utf8",
    });
    assert.equal(result.status, 1, mutation);
    const report = JSON.parse(fs.readFileSync(path.join(output, "aggregate.json")));
    assert.equal(report.finalized, false);
    assert.equal(report.checksPassed, false);
    assert.equal(report.releaseReady, false);
    assert.ok(report.failure);
  }
});
test("successful CI dependencies and finalized platform evidence reach the normal blocked summary", (t) => {
  const f = fixture(t);
  const paths = writeIOS(f, backend(f));
  const report = gate.aggregateReport(f.repo, paths, ciEnvironment(f));
  assert.equal(report.finalized, true);
  assert.equal(report.checksPassed, true);
  assert.equal(report.releaseReady, false);
  assert.deepEqual(report.dependencies, { backend: "success", ios: "success", artifactDownload: "success" });
  assert.match(report.summary, /BLOCKED BY: F15, PHYSICAL_IOS_26_1/);
});
test("only F15 and physical qualification remain policy blockers; either open blocks release", (t) => {
  assert.deepEqual(gate.policy(source).config.blockers.map((b) => [b.id, b.status]),
    [["F15", "open"], ["PHYSICAL_IOS_26_1", "open"]]);
  for (const open of ["F15", "PHYSICAL_IOS_26_1", null]) {
    const f = fixture(t);
    const file = path.join(f.repo, "scripts/release-gates.json");
    const config = JSON.parse(fs.readFileSync(file));
    for (const blocker of config.blockers) blocker.status = blocker.id === open ? "open" : "closed";
    fs.writeFileSync(file, JSON.stringify(config));
    assert.equal(spawnSync("git", ["add", "scripts/release-gates.json"], { cwd: f.repo }).status, 0);
    assert.equal(spawnSync("git", ["-c", "user.name=Validation Fixture", "-c", "user.email=fixture@example.invalid",
      "commit", "-qm", "Synthetic policy disposition"], { cwd: f.repo }).status, 0);
    const paths = writeIOS(f, backend(f));
    for (const mode of ["summary", "release"]) {
      const result = spawnSync(process.execPath, [path.join(f.repo, "scripts/validate-candidate.js"), mode,
        "--backend", paths[0], "--ios", paths[1], "--evidence", path.join(f.root, mode)], { env: f.env, encoding: "utf8" });
      assert.equal(result.status, mode === "release" && open ? 2 : 0);
      const report = JSON.parse(fs.readFileSync(path.join(f.root, mode, "aggregate.json")));
      assert.equal(report.checksPassed, true);
      assert.equal(report.releaseReady, open === null);
      assert.deepEqual(report.blockers.filter((b) => b.status === "open").map((b) => b.id), open ? [open] : []);
    }
  }
});
test("stale SHA, incomplete gate set, nonzero test skips, or changed evidence cannot aggregate", (t) => {
  for (const mutation of ["sha", "gates", "skip", "log"]) {
    const f = fixture(t);
    const paths = writeIOS(f, backend(f));
    const value = JSON.parse(fs.readFileSync(paths[1]));
    if (mutation === "sha") value.commit = "a".repeat(40);
    if (mutation === "gates") value.gates.pop();
    if (mutation === "skip") value.gates.at(-1).tests.skippedTests = 1;
    if (mutation === "log") fs.appendFileSync(path.join(path.dirname(paths[1]), "ios-stable.log"), "changed");
    fs.writeFileSync(paths[1], JSON.stringify(value));
    assert.throws(() => gate.aggregate(f.repo, paths, f.env));
  }
});
test("CI identity must equal actual checkout SHA, including PR merge candidates", (t) => {
  const f = fixture(t);
  const base = gate.identity(f.repo, f.env).ref;
  const git = (args) => {
    const result = spawnSync("git", ["-c", "user.name=Validation Fixture", "-c", "user.email=fixture@example.invalid", ...args],
      { cwd: f.repo, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };
  git(["switch", "-c", "candidate-tip"]);
  fs.writeFileSync(path.join(f.repo, "candidate.txt"), "Synthetic branch-head source\n");
  git(["add", "candidate.txt"]);
  git(["commit", "-qm", "Synthetic branch head"]);
  const branchSHA = git(["rev-parse", "HEAD"]);
  git(["switch", base]);
  git(["merge", "--no-ff", "candidate-tip", "-m", "Synthetic PR merge candidate"]);
  const mergeSHA = git(["rev-parse", "HEAD"]);
  assert.notEqual(branchSHA, mergeSHA);
  const env = { ...f.env, GITHUB_ACTIONS: "true", GITHUB_SHA: mergeSHA, GITHUB_REF: "refs/pull/123/merge" };
  const result = gate.execute({ ...f, mode: "backend" }, { run: passingRun, env });
  assert.equal(result.commit, mergeSHA);
  assert.equal(result.ref, "refs/pull/123/merge");
  assert.equal(result.finalized, true);
  assert.throws(() => gate.identity(f.repo, { ...env, GITHUB_SHA: branchSHA }), /GITHUB_SHA/);
});
test("stable hosted selection resolves accepted source tests and excludes all fatal diagnostics", (t) => {
  const config = gate.policy(source).config;
  const diagnosticClasses = ["RuntimeLifecycleDiagnosticTests", "SwiftDataModelLifetimeDiagnosticTests"];
  let expanded = [];
  for (const selector of Object.values(config.ios).flatMap((s) => s.selection)) {
    const [group, method] = selector.split("/");
    assert.ok(!diagnosticClasses.includes(group));
    assert.doesNotMatch(selector, /Diagnostic|ActorLifetimeProbe|ImplicitActorDestruction|ReleaseContainer|ContainerRelease/);
    const file = group === "KeychainEnvironmentSessionTests" ? "AuthEnvironmentSessionTests" : group;
    const contents = fs.readFileSync(path.join(source, "budgetTestTests", `${file}.swift`), "utf8");
    if (method) {
      assert.ok(contents.includes(`func ${method}(`), `Missing production test identifier: ${selector}`);
      expanded.push(selector);
    } else {
      assert.ok(["ContainedTestTransportTests", "AuthEnvironmentSessionTests"].includes(group));
      const body = contents.split(`final class ${group}:`)[1].split(/\n(?:@MainActor\n)?(?:private )?final class /)[0];
      expanded.push(...[...body.matchAll(/func (test\w+)\(/g)].map((m) => `${group}/${m[1]}`));
    }
  }
  assert.equal(new Set(expanded).size, Object.values(config.ios).reduce((n, s) => n + s.total, 0));
  assert.equal(expanded.length, 46);
  for (const group of diagnosticClasses) {
    const diagnostic = fs.readFileSync(path.join(source, "budgetTestTests", `${group}.swift`), "utf8");
    for (const [, method] of diagnostic.matchAll(/func (test\w+)\(/g)) {
      assert.ok(!expanded.includes(`${group}/${method}`));
    }
    for (const selector of [group, `${group}/testFMainContextContainerReleaseInMemory`]) {
      const f = fixture(t);
      const file = path.join(f.repo, "scripts/release-gates.json");
      const value = JSON.parse(fs.readFileSync(file));
      value.ios.stable.selection = [selector];
      assert.throws(() => { fs.writeFileSync(file, JSON.stringify(value)); gate.policy(f.repo); }, /diagnostic/);
    }
  }
});
test("iOS plan composes accepted wrappers with containment and separate Debug/RC checks", () => {
  const config = gate.policy(source).config;
  const plan = gate.commands(source, "ios", { evidence: "/tmp/fixture", packages: "/tmp/packages",
    simulator: "00000000-0000-0000-0000-000000000000" }, config);
  assert.deepEqual(plan.map((p) => p[0]), gate.GATES.ios);
  assert.ok(plan[0][2].includes("APP_API_KEY="));
  assert.match(plan[0][2][0], /build-debug.sh$/);
  assert.match(plan[1][2][0], /build-release.sh$/);
  assert.match(plan[2][2][0], /test-contained-ios.sh$/);
  assert.deepEqual(plan[3][2].slice(4), config.ios.stable.selection);
  // V14's absolute-zero construction assertion requires a process that has
  // never constructed the test-only validation control. Hold/mounted fixtures
  // also keep their independent process lifecycle and result obligations.
  for (const [index, suite] of ["hold", "mounted", "production"].entries()) {
    assert.deepEqual(plan[index + 4][2].slice(4), config.ios[suite].selection);
    assert.equal(plan[index + 4][2][2], `/tmp/fixture/${suite}`);
  }
  assert.deepEqual(config.ios.production.selection,
    ["OrdinaryProductionCompatibilityTests/testOrdinaryProductionGraphOneIteration"]);
  assert.equal(config.ios.contract.expectedFailures, 5);
  assert.throws(() => gate.testSummary({ result: "Passed", totalTestCount: 0 }, config.ios.contract));
});
test("backend external socket and DNS attempts reject before any connection", () => {
  const guard = path.join(source, "scripts/validation/contained-network.cjs");
  for (const expression of ["require('node:net').connect({host:'example.invalid',port:443})",
    "require('node:dns').lookup('example.invalid',()=>{})",
    "require('node:net').connect({host:'127.0.0.1',port:5432})",
    "try { require('node:net').connect({host:'127.0.0.1',port:8080}); } catch (error) { console.error(error.message); }"]) {
    const result = spawnSync(process.execPath, ["--require", guard, "-e", expression], { encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Validation blocked/);
  }
});
test("actual iOS wrappers forward isolated paths, locked resolution and containment flags", (t) => {
  const f = fixture(t);
  const tools = path.join(f.root, "tools");
  const packages = path.join(f.root, "packages");
  fs.mkdirSync(tools);
  fs.mkdirSync(path.join(packages, "artifacts"), { recursive: true });
  fs.mkdirSync(path.join(packages, "checkouts/plaid-link-ios"), { recursive: true });
  const stub = path.join(tools, "xcodebuild");
  fs.writeFileSync(stub, '#!/usr/bin/env bash\nprintf "%s\\n" "$@"\n');
  fs.chmodSync(stub, 0o700);
  for (const [script, scheme] of [["build-debug.sh", "Caldera Debug Local"], ["build-release.sh", "Caldera Release Candidate"]]) {
    const result = spawnSync("bash", [path.join(source, "scripts", script), "-derivedDataPath", f.evidence,
      "-clonedSourcePackagesDirPath", packages, "-skipPackageUpdates", "APP_API_KEY="], {
      env: { PATH: `${tools}:${process.env.PATH}`, DEVELOPER_DIR: "/synthetic/Xcode" }, encoding: "utf8",
    });
    assert.equal(result.status, 0);
    assert.ok(result.stdout.includes(scheme));
    assert.ok(result.stdout.includes(f.evidence));
    assert.ok(result.stdout.includes("APP_API_KEY="));
    assert.ok(result.stdout.includes("-skipPackageUpdates"));
  }
  fs.mkdirSync(f.evidence);
  const result = spawnSync("bash", [path.join(source, "scripts/test-contained-ios.sh"),
    "00000000-0000-0000-0000-000000000000", f.evidence, packages, "ContainedTestTransportTests"], {
    env: { PATH: `${tools}:${process.env.PATH}` }, encoding: "utf8",
  });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG CALDERA_UI_VALIDATION CALDERA_TEST_NETWORK_CONTAINMENT/);
  assert.match(result.stdout, /-only-testing:budgetTestTests\/ContainedTestTransportTests/);
  assert.match(result.stdout, /APP_API_KEY=/);
  for (const selector of Object.values(gate.policy(source).config.ios).flatMap((s) => s.selection)) {
    const selected = spawnSync("bash", [path.join(source, "scripts/test-contained-ios.sh"),
      "00000000-0000-0000-0000-000000000000", f.evidence, packages, selector], {
      env: { PATH: `${tools}:${process.env.PATH}` }, encoding: "utf8",
    });
    assert.equal(selected.status, 0, selector);
    assert.ok(selected.stdout.includes(`-only-testing:budgetTestTests/${selector}`));
  }
  for (const selector of ["budgetTestTests", "RuntimeLifecycleDiagnosticTests", "RuntimeLifecycleDiagnosticTests/testImplicitActorDestructionInsideActorTask",
    "SwiftDataModelLifetimeDiagnosticTests/testFMainContextContainerReleaseInMemory"]) {
    const rejected = spawnSync("bash", [path.join(source, "scripts/test-contained-ios.sh"),
      "00000000-0000-0000-0000-000000000000", f.evidence, packages, selector], {
      env: { PATH: `${tools}:${process.env.PATH}` }, encoding: "utf8",
    });
    assert.equal(rejected.status, 64);
    assert.match(rejected.stderr, /diagnostics excluded/);
    assert.equal(rejected.stdout, "");
  }
});
test("tracked workflow parses, has conservative triggers, immutable actions, no deploy/write/continue-on-error", () => {
  const file = path.join(source, ".github/workflows/candidate-validation.yml");
  const result = spawnSync("ruby", ["-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.load_file(ARGV[0]))", file], { encoding: "utf8" });
  assert.equal(result.status, 0);
  const workflow = JSON.parse(result.stdout);
  assert.deepEqual(Object.keys(workflow.on || workflow.true).sort(), ["pull_request", "workflow_dispatch"]);
  assert.deepEqual(workflow.permissions, { contents: "read" });
  assert.deepEqual(Object.keys(workflow.jobs).sort(), ["backend", "ios", "summary"]);
  assert.doesNotMatch(fs.readFileSync(file, "utf8"), /secrets\.|pull_request_target|id-token:\s*write|contents:\s*write/);
  for (const job of Object.values(workflow.jobs)) for (const step of job.steps) {
    assert.equal(step["continue-on-error"], undefined);
    if (step.uses) assert.match(step.uses, /^actions\/(checkout|setup-node|upload-artifact|download-artifact)@[a-f0-9]{40}$/);
    if (step.run) assert.doesNotMatch(step.run, /git\s+(push|merge)|render\s+deploy|migrate:token-store/);
    if (step.uses?.startsWith("actions/checkout@")) {
      assert.equal(step.with["persist-credentials"], false);
      assert.equal(step.with.ref, undefined, "Default event SHA must select the PR merge candidate");
    }
  }
  assert.ok(workflow.jobs.backend.steps.some((step) => step.run === "npm ci --ignore-scripts"));
  assert.ok(workflow.jobs.backend.steps.some((step) => step.env?.CALDERA_DISPOSABLE_POSTGRES_CONFIRM === "disposable-loopback-cluster"));
  assert.equal(workflow.jobs.backend.env?.CALDERA_POSTGRES_TEST_CONFIRM, undefined);
  for (const step of workflow.jobs.backend.steps) {
    assert.equal(step.env?.CALDERA_POSTGRES_TEST_CONFIRM, undefined);
    assert.equal(step.env?.DATABASE_URL, undefined);
  }
  const backendUpload = workflow.jobs.backend.steps.find((step) => step.uses?.startsWith("actions/upload-artifact@"));
  assert.equal(backendUpload.with.path, "${{ runner.temp }}/backend-evidence/publish/",
    "Upload only sanitized reports/manifest/counts, never parent raw logs");
  const summary = workflow.jobs.summary;
  assert.deepEqual(summary.needs, ["backend", "ios"]);
  assert.equal(summary.if, "always()");
  const reporting = summary.steps.find((step) => step.run?.includes("validate-candidate.js summary"));
  assert.equal(reporting.if, "always()");
  assert.deepEqual(reporting.env, {
    CALDERA_BACKEND_JOB_RESULT: "${{ needs.backend.result }}",
    CALDERA_IOS_JOB_RESULT: "${{ needs.ios.result }}",
    CALDERA_ARTIFACT_DOWNLOAD_RESULT: "${{ steps.candidate-inputs.outcome }}",
  });
  assert.ok(summary.steps.some((step) => step.id === "candidate-inputs" && step.uses?.startsWith("actions/download-artifact@")));
  for (const job of Object.values(workflow.jobs)) {
    const upload = job.steps.find((step) => step.uses?.startsWith("actions/upload-artifact@"));
    assert.equal(upload.if, "always()");
    assert.equal(upload.with["retention-days"], 14);
    assert.equal(upload.with["if-no-files-found"], "error");
  }
});
