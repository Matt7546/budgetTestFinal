const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const sourceWrapper = path.join(__dirname, "..", "validate-summary.sh");

function runWrapper(checkExitCode) {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "caldera-validation-wrapper-"));
  try {
    const fixtureScripts = path.join(fixtureRoot, "scripts");
    fs.mkdirSync(fixtureScripts);
    const wrapper = path.join(fixtureScripts, "validate-summary.sh");
    const check = path.join(fixtureScripts, "validate.sh");
    const log = path.join(fixtureRoot, "validation.log");

    fs.copyFileSync(sourceWrapper, wrapper);
    fs.writeFileSync(check, [
      "#!/usr/bin/env bash",
      'printf "** BUILD SUCCEEDED **\\n"',
      'printf "error: simulated validation failure\\n" >&2',
      'exit "${VALIDATE_EXIT_CODE}"',
      "",
    ].join("\n"));
    fs.chmodSync(check, 0o700);

    const result = spawnSync("bash", [wrapper], {
      encoding: "utf8",
      env: {
        ...process.env,
        VALIDATE_EXIT_CODE: String(checkExitCode),
        CALDERA_VALIDATION_LOG_PATH: log,
      },
    });

    assert.equal(result.error, undefined);
    assert.equal(fs.existsSync(log), true);
    return result;
  } finally {
    fs.rmSync(fixtureRoot, { recursive: true, force: true });
  }
}

test("validation wrapper reports success only when the check succeeds", () => {
  const result = runWrapper(0);
  assert.equal(result.status, 0);
  assert.match(result.stdout, /Result: BUILD CHECKS PASSED/);
});

for (const failureCode of [3, 17]) {
  test(`validation wrapper preserves failure exit ${failureCode}`, () => {
    const result = runWrapper(failureCode);
    assert.equal(result.status, failureCode);
    assert.match(result.stdout, /Result: BUILD CHECKS FAILED/);
    assert.doesNotMatch(result.stdout, /Result: BUILD CHECKS PASSED/);
  });
}
