const assert = require("node:assert/strict");
const http = require("node:http");
const express = require("express");
const {
  createRateLimiters,
  resolveRateLimitSettings,
} = require("../rateLimit");

function testSettings(overrides = {}) {
  return {
    enabled: true,
    windowMs: 60_000,
    generalMax: 300,
    authMax: 30,
    linkTokenMax: 10,
    tokenExchangeMax: 10,
    accountsMax: 20,
    transactionsMax: 10,
    liabilitiesMax: 10,
    trustProxyHops: 0,
    ...overrides,
  };
}

async function request(port, path, { method = "GET", headers = {} } = {}) {
  return new Promise((resolve, reject) => {
    const outgoingRequest = http.request(
      {
        hostname: "127.0.0.1",
        port,
        path,
        method,
        headers,
      },
      (response) => {
        let body = "";

        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          body += chunk;
        });
        response.on("end", () => {
          resolve({
            status: response.statusCode,
            headers: response.headers,
            body: body ? JSON.parse(body) : null,
          });
        });
      }
    );

    outgoingRequest.on("error", reject);
    outgoingRequest.end();
  });
}

async function withServer(app, run) {
  const server = app.listen(0, "127.0.0.1");

  try {
    await new Promise((resolve) => server.once("listening", resolve));
    await run(server.address().port);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
}

function assertLimited(response) {
  assert.equal(response.status, 429);
  assert.equal(response.body.error, "rate_limited");
  assert.equal(typeof response.body.retry_after_seconds, "number");
  assert.ok(response.body.retry_after_seconds > 0);
  assert.equal(
    Number(response.headers["retry-after"]),
    response.body.retry_after_seconds
  );
}

function trustedAppLimiters(settings) {
  return createRateLimiters(settings, {
    isTrustedAppRequest: (req) => req.get("x-app-api-key") === "test-app-key",
  });
}

async function checkGeneralLimitAndHealthExclusion() {
  const limiters = createRateLimiters(testSettings({ generalMax: 1 }));
  const app = express();

  app.get("/api/health", (req, res) => res.json({ status: "ok" }));
  app.use("/api", limiters.general);
  app.get("/api/capabilities", (req, res) => res.json({ enabled: true }));

  await withServer(app, async (port) => {
    assert.equal((await request(port, "/api/health")).status, 200);
    assert.equal((await request(port, "/api/health")).status, 200);
    assert.equal((await request(port, "/api/capabilities")).status, 200);
    assertLimited(await request(port, "/api/capabilities"));
  });
}

async function checkAuthLimitAndNoGeneralStacking() {
  const limiters = trustedAppLimiters(testSettings({
    generalMax: 1,
    authMax: 2,
  }));
  const app = express();

  app.use("/api", limiters.general);
  app.post("/api/auth/apple", limiters.auth, (req, res) => res.json({ ok: true }));

  await withServer(app, async (port) => {
    const options = {
      method: "POST",
      headers: { "x-app-api-key": "test-app-key" },
    };
    assert.equal((await request(port, "/api/auth/apple", options)).status, 200);
    assert.equal((await request(port, "/api/auth/apple", options)).status, 200);
    assertLimited(await request(port, "/api/auth/apple", options));
  });
}

async function checkAuthenticatedUserIsolationAndIPFallback() {
  const limiters = trustedAppLimiters(testSettings({
    generalMax: 1,
    accountsMax: 2,
  }));
  const app = express();

  app.use("/api", limiters.general);
  app.use((req, res, next) => {
    const userID = req.get("x-test-user");
    if (userID) req.user = { id: userID };
    next();
  });
  app.get("/api/accounts", limiters.accounts, (req, res) => res.json({ ok: true }));

  await withServer(app, async (port) => {
    const userA = {
      "x-app-api-key": "test-app-key",
      "x-test-user": "test-user-a",
    };
    const userB = {
      "x-app-api-key": "test-app-key",
      "x-test-user": "test-user-b",
    };
    const trustedWithoutUser = { "x-app-api-key": "test-app-key" };

    assert.equal((await request(port, "/api/accounts", { headers: userA })).status, 200);
    assert.equal((await request(port, "/api/accounts", { headers: userA })).status, 200);
    assertLimited(await request(port, "/api/accounts", { headers: userA }));
    assert.equal((await request(port, "/api/accounts", { headers: userB })).status, 200);
    assert.equal((await request(port, "/api/accounts", { headers: trustedWithoutUser })).status, 200);
    assert.equal((await request(port, "/api/accounts", { headers: trustedWithoutUser })).status, 200);
    assertLimited(await request(port, "/api/accounts", { headers: trustedWithoutUser }));
  });
}

async function checkUntrustedTrafficKeepsGeneralLimit() {
  const limiters = trustedAppLimiters(testSettings({
    generalMax: 1,
    accountsMax: 100,
  }));
  const app = express();

  app.use("/api", limiters.general);
  app.get("/api/accounts", limiters.accounts, (req, res) => res.json({ ok: true }));

  await withServer(app, async (port) => {
    assert.equal((await request(port, "/api/accounts")).status, 200);
    assertLimited(await request(port, "/api/accounts"));
  });
}

async function checkAccurateRetryTiming() {
  const windowMs = 3_000;
  const limiters = createRateLimiters(testSettings({
    windowMs,
    generalMax: 1,
  }));
  const app = express();

  app.use("/api", limiters.general);
  app.get("/api/capabilities", (req, res) => res.json({ enabled: true }));

  await withServer(app, async (port) => {
    assert.equal((await request(port, "/api/capabilities")).status, 200);
    await new Promise((resolve) => setTimeout(resolve, 1_250));
    const limited = await request(port, "/api/capabilities");

    assertLimited(limited);
    assert.ok(limited.body.retry_after_seconds <= 2);
    assert.ok(limited.body.retry_after_seconds < Math.ceil(windowMs / 1000));
  });
}

async function checkDisabledLimiter() {
  const limiters = createRateLimiters(testSettings({
    enabled: false,
    generalMax: 1,
  }));
  const app = express();

  app.use("/api", limiters.general);
  app.get("/api/capabilities", (req, res) => res.json({ enabled: false }));

  await withServer(app, async (port) => {
    assert.equal((await request(port, "/api/capabilities")).status, 200);
    assert.equal((await request(port, "/api/capabilities")).status, 200);
  });
}

async function checkProxyBehavior() {
  const settings = testSettings({ generalMax: 1 });
  const trustedProxyApp = express();
  const trustedProxyLimiters = createRateLimiters(settings);

  trustedProxyApp.set("trust proxy", 1);
  trustedProxyApp.use("/api", trustedProxyLimiters.general);
  trustedProxyApp.get("/api/capabilities", (req, res) => res.json({ ok: true }));

  await withServer(trustedProxyApp, async (port) => {
    const clientA = { "x-forwarded-for": "198.51.100.10" };
    const clientB = { "x-forwarded-for": "198.51.100.11" };

    assert.equal((await request(port, "/api/capabilities", { headers: clientA })).status, 200);
    assertLimited(await request(port, "/api/capabilities", { headers: clientA }));
    assert.equal((await request(port, "/api/capabilities", { headers: clientB })).status, 200);
  });

  const localApp = express();
  const localLimiters = createRateLimiters(settings);

  localApp.use("/api", localLimiters.general);
  localApp.get("/api/capabilities", (req, res) => res.json({ ok: true }));

  await withServer(localApp, async (port) => {
    assert.equal((await request(port, "/api/capabilities", {
      headers: { "x-forwarded-for": "198.51.100.20" },
    })).status, 200);
    assertLimited(await request(port, "/api/capabilities", {
      headers: { "x-forwarded-for": "198.51.100.21" },
    }));
  });
}

function checkEnablementDefaults() {
  assert.equal(resolveRateLimitSettings({ env: {} }).enabled, false);
  assert.equal(resolveRateLimitSettings({ env: {}, isProduction: true }).enabled, true);
  assert.equal(resolveRateLimitSettings({ env: {}, isDeployed: true }).enabled, true);
  assert.equal(resolveRateLimitSettings({
    env: { RATE_LIMIT_ENABLED: "false" },
    isProduction: true,
    isDeployed: true,
  }).enabled, false);
  assert.equal(resolveRateLimitSettings({
    env: { RATE_LIMIT_ENABLED: "true" },
  }).enabled, true);
  assert.equal(resolveRateLimitSettings({ env: {}, isDeployed: true }).trustProxyHops, 1);
  assert.equal(resolveRateLimitSettings({ env: {} }).trustProxyHops, 0);
}

async function main() {
  const warnings = [];
  const originalWarn = console.warn;
  console.warn = (...values) => warnings.push(values.join(" "));

  try {
    checkEnablementDefaults();
    await checkGeneralLimitAndHealthExclusion();
    await checkAuthLimitAndNoGeneralStacking();
    await checkAuthenticatedUserIsolationAndIPFallback();
    await checkUntrustedTrafficKeepsGeneralLimit();
    await checkAccurateRetryTiming();
    await checkDisabledLimiter();
    await checkProxyBehavior();

    const warningText = warnings.join("\n");
    assert.ok(warnings.length > 0);
    assert.ok(warnings.every((warning) => warning.startsWith("Rate limit exceeded:")));
    assert.ok(!warningText.includes("test-user-a"));
    assert.ok(!warningText.includes("test-user-b"));
    assert.ok(!warningText.includes("198.51.100"));
  } finally {
    console.warn = originalWarn;
  }

  console.log("Rate limit checks passed.");
}

main().catch((error) => {
  console.error("Rate limit checks failed.", error);
  process.exitCode = 1;
});
