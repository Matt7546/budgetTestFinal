const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const path = require("path");
const plaid = require("plaid");
const {
  createPlaidItemStore,
  resolveTokenStoreDriver,
} = require("./plaidItemStore");
const {
  importJsonTokenStoreToPostgres,
} = require("./tokenStoreMigration");
const {
  personalUserID,
  resolveAuthMode,
} = require("./authConfig");
const { createSessionStore } = require("./sessionStore");
const { createAuthMiddleware } = require("./authMiddleware");
const { createDevelopmentAuth } = require("./developmentAuth");
const {
  createRateLimiters,
  resolveRateLimitSettings,
} = require("./rateLimit");
const { verifyAppleIdentityToken } = require("./appleTokenVerifier");
const {
  deleteAccountForUser,
  removePlaidItemsForUser,
} = require("./accountLifecycle");
const {
  sanitizedCardPaymentDetailsFromPlaidResponse,
} = require("./cardPaymentDetails");

dotenv.config();

const app = express();

app.use(cors());
app.use(express.json());

const plaidEnvironmentName = (
  process.env.PLAID_ENV || "sandbox"
).toLowerCase();

const plaidEnvironments = {
  sandbox: plaid.PlaidEnvironments.sandbox,
  development: plaid.PlaidEnvironments.development,
  production: plaid.PlaidEnvironments.production,
};

const activePlaidEnvironment =
  plaidEnvironments[plaidEnvironmentName] ||
  plaid.PlaidEnvironments.sandbox;

const activePlaidEnvironmentName =
  plaidEnvironments[plaidEnvironmentName]
    ? plaidEnvironmentName
    : "sandbox";
const isDeployedEnvironment =
  String(process.env.RENDER || "").toLowerCase() === "true" ||
  process.env.NODE_ENV === "production";
const rateLimitSettings = resolveRateLimitSettings({
  isProduction: activePlaidEnvironmentName === "production",
  isDeployed: isDeployedEnvironment,
});

if (rateLimitSettings.enabled && rateLimitSettings.trustProxyHops > 0) {
  // Render forwards requests through one known reverse proxy. Do not trust every proxy.
  app.set("trust proxy", rateLimitSettings.trustProxyHops);
}

const rateLimiters = createRateLimiters(rateLimitSettings, {
  isTrustedAppRequest: (req) => {
    const configuredApiKey = process.env.APP_API_KEY;
    return Boolean(configuredApiKey) &&
      req.get("x-app-api-key") === configuredApiKey;
  },
});

const configuredTokenStorePath = process.env.PLAID_TOKEN_STORE_PATH;
const tokenStorePath = configuredTokenStorePath
  ? path.isAbsolute(configuredTokenStorePath)
    ? configuredTokenStorePath
    : path.join(__dirname, configuredTokenStorePath)
  : path.join(__dirname, ".plaid-token-store.json");

const tokenStoreDriver = resolveTokenStoreDriver();
const plaidItemStore = createPlaidItemStore({
  tokenStorePath,
});
const authMode = resolveAuthMode();
const compatibilityUserID = personalUserID();
const sessionStore = process.env.DATABASE_URL
  ? createSessionStore()
  : null;

const plaidRedirectUri = process.env.PLAID_REDIRECT_URI;
const plaidRedirectUriHost = plaidRedirectUri
  ? (() => {
      try {
        return new URL(plaidRedirectUri).host;
      } catch {
        return "invalid_url";
      }
    })()
  : null;

