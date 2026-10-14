const { performance } = require("node:perf_hooks");

const VERIFICATION_KEY_LIMITS = Object.freeze({
  maxEntries: 16,
  ttlMs: 5 * 60 * 1000,
  maxInFlight: 2,
  fetchTimeoutMs: 3000,
});

class VerificationUnavailableError extends Error {
  constructor() { super("Webhook verification is temporarily unavailable."); }
}
class InvalidVerificationKeyError extends Error {
  constructor() { super("Invalid webhook verification key."); }
}

function validKeyID(kid) {
  return typeof kid === "string" && /^[\x21-\x7e]{1,128}$/.test(kid);
}

function createWebhookVerificationKeys({
  client,
  now = () => new Date(),
  monotonicNow = () => performance.now(),
  limits = {},
}) {
  const settings = { ...VERIFICATION_KEY_LIMITS, ...limits };
  for (const name of Object.keys(VERIFICATION_KEY_LIMITS)) {
    if (!Number.isInteger(settings[name]) || settings[name] < 1 ||
        settings[name] > VERIFICATION_KEY_LIMITS[name]) {
      throw new Error("Invalid webhook verification resource limit.");
    }
  }
  const cache = new Map();
  const inFlight = new Map();

  function clock() {
    const seconds = Math.floor(now().getTime() / 1000);
    const ticks = monotonicNow();
    if (!Number.isFinite(seconds) || !Number.isFinite(ticks)) {
      throw new VerificationUnavailableError();
    }
    return { seconds, ticks };
  }
  function prune() {
    const { seconds, ticks } = clock();
    for (const [kid, entry] of cache) {
      if (ticks >= entry.expiresAtTicks ||
          (entry.expiredAt !== null && seconds >= entry.expiredAt)) {
        cache.delete(kid);
      }
    }
  }

  function get(kid) {
    if (!validKeyID(kid)) throw new InvalidVerificationKeyError();
    prune();
    if (cache.has(kid)) {
      const entry = cache.get(kid);
      cache.delete(kid);
      cache.set(kid, entry);
      return Promise.resolve(entry);
    }
    if (inFlight.has(kid)) return inFlight.get(kid).promise;
    // No queue or attacker-key backlog. Same-kid callers share the bounded job.
    if (inFlight.size >= settings.maxInFlight) throw new VerificationUnavailableError();

    const controller = new AbortController();
    let resolveResult;
    let rejectResult;
    const promise = new Promise((resolve, reject) => {
      resolveResult = resolve;
      rejectResult = reject;
    });
    const flight = { promise };
    inFlight.set(kid, flight);
    const timer = setTimeout(() => {
      controller.abort();
      rejectResult(new VerificationUnavailableError());
    }, settings.fetchTimeoutMs);

    // Keep the concurrency slot until the underlying work actually settles,
    // even if a broken transport ignores cancellation. Late results never cache.
    Promise.resolve().then(async () => {
      const response = await client.webhookVerificationKeyGet({ key_id: kid }, {
        signal: controller.signal,
        timeout: settings.fetchTimeoutMs,
        maxContentLength: 16 * 1024,
        maxRedirects: 0,
      });
      if (controller.signal.aborted) throw new VerificationUnavailableError();
      const key = response?.data?.key;
      const { seconds } = clock();
      if (!key || key.kid !== kid || key.alg !== "ES256" || key.kty !== "EC" ||
          key.crv !== "P-256" || key.use !== "sig" || key.d !== undefined ||
          typeof key.x !== "string" || typeof key.y !== "string" ||
          !/^[A-Za-z0-9_-]{43}$/.test(key.x) || !/^[A-Za-z0-9_-]{43}$/.test(key.y) ||
          !Number.isSafeInteger(key.created_at) || key.created_at < 0 || key.created_at > seconds ||
          (key.expired_at !== null &&
            (!Number.isSafeInteger(key.expired_at) || key.expired_at <= seconds ||
             key.expired_at < key.created_at))) {
        throw new InvalidVerificationKeyError();
      }
      const { importJWK } = await import("jose");
      let publicKey;
      try { publicKey = await importJWK(key, "ES256"); }
      catch { throw new InvalidVerificationKeyError(); }
      if (controller.signal.aborted) throw new VerificationUnavailableError();
      const current = clock();
      if (key.expired_at !== null && key.expired_at <= current.seconds) {
        throw new InvalidVerificationKeyError();
      }
      prune();
      if (cache.size >= settings.maxEntries) cache.delete(cache.keys().next().value);
      const entry = Object.freeze({ publicKey, expiredAt: key.expired_at,
        expiresAtTicks: current.ticks + settings.ttlMs });
      cache.set(kid, entry);
      resolveResult(entry);
    }).catch((error) => {
      rejectResult(error instanceof InvalidVerificationKeyError
        ? error : new VerificationUnavailableError());
    }).finally(() => {
      clearTimeout(timer);
      if (inFlight.get(kid) === flight) inFlight.delete(kid);
    });
    return promise;
  }

  return {
    get,
    getState() { prune(); return { cached: cache.size, inFlight: inFlight.size }; },
  };
}

module.exports = {
  createWebhookVerificationKeys,
  VerificationUnavailableError,
  VERIFICATION_KEY_LIMITS,
  validKeyID,
};
