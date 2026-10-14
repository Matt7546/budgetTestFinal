const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { runFiles } = require("./backend-suite-result");
const repo = path.resolve(__dirname, "../..");
function check(command, args) {
  const result = spawnSync(command, args, { cwd: repo, stdio: "inherit" });
  if (result.status !== 0) process.exit(result.status || 1);
}
function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if (["node_modules", ".git"].includes(entry.name)) return [];
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(file) : [file];
  });
}
check("git", ["diff", "--check"]);
for (const file of [...walk(path.join(repo, "scripts")), ...walk(path.join(repo, "plaid-backend"))]) {
  if (/\.(js|cjs)$/.test(file)) check("node", ["--check", file]);
  if (file.endsWith(".sh")) check("bash", ["-n", file]);
}
// Stable structured diagnostics regardless of the Node version's default reporter.
const result = runFiles({ suite: "static", cwd: repo, files: ["scripts/tests/validate-summary.test.js", "scripts/tests/validate-candidate.test.js",
  "scripts/tests/backend-failure-evidence.test.js",
  "scripts/tests/contained-network.test.js", "scripts/tests/backend-test-chain.test.js",
  "scripts/tests/backend-suite-result.test.js", "plaid-backend/scripts/postgres-test-target.test.js"] });
if (result.exitCode !== 0) process.exit(result.exitCode);
console.log("Static and validation-contract checks passed.");