function envFlagEnabled(name, defaultValue) {
  const rawValue = process.env[name];

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

function envIntegerInRange(name, defaultValue, minValue, maxValue) {
  const rawValue = process.env[name];

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

const developmentAuthRequested = envFlagEnabled("DEV_AUTH_ENABLED", false);
const developmentAuthEnabled =
  developmentAuthRequested && activePlaidEnvironmentName !== "production";

if (developmentAuthRequested && !developmentAuthEnabled) {
  console.warn(
    "DEV_AUTH_ENABLED was requested but is disabled because PLAID_ENV=production."
  );
}

function developmentAuthDisabledMessage() {
  if (activePlaidEnvironmentName === "production") {
    return "Local dev sign-in is disabled because PLAID_ENV=production. Use real Sign in with Apple.";
  }

  return "Local dev sign-in is disabled. Add DEV_AUTH_ENABLED=true to plaid-backend/.env and restart the backend.";
}

const developmentAuth = createDevelopmentAuth({
  enabled: developmentAuthEnabled,
  userID: process.env.DEV_AUTH_USER_ID || "dev_local_user",
  email: process.env.DEV_AUTH_EMAIL || "debug@local.caldera",
  fullName: process.env.DEV_AUTH_FULL_NAME || "Local Debug User",
});

const authMiddleware = createAuthMiddleware({
  authMode,
  personalUserID: compatibilityUserID,
  sessionStore,
  developmentAuth,
});
const {
  getRequestUserID,
  requireSessionAuth,
  resolvePlaidAuth,
} = authMiddleware;

const plaidTransactionsEnabled = envFlagEnabled(
  "PLAID_TRANSACTIONS_ENABLED",
  true
);
const plaidTransactionsLookbackDays = envIntegerInRange(
  "PLAID_TRANSACTIONS_LOOKBACK_DAYS",
  30,
  30,
  730
);
const plaidLiabilitiesEnabled = envFlagEnabled(
  "PLAID_LIABILITIES_ENABLED",
  false
);
const plaidLiabilitiesLinkEnabled = envFlagEnabled(
  "PLAID_LIABILITIES_LINK_ENABLED",
  false
);
const plaidAccountsEnabled = true;

function limiterWhen(enabled, limiter) {
  if (enabled) {
    return limiter;
  }

  return (req, res, next) => next();
}

const transactionsRateLimiter = limiterWhen(
  plaidTransactionsEnabled,
  rateLimiters.transactions
);
const cardPaymentDetailsRateLimiter = limiterWhen(
  plaidLiabilitiesEnabled,
  rateLimiters.liabilities
);
const cardPaymentDetailsUpdateRateLimiter = limiterWhen(
  plaidLiabilitiesEnabled && plaidLiabilitiesLinkEnabled,
  rateLimiters.linkToken
);

function plaidCapabilitiesResponse() {
  return {
    accounts_enabled: plaidAccountsEnabled,
    transactions_enabled: plaidTransactionsEnabled,
    liabilities_enabled: plaidLiabilitiesEnabled,
    liabilities_link_enabled: plaidLiabilitiesLinkEnabled,
  };
}

const appleAppSiteAssociation = {
  applinks: {
    apps: [],
    details: [
      {
        appID: "HT5R7T5J34.com.matthewthomas.caldera",
        paths: ["/plaid/oauth"],
      },
    ],
  },
};

function requireAppApiKey(req, res, next) {
  const configuredApiKey = process.env.APP_API_KEY;

  if (!configuredApiKey) {
    console.warn("Protected Plaid route rejected: APP_API_KEY missing.");

    return res.status(503).json({
      error: "server_not_configured",
      message: "Backend API key is not configured.",
    });
  }

  if (req.get("x-app-api-key") !== configuredApiKey) {
    return res.status(401).json({
      error: "unauthorized",
      message: "Missing or invalid API key.",
    });
  }

  next();
}

function logPlaidError(context, error) {
  const plaidError = error.response?.data;
  const errorCode = plaidErrorCode(error);
  const errorType = plaidError?.error_type || "unknown";
  const status = error.response?.status || "unknown";

  console.error(
    `${context}: status=${status} type=${errorType} code=${errorCode}`
  );
}

function plaidErrorCode(error) {
  return error.response?.data?.error_code || error.code || "unknown";
}

function isAdditionalConsentRequired(error) {
  return plaidErrorCode(error) === "ADDITIONAL_CONSENT_REQUIRED";
}

function logStoreError(context, error) {
  console.error(`${context}: token_store_error`);
}

function withInstitutionMetadata(record, item) {
  return {
    ...record,
    item_id: item.itemId,
    institution_name: item.institutionName,
    institution_id: item.institutionId,
  };
}

function dedupeByID(records, key) {
  const byID = new Map();

  records.forEach((record) => {
    const id = record?.[key];

    if (id) {
      byID.set(id, record);
    }
  });

  return Array.from(byID.values());
}

function stringOrNull(value) {
  if (typeof value !== "string") {
    return null;
  }

  const trimmedValue = value.trim();

  return trimmedValue.length > 0 ? trimmedValue : null;
}

const configuration = new plaid.Configuration({
  basePath: activePlaidEnvironment,
  baseOptions: {
    headers: {
      "PLAID-CLIENT-ID": process.env.PLAID_CLIENT_ID,
      "PLAID-SECRET": process.env.PLAID_SECRET,
    },
  },
});

const client = new plaid.PlaidApi(configuration);

console.log(
  `Plaid backend configured for ${activePlaidEnvironmentName}.`
);
console.log(
  `Plaid redirect URI configured: ${Boolean(plaidRedirectUri)} host=${plaidRedirectUriHost || "none"}.`
);
console.log(
  `Plaid token store driver: ${tokenStoreDriver}.`
);
console.log(
  `Caldera auth mode: ${authMode}.`
);
console.log(
  `Caldera development auth enabled: ${developmentAuth.isEnabled()}.`
);
console.log(
  `Caldera rate limiting: enabled=${rateLimitSettings.enabled} window_ms=${rateLimitSettings.windowMs} trust_proxy_hops=${rateLimitSettings.enabled ? rateLimitSettings.trustProxyHops : 0}.`
);

app.get("/.well-known/apple-app-site-association", (req, res) => {
  res
    .type("application/json")
    .send(JSON.stringify(appleAppSiteAssociation));
});

app.get("/plaid/oauth", (req, res) => {
  res
    .type("html")
    .send("<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Return to Caldera</title></head><body><main style=\"font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;line-height:1.5;\"><h1>Return to Caldera</h1><p>If Caldera did not reopen automatically, return to the app to finish linking your account.</p></main></body></html>");
});

// Health Check
app.get("/api/health", (req, res) => {
  res.json({
    status: "ok",
    plaid_env: activePlaidEnvironmentName,
    storage_driver: tokenStoreDriver,
    auth_mode: authMode,
    redirect_uri_configured: Boolean(plaidRedirectUri),
    redirect_uri_host: plaidRedirectUriHost,
  });
});

// Keep the lightweight health route above this middleware for Render monitoring.
app.use("/api", rateLimiters.general);

function sanitizeOptionalString(value) {
  if (typeof value !== "string") {
    return null;
  }

  const trimmedValue = value.trim();

  return trimmedValue.length > 0 ? trimmedValue : null;
}

function authUserResponse(user) {
  return {
    id: user.id,
    email: user.email || null,
    full_name: user.full_name || null,
  };
}

// Debug/local development auth. This endpoint is only available when
// DEV_AUTH_ENABLED=true and the backend is not configured for Plaid Production.
app.post("/api/auth/development", requireAppApiKey, rateLimiters.auth, async (req, res) => {
  if (!developmentAuth.isEnabled()) {
    return res.status(409).json({
      error: "dev_auth_disabled",
      message: developmentAuthDisabledMessage(),
      development_auth_enabled: false,
      plaid_env: activePlaidEnvironmentName,
    });
  }

  try {
    const session = await developmentAuth.createSession({
      userAgent: req.get("user-agent") || null,
    });

    res.json({
      session_token: session.token,
      user: authUserResponse(session.user),
      expires_at: session.expiresAt,
    });
  } catch {
    res.status(500).json({
      error: "dev_auth_failed",
      message: "Unable to create development session.",
    });
  }
});

// Sign in with Apple
app.post("/api/auth/apple", requireAppApiKey, rateLimiters.auth, async (req, res) => {
  if (!sessionStore) {
    return res.status(503).json({
      error: "auth_not_configured",
      message: "Authentication is not configured.",
    });
  }

  const {
    identity_token,
    nonce,
    full_name,
    email,
  } = req.body || {};

  if (!identity_token) {
    return res.status(400).json({
      error: "missing_identity_token",
      message: "An Apple identity token is required.",
    });
  }

  let verifiedIdentity;

  try {
    verifiedIdentity = await verifyAppleIdentityToken(identity_token, {
      nonce: sanitizeOptionalString(nonce),
    });
  } catch (error) {
    if (error.message.includes("APPLE_CLIENT_ID")) {
      return res.status(503).json({
        error: "auth_not_configured",
        message: "Apple authentication is not configured.",
      });
    }

    return res.status(401).json({
      error: "invalid_apple_token",
      message: "Apple authentication failed.",
    });
  }

  try {
    const user = await sessionStore.findOrCreateAppleUser({
      appleSub: verifiedIdentity.appleSub,
      email: sanitizeOptionalString(email) || verifiedIdentity.email,
      fullName: sanitizeOptionalString(full_name),
    });
    const session = await sessionStore.createSession(user.id, {
      userAgent: req.get("user-agent") || null,
    });

    res.json({
      session_token: session.token,
      user: authUserResponse(user),
      expires_at: session.expiresAt,
    });
  } catch {
    res.status(500).json({
      error: "auth_failed",
      message: "Unable to create session.",
    });
  }
});

app.get("/api/auth/me", requireAppApiKey, requireSessionAuth, (req, res) => {
  res.json({
    user: authUserResponse(req.user),
  });
});

app.post("/api/auth/logout", requireAppApiKey, requireSessionAuth, async (req, res) => {
  try {
    if (req.isDevelopmentSession) {
      await developmentAuth.revokeSessionToken(req.sessionToken);

      return res.json({
        success: true,
      });
    }

    if (!sessionStore) {
      return res.status(503).json({
        error: "auth_not_configured",
        message: "Authentication is not configured.",
      });
    }

    await sessionStore.revokeSessionToken(req.sessionToken);

    res.json({
      success: true,
    });
  } catch {
    res.status(500).json({
      error: "logout_failed",
      message: "Unable to log out.",
    });
  }
});

app.get("/api/capabilities", requireAppApiKey, (req, res) => {
  res.json(plaidCapabilitiesResponse());
});

// Create Link Token
app.post("/api/create_link_token", requireAppApiKey, resolvePlaidAuth, rateLimiters.linkToken, async (req, res) => {
  try {
    const userId = getRequestUserID(req);
    const products = plaidTransactionsEnabled ? ["transactions"] : [];
    const linkTokenRequest = {
      user: {
        client_user_id: userId,
      },
      client_name: "Caldera",
      products,
      country_codes: ["US"],
      language: "en",
    };

    if (plaidLiabilitiesLinkEnabled) {
      linkTokenRequest.optional_products = ["liabilities"];
    }

    if (plaidRedirectUri) {
      linkTokenRequest.redirect_uri = plaidRedirectUri;
    }

    console.log(
      `Creating Plaid link token: transactions_enabled=${plaidTransactionsEnabled} liabilities_link_enabled=${plaidLiabilitiesLinkEnabled} products=${products.join(",") || "none"} optional_products=${linkTokenRequest.optional_products?.join(",") || "none"} redirect_uri_included=${Boolean(linkTokenRequest.redirect_uri)} redirect_uri_host=${plaidRedirectUriHost || "none"}.`
    );

    if (!plaidTransactionsEnabled) {
      console.warn(
        "PLAID_TRANSACTIONS_ENABLED=false. Attempting accounts-only Link token creation with no paid product fallback. Confirm productless Link support with Plaid before enabling this in production."
      );
    }

    const response = await client.linkTokenCreate(linkTokenRequest);

    res.json({
      link_token: response.data.link_token,
    });
  } catch (error) {
    logPlaidError("Create Link Token Error", error);

    if (!plaidTransactionsEnabled) {
      return res.status(503).json({
        error: "accounts_only_link_unavailable",
        message:
          "Accounts-only Link mode is not available with the current Plaid configuration. Confirm productless Link support with Plaid or re-enable Transactions.",
        ...plaidCapabilitiesResponse(),
      });
    }

    res.status(500).json({
      error: "Failed to create link token",
    });
  }
});

// Exchange Public Token
app.post("/api/exchange_public_token", requireAppApiKey, resolvePlaidAuth, rateLimiters.tokenExchange, async (req, res) => {
  try {
    const {
      public_token,
      institution_name,
      institution_id,
    } = req.body;

    if (!public_token) {
      return res.status(400).json({
        error: "missing_public_token",
        message: "A public token is required.",
      });
    }

    const userId = getRequestUserID(req);
    const response = await client.itemPublicTokenExchange({
      public_token,
    });

    const linkedItemCount = await plaidItemStore.saveUserItem(userId, {
      accessToken: response.data.access_token,
      itemId: response.data.item_id,
      institutionName: institution_name,
      institutionId: institution_id,
    });

    console.log(`Plaid item linked. linked_items=${linkedItemCount}`);

    res.json({
      success: true,
      item_id: response.data.item_id,
      linked_items: linkedItemCount,
    });
  } catch (error) {
    logPlaidError("Exchange Token Error", error);

    res.status(500).json({
      error: "Failed to exchange token",
    });
  }
});

// Disconnect all Plaid Items for the authenticated user.
app.post("/api/disconnect", requireAppApiKey, resolvePlaidAuth, rateLimiters.accounts, async (req, res) => {
  const userId = getRequestUserID(req);

  try {
    const removalResult = await removePlaidItemsForUser({
      userId,
      plaidItemStore,
      plaidClient: client,
    });

    console.log(
      `Plaid disconnect all completed. removed_items=${removalResult.removed_items} failed_items=${removalResult.failed_items}`
    );

    if (removalResult.failed_items > 0) {
      return res.status(502).json({
        success: false,
        linked: true,
        retryable: true,
        message: "Some bank connections could not be disconnected. Try again.",
        ...removalResult,
      });
    }

    return res.json({
      success: true,
      linked: false,
      retryable: false,
      ...removalResult,
    });
  } catch (error) {
    logStoreError("Disconnect All Banks Error", error);

    return res.status(500).json({
      success: false,
      error: "disconnect_failed",
      message: "Failed to disconnect bank connections.",
    });
  }
});

app.delete("/api/account", requireAppApiKey, requireSessionAuth, rateLimiters.accounts, async (req, res) => {
  if (!sessionStore) {
    return res.status(503).json({
      success: false,
      error: "auth_not_configured",
      message: "Authentication is not configured.",
    });
  }

  const userId = req.user?.id;

  if (!userId) {
    return res.status(401).json({
      success: false,
      error: "unauthorized",
      message: "Authentication required.",
    });
  }

  try {
    const result = await deleteAccountForUser({
      userId,
      plaidItemStore,
      plaidClient: client,
      sessionStore,
    });

    if (!result.success) {
      console.warn(
        `Account deletion blocked by Plaid removal failure. removed_items=${result.removed_items} failed_items=${result.failed_items}`
      );

      return res.status(502).json({
        success: false,
        retryable: true,
        message: "Some bank connections could not be removed. Try again.",
        removed_items: result.removed_items,
        failed_items: result.failed_items,
        removal_errors: result.removal_errors,
        sessions_revoked: result.sessions_revoked,
        user_deleted: result.user_deleted,
      });
    }

    console.log(
      `Caldera account deleted. removed_items=${result.removed_items} sessions_revoked=${result.sessions_revoked}`
    );

    return res.json({
      success: true,
      removed_items: result.removed_items,
      failed_items: result.failed_items,
      sessions_revoked: result.sessions_revoked,
      user_deleted: result.user_deleted,
    });
  } catch (error) {
    logStoreError("Delete Account Error", error);

    return res.status(500).json({
      success: false,
      error: "delete_account_failed",
      message: "Failed to delete account.",
    });
  }
});

// Create an update-mode Link token to add card payment details consent for an existing Item.
app.post("/api/card-payment-details/update-link-token", requireAppApiKey, resolvePlaidAuth, cardPaymentDetailsUpdateRateLimiter, async (req, res) => {
  if (!plaidLiabilitiesEnabled || !plaidLiabilitiesLinkEnabled) {
    return res.status(409).json({
      error: "card_payment_details_update_disabled",
      message: "Card payment details permission is not enabled.",
      mode: "card_payment_details_update",
      ...plaidCapabilitiesResponse(),
    });
  }

  const itemID = stringOrNull(req.body?.item_id);
  const accountID = stringOrNull(req.body?.account_id);

  if (!itemID || !accountID) {
    return res.status(400).json({
      error: "invalid_card_payment_details_update_request",
      message: "A linked account and selected card are required.",
      mode: "card_payment_details_update",
      ...plaidCapabilitiesResponse(),
    });
  }

  const userId = getRequestUserID(req);
  let items;

  try {
    items = await plaidItemStore.getUserItems(userId);
  } catch (error) {
    logStoreError("Card Payment Details Update Item Store Error", error);

    return res.status(500).json({
      error: "card_payment_details_update_unavailable",
      message: "Card payment details permission could not be started.",
      mode: "card_payment_details_update",
      ...plaidCapabilitiesResponse(),
    });
  }

  const item = items.find((storedItem) => storedItem.itemId === itemID);

  if (!item) {
    return res.status(404).json({
      error: "item_not_found",
      message: "This linked account could not be found.",
      mode: "card_payment_details_update",
      item_id: itemID,
      account_id: accountID,
      ...plaidCapabilitiesResponse(),
    });
  }

  try {
    const linkTokenRequest = {
      user: {
        client_user_id: userId,
      },
      client_name: "Caldera",
      access_token: item.accessToken,
      country_codes: ["US"],
      language: "en",
      additional_consented_products: ["liabilities"],
    };

    if (plaidRedirectUri) {
      linkTokenRequest.redirect_uri = plaidRedirectUri;
    }

    console.log(
      `Creating card payment details update Link token: additional_consented_products=liabilities redirect_uri_included=${Boolean(linkTokenRequest.redirect_uri)} redirect_uri_host=${plaidRedirectUriHost || "none"}.`
    );

    const response = await client.linkTokenCreate(linkTokenRequest);

    return res.json({
      link_token: response.data.link_token,
      mode: "card_payment_details_update",
      item_id: itemID,
      account_id: accountID,
      liabilities_enabled: true,
      liabilities_link_enabled: true,
    });
  } catch (error) {
    logPlaidError("Card Payment Details Update Link Token Error", error);

    return res.status(502).json({
      error: "card_payment_details_update_unavailable",
      message: "Card payment details permission could not be started.",
      mode: "card_payment_details_update",
      item_id: itemID,
      account_id: accountID,
      ...plaidCapabilitiesResponse(),
    });
  }
});

// Get Card Payment Details
app.get("/api/card-payment-details", requireAppApiKey, resolvePlaidAuth, cardPaymentDetailsRateLimiter, async (req, res) => {
  if (!plaidLiabilitiesEnabled) {
    return res.json({
      enabled: false,
      cards: [],
      message: "Card payment details are not enabled.",
      ...plaidCapabilitiesResponse(),
    });
  }

  const userId = getRequestUserID(req);
  let items;

  try {
    items = await plaidItemStore.getUserItems(userId);
  } catch (error) {
    logStoreError("Card Payment Details Item Store Error", error);

    return res.status(500).json({
      enabled: true,
      cards: [],
      error: "card_payment_details_unavailable",
      message: "Card payment details could not be loaded.",
      ...plaidCapabilitiesResponse(),
    });
  }

  if (items.length === 0) {
    return res.status(409).json({
      enabled: true,
      cards: [],
      error: "not_linked",
      message: "No linked bank connection found.",
      ...plaidCapabilitiesResponse(),
    });
  }

  const refreshedAt = new Date().toISOString();
  const cards = [];
  let successfulItems = 0;
  let failedItems = 0;
  let consentRequired = false;

  for (const item of items) {
    try {
      const response = await client.liabilitiesGet({
        access_token: item.accessToken,
      });

      successfulItems += 1;
      cards.push(
        ...sanitizedCardPaymentDetailsFromPlaidResponse(
          response.data,
          item,
          refreshedAt
        )
      );
    } catch (error) {
      failedItems += 1;
      consentRequired = consentRequired || isAdditionalConsentRequired(error);
      logPlaidError("Card Payment Details Item Error", error);
    }
  }

  if (successfulItems === 0 && consentRequired) {
    return res.status(409).json({
      enabled: true,
      cards: [],
      consent_required: true,
      error: "additional_consent_required",
      message: "Card payment details need permission for this connection.",
      ...plaidCapabilitiesResponse(),
    });
  }

  if (successfulItems === 0 && failedItems > 0) {
    return res.status(502).json({
      enabled: true,
      cards: [],
      error: "card_payment_details_unavailable",
      message: "Card payment details could not be loaded for this connection.",
      ...plaidCapabilitiesResponse(),
    });
  }

  return res.json({
    enabled: true,
    cards: dedupeByID(cards, "account_id"),
    partial_failure: failedItems > 0,
    message: failedItems > 0
      ? "Some card payment details could not be loaded."
      : undefined,
    ...plaidCapabilitiesResponse(),
  });
});

// Get Accounts
app.get("/api/accounts", requireAppApiKey, resolvePlaidAuth, rateLimiters.accounts, async (req, res) => {
  const userId = getRequestUserID(req);
  let items;

  try {
    items = await plaidItemStore.getUserItems(userId);
  } catch (error) {
    logStoreError("Accounts Item Store Error", error);

    return res.status(500).json({
      error: "Failed to fetch accounts",
    });
  }

  if (items.length === 0) {
    return res.status(409).json({
      error: "not_linked",
      message: "No linked Plaid item found.",
    });
  }

  const accounts = [];
  const itemErrors = [];
  let successfulItems = 0;

  for (const item of items) {
    try {
      const response = await client.accountsGet({
        access_token: item.accessToken,
      });

      successfulItems += 1;

      accounts.push(
        ...response.data.accounts.map((account) =>
          withInstitutionMetadata(account, item)
        )
      );
    } catch (error) {
      itemErrors.push({
        error: "accounts_fetch_failed",
      });
      logPlaidError("Accounts Item Error", error);
    }
  }

  if (successfulItems === 0 && itemErrors.length > 0) {
    return res.status(500).json({
      error: "Failed to fetch accounts",
    });
  }

  res.json({
    accounts: dedupeByID(accounts, "account_id"),
    item_errors: itemErrors,
    partial_failure: itemErrors.length > 0,
  });
});

// Get Transactions
app.get("/api/transactions", requireAppApiKey, resolvePlaidAuth, transactionsRateLimiter, async (req, res) => {
  if (!plaidTransactionsEnabled) {
    return res.status(409).json({
      error: "transactions_disabled",
      message: "Transactions are disabled for this backend.",
      transactions: [],
      accounts: [],
      partial_failure: false,
      ...plaidCapabilitiesResponse(),
    });
  }

  const userId = getRequestUserID(req);
  let items;

  try {
    items = await plaidItemStore.getUserItems(userId);
  } catch (error) {
    logStoreError("Transactions Item Store Error", error);

    return res.status(500).json({
      error: "Failed to fetch transactions",
    });
  }

  if (items.length === 0) {
    return res.status(409).json({
      error: "not_linked",
      message: "No linked Plaid item found.",
    });
  }

  const today = new Date();
  const startDate = new Date();
  startDate.setDate(today.getDate() - plaidTransactionsLookbackDays);

  const transactions = [];
  const accounts = [];
  const itemErrors = [];
  let successfulItems = 0;

  for (const item of items) {
    try {
      const response = await client.transactionsGet({
        access_token: item.accessToken,
        start_date: startDate.toISOString().split("T")[0],
        end_date: today.toISOString().split("T")[0],
      });

      successfulItems += 1;

      transactions.push(
        ...response.data.transactions.map((transaction) =>
          withInstitutionMetadata(transaction, item)
        )
      );

      if (Array.isArray(response.data.accounts)) {
        accounts.push(
          ...response.data.accounts.map((account) =>
            withInstitutionMetadata(account, item)
          )
        );
      }
    } catch (error) {
      itemErrors.push({
        error: "transactions_fetch_failed",
      });
      logPlaidError("Transactions Item Error", error);
    }
  }

  if (successfulItems === 0 && itemErrors.length > 0) {
    return res.status(500).json({
      error: "Failed to fetch transactions",
    });
  }

  res.json({
    transactions: dedupeByID(transactions, "transaction_id"),
    accounts: dedupeByID(accounts, "account_id"),
    item_errors: itemErrors,
    partial_failure: itemErrors.length > 0,
  });
});

const PORT = process.env.PORT || 3001;

async function initializeTokenStore() {
  if (tokenStoreDriver !== "postgres") {
    return;
  }

  try {
    await plaidItemStore.ensureSchema();
    console.log("Postgres Plaid item store initialized.");

    if (process.env.MIGRATE_JSON_TOKEN_STORE_ON_START === "true") {
      console.log("Startup JSON token store import started.");
      const importResult = await importJsonTokenStoreToPostgres({
        sourcePath: tokenStorePath,
        postgresStore: plaidItemStore,
      });

      if (!importResult.skipped) {
        console.log("Startup JSON token store import completed.");
      }
    } else {
      console.log("Startup JSON token store import skipped.");
    }
  } catch (error) {
    console.error(
      `Postgres Plaid item store initialization failed: ${error.message}`
    );
    throw error;
  }
}

async function initializeAuthStore() {
  if (!sessionStore) {
    if (authMode !== "personal") {
      throw new Error("DATABASE_URL is required when AUTH_MODE is optional or required.");
    }

    return;
  }

  if (tokenStoreDriver !== "postgres" && authMode === "personal") {
    return;
  }

  try {
    await sessionStore.ensureSchema();
    console.log("Caldera auth session store initialized.");
  } catch (error) {
    console.error(`Caldera auth session store initialization failed: ${error.message}`);
    throw error;
  }
}

async function startServer() {
  await initializeTokenStore();
  await initializeAuthStore();

  app.listen(PORT, () => {
    console.log(`🚀 Plaid backend running on port ${PORT}`);
  });
}

startServer().catch((error) => {
  console.error(`Plaid backend startup failed: ${error.message}`);
  process.exit(1);
});
