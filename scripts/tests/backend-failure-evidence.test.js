const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");
const source = path.resolve(__dirname, "../..");
const { failureReport, prepareFailurePublication } = require("../validation/backend-failure-evidence");
let completedPublicationScans = 0;
let scannedPublicationFiles = 0;
test.after(() => console.log(`Completed recursive publication scans: ${completedPublicationScans}; files: ${scannedPublicationFiles}`));

function report(message, extra = "", name = "ordinary failure identity") {
  return failureReport({ gate: "backend-chain", exitCode: 17, repo: source,
    raw: `not ok 1 - ${name}\n  ---\n  name: 'AssertionError'\n  error: ${JSON.stringify(message)}\n  stack: |-\n    TestContext.run (${source}/plaid-backend/scripts/auth-check.js:42:7)\n${extra}\n  ...\n` });
}

function fixture(t, script, options = {}) {
  const root = fs.mkdtempSync(path.join(options.tempRoot || os.tmpdir(), options.rootPrefix || "caldera-failure-evidence-test-"));
  const repo = path.join(root, options.repoPath || "repo");
  const scriptPath = options.scriptPath || "scripts/failure-fixture.test.js";
  fs.mkdirSync(path.join(repo, "scripts/validation"), { recursive: true });
  for (const name of ["validate-candidate.js", "release-gates.json"]) {
    fs.copyFileSync(path.join(source, "scripts", name), path.join(repo, "scripts", name));
  }
  const sanitizer = path.join(source, "scripts/validation/backend-failure-evidence.js");
  if (fs.existsSync(sanitizer)) fs.copyFileSync(sanitizer,
    path.join(repo, "scripts/validation/backend-failure-evidence.js"));
  for (const name of ["backend-test-chain.js", "backend-suite-result.js", "node-test-reporter.cjs"]) {
    fs.copyFileSync(path.join(source, "scripts/validation", name), path.join(repo, "scripts/validation", name));
  }
  fs.mkdirSync(path.join(repo, "plaid-backend"));
  fs.copyFileSync(path.join(source, "plaid-backend/package.json"), path.join(repo, "plaid-backend/package.json"));
  fs.mkdirSync(path.dirname(path.join(repo, scriptPath)), { recursive: true });
  fs.writeFileSync(path.join(repo, scriptPath), script);
  fs.writeFileSync(path.join(repo, "scripts/validation/static-check.js"),
    'const {runFiles}=require("./backend-suite-result");\n' +
    `process.exitCode=runFiles({suite:"static",files:[${JSON.stringify(scriptPath)}],cwd:process.cwd()}).exitCode;\n`);
  for (const args of [["init", "-q"], ["add", "scripts", "plaid-backend/package.json"],
    ["-c", "user.name=Validation Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "Synthetic evidence fixture"]]) {
    assert.equal(spawnSync("git", args, { cwd: repo }).status, 0);
  }
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return { root, repo, evidence: path.join(root, "evidence"), env: { PATH: process.env.PATH } };
}
function execute(f) {
  const result = spawnSync(process.execPath, [...(f.preload ? ["--require", f.preload] : []), path.join(f.repo, "scripts/validate-candidate.js"),
    "backend", "--evidence", f.evidence], { env: f.env, encoding: "utf8" });
  const manifest = JSON.parse(fs.readFileSync(path.join(f.evidence, "publish/backend.json")));
  return { result, manifest, published: path.join(f.evidence, "publish") };
}
function syntheticPassingSuites(args, options) {
  const id = args.at(-1) === "chain" ? "backend-chain" : args.at(-1) === "startup" ? "postgres-startup" : "static";
  for (const suite of require("../validate-candidate").backendSuites(options.repo, id)) {
    require("../validation/backend-suite-result").writeRecord(options.env.CALDERA_SUITE_REPORT_DIR, {
      version: 1, suite, runID: options.env.CALDERA_SUITE_RUN_ID, operation: require("node:crypto").randomUUID(),
      pid: process.pid, nodeVersion: process.version, counts: { total: 1, pass: 1, fail: 0, skip: 0, cancel: 0, todo: 0 },
      success: true, finalized: true, childExitCode: 0, decision: "passed",
    });
  }
}

test("actual backend CLI retains a failing Node test name, assertion, source and exit without green aggregation", (t) => {
  const f = fixture(t, `const test = require("node:test");
const assert = require("node:assert/strict");
test("synthetic durable save acknowledgment", () => {
  assert.equal(1, 2, "expected one durable acknowledgment");
});\n`);
  const { result, manifest, published } = execute(f);
  assert.equal(result.status, 1);
  assert.equal(manifest.gates[0].exitCode, 1);
  assert.equal(manifest.checksPassed, false);
  assert.equal(manifest.finalized, false);
  assert.match(fs.readFileSync(path.join(f.evidence, "static.raw.log"), "utf8"),
    /synthetic durable save acknowledgment/);
  const report = JSON.parse(fs.readFileSync(path.join(published, "static.failure.json")));
  assert.equal(report.gate, "static");
  assert.equal(report.command, "node scripts/validation/static-check.js");
  assert.equal(report.exitCode, 1);
  assert.equal(report.failingTests[0].name, "synthetic durable save acknowledgment");
  assert.equal(report.failingTests[0].errorClass, "AssertionError");
  assert.equal(report.failingTests[0].message, "expected one durable acknowledgment");
  assert.match(report.failingTests[0].sourceLocation, /^scripts\/failure-fixture\.test\.js:\d+:\d+$/);
  assert.equal(manifest.gates[0].failureEvidence.file, "static.failure.json");
  assert.equal(manifest.gates[0].failureEvidence.availability, "available");
  assert.equal(require("../validate-candidate").digest(fs.readFileSync(path.join(published, "static.failure.json"))),
    manifest.gates[0].failureEvidence.hash);
  assert.doesNotMatch(result.stdout + result.stderr, /expected one durable acknowledgment/);
  const aggregate = spawnSync(process.execPath, [path.join(f.repo, "scripts/validate-candidate.js"), "summary",
    "--backend", path.join(published, "backend.json"), "--ios", path.join(f.root, "missing-ios.json"),
    "--evidence", path.join(f.root, "aggregate")], { env: f.env, encoding: "utf8" });
  assert.equal(aggregate.status, 1);
  const summary = JSON.parse(fs.readFileSync(path.join(f.root, "aggregate/aggregate.json")));
  assert.equal(summary.checksPassed, false);
  assert.equal(summary.releaseReady, false);
});

test("Authorization and Bearer credentials redact in recognized names, messages and excerpts", (t) => {
  for (const message of ["assertion; Authorization: Bearer sentinel-auth-secret; expected rejection",
    "assertion; authorization='sentinel-header-secret'", "expected rejection of Bearer sentinel-bearer-secret"]) {
    const result = report(message, "", "rejects Bearer sentinel-name-secret");
    const published = JSON.stringify(result);
    assert.doesNotMatch(published, /sentinel-(?:auth|header|bearer|name)-secret/);
    assert.equal(result.failingTests[0].name, null);
    assert.equal(result.failingTests[0].fieldAvailability.name, "redacted");
    assert.equal(result.fieldAvailability.message, "redacted");
    const f = fixture(t, `const test=require("node:test"),assert=require("node:assert/strict");\ntest("rejects Bearer sentinel-name-secret",()=>assert.fail(${JSON.stringify(message)}));\n`);
    publishedFailure(f, ["sentinel-auth-secret", "sentinel-header-secret", "sentinel-bearer-secret", "sentinel-name-secret"]);
  }
});
test("credential-bearing database URLs cannot enter any published diagnostic field", (t) => {
  const message = "expected rejection of postgresql://validation:sentinel-db-password@127.0.0.1:5432/disposable";
  const result = report(message);
  assert.doesNotMatch(JSON.stringify(result), /sentinel-db-password|127\.0\.0\.1|5432\/disposable/);
  assert.equal(result.message, null);
  assert.equal(result.fieldAvailability.message, "redacted");
  const f = fixture(t, `const test=require("node:test"),assert=require("node:assert/strict");\ntest("safe database rejection",()=>assert.fail(${JSON.stringify(message)}));\n`);
  publishedFailure(f, ["sentinel-db-password"]);
});
test("Plaid, JWT/session, encryption, GitHub and generic secret assignments redact fail closed", (t) => {
  const cases = [
    ["PLAID_CLIENT_ID=sentinel-client", "sentinel-client"],
    ["PLAID_SECRET='sentinel-plaid-secret'", "sentinel-plaid-secret"],
    ["access_token: access-sandbox-sentinel-provider", "access-sandbox-sentinel-provider"],
    ["public_token=public-production-sentinel-public", "public-production-sentinel-public"],
    ["session_token=sentinel-session", "sentinel-session"],
    ["session: sentinel-session-value", "sentinel-session-value"],
    ["TOKEN_ENCRYPTION_KEY=sentinel-encryption-key", "sentinel-encryption-key"],
    ["encryption key: sentinel-encryption-key", "sentinel-encryption-key"],
    ["ghp_sentinelGithubToken0123456789", "ghp_sentinelGithubToken0123456789"],
    ["github_pat_sentinelGithubToken0123456789", "github_pat_sentinelGithubToken0123456789"],
    ["eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJzZW50aW5lbCJ9.signatureSentinel", "eyJhbGciOiJIUzI1NiJ9"],
    ["password = 'sentinel password with spaces'", "sentinel password with spaces"],
    ['"CUSTOM_SECRET": "sentinel-generic-secret"', "sentinel-generic-secret"],
  ];
  for (const [assignment, secret] of cases) {
    const result = report(`expected rejection; ${assignment}`);
    assert.ok(!JSON.stringify(result).includes(secret), assignment.split(/[=:]/)[0]);
    assert.equal(result.message, null);
    assert.equal(result.fieldAvailability.message, "redacted");
    const f = fixture(t, `const test=require("node:test"),assert=require("node:assert/strict");\ntest("safe credential rejection",()=>assert.fail(${JSON.stringify(`expected rejection; ${assignment}`)}));\n`);
    publishedFailure(f, [secret]);
  }
});

const credentialCases = [
  ["Bearer qb1-72a9", ["qb1-72a9"]],
  ["Bearer 'qb2-82b9'", ["qb2-82b9"]],
  ['Bearer "qb3-92c9"', ["qb3-92c9"]],
  ["Authorization: Bearer hb1-62d8", ["hb1-62d8"]],
  ["Authorization=Bearer hb2-52e8", ["hb2-52e8"]],
  ["  aUtHoRiZaTiOn: bEaReR 'hb3-42f8',  ", ["hb3-42f8"]],
  ["PASSWORD=pc1-31a7 pc2-31a7 pc3-31a7", ["pc1-31a7", "pc2-31a7", "pc3-31a7"]],
  ["PASSWORD=first second third", ["first", "second", "third"]],
  ["PASSWORD='first second third'", ["first", "second", "third"]],
  ["PASSWORD='ps1-21b7 ps2-21b7 ps3-21b7'", ["ps1-21b7", "ps2-21b7", "ps3-21b7"]],
  ['PASSWORD="pd1-11c7 pd2-11c7 pd3-11c7"', ["pd1-11c7", "pd2-11c7", "pd3-11c7"]],
  ["session token sn1-90d6", ["sn1-90d6"]],
  ["access token an1-80e6", ["an1-80e6"]],
  ["refresh token rn1-70f6", ["rn1-70f6"]],
  ["API key ak1-60a5", ["ak1-60a5"]],
  ["client secret cs1-50b5", ["cs1-50b5"]],
  ["database password dp1-40c5 dp2-40c5", ["dp1-40c5", "dp2-40c5"]],
  ["DATABASE_URL=postgresql://du1-30d4:db1-30d4@127.0.0.1/disposable", ["du1-30d4", "db1-30d4"]],
  ["TOKEN_ENCRYPTION_KEY=ek1-20e4", ["ek1-20e4"]],
  ["PLAID_SECRET=pl1-10f4", ["pl1-10f4"]],
  ["PLAID_CLIENT_ID=pi1-99a3", ["pi1-99a3"]],
  ["GITHUB_TOKEN=gt1-89b3", ["gt1-89b3"]],
  ["SESSION_TOKEN=st1-79c3", ["st1-79c3"]],
  ["JWT=jt1-69d3", ["jt1-69d3"]],
  ["db_passwd=pw1-59e3", ["pw1-59e3"]],
  ["custom_secret=sc1-49f3", ["sc1-49f3"]],
  ["custom_token=ct1-39a2", ["ct1-39a2"]],
  ["custom_api_key=ck1-29b2", ["ck1-29b2"]],
  ["custom_api-key=ch1-19c2", ["ch1-19c2"]],
  ["custom_authorization=ca1-09d2", ["ca1-09d2"]],
  ["custom_credential=cc1-98e1", ["cc1-98e1"]],
  ["my-secret-value: sf1-87d1 sf2-87d1", ["sf1-87d1", "sf2-87d1"]],
  ["token_value: tv1-76e1", ["tv1-76e1"]],
  ["api-key-value: ak2-65f1", ["ak2-65f1"]],
  ["Bearer 'mx1-88f1'; PASSWORD=mx2-88f1 mx3-88f1; session token mx4-88f1", ["mx1-88f1", "mx2-88f1", "mx3-88f1", "mx4-88f1"]],
];
function assertNoSentinels(value, sentinels) {
  const serialized = typeof value === "string" ? value : JSON.stringify(value);
  for (const sentinel of sentinels) assert.ok(!serialized.includes(sentinel), "Synthetic credential survived publication policy");
}
function scanPublished(directory, sentinels) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...scanPublished(file, sentinels));
    else { assertNoSentinels(fs.readFileSync(file, "utf8"), sentinels); files.push(file); }
  }
  return files;
}
function publishedFailure(f, sentinels) {
  const { result, manifest, published } = execute(f);
  assert.equal(result.status, 1);
  assert.equal(manifest.finalized, false);
  assert.equal(manifest.checksPassed, false);
  assert.equal(manifest.releaseReady, false);
  assertNoSentinels(result.stdout + result.stderr, sentinels);
  const files = scanPublished(published, sentinels);
  assert.deepEqual(files.map((file) => path.basename(file)).sort(), ["backend.json", "static.failure.json", "static.log", "static.suites.json"]);
  const bytes = fs.readFileSync(path.join(published, "static.failure.json"));
  const detail = JSON.parse(bytes);
  assert.equal(detail.gate, manifest.gates[0].id);
  assert.equal(detail.exitCode, manifest.gates[0].exitCode);
  assert.equal(detail.availability, manifest.gates[0].failureEvidence.availability);
  assert.equal(detail.publicationSafety, manifest.gates[0].failureEvidence.publicationSafety);
  assert.equal(require("../validate-candidate").digest(bytes), manifest.gates[0].failureEvidence.hash);
  assert.equal(manifest.commit, spawnSync("git", ["rev-parse", "HEAD"], { cwd: f.repo, encoding: "utf8" }).stdout.trim());
  assert.equal(bytes.toString(), JSON.stringify(detail, null, 2) + "\n");
  completedPublicationScans++;
  scannedPublicationFiles += files.length;
  return detail;
}
test("credential variants fence whole names/messages in memory, serialization and actual CLI artifacts", (t) => {
  for (const [credential, sentinels] of credentialCases) {
    const message = `expected safe rejection; ${credential}; ordinary trailing assertion`;
    const name = `ordinary case; ${credential}`;
    const memory = report(message, "", name);
    assertNoSentinels(memory, sentinels);
    assert.equal(memory.failingTests[0].fieldAvailability.name, "redacted");
    assert.equal(memory.fieldAvailability.message, "redacted");
    assert.notEqual(memory.availability, "available");
    const prepared = prepareFailurePublication(memory, { gate: "backend-chain", exitCode: 17, reason: "command-failed", repo: source });
    assertNoSentinels(prepared.serialized, sentinels);
    assert.equal(prepared.report.publicationSafety, "passed");
    assert.equal(JSON.parse(prepared.serialized).fieldAvailability.message, "redacted");
    const f = fixture(t, `const test=require("node:test"),assert=require("node:assert/strict");\ntest(${JSON.stringify(name)},()=>assert.fail(${JSON.stringify(message)}));\n`);
    const output = publishedFailure(f, sentinels);
    assert.equal(output.failingTests[0].name, null);
    assert.equal(output.message, null);
    assert.equal(output.fieldAvailability.message, "redacted");
    assert.equal(output.publicationSafety, "passed");
  }
});
test("redaction of a single field does not erase other safe failure identity or assertion fields", () => {
  const name = report("expected one denied request", "", "rejects Bearer 'nm1-77a1'");
  assert.equal(name.failingTests[0].name, null);
  assert.equal(name.message, "expected one denied request");
  assert.equal(name.fieldAvailability.name, "redacted");
  const message = report("expected rejection; session token ms1-66b1");
  assert.equal(message.failingTests[0].name, "ordinary failure identity");
  assert.equal(message.errorClass, "AssertionError");
  assert.equal(message.sourceLocation, "plaid-backend/scripts/auth-check.js:42:7");
  assert.equal(message.fieldAvailability.message, "redacted");
  assertNoSentinels([name, message], ["nm1-77a1", "ms1-66b1"]);
});
test("publication refuses inconsistent availability and root diagnostic aliases", () => {
  const context = { gate: "backend-chain", exitCode: 17, reason: "command-failed", repo: source };
  const redacted = report("expected rejection; session token av1-68c1");
  assert.equal(redacted.availability, "partial");
  redacted.availability = "available";
  const denied = prepareFailurePublication(redacted, context);
  assert.equal(denied.report.publicationSafety, "rejected");
  assert.equal(denied.report.availability, "unavailable");
  assertNoSentinels(denied.serialized, ["av1-68c1"]);
  const mismatched = report("expected exactly one acknowledgment");
  mismatched.message = "unrelated safe assertion";
  assert.equal(prepareFailurePublication(mismatched, context).report.publicationSafety, "rejected");
});
test("final serialized publication gate rejects bypassed sensitive fields including excerpts and command", (t) => {
  for (const options of [
    { tempRoot: fs.realpathSync("/tmp") },
    { rootPrefix: "caldera failure (safe)-", repoPath: "nested fixtures/repo (safe)-one" },
  ]) {
  for (const field of ["name", "message", "errorClass", "sourceLocation", "sanitizedExcerpt", "command", "extraPayload"]) {
    const sentinel = `fg-${field}-51c1`;
    const bypassed = report("expected one denied request");
    if (field === "name") bypassed.failingTests[0].name = `Bearer '${sentinel}'`;
    else if (field === "sanitizedExcerpt") bypassed.sanitizedExcerpt.push(`session token ${sentinel}`);
    else bypassed[field] = `PASSWORD=${sentinel} trailing secret word`;
    const context = { gate: "backend-chain", exitCode: 17, reason: "command-failed", repo: source };
    const publication = prepareFailurePublication(bypassed, context);
    assert.equal(publication.report.publicationSafety, "rejected");
    assert.equal(publication.report.availability, "unavailable");
    assert.match(publication.report.diagnosticNotice, /publication redaction policy/);
    assertNoSentinels(publication.serialized, [sentinel]);

    const f = fixture(t, 'const test=require("node:test"),assert=require("node:assert/strict");\ntest("ordinary safe failure",()=>assert.fail("expected one denied request"));\n', options);
    // Test-only preload bypasses the primary extractor, NOT the final gate or
    // writer. It is outside the clean synthetic Git candidate and never enabled
    // by a production CLI argument or the workflow.
    const preload = path.join(f.root, options.repoPath ? "fixture preloads/bypass-primary (safe).cjs" : "bypass-primary.cjs");
    fs.mkdirSync(path.dirname(preload), { recursive: true });
    fs.writeFileSync(preload, `const api=require(${JSON.stringify(path.join(f.repo, "scripts/validation/backend-failure-evidence.js"))});
const original=api.failureReport; api.failureReport=(context)=>{const report=original(context);
${field === "name" ? `report.failingTests[0].name=${JSON.stringify(`Bearer '${sentinel}'`)};` :
  field === "sanitizedExcerpt" ? `report.sanitizedExcerpt.push(${JSON.stringify(`session token ${sentinel}`)});` :
  `report[${JSON.stringify(field)}]=${JSON.stringify(`PASSWORD=${sentinel} trailing secret word`)};`}
return report;};\n`);
    f.preload = preload;
    const output = publishedFailure(f, [sentinel]);
    assert.equal(output.publicationSafety, "rejected");
    assert.equal(output.availability, "unavailable");
  }
  }
});

