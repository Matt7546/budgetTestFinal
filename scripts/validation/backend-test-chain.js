// Execute the non-DB components of the DECLARED npm test chain. The disposable
// wrapper runs its final Postgres component separately with the guarded target.
const fs = require("node:fs");
const path = require("node:path");
const { runFiles } = require("./backend-suite-result");

function declaredTests(packageJSON) {
  const scripts = packageJSON.scripts;
  const chain = scripts?.test;
  if (typeof chain !== "string") throw new Error("Declared backend test chain is missing.");
  const tests = chain.split(/\s*&&\s*/).map((command) => {
    const match = command.match(/^npm run (test:[a-z0-9-]+)$/);
    if (!match || typeof scripts[match[1]] !== "string") throw new Error("Unsupported declared backend test chain.");
    return match[1];
  });
  if (tests.length < 2 || new Set(tests).size !== tests.length || tests.at(-1) !== "test:postgres-store") {
    throw new Error("Declared backend chain must end with one required Postgres storage check.");
  }
  return tests;
}
function suiteFile(packageJSON, suite) {
  const match = packageJSON.scripts[suite]?.match(/^node(?: --test)? (scripts\/[a-z0-9.-]+\.js)$/);
  if (!match || packageJSON.scripts[`pre${suite}`] || packageJSON.scripts[`post${suite}`]) {
    throw new Error("Unsupported backend suite invocation.");
  }
  return match[1];
}

if (require.main === module) {
  try {
    const backend = path.resolve(__dirname, "../../plaid-backend");
    const pkg = JSON.parse(fs.readFileSync(path.join(backend, "package.json")));
    const tests = declaredTests(pkg);
    const specific = process.argv[2];
    if (specific && ![tests.at(-1), "test:startup-postgres"].includes(specific)) throw new Error("Unsupported exact DB suite.");
    if (!specific && (process.env.CALDERA_POSTGRES_TEST_CONFIRM !== undefined || process.env.DATABASE_URL !== undefined)) {
      throw new Error("Non-Postgres backend checks must not inherit a database exception.");
    }
    for (const name of specific ? [specific] : tests.slice(0, -1)) {
      const result = runFiles({ suite: name, files: [suiteFile(pkg, name)], cwd: backend });
      if (result.exitCode !== 0) { process.exitCode = result.exitCode; break; }
    }
  } catch {
    console.error("Backend test-chain configuration is invalid; no database exception was granted.");
    process.exitCode = 1;
  }
}
module.exports = { declaredTests, suiteFile };
