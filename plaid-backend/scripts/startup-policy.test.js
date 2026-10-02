const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { resolveBackendStartupPolicy } = require("../startupPolicy");
const { resolveAuthMode } = require("../authConfig");
const { resolveTokenStoreDriver, createPlaidItemStore } = require("../plaidItemStore");
const { launchBackend, stopBackend, requestJSON, waitForEvent } = require("./startup-test-process");

// Synthetic values only. No provider or database credentials are inherited.
const deployed = {
  RENDER: "true", PLAID_ENV: "sandbox", AUTH_MODE: "required",
  TOKEN_STORE_DRIVER: "postgres", DATABASE_URL: "postgresql://127.0.0.1:55439/synthetic",
  TOKEN_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString("base64"),
  APP_API_KEY: "synthetic-app-key", PLAID_CLIENT_ID: "synthetic-client",
  PLAID_SECRET: "synthetic-provider-secret", APPLE_CLIENT_ID: "com.example.test",
};
const local = {
  NODE_ENV: "development", PLAID_ENV: "sandbox", AUTH_MODE: "personal",
  TOKEN_STORE_DRIVER: "json", APP_API_KEY: "synthetic-app-key",
};
const invalidCases = [
  ["deployed missing AUTH_MODE", { AUTH_MODE: undefined }, /AUTH_MODE/],
  ["deployed personal auth", { AUTH_MODE: "personal" }, /AUTH_MODE/],
  ["deployed optional auth", { AUTH_MODE: "optional" }, /AUTH_MODE/],
  ["deployed missing driver", { TOKEN_STORE_DRIVER: undefined }, /TOKEN_STORE_DRIVER/],
  ["deployed JSON driver", { TOKEN_STORE_DRIVER: "json" }, /TOKEN_STORE_DRIVER/],
  ["deployed dev auth", { DEV_AUTH_ENABLED: "true" }, /DEV_AUTH_ENABLED/],
  ["unknown auth mode", { AUTH_MODE: "unknown" }, /AUTH_MODE/],
  ["unknown store driver", { TOKEN_STORE_DRIVER: "unknown" }, /TOKEN_STORE_DRIVER/],
  ["missing database", { DATABASE_URL: undefined }, /DATABASE_URL/],
  ["malformed database URL", { DATABASE_URL: "https://secret-user:secret-password@example.invalid/db" }, /DATABASE_URL/],
  ["missing encryption key", { TOKEN_ENCRYPTION_KEY: undefined }, /TOKEN_ENCRYPTION_KEY/],
  ["malformed encryption key", { TOKEN_ENCRYPTION_KEY: "invalid-key" }, /TOKEN_ENCRYPTION_KEY/],
  ["unknown dev auth value", { DEV_AUTH_ENABLED: "unknown" }, /DEV_AUTH_ENABLED/],
  ["unknown Plaid environment", { PLAID_ENV: "unknown" }, /PLAID_ENV/],
  ["missing Plaid environment", { PLAID_ENV: undefined }, /PLAID_ENV/],
  ["unknown NODE_ENV", { NODE_ENV: "unknown" }, /NODE_ENV/],
  ["malformed Render identity", { RENDER: "unknown" }, /RENDER/],
  ...["APP_API_KEY", "PLAID_CLIENT_ID", "PLAID_SECRET", "APPLE_CLIENT_ID"]
    .map((name) => [`deployed missing ${name}`, { [name]: undefined }, new RegExp(name)]),
];

for (const [name, override, expected] of invalidCases) {
  test(`startup policy rejects ${name}`, () => {
    assert.throws(() => resolveBackendStartupPolicy({ ...deployed, ...override }), expected);
  });
}

test("production signals cannot be weakened by local settings", () => {
  for (const signal of [{ RENDER: "true" }, { RENDER_SERVICE_ID: "synthetic-service" },
    { NODE_ENV: "production" }, { PLAID_ENV: "production" }]) {
    assert.throws(() => resolveBackendStartupPolicy({ ...local, ...signal }), /AUTH_MODE/);
    const policy = resolveBackendStartupPolicy({ ...deployed, RENDER: "false", NODE_ENV: "development", ...signal });
    assert.equal(policy.deploymentClass, "deployed");
    assert.equal(policy.developmentAuthEnabled, false);
    assert.equal(policy.hasDeploymentSignal, signal.PLAID_ENV !== "production");
  }
});

