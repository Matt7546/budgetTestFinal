const {
  ipKeyGenerator,
  rateLimit,
} = require("express-rate-limit");

const DEFAULT_WINDOW_MS = 15 * 60 * 1000;
const MAX_WINDOW_MS = 24 * 60 * 60 * 1000;
const ROUTE_SPECIFIC_LIMIT_KEYS = new Set([
  "POST /api/auth/development",
  "POST /api/auth/apple",
  "POST /api/create_link_token",
  "POST /api/exchange_public_token",
  "POST /api/disconnect",
  "DELETE /api/account",
  "POST /api/card-payment-details/update-link-token",
  "GET /api/card-payment-details",
  "GET /api/accounts",
  "GET /api/transactions",
]);

function envFlagEnabled(name, defaultValue, env = process.env) {
  const rawValue = env[name];

  if (rawValue === undefined || rawValue === null || rawValue === "") {
    return defaultValue;
  }

  const normalizedValue = String(rawValue).trim().toLowerCase();

  if (["false", "0", "no", "off"].includes(normalizedValue)) {
    return false;
  }

  if (["true", "1", "yes", "on"].includes(normalizedValue)) {
    return true;
  }

  console.warn(
    `${name} has unrecognized value "${rawValue}". Using default=${defaultValue}.`
  );

  return defaultValue;
}

function envIntegerInRange(name, defaultValue, minValue, maxValue, env = process.env) {
  const rawValue = env[name];

  if (rawValue === undefined || rawValue === null || rawValue === "") {
    return defaultValue;
  }

  const parsedValue = Number(String(rawValue).trim());

  if (!Number.isInteger(parsedValue)) {
    console.warn(
      `${name} has unrecognized value "${rawValue}". Using default=${defaultValue}.`
    );
    return defaultValue;
  }

  if (parsedValue < minValue) {
    console.warn(
      `${name}=${parsedValue} is below minimum ${minValue}. Using ${minValue}.`
    );
    return minValue;
  }

  if (parsedValue > maxValue) {
    console.warn(
      `${name}=${parsedValue} is above maximum ${maxValue}. Using ${maxValue}.`
    );
    return maxValue;
  }

  return parsedValue;
}

function resolveRateLimitSettings({
  env = process.env,
  isProduction = false,
  isDeployed = false,
} = {}) {
  return {
    enabled: envFlagEnabled(
      "RATE_LIMIT_ENABLED",
      isProduction || isDeployed,
      env
    ),
    windowMs: envIntegerInRange(
      "RATE_LIMIT_GENERAL_WINDOW_MS",
      DEFAULT_WINDOW_MS,
      60 * 1000,
      MAX_WINDOW_MS,
      env
    ),
    generalMax: envIntegerInRange("RATE_LIMIT_GENERAL_MAX", 300, 1, 10_000, env),
    authMax: envIntegerInRange("RATE_LIMIT_AUTH_MAX", 30, 1, 1_000, env),
    linkTokenMax: envIntegerInRange("RATE_LIMIT_LINK_TOKEN_MAX", 10, 1, 1_000, env),
    tokenExchangeMax: envIntegerInRange("RATE_LIMIT_TOKEN_EXCHANGE_MAX", 10, 1, 1_000, env),
    accountsMax: envIntegerInRange("RATE_LIMIT_ACCOUNTS_MAX", 20, 1, 5_000, env),
    transactionsMax: envIntegerInRange("RATE_LIMIT_TRANSACTIONS_MAX", 10, 1, 5_000, env),
    liabilitiesMax: envIntegerInRange("RATE_LIMIT_LIABILITIES_MAX", 10, 1, 5_000, env),
    trustProxyHops: envIntegerInRange(
      "RATE_LIMIT_TRUST_PROXY_HOPS",
      isDeployed ? 1 : 0,
      0,
      5,
      env
    ),
  };
}

function noOpLimiter(req, res, next) {
  next();
}

function retryAfterSeconds(req, windowMs) {
  const resetTime = req.rateLimit?.resetTime;

  if (resetTime instanceof Date) {
    return Math.max(1, Math.ceil((resetTime.getTime() - Date.now()) / 1000));
  }

  return Math.max(1, Math.ceil(windowMs / 1000));
}

function requestIPKey(req) {
  return `ip:${ipKeyGenerator(req.ip)}`;
}

function requestUserOrIPKey(req) {
  const userID = req.user?.id;

  if (typeof userID === "string" && userID.length > 0) {
    return `user:${userID}`;
  }

  return requestIPKey(req);
}

function requestKeyType(req, usesUserKey) {
  if (usesUserKey && typeof req.user?.id === "string" && req.user.id.length > 0) {
    return "user";
  }

  return "ip";
}

function isRouteSpecificLimitedRequest(req) {
  const route = (req.originalUrl || req.url || "").split("?")[0] || "/";
  return ROUTE_SPECIFIC_LIMIT_KEYS.has(`${req.method} ${route}`);
}

function createLimiter({
  category,
  limit,
  settings,
  keyGenerator,
  usesUserKey,
  skip,
}) {
  if (!settings.enabled) {
    return noOpLimiter;
  }

  return rateLimit({
    windowMs: settings.windowMs,
    limit,
    standardHeaders: "draft-6",
    legacyHeaders: false,
    identifier: category,
    keyGenerator,
    skip,
    handler: (req, res) => {
      const retryAfter = retryAfterSeconds(req, settings.windowMs);
      const route = (req.originalUrl || req.url || "").split("?")[0] || "/";

      console.warn(
        `Rate limit exceeded: category=${category} method=${req.method} route=${route} key_type=${requestKeyType(req, usesUserKey)} retry_after_seconds=${retryAfter}`
      );

      res.set("Retry-After", String(retryAfter));
      res.status(429).json({
        error: "rate_limited",
        message: "Too many requests. Please try again shortly.",
        retry_after_seconds: retryAfter,
      });
    },
  });
}

function createRateLimiters(
  settings,
  { isTrustedAppRequest = () => false } = {}
) {
  return {
    general: createLimiter({
      category: "general_api",
      limit: settings.generalMax,
      settings,
      keyGenerator: requestIPKey,
      usesUserKey: false,
      skip: (req) =>
        isRouteSpecificLimitedRequest(req) && isTrustedAppRequest(req),
    }),
    auth: createLimiter({
      category: "auth",
      limit: settings.authMax,
      settings,
      keyGenerator: requestIPKey,
      usesUserKey: false,
    }),
    linkToken: createLimiter({
      category: "link_token",
      limit: settings.linkTokenMax,
      settings,
      keyGenerator: requestUserOrIPKey,
      usesUserKey: true,
    }),
    tokenExchange: createLimiter({
      category: "token_exchange",
      limit: settings.tokenExchangeMax,
      settings,
      keyGenerator: requestUserOrIPKey,
      usesUserKey: true,
    }),
    accounts: createLimiter({
      category: "accounts",
      limit: settings.accountsMax,
      settings,
      keyGenerator: requestUserOrIPKey,
      usesUserKey: true,
    }),
    transactions: createLimiter({
      category: "transactions",
      limit: settings.transactionsMax,
      settings,
      keyGenerator: requestUserOrIPKey,
      usesUserKey: true,
    }),
    liabilities: createLimiter({
      category: "liabilities",
      limit: settings.liabilitiesMax,
      settings,
      keyGenerator: requestUserOrIPKey,
      usesUserKey: true,
    }),
  };
}

module.exports = {
  createRateLimiters,
  resolveRateLimitSettings,
};
