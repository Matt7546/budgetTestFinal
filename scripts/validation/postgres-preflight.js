const { requireDisposableTarget, assertDisposableTarget } = require("../../plaid-backend/scripts/postgres-test-target");

async function run() {
  const target = requireDisposableTarget();
  const { createPool } = require("../../plaid-backend/db");
  const pool = createPool(target.databaseUrl);
  try { await assertDisposableTarget(pool, target); }
  finally { await pool.end(); }
  console.log("Disposable Postgres target verified before test execution.");
}
run().catch(() => {
  console.error("Validation blocked: disposable Postgres target verification failed.");
  process.exitCode = 1;
});