test("unknown identity fails closed despite explicit personal/JSON", () => {
  assert.throws(() => resolveBackendStartupPolicy({ ...local, NODE_ENV: undefined }), /identity/);
  assert.throws(() => resolveBackendStartupPolicy({}), /PLAID_ENV/);
});

test("explicit local and test compatibility retains supported modes", () => {
  for (const NODE_ENV of ["development", "test"]) {
    const policy = resolveBackendStartupPolicy({ ...local, NODE_ENV, DEV_AUTH_ENABLED: "true" });
    assert.equal(policy.deploymentClass, "local");
    assert.equal(policy.authMode, "personal");
    assert.equal(policy.tokenStoreDriver, "json");
    assert.equal(policy.developmentAuthEnabled, true);
  }
  for (const AUTH_MODE of ["optional", "required"]) {
    assert.equal(resolveBackendStartupPolicy({ ...local, AUTH_MODE,
      DATABASE_URL: deployed.DATABASE_URL }).authMode, AUTH_MODE);
    assert.throws(() => resolveBackendStartupPolicy({ ...local, AUTH_MODE }), /DATABASE_URL/);
  }
  assert.equal(resolveBackendStartupPolicy({ ...local, PLAID_ENV: "development" }).deploymentClass, "local");
  assert.throws(() => resolveBackendStartupPolicy({ ...local, AUTH_MODE: undefined }), /AUTH_MODE/);
  assert.throws(() => resolveBackendStartupPolicy({ ...local, TOKEN_STORE_DRIVER: undefined }), /TOKEN_STORE_DRIVER/);
});

