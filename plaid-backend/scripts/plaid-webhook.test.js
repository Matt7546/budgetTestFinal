const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { performance } = require("node:perf_hooks");
const test = require("node:test");
const express = require("express");
const { verifyPlaidWebhook, createPlaidWebhookHandler } = require("../plaidWebhook");
const { createWebhookVerificationKeys, VERIFICATION_KEY_LIMITS } = require("../plaidWebhookVerificationKeys");
const { createWebhookProtection, WEBHOOK_LIMITS,
  createWebhookVerificationWork, MAX_VERIFICATION_WORK } = require("../plaidWebhookProtection");
const { createJsonPlaidItemStore } = require("../jsonPlaidItemStore");
const { launchBackend, stopBackend, requestJSON, waitForEvent } = require("./startup-test-process");

const instant = new Date("2026-10-02T12:00:00Z");
const pair = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const otherPair = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const event = { webhook_type: "TRANSACTIONS", webhook_code: "HISTORICAL_UPDATE",
  environment: "sandbox", item_id: "item-a", error: null };
const raw = Buffer.from(JSON.stringify(event));
function key(kid = "test-key", keys = pair) {
  return { ...keys.publicKey.export({ format: "jwk" }), kid, alg: "ES256", use: "sig",
    created_at: Math.floor(instant.getTime() / 1000) - 60, expired_at: null };
}
function signed(body = raw, { kid = "test-key", keys = pair, date = instant,
  header = {}, claims = {} } = {}) {
  const encodedHeader = Buffer.from(JSON.stringify({ alg: "ES256", kid, typ: "JWT", ...header })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({ iat: Math.floor(date.getTime() / 1000),
    request_body_sha256: crypto.createHash("sha256").update(body).digest("hex"), ...claims })).toString("base64url");
  const input = `${encodedHeader}.${payload}`;
  return `${input}.${crypto.sign("sha256", Buffer.from(input),
    { key: keys.privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}
function deferred() { let resolve; let reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }
async function turn() { await new Promise(setImmediate); }
async function until(predicate) {
  const deadline = performance.now() + 2000;
  while (!predicate()) {
    assert.ok(performance.now() < deadline, "Contained test barrier was not reached.");
    await turn();
  }
}
function fixture({ fetch, limits, workLimit, now = () => instant, monotonicNow = () => 0 } = {}) {
  let calls = 0;
  const client = { async webhookVerificationKeyGet(request, options) {
    calls += 1;
    assert.equal(options.timeout, limits?.fetchTimeoutMs || 3000);
    assert.ok(options.signal);
    return fetch ? fetch(request, options) : { data: { key: key(request.key_id) } };
  } };
  const keys = createWebhookVerificationKeys({ client, limits, now, monotonicNow });
  const work = createWebhookVerificationWork({ maxConcurrent: workLimit });
  let acquired = 0; let releases = 0; let attempts = 0; let peak = 0; let lookups = 0;
  const verificationWork = { getState: work.getState, tryAcquire() {
    attempts += 1;
    const release = work.tryAcquire();
    if (!release) return null;
    acquired += 1;
    peak = Math.max(peak, work.getState().active);
    return () => { releases += 1; release(); };
  } };
  const verificationKeys = { getState: keys.getState, get(kid) {
    lookups += 1;
    assert.ok(work.getState().active > 0, "Key lookup must hold verification work.");
    return keys.get(kid);
  } };
  return { verificationKeys, verificationWork, calls: () => calls,
    workStats: () => ({ attempts, acquired, releases, peak, lookups }),
    verify: (jwt = signed(), body = raw) => verifyPlaidWebhook({
      verificationHeader: jwt, rawBody: body, verificationKeys, verificationWork, now }) };
}

function assertReleased(f) {
  assert.deepEqual(f.verificationWork.getState(), { active: 0 });
  assert.equal(f.workStats().releases, f.workStats().acquired);
}

test("valid uncached webhook verifies once; repeated signatures use the key cache", async () => {
  const f = fixture();
  assert.equal(await f.verify(), instant.toISOString());
  assert.equal(await f.verify(), instant.toISOString());
  assert.equal(f.calls(), 1);
  await turn();
  assert.deepEqual(f.verificationKeys.getState(), { cached: 1, inFlight: 0 });
  assert.equal(f.workStats().acquired, 2);
  assertReleased(f);
});

test("32 concurrent same-kid verifications share one upstream fetch", async () => {
  const gate = deferred();
  const f = fixture({ fetch: async () => { await gate.promise; return { data: { key: key() } }; } });
  const checks = Array.from({ length: 32 }, () => f.verify());
  await turn();
  assert.equal(f.calls(), 1);
  assert.equal(f.verificationKeys.getState().inFlight, 1);
  assert.equal(f.verificationWork.getState().active, 32);
  await assert.rejects(f.verify());
  assert.equal(f.workStats().lookups, 32);
  assert.equal(f.calls(), 1);
  gate.resolve();
  assert.deepEqual(await Promise.all(checks), Array(32).fill(instant.toISOString()));
  await turn();
  assert.equal(f.verificationKeys.getState().inFlight, 0);
  assertReleased(f);
});

test("unknown/distinct attacker kids cannot exceed two fetches or grow a queue", async () => {
  const gate = deferred();
  const f = fixture({ fetch: async () => { await gate.promise; throw new Error("synthetic failure"); } });
  const checks = Array.from({ length: 80 }, (_, n) => f.verify(signed(raw, { kid: `attacker-${n}` })).catch(() => false));
  await turn();
  assert.equal(f.calls(), 2);
  assert.deepEqual(f.verificationKeys.getState(), { cached: 0, inFlight: 2 });
  assert.equal(f.verificationWork.getState().active, 2);
  gate.resolve();
  assert.ok((await Promise.all(checks)).every((result) => result === false));
  await turn();
  assert.deepEqual(f.verificationKeys.getState(), { cached: 0, inFlight: 0 });
  assertReleased(f);
});

test("cache has an LRU bound and expires using a monotonic TTL", async () => {
  let ticks = 0;
  const f = fixture({ limits: { maxEntries: 2, ttlMs: 100 }, monotonicNow: () => ticks });
  for (const kid of ["a", "b", "c"]) assert.ok(await f.verify(signed(raw, { kid })));
  assert.equal(f.verificationKeys.getState().cached, 2);
  assert.ok(await f.verify(signed(raw, { kid: "a" })));
  assert.equal(f.calls(), 4);
  ticks = 100;
  assert.equal(f.verificationKeys.getState().cached, 0);
  assert.ok(await f.verify(signed(raw, { kid: "a" })));
  assert.equal(f.calls(), 5);
});

test("production defaults retain at most 16 validated keys and expire after five minutes", async () => {
  let ticks = 0;
  const f = fixture({ monotonicNow: () => ticks });
  for (let n = 0; n < 40; n += 1) {
    assert.ok(await f.verify(signed(raw, { kid: `provider-${n}` })));
    assert.ok(f.verificationKeys.getState().cached <= 16);
  }
  await turn();
  assert.deepEqual(f.verificationKeys.getState(), { cached: 16, inFlight: 0 });
  ticks = 300_000;
  assert.deepEqual(f.verificationKeys.getState(), { cached: 0, inFlight: 0 });
  assert.ok(await f.verify());
  assert.equal(f.calls(), 41);
});

test("known provider expiration beats TTL; expired provider responses are not cached", async () => {
  let date = instant;
  const f = fixture({ now: () => date, fetch: async () => ({ data: { key: {
    ...key(), expired_at: Math.floor(instant.getTime() / 1000) + 1 } } }) });
  assert.ok(await f.verify());
  date = new Date(instant.getTime() + 1000);
  assert.equal(f.verificationKeys.getState().cached, 0);
  assert.equal(await f.verify(), false);
  assert.equal(f.calls(), 2);
  assert.equal(f.verificationKeys.getState().cached, 0);
});

test("a legitimate new provider kid verifies without restart and old-key signatures still verify", async () => {
  const f = fixture({ fetch: async ({ key_id }) => ({ data: { key: key(key_id, key_id === "new" ? otherPair : pair) } }) });
  assert.ok(await f.verify());
  assert.ok(await f.verify(signed(raw, { kid: "new", keys: otherPair })));
  assert.ok(await f.verify());
  assert.equal(f.calls(), 2);
});

test("malformed, mismatched, expired, or private provider keys never become cache entries", async () => {
  for (const change of [{ kid: "other" }, { alg: "RS256" }, { kty: "RSA" }, { crv: "P-384" },
    { use: "enc" }, { x: "invalid" }, { y: "invalid" }, { x: [key().x] }, { d: "private" },
    { created_at: null }, { expired_at: undefined }, { expired_at: "future" },
    { expired_at: Math.floor(instant.getTime() / 1000) }]) {
    const f = fixture({ fetch: async () => ({ data: { key: { ...key(), ...change } } }) });
    assert.equal(await f.verify(), false);
    await turn();
    assert.deepEqual(f.verificationKeys.getState(), { cached: 0, inFlight: 0 });
    assertReleased(f);
  }
});

test("timeout aborts the fetch, fails every waiter, and permits a later healthy fetch", async () => {
  let aborted = false;
  let fail = true;
  const f = fixture({ limits: { fetchTimeoutMs: 20 }, fetch: (request, { signal }) => {
    if (!fail) return { data: { key: key() } };
    return new Promise((resolve, reject) => signal.addEventListener("abort", () => {
      aborted = true; reject(new Error("aborted"));
    }, { once: true }));
  } });
  const results = await Promise.allSettled(Array.from({ length: 32 }, () => f.verify()));
  assert.ok(results.every((result) => result.status === "rejected"));
  assert.equal(aborted, true);
  await turn();
  assert.deepEqual(f.verificationKeys.getState(), { cached: 0, inFlight: 0 });
  assert.equal(f.workStats().peak, 32);
  assertReleased(f);
  fail = false;
  assert.ok(await f.verify());
  assert.equal(f.calls(), 2);
  assertReleased(f);
});

test("an abort-ignoring transport retains its concurrency slot and cannot cache a late result", async () => {
  const gates = [deferred(), deferred()];
  let index = 0;
  const f = fixture({ limits: { fetchTimeoutMs: 20 }, fetch: async ({ key_id }) => {
    await gates[index++].promise; return { data: { key: key(key_id) } };
  } });
  await Promise.allSettled([f.verify(signed(raw, { kid: "a" })), f.verify(signed(raw, { kid: "b" }))]);
  assert.deepEqual(f.verificationKeys.getState(), { cached: 0, inFlight: 2 });
  assertReleased(f);
  await assert.rejects(f.verify(signed(raw, { kid: "c" })));
  assert.equal(f.calls(), 2);
  gates.forEach((gate) => gate.resolve());
  await turn(); await turn();
  assert.deepEqual(f.verificationKeys.getState(), { cached: 0, inFlight: 0 });
  assertReleased(f);
});

test("network failure never caches and the next request can recover", async () => {
  let failed = true;
  const f = fixture({ fetch: async () => { if (failed) throw new Error("network"); return { data: { key: key() } }; } });
  await assert.rejects(f.verify());
  await turn();
  assert.deepEqual(f.verificationKeys.getState(), { cached: 0, inFlight: 0 });
  assertReleased(f);
  failed = false;
  assert.ok(await f.verify());
});

test("invalid signatures cannot authenticate even with a cached valid key", async () => {
  const f = fixture();
  assert.ok(await f.verify());
  assert.equal(await f.verify(signed(raw, { keys: otherPair })), false);
  assert.equal(f.calls(), 1);
  assertReleased(f);
});

test("malformed JWT, unsupported headers, missing header, and bad claims reject without key work", async () => {
  const f = fixture();
  for (const jwt of [undefined, "", "not-a-jwt", "a.b.c", "x".repeat(4097),
    signed(raw, { header: { alg: "none" } }), signed(raw, { header: { alg: "RS256" } }),
    signed(raw, { header: { kid: "x".repeat(129) } }), signed(raw, { header: { crit: ["unknown"] } }),
    signed(raw, { header: { jwk: key() } }), signed(raw, { claims: { iat: "today" } }),
    signed(raw, { claims: { request_body_sha256: "invalid" } }),
    signed(raw, { date: new Date(instant.getTime() - 301000) }),
    signed(raw, { date: new Date(instant.getTime() + 1000) })]) {
    assert.equal(await verifyPlaidWebhook({ verificationHeader: jwt, rawBody: raw,
      verificationKeys: f.verificationKeys, verificationWork: f.verificationWork, now: () => instant }), false);
  }
  assert.equal(await f.verify(signed(), Buffer.from("tampered")), false);
  assert.equal(f.calls(), 0);
  assert.equal(f.workStats().attempts, 0);
  assertReleased(f);
});

test("limits cannot be configured above the production hard bounds", () => {
  assert.throws(() => fixture({ limits: { maxEntries: 17 } }));
  assert.throws(() => createWebhookProtection({ limits: { maxRequests: 301 } }));
  assert.throws(() => createWebhookVerificationWork({ maxConcurrent: 33 }));
  assert.equal(VERIFICATION_KEY_LIMITS.maxInFlight, 2);
  assert.equal(WEBHOOK_LIMITS.maxConcurrent, 32);
  assert.equal(MAX_VERIFICATION_WORK, 32);
});

async function compose({ limits, fetch, keyLimits, monotonicNow, onResponse = () => {}, store } = {}) {
  const writes = [];
  const f = fixture({ fetch, limits: keyLimits });
  const protection = createWebhookProtection({ limits, monotonicNow });
  const app = express();
  app.use((req, res, next) => { onResponse(req, res); next(); });
  app.post("/api/plaid/webhook", protection.middleware,
    express.raw({ type: "application/json", limit: WEBHOOK_LIMITS.bodyBytes, inflate: false }),
    createPlaidWebhookHandler({ environment: "sandbox", now: () => instant,
      verificationKeys: f.verificationKeys, verificationWork: f.verificationWork,
      plaidItemStore: store || { async markHistoricalReadyByItemID(...args) { writes.push(args); } } }),
    protection.bodyErrorHandler);
  const server = app.listen(0, "127.0.0.1");
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.once("listening", resolve);
  });
  const backend = { port: server.address().port };
  return { ...f, writes, protection, backend,
    stop: () => new Promise((resolve) => server.close(resolve)) };
}
function send(backend, body = raw, jwt = signed(), extraHeaders = {}) {
  return requestJSON(backend, "/api/plaid/webhook", { method: "POST", body,
    headers: { "Content-Type": "application/json", "Plaid-Verification": jwt, ...extraHeaders } });
}

function disconnectable(backend, jwt, caller) {
  let request;
  let aborted = false;
  const completed = new Promise((resolve, reject) => {
    request = http.request({ hostname: "127.0.0.1", port: backend.port,
      path: "/api/plaid/webhook", method: "POST", headers: {
        "Content-Type": "application/json", "Content-Length": raw.length,
        "Plaid-Verification": jwt, "X-Test-Caller": caller,
      } }, (response) => {
      response.resume();
      response.once("end", () => resolve({ status: response.statusCode }));
      response.once("error", reject);
    });
    request.once("error", (error) => aborted ? resolve({ disconnected: true }) : reject(error));
    request.setTimeout(5000, () => request.destroy(new Error("Contained request timed out.")));
    request.end(raw);
  });
  completed.catch(() => {}); // Preserve failures for the final await, without an unhandled rejection.
  return { completed, abort() { aborted = true; request.destroy(); } };
}

test("verification-work leases release once and cannot go negative", () => {
  const work = createWebhookVerificationWork({ maxConcurrent: 1 });
  const release = work.tryAcquire();
  assert.equal(typeof release, "function");
  assert.equal(work.tryAcquire(), null);
  assert.deepEqual(work.getState(), { active: 1 });
  release(); release();
  assert.deepEqual(work.getState(), { active: 0 });
  const next = work.tryAcquire();
  assert.deepEqual(work.getState(), { active: 1 });
  release();
  assert.deepEqual(work.getState(), { active: 1 });
  next(); next();
  assert.deepEqual(work.getState(), { active: 0 });
});

test("cache-hit crypto still requires a verification-work permit", async () => {
  const f = fixture({ workLimit: 1 });
  assert.ok(await f.verify());
  const held = f.verificationWork.tryAcquire();
  const before = f.workStats();
  await assert.rejects(f.verify());
  assert.equal(f.workStats().lookups, before.lookups);
  assert.equal(f.calls(), 1);
  assert.equal(f.verificationWork.getState().active, 1);
  held();
  assert.ok(await f.verify());
  assert.equal(f.workStats().lookups, before.lookups + 1);
  assert.equal(f.calls(), 1);
  assertReleased(f);
});

test("JWT or key expiry while awaiting a fetch releases retained verification work", async () => {
  for (const expiresKey of [false, true]) {
    const gate = deferred();
    let date = instant;
    const f = fixture({ now: () => date, fetch: async () => {
      await gate.promise;
      return { data: { key: { ...key(), expired_at: expiresKey
        ? Math.floor(instant.getTime() / 1000) + 1 : null } } };
    } });
    const check = f.verify();
    await until(() => f.calls() === 1);
    assert.equal(f.verificationWork.getState().active, 1);
    date = new Date(instant.getTime() + 301_000);
    gate.resolve();
    assert.equal(await check, false);
    await turn();
    assert.equal(f.verificationKeys.getState().inFlight, 0);
    assertReleased(f);
  }
});

test("production-default Express disconnect churn never retains caller 33", { timeout: 10_000 }, async (t) => {
  const gate = deferred();
  const responses = new Map();
  const callers = [];
  const f = await compose({ onResponse(req, res) {
    const caller = req.get("X-Test-Caller");
    if (caller) responses.set(caller, res);
  }, fetch: async () => { await gate.promise; return { data: { key: key() } }; } });
  try {
    const jwt = signed(raw, { keys: otherPair });
    for (let n = 0; n < 32; n += 1) callers.push(disconnectable(f.backend, jwt, `caller-${n}`));
    await until(() => f.verificationWork.getState().active === 32);
    assert.equal(f.protection.getState().active, 32);
    assert.equal(f.calls(), 1);
    assert.equal(f.verificationKeys.getState().inFlight, 1);
    const beforeAdmission = f.workStats();
    assert.equal((await send(f.backend, raw, jwt)).status, 429);
    assert.deepEqual(f.workStats(), beforeAdmission);
    for (let n = 0; n < 8; n += 1) {
      const closed = new Promise((resolve) => responses.get(`caller-${n}`).once("close", resolve));
      callers[n].abort();
      await closed;
      assert.equal(f.protection.getState().active, 31 - n);
      assert.equal(f.verificationWork.getState().active, 32);
      const replacement = await send(f.backend, raw, jwt);
      assert.equal(replacement.status, 503);
      assert.equal(replacement.headers["retry-after"], "30");
      assert.equal(replacement.body.error, "verification_unavailable");
      assert.equal(f.verificationWork.getState().active, 32);
      assert.equal(f.workStats().lookups, 32);
      assert.equal(f.workStats().acquired, 32);
      assert.equal(f.calls(), 1);
      assert.equal(f.writes.length, 0);
    }
    gate.resolve();
    const results = await Promise.all(callers.map((caller) => caller.completed));
    assert.ok(results.slice(0, 8).every((result) => result.disconnected));
    assert.ok(results.slice(8).every((result) => result.status === 401));
    await until(() => f.verificationKeys.getState().inFlight === 0);
    assertReleased(f);
    assert.equal(f.workStats().peak, 32);
    assert.equal(f.protection.getState().active, 0);
    assert.equal(f.writes.length, 0);
    // Only the independently validated provider public key is cached; invalid
    // signatures never cache payloads or authenticate readiness.
    assert.deepEqual(f.verificationKeys.getState(), { cached: 1, inFlight: 0 });
    assert.equal(f.calls(), 1);
    t.diagnostic(JSON.stringify({ openAfterFirstAbort: 31, retainedAfterAbort: 32,
      rejectedReplacements: 8, peakRetained: f.workStats().peak,
      finalRetained: f.verificationWork.getState().active,
      finalInFlight: f.verificationKeys.getState().inFlight, readinessWrites: f.writes.length }));
  } finally {
    gate.resolve();
    callers.forEach((caller) => caller.abort());
    await Promise.allSettled(callers.map((caller) => caller.completed));
    await f.stop();
  }
});

test("valid disconnected delivery continues exact idempotent readiness handling", { timeout: 10_000 }, async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "caldera-webhook-disconnect-"));
  const tokenStorePath = path.join(directory, "items.json");
  const store = createJsonPlaidItemStore({ tokenStorePath });
  const gate = deferred();
  let response;
  let caller;
  let f;
  let applied = 0;
  try {
    for (const id of ["a", "b"]) await store.saveUserItem(`owner-${id}`, {
      itemId: `item-${id}`, accessToken: `synthetic-${id}`,
      linkedAt: new Date(instant.getTime() - 60_000).toISOString(),
    });
    f = await compose({ store: { async markHistoricalReadyByItemID(...args) {
      const result = await store.markHistoricalReadyByItemID(...args);
      applied += 1;
      return result;
    } }, onResponse(req, res) { response = res; },
      fetch: async () => { await gate.promise; return { data: { key: key() } }; } });
    caller = disconnectable(f.backend, signed(), "valid");
    await until(() => f.verificationWork.getState().active === 1);
    const closed = new Promise((resolve) => response.once("close", resolve));
    caller.abort();
    await closed;
    assert.equal(f.protection.getState().active, 0);
    assert.equal(f.verificationWork.getState().active, 1);
    gate.resolve();
    await until(() => applied === 1);
    const reopened = createJsonPlaidItemStore({ tokenStorePath });
    assert.equal((await reopened.getUserItemReadiness("owner-a", "item-a")).historicalReadyAt,
      instant.toISOString());
    assert.equal((await reopened.getUserItemReadiness("owner-b", "item-b")).historicalReadyAt, null);
    // Verify the disconnected delivery before a duplicate can establish it.
    assertReleased(f);
    assert.equal((await send(f.backend)).status, 204);
    assert.equal(applied, 2);
    assert.equal((await reopened.getUserItemReadiness("owner-a", "item-a")).historicalReadyAt,
      instant.toISOString());
    assert.equal((await reopened.getUserItemReadiness("owner-b", "item-b")).historicalReadyAt, null);
    assertReleased(f);
    assert.equal(f.workStats().acquired, 2);
    assert.equal(f.calls(), 1);
  } finally {
    gate.resolve();
    caller?.abort();
    if (caller) await caller.completed;
    if (f) await f.stop();
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("handler storage failure leaves no verification-work lease", async () => {
  const f = await compose({ store: { async markHistoricalReadyByItemID() {
    throw new Error("synthetic store failure");
  } } });
  try {
    const response = await send(f.backend);
    assert.equal(response.status, 503);
    assert.equal(response.body.error, "readiness_unavailable");
    assertReleased(f);
    assert.equal(f.protection.getState().active, 0);
  } finally { await f.stop(); }
});

test("real Express route limits attempts before key lookup and ignores spoofed forwarded addresses", async () => {
  const f = await compose({ limits: { maxRequests: 2 } });
  try {
    assert.equal((await send(f.backend)).status, 204);
    assert.equal((await send(f.backend)).status, 204);
    const before = f.workStats();
    const response = await send(f.backend, raw, signed(raw, { kid: "unknown" }), { "X-Forwarded-For": "203.0.113.5" });
    assert.equal(response.status, 429);
    assert.ok(Number(response.headers["retry-after"]) > 0);
    assert.equal(f.calls(), 1);
    assert.equal(f.writes.length, 2);
    assert.deepEqual(f.workStats(), before);
    assertReleased(f);
  } finally { await f.stop(); }
});

test("Express rejects oversized headers/bodies and compressed bodies without upstream calls", async () => {
  const f = await compose();
  try {
    assert.equal((await send(f.backend, raw, "x".repeat(4097))).status, 401);
    assert.equal((await send(f.backend, Buffer.alloc(65537), signed())).status, 413);
    assert.equal((await send(f.backend, raw, signed(), { "Content-Encoding": "gzip" })).status, 400);
    assert.equal(f.calls(), 0);
    assert.equal(f.writes.length, 0);
    assert.equal(f.protection.getState().active, 0);
    assert.equal(f.workStats().attempts, 0);
    assertReleased(f);
  } finally { await f.stop(); }
});

test("Express budget refills after its window and resumes normal verification", async () => {
  let ticks = 0;
  const f = await compose({ limits: { maxRequests: 1 }, monotonicNow: () => ticks });
  try {
    assert.equal((await send(f.backend)).status, 204);
    assert.equal((await send(f.backend)).status, 429);
    assert.equal(f.calls(), 1);
    ticks = 60_000;
    assert.equal((await send(f.backend)).status, 204);
    assert.equal(f.calls(), 1);
    assert.equal(f.writes.length, 2);
    assert.equal(f.protection.getState().active, 0);
    assertReleased(f);
  } finally { await f.stop(); }
});

test("Express invalid signatures and signed malformed bodies cannot mutate readiness", async () => {
  const f = await compose();
  try {
    assert.equal((await send(f.backend, raw, signed(raw, { keys: otherPair }))).status, 401);
    const malformed = Buffer.from("{");
    assert.equal((await send(f.backend, malformed, signed(malformed))).status, 400);
    assert.equal(f.writes.length, 0);
    assert.equal(f.calls(), 1);
    assert.equal((await send(f.backend)).status, 204);
    assert.equal(f.writes.length, 1);
    assertReleased(f);
  } finally { await f.stop(); }
});

test("Express timeout returns retryable failure with no readiness mutation", async () => {
  const f = await compose({ keyLimits: { fetchTimeoutMs: 20 }, fetch: (request, { signal }) =>
    new Promise((resolve, reject) => signal.addEventListener("abort", () => reject(new Error("timeout")), { once: true })) });
  try {
    const response = await send(f.backend);
    assert.equal(response.status, 503);
    assert.equal(response.headers["retry-after"], "30");
    assert.equal(f.writes.length, 0);
    await turn();
    assert.deepEqual(f.verificationKeys.getState(), { cached: 0, inFlight: 0 });
    assert.equal(f.protection.getState().active, 0);
    assertReleased(f);
  } finally { await f.stop(); }
});

test("Express concurrent ingress is bounded; completed requests release admission", async () => {
  const gate = deferred();
  const entered = deferred();
  const f = await compose({ limits: { maxConcurrent: 1 }, fetch: async () => {
    entered.resolve(); await gate.promise; return { data: { key: key() } };
  } });
  try {
    const first = send(f.backend);
    await entered.promise;
    const before = f.workStats();
    assert.equal((await send(f.backend)).status, 429);
    assert.deepEqual(f.workStats(), before);
    assert.equal(f.calls(), 1);
    gate.resolve();
    assert.equal((await first).status, 204);
    assert.equal(f.protection.getState().active, 0);
    assert.equal((await send(f.backend)).status, 204);
    assertReleased(f);
  } finally { gate.resolve(); await f.stop(); }
});

const local = { NODE_ENV: "test", PLAID_ENV: "sandbox", AUTH_MODE: "personal",
  TOKEN_STORE_DRIVER: "json", APP_API_KEY: "synthetic-app-key", RATE_LIMIT_ENABLED: "true",
  RATE_LIMIT_GENERAL_MAX: "1" };

test("actual index uses intercepted SDK keys, a persistent cache, and exact owned Item readiness", async () => {
  const date = new Date();
  const providerKey = { ...key(), created_at: Math.floor(date.getTime() / 1000) - 60 };
  const backend = await launchBackend({ ...local,
    CALDERA_STARTUP_TEST_WEBHOOK_KEY: JSON.stringify(providerKey) }, { seedItems: [
    { owner: "owner-a", item: { itemId: "item-a", accessToken: "synthetic-a",
      linkedAt: new Date(date.getTime() - 60_000).toISOString() } },
    { owner: "owner-b", item: { itemId: "item-b", accessToken: "synthetic-b",
      linkedAt: new Date(date.getTime() - 60_000).toISOString() } },
  ] });
  try {
    const jwt = signed(raw, { date });
    const store = createJsonPlaidItemStore({ tokenStorePath: path.join(backend.directory, "items.json") });
    assert.equal((await send(backend, Buffer.from("tampered"), jwt)).status, 401);
    assert.equal((await requestJSON(backend, "/api/plaid/webhook", { method: "POST", body: raw })).status, 401);
    assert.equal((await send(backend, raw, jwt)).status, 204);
    assert.equal((await send(backend, raw, jwt)).status, 204);
    assert.equal((await store.getUserItemReadiness("owner-a", "item-a")).historicalReadyAt,
      new Date(Math.floor(date.getTime() / 1000) * 1000).toISOString());
    assert.equal((await store.getUserItemReadiness("owner-b", "item-b")).historicalReadyAt, null);
    const unknown = Buffer.from(JSON.stringify({ ...event, item_id: "missing" }));
    assert.equal((await send(backend, unknown, signed(unknown, { date }))).status, 204);
    assert.equal((await store.getUserItemReadiness("owner-b", "item-b")).historicalReadyAt, null);
    await waitForEvent(backend, "verification-key-request");
    assert.equal(backend.events.filter((entry) => entry.kind === "verification-key-request").length, 1);
    // Ordinary API limiter still protects API requests; webhook budget is separate.
    assert.equal((await requestJSON(backend, "/api/accounts")).status, 401);
    assert.equal((await requestJSON(backend, "/api/accounts")).status, 429);
    assert.equal((await send(backend, raw, jwt)).status, 204);
    assert.equal(backend.events.some((entry) => entry.kind === "unexpected-network"), false);
  } finally { await stopBackend(backend); }
});

test("actual index global webhook budget runs even when ordinary API limiting is disabled", async () => {
  const date = new Date();
  const body = Buffer.from(JSON.stringify({ webhook_type: "ITEM", environment: "sandbox" }));
  const providerKey = { ...key(), created_at: Math.floor(date.getTime() / 1000) - 60 };
  const backend = await launchBackend({ ...local, RATE_LIMIT_ENABLED: "false",
    CALDERA_STARTUP_TEST_WEBHOOK_KEY: JSON.stringify(providerKey) });
  try {
    assert.equal((await send(backend, body, signed(body, { date }))).status, 204);
    for (let n = 1; n < WEBHOOK_LIMITS.maxRequests; n += 1) {
      assert.equal((await send(backend, body, "malformed", { "X-Forwarded-For": `203.0.113.${n % 255}` })).status, 401);
    }
    const response = await send(backend, body, signed(body, { date }));
    assert.equal(response.status, 429);
    assert.ok(Number(response.headers["retry-after"]) > 0);
    assert.equal(backend.events.filter((entry) => entry.kind === "verification-key-request").length, 1);
    assert.equal(backend.events.some((entry) => entry.kind === "unexpected-network"), false);
  } finally { await stopBackend(backend); }
});

test("actual index SDK timeout fails coalesced requests closed and a later retry recovers", async () => {
  const date = new Date();
  const backend = await launchBackend({ ...local,
    CALDERA_STARTUP_TEST_WEBHOOK_KEY: JSON.stringify({ ...key(),
      created_at: Math.floor(date.getTime() / 1000) - 60 }),
    CALDERA_STARTUP_TEST_WEBHOOK_FAILURE: "timeout-once",
  }, { seedItems: [{ owner: "owner-a", item: { itemId: "item-a", accessToken: "synthetic-a",
    linkedAt: new Date(date.getTime() - 60_000).toISOString() } }] });
  try {
    const jwt = signed(raw, { date });
    const responses = await Promise.all(Array.from({ length: 3 }, () => send(backend, raw, jwt)));
    assert.ok(responses.every((response) => response.status === 503 && response.headers["retry-after"] === "30"));
    const store = createJsonPlaidItemStore({ tokenStorePath: path.join(backend.directory, "items.json") });
    assert.equal((await store.getUserItemReadiness("owner-a", "item-a")).historicalReadyAt, null);
    await waitForEvent(backend, "verification-key-aborted");
    assert.equal(backend.events.filter((entry) => entry.kind === "verification-key-request").length, 1);
    assert.equal((await send(backend, raw, jwt)).status, 204);
    assert.equal((await store.getUserItemReadiness("owner-a", "item-a")).historicalReadyAt,
      new Date(Math.floor(date.getTime() / 1000) * 1000).toISOString());
    assert.equal(backend.events.filter((entry) => entry.kind === "verification-key-request").length, 2);
    assert.equal(backend.events.some((entry) => entry.kind === "unexpected-network"), false);
  } finally { await stopBackend(backend); }
});