function sourceReport(value) {
  return failureReport({ gate: "static", exitCode: 1, repo: source,
    raw: `not ok 1 - ordinary source fixture\n  ---\n  name: 'AssertionError'\n  error: 'expected one denied request'\n  location: ${value}\n  ...\n` });
}
test("owned source locations parse right-anchored coordinates with spaces and punctuation", () => {
  for (const [value, expected] of [
    ["scripts/check.js:42:7", "scripts/check.js:42:7"],
    [`${source}/scripts/folder with spaces/check.js:42`, "scripts/folder with spaces/check.js:42"],
    [`TestContext.run (${source}/scripts/folder with spaces/check.js:42:7)`, "scripts/folder with spaces/check.js:42:7"],
    [`at check (${source}/plaid-backend/scripts/check (old)-one.js:42)`, "plaid-backend/scripts/check (old)-one.js:42"],
    [`'file://${source}/scripts/check (old)-one.js:42:7'`, "scripts/check (old)-one.js:42:7"],
    ["scripts/check+one,@!.js:42", "scripts/check+one,@!.js:42"],
  ]) {
    const parsed = sourceReport(value);
    assert.equal(parsed.sourceLocation, expected);
    const publication = prepareFailurePublication(parsed, { gate: "static", exitCode: 1, reason: "command-failed", repo: source });
    assert.equal(publication.report.publicationSafety, "passed");
    assert.equal(JSON.parse(publication.serialized).sourceLocation, expected);
  }
});
test("malformed, credential-bearing and ambiguous source locations stay unavailable", () => {
  for (const value of ["scripts/check.js:0", "scripts/check.js:-1", "scripts/check.js:1:0", "scripts/check.js:1:-2",
    "scripts/check.js:1.2", "scripts/check.js:10000000", "scripts/check.js:9007199254740993",
    "scripts/check.js:1:2:3", "scripts/check.js:1:", "scripts/check.js:1:two",
    "arbitrary payload scripts/check.js:42:7", `arbitrary payload (${source}/scripts/check.js:42:7)`,
    "scripts/../check.js:42:7", "scripts//check.js:42:7",
    "/unowned/scripts/check.js:42:7", "scripts/node_modules/check.js:42:7",
    "scripts/PASSWORD=source-sentinel.js:42:7", "scripts/session token source-sentinel.js:42:7",
    `Bearer source-sentinel (${source}/scripts/check.js:42:7)`,
    "https://source-sentinel@example.invalid/scripts/check.js:42:7"]) {
    const parsed = sourceReport(value);
    assert.equal(parsed.sourceLocation, null, "Unsafe or malformed location was accepted");
    const publication = prepareFailurePublication(parsed, { gate: "static", exitCode: 1, reason: "command-failed", repo: source });
    assert.equal(publication.report.publicationSafety, "passed");
    assertNoSentinels(publication.serialized, ["source-sentinel"]);
  }
});
test("actual CLI publishes a safe source path with spaces and punctuation with matching hashes", (t) => {
  const f = fixture(t, 'const test=require("node:test"),assert=require("node:assert/strict");\ntest("ordinary source fixture",()=>assert.fail("expected one denied request"));\n',
    { rootPrefix: "caldera source (safe)-", repoPath: "nested fixtures/repo (safe)-one", scriptPath: "scripts/source fixtures/check (old)-one.test.js" });
  const output = publishedFailure(f, ["source-secret-sentinel"]);
  assert.equal(output.publicationSafety, "passed");
  assert.equal(output.availability, "available");
  assert.match(output.sourceLocation, /^scripts\/source fixtures\/check \(old\)-one\.test\.js:[1-9][0-9]*:[1-9][0-9]*$/);
});
test("known safe containment assertion and ordinary source paths survive final publication", () => {
  const safe = report("The input did not match the regular expression /Validation blocked/. Input:", "",
    "backend external socket and DNS attempts reject before any connection");
  safe.sourceLocation = safe.failingTests[0].sourceLocation = "scripts/tests/validate-candidate.test.js:419:12";
  const publication = prepareFailurePublication(safe, { gate: "backend-chain", exitCode: 17, reason: "command-failed", repo: source });
  // Reconstruct after updating the controlled source fixture, exactly as the
  // real parser does; the gate intentionally rejects inconsistent excerpts.
  assert.equal(publication.report.publicationSafety, "rejected");
  const real = failureReport({ gate: "static", exitCode: 1, repo: source,
    raw: `not ok 1 - backend external socket and DNS attempts reject before any connection\n  ---\n  error: |-\n    The input did not match the regular expression /Validation blocked/. Input:\n\n    private comparison payload omitted\n  code: 'ERR_ASSERTION'\n  stack: |-\n    Test.run (${source}/scripts/tests/validate-candidate.test.js:419:12)\n  ...\n` });
  const output = prepareFailurePublication(real, { gate: "static", exitCode: 1, reason: "command-failed", repo: source });
  assert.equal(output.report.publicationSafety, "passed");
  assert.equal(output.report.availability, "available");
  assert.match(output.report.message, /regular expression \/Validation blocked\//);
  assert.equal(output.report.errorClass, "AssertionError");
  assert.equal(output.report.sourceLocation, "scripts/tests/validate-candidate.test.js:419:12");
  assert.doesNotMatch(output.serialized, /private comparison payload/);
});
test("actual and expected financial/provider payloads survive only in private child logs", (t) => {
  const f = fixture(t, `const test=require("node:test"),assert=require("node:assert/strict");
test("safe structured assertion",()=>assert.deepEqual({accounts:[{name:"fp1-47d2",balance:987.12}],access_token:"fp2-47d2"},{}));\n`);
  const output = publishedFailure(f, ["fp1-47d2", "fp2-47d2", "987.12"]);
  assert.equal(output.publicationSafety, "passed");
  assert.equal(output.errorClass, "AssertionError");
  assert.match(fs.readFileSync(path.join(f.evidence, "static.raw.log"), "utf8"), /fp1-47d2/);
});
test("ordinary assertion prose remains useful without publishing actual/expected payloads", () => {
  const result = report("expected exactly one durable acknowledgment", `  actual:\n    accounts: [{ balance: 900, name: 'sentinel-financial-name' }]\n  expected:\n    access_token: 'sentinel-raw-token'\n  operator: 'deepStrictEqual'`);
  assert.equal(result.message, "expected exactly one durable acknowledgment");
  assert.equal(result.failingTests[0].sourceLocation, "plaid-backend/scripts/auth-check.js:42:7");
  assert.equal(result.availability, "available");
  assert.doesNotMatch(JSON.stringify(result), /sentinel-financial-name|sentinel-raw-token|900|deepStrictEqual/);
  const multiline = failureReport({ gate: "static", exitCode: 1, repo: source,
    raw: "not ok 1 - safe numeric assertion\n  ---\n  error: |-\n    Expected values to be strictly equal:\n    \n    987.12 !== 900.45\n  code: 'ERR_ASSERTION'\n  ...\n" });
  assert.equal(multiline.message, "Expected values to be strictly equal:");
  assert.doesNotMatch(JSON.stringify(multiline), /987\.12|900\.45/);
  const regex = report("The input did not match the regular expression /sentinel-private-pattern/. Input:");
  assert.equal(regex.message, "The input did not match the required regular expression; regex/input values omitted.");
  assert.doesNotMatch(JSON.stringify(regex), /sentinel-private-pattern/);
});
test("unclassified output and unsafe fields explicitly report unavailable safe detail", () => {
  for (const raw of ["unstructured private stdout sentinel-private-data", "{\"accounts\":[987.12]}",
    "DATABASE_URL=sentinel-database-value\nCUSTOM_ENV_VALUE=sentinel-env-value"]) {
    const result = failureReport({ gate: "postgres-startup", exitCode: 64, repo: source, raw });
    assert.equal(result.availability, "unavailable");
    assert.match(result.diagnosticNotice, /Safe failure detail unavailable/);
    assert.ok(result.missingDetails.length);
    assert.equal(result.exitCode, 64);
    assert.doesNotMatch(JSON.stringify(result), /sentinel-|987\.12/);
  }
  for (const message of ['{"accounts":[{"balance":987.12}]}', "balance: 987.12", "Cushion $987.12", "987.12", "Checking was 987.12",
    "CUSTOM_ENV_VALUE=unclassified-value", "read /private/credentials/.env", "assertion \u0000 private"]) {
    const result = report(message);
    assert.equal(result.message, null);
    assert.ok(result.missingDetails.includes("safe assertion/message unavailable"));
    assert.doesNotMatch(JSON.stringify(result), /987\.12|unclassified-value|credentials|private/);
  }
});
test("plain Node assertion errors retain class, safe message and owned source but not source dumps", () => {
  const result = failureReport({ gate: "backend-chain", exitCode: 1, repo: source,
    raw: `${source}/plaid-backend/scripts/auth-check.js:42\nassert.equal(account.balance, 987.12);\n\nAssertionError [ERR_ASSERTION]: expected a rejected request\n    at check (${source}/plaid-backend/scripts/auth-check.js:42:7)\n  actual: { balance: 987.12 },\n  expected: 0\n` });
  assert.equal(result.errorClass, "AssertionError");
  assert.equal(result.message, "expected a rejected request");
  assert.equal(result.sourceLocation, "plaid-backend/scripts/auth-check.js:42:7");
  assert.equal(result.availability, "partial");
  assert.doesNotMatch(JSON.stringify(result), /987\.12|account\.balance|expected: 0/);
  const nested = failureReport({ gate: "backend-chain", exitCode: 1, repo: source,
    raw: `not ok 1 - safe failure name\n  ---\n  actual:\n    error: 'sentinel-nested-provider-error'\n    name: 'AssertionError'\n    stack: '${source}/plaid-backend/scripts/auth-check.js:42:7'\n  ...\n` });
  assert.equal(nested.message, null);
  assert.equal(nested.errorClass, null);
  assert.equal(nested.sourceLocation, null);
  assert.doesNotMatch(JSON.stringify(nested), /sentinel-nested-provider-error/);
});
test("every failed backend gate retains explicit failure evidence; successful gates fabricate none", (t) => {
  const f = fixture(t, "process.exit(0);\n");
  const gate = require("../validate-candidate");
  const passed = (command, args, options) => {
    const raw = args.at(-1) === "chain" ? "Postgres Plaid item store check passed.\n" :
      args.at(-1) === "startup" ? "Guarded real backend Postgres startup passed: migrations, required auth, disabled dev auth, no provider requests.\n" : "";
    fs.writeFileSync(options.log, raw);
    syntheticPassingSuites(args, options);
    return 0;
  };
  for (const failed of gate.GATES.backend) {
    const evidence = path.join(f.root, `failed-${failed}`);
    const value = gate.execute({ repo: f.repo, evidence, mode: "backend" }, { env: f.env,
      run(command, args, options) {
        passed(command, args, options);
        const id = args.at(-1) === "chain" ? "backend-chain" : args.at(-1) === "startup" ? "postgres-startup" : "static";
        if (id !== failed) return 0;
        fs.writeFileSync(options.log, "unknown sensitive provider output sentinel-not-publishable");
        return 23;
      } });
    assert.equal(value.checksPassed, false);
    assert.equal(value.gates.at(-1).exitCode, 23);
    const report = JSON.parse(fs.readFileSync(path.join(evidence, `publish/${failed}.failure.json`)));
    assert.equal(report.availability, "unavailable");
    assert.equal(report.exitCode, 23);
    assert.doesNotMatch(JSON.stringify(report), /sentinel-not-publishable/);
  }
  const evidence = path.join(f.root, "healthy");
  const value = gate.execute({ repo: f.repo, evidence, mode: "backend" }, { env: f.env, run: passed });
  assert.equal(value.checksPassed, true);
  assert.ok(value.gates.every((g) => g.failureEvidence === undefined));
  assert.equal(fs.readdirSync(path.join(evidence, "publish")).some((name) => name.endsWith(".failure.json")), false);
});
test("zero-exit skips or missing required execution remain failed with reason and missing-detail notice", (t) => {
  const f = fixture(t, "process.exit(0);\n");
  const gate = require("../validate-candidate");
  for (const raw of ["# skipped 1\n", "no execution marker\n"]) {
    const evidence = path.join(f.root, raw.startsWith("#") ? "skipped" : "missing-marker");
    const value = gate.execute({ repo: f.repo, evidence, mode: "backend" }, { env: f.env,
      run(command, args, options) { syntheticPassingSuites(args, options); fs.writeFileSync(options.log, args.at(-1) === "chain" ? raw : ""); return 0; } });
    assert.equal(value.checksPassed, false);
    const failure = JSON.parse(fs.readFileSync(path.join(evidence, "publish/backend-chain.failure.json")));
    assert.equal(failure.exitCode, 0);
    assert.equal(failure.availability, "unavailable");
    assert.equal(failure.reason, raw.startsWith("#") ? "required-tests-skipped" : "required-postgres-execution-marker-missing");
  }
});