test("legacy selection helpers remain local-tool compatible, never server defaults", async () => {
  assert.equal(resolveAuthMode({}), "personal");
  assert.equal(resolveTokenStoreDriver({}), "json");
  assert.equal(resolveTokenStoreDriver({ TOKEN_STORE_DRIVER: "postgres" }), "postgres");
  assert.throws(() => resolveTokenStoreDriver({ TOKEN_STORE_DRIVER: "sqlite" }), /TOKEN_STORE_DRIVER/);
  assert.throws(() => createPlaidItemStore({ env: { TOKEN_STORE_DRIVER: "postgres" } }), /DATABASE_URL/);
  assert.throws(() => createPlaidItemStore({ env: { TOKEN_STORE_DRIVER: "postgres",
    DATABASE_URL: deployed.DATABASE_URL } }), /TOKEN_ENCRYPTION_KEY/);
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "caldera-store-selection-"));
  try {
    const store = createPlaidItemStore({ env: { TOKEN_STORE_DRIVER: "json" },
      tokenStorePath: path.join(directory, "items.json") });
    assert.deepEqual(await store.getUserItems("synthetic-owner"), []);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test("safe deployed configuration accepts without connecting or exposing secrets", () => {
  const result = resolveBackendStartupPolicy(deployed);
  assert.deepEqual(result, { deploymentClass: "deployed", isDeployed: true, hasDeploymentSignal: true,
    plaidEnvironment: "sandbox", authMode: "required", tokenStoreDriver: "postgres",
    developmentAuthEnabled: false });
  assert.ok(Object.isFrozen(result));
  assert.equal(JSON.stringify(result).includes(deployed.TOKEN_ENCRYPTION_KEY), false);
});

test("configuration errors contain names, not supplied credentials", () => {
  for (const override of [
    { DATABASE_URL: "https://secret-user:secret-password@example.invalid/db" },
    { TOKEN_ENCRYPTION_KEY: "secret-encryption-value" },
    { AUTH_MODE: "secret-session-value" },
  ]) {
    try {
      resolveBackendStartupPolicy({ ...deployed, ...override });
      assert.fail("Malformed configuration must reject");
    } catch (error) {
      for (const secret of Object.values(override)) assert.equal(error.message.includes(secret), false);
    }
  }
});

test("real index.js rejects unsafe configuration before app/store/client/listen", async () => {
  const cases = [
    ...invalidCases.map(([name, override, expected]) => [name, { ...deployed, ...override }, expected]),
    ["unknown deployment identity", { ...local, NODE_ENV: undefined }, /identity/],
    ["production Plaid overrides local", { ...local, PLAID_ENV: "production" }, /AUTH_MODE/],
    ["production NODE_ENV overrides local", { ...local, NODE_ENV: "production" }, /AUTH_MODE/],
    ["Render identity cannot be weakened by false flag", { ...local, RENDER: "false",
      RENDER_SERVICE_ID: "synthetic-service" }, /AUTH_MODE/],
    ["production Plaid rejects dev auth", { ...deployed, RENDER: "false",
      NODE_ENV: "development", PLAID_ENV: "production", DEV_AUTH_ENABLED: "true" }, /DEV_AUTH_ENABLED/],
    ["production NODE_ENV rejects dev auth", { ...deployed, RENDER: "false",
      NODE_ENV: "production", DEV_AUTH_ENABLED: "true" }, /DEV_AUTH_ENABLED/],
  ];
  for (const [name, env, expected] of cases) {
    const backend = await launchBackend(env);
    try {
      assert.equal(backend.exitCode, 1, name);
      assert.equal(backend.port, null, name);
      assert.deepEqual(backend.events, [], name);
      assert.match(backend.output(), expected);
      assert.doesNotMatch(backend.output(), /backend running|store initialized|secret-password|secret-provider|invalid-key/);
      assert.deepEqual(fs.readdirSync(backend.directory), [], name);
    } finally { await stopBackend(backend); }
  }
});

test("real local Express composition boots with explicit personal/JSON and contained dev auth", async () => {
  const backend = await launchBackend({ ...local, DEV_AUTH_ENABLED: "true" });
  try {
    assert.ok(backend.port);
    assert.equal(backend.events.some((event) => event.kind === "unexpected-network"), false);
    const health = await requestJSON(backend, "/api/health");
    assert.equal(health.status, 200);
    assert.equal(health.body.auth_mode, "personal");
    assert.equal(health.body.storage_driver, "json");
    assert.equal(health.body.plaid_env, "sandbox");
    const noKey = await requestJSON(backend, "/api/accounts");
    assert.equal(noKey.status, 401);
    const dev = await requestJSON(backend, "/api/auth/development", {
      method: "POST", headers: { "x-app-api-key": local.APP_API_KEY },
    });
    assert.equal(dev.status, 200);
    assert.equal(typeof dev.body.session_token, "string");
    assert.equal(backend.events.some((event) => event.kind === "unexpected-network"), false);
    assert.deepEqual(fs.readdirSync(backend.directory), []);
  } finally { await stopBackend(backend); }
});

test("real startup schema failure never listens or logs driver credentials", async () => {
  const backend = await launchBackend({ ...deployed, CALDERA_STARTUP_TEST_FAIL_SCHEMA: "true" });
  try {
    assert.equal(backend.exitCode, 1);
    assert.equal(backend.events.some((event) => event.kind === "item-store-created"), true);
    assert.equal(backend.events.some((event) => event.kind === "listen-attempt"), false);
    assert.equal(backend.events.some((event) => event.kind === "unexpected-network"), false);
    assert.doesNotMatch(backend.output(), /synthetic-database-password|backend running/);
    assert.match(backend.output(), /startup failed/);
  } finally { await stopBackend(backend); }
});

test("contained startup harness intercepts real SDK transport before an external socket", async () => {
  const backend = await launchBackend(local);
  try {
    const response = await requestJSON(backend, "/api/create_link_token", {
      method: "POST", headers: { "x-app-api-key": local.APP_API_KEY },
    });
    assert.equal(response.status, 500);
    await waitForEvent(backend, "unexpected-network");
    // The interception event is sent BEFORE original Socket.connect is called.
    // This intentionally rejected SDK attempt is not a live provider request.
  } finally { await stopBackend(backend); }
});
