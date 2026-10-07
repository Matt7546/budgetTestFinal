const { performance } = require("node:perf_hooks");

const WEBHOOK_LIMITS = Object.freeze({
  windowMs: 60 * 1000,
  maxRequests: 300,
  maxConcurrent: 32,
  headerBytes: 4096,
  bodyBytes: 64 * 1024,
});

const MAX_VERIFICATION_WORK = 32;

// This counts retained verification callers, not open HTTP responses. A peer
// closing its socket cannot release work still awaiting a shared key promise.
function createWebhookVerificationWork({ maxConcurrent = MAX_VERIFICATION_WORK } = {}) {
  if (!Number.isInteger(maxConcurrent) || maxConcurrent < 1 || maxConcurrent > MAX_VERIFICATION_WORK) {
    throw new Error("Invalid webhook verification-work limit.");
  }
  let active = 0;
  return {
    tryAcquire() {
      if (active >= maxConcurrent) return null;
      active += 1;
      let released = false;
      return function release() {
        if (released) return;
        released = true;
        active -= 1;
      };
    },
    getState: () => ({ active }),
  };
}

function createWebhookProtection({ monotonicNow = () => performance.now(), limits = {} } = {}) {
  const settings = { ...WEBHOOK_LIMITS, ...limits };
  for (const name of Object.keys(WEBHOOK_LIMITS)) {
    if (!Number.isInteger(settings[name]) || settings[name] < 1 || settings[name] > WEBHOOK_LIMITS[name]) {
      throw new Error("Invalid webhook ingress resource limit.");
    }
  }
  let windowStart = monotonicNow();
  let requests = 0;
  let active = 0;

  function middleware(req, res, next) {
    const ticks = monotonicNow();
    if (ticks - windowStart >= settings.windowMs) { windowStart = ticks; requests = 0; }
    if (!Number.isFinite(ticks) || requests >= settings.maxRequests || active >= settings.maxConcurrent) {
      const retry = requests >= settings.maxRequests
        ? Math.max(1, Math.ceil((settings.windowMs - (ticks - windowStart)) / 1000)) : 1;
      return res.set("Retry-After", String(Number.isFinite(retry) ? retry : 1))
        .status(429).json({ error: "webhook_rate_limited" });
    }
    requests += 1;
    const header = req.get("Plaid-Verification");
    if (typeof header !== "string" || !header || Buffer.byteLength(header) > settings.headerBytes) {
      return res.status(401).json({ error: "invalid_webhook" });
    }
    active += 1;
    let released = false;
    function release() {
      if (released) return;
      released = true;
      active -= 1;
      res.off("finish", release);
      res.off("close", release);
    }
    res.once("finish", release);
    res.once("close", release);
    next();
  }

  function bodyErrorHandler(error, req, res, next) {
    if (!error) return next();
    return res.status(error.type === "entity.too.large" ? 413 : 400)
      .json({ error: "invalid_webhook_body" });
  }
  return { middleware, bodyErrorHandler,
    getState: () => ({ requests, active }) };
}

module.exports = { createWebhookProtection, WEBHOOK_LIMITS,
  createWebhookVerificationWork, MAX_VERIFICATION_WORK };
