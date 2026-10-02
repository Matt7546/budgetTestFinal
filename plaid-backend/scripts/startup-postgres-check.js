const assert = require("node:assert/strict");
const { requireDisposableTarget, assertDisposableTarget } = require("./postgres-test-target");
const { launchBackend, stopBackend, requestJSON } = require("./startup-test-process");
let phase = "disposable_preflight";

async function run() {
  // Authorize and prove an empty disposable target BEFORE the real server can
  // apply any migration. No application .env or inherited credential is used.
  const target = requireDisposableTarget();
  const { createPool } = require("../db");
  const pool = createPool(target.databaseUrl);
  let backend;
  try {
    phase = "database_identity";
    await assertDisposableTarget(pool, target);
    phase = "backend_startup";
    backend = await launchBackend({
      RENDER: "true", NODE_ENV: "production", PLAID_ENV: "sandbox",
      AUTH_MODE: "required", TOKEN_STORE_DRIVER: "postgres", DEV_AUTH_ENABLED: "false",
      DATABASE_URL: target.databaseUrl, TOKEN_ENCRYPTION_KEY: process.env.TOKEN_ENCRYPTION_KEY,
      APP_API_KEY: "synthetic-app-key", PLAID_CLIENT_ID: "synthetic-client",
      PLAID_SECRET: "synthetic-provider-secret", APPLE_CLIENT_ID: "com.example.test",
    }, { databasePort: new URL(target.databaseUrl).port });
    assert.ok(backend.port, "Real deployed-like backend must complete startup");
    phase = "health_and_auth";
    const health = await requestJSON(backend, "/api/health");
    assert.equal(health.status, 200);
    assert.equal(health.body.auth_mode, "required");
    assert.equal(health.body.storage_driver, "postgres");
    const unauthenticated = await requestJSON(backend, "/api/accounts", {
      headers: { "x-app-api-key": "synthetic-app-key" },
    });
    assert.equal(unauthenticated.status, 401);
    const development = await requestJSON(backend, "/api/auth/development", {
      method: "POST", headers: { "x-app-api-key": "synthetic-app-key" },
    });
    assert.equal(development.status, 409);
    assert.equal(development.body.development_auth_enabled, false);
    assert.match(development.body.message, /deployed or production/);
    assert.doesNotMatch(development.body.message, /Add DEV_AUTH_ENABLED/);
    assert.equal(backend.events.some((event) => event.kind === "unexpected-network"), false);
    assert.match(backend.output(), /Postgres Plaid item store initialized/);
    assert.match(backend.output(), /Caldera auth session store initialized/);
    for (const completion of ["Postgres Plaid item store initialized", "Caldera auth session store initialized"]) {
      assert.ok(backend.output().indexOf(completion) < backend.output().indexOf("backend running"));
    }
    assert.match(backend.output(), /Startup JSON token store import skipped/);
    phase = "migrated_schema";
    const schema = await pool.query(`SELECT to_regclass('public.user_sessions') AS sessions,
      to_regclass('public.plaid_item_exchange_leases') AS leases,
      EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
        AND table_name='plaid_items' AND column_name='historical_ready_at') AS readiness`);
    assert.ok(schema.rows[0].sessions);
    assert.ok(schema.rows[0].leases);
    assert.equal(schema.rows[0].readiness, true);
    console.log("Guarded real backend Postgres startup passed: migrations, required auth, disabled dev auth, no provider requests.");
  } finally {
    if (backend) await stopBackend(backend);
    await pool.end();
  }
}

run().catch((error) => {
  // Even test failures must not echo connection credentials or test keys.
  const knownSafeGuardMessages = new Set([
    "Explicit disposable Postgres test authorization is required.",
    "Postgres test database must be newly created and empty.",
  ]);
  const detail = knownSafeGuardMessages.has(error.message) ? ` ${error.message}` : "";
  console.error(`Guarded backend startup check failed at ${phase}; verify disposable authorization, dependencies, target, and assertions.${detail}`);
  process.exitCode = 1;
});
