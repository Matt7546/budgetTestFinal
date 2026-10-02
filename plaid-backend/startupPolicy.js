const { resolveAuthMode } = require("./authConfig");
const { resolveTokenStoreDriver } = require("./plaidItemStore");
const { decodeEncryptionKey } = require("./tokenCrypto");

function value(env, name) {
  const raw = env[name];
  if (raw === undefined || raw === null) return "";
  if (typeof raw !== "string") throw new Error(`${name} must be a string.`);
  return raw.trim();
}

function requiredValue(env, name) {
  const result = value(env, name);
  if (!result) throw new Error(`${name} must be explicitly configured.`);
  return result;
}

function booleanValue(env, name) {
  const raw = value(env, name).toLowerCase();
  if (!raw || ["false", "0", "no", "off"].includes(raw)) return false;
  if (["true", "1", "yes", "on"].includes(raw)) return true;
  throw new Error(`${name} must be an explicit boolean when configured.`);
}

// Pure validation only: no connection, store creation, migration, or listener.
// Render is an existing deployment signal; a local NODE_ENV cannot override it
// or production Plaid. Unknown identity never receives compatibility defaults.
function resolveBackendStartupPolicy(env = process.env) {
  const nodeEnvironment = value(env, "NODE_ENV").toLowerCase();
  if (nodeEnvironment && !["development", "test", "production"].includes(nodeEnvironment)) {
    throw new Error("NODE_ENV must be development, test, or production.");
  }
  const renderValue = value(env, "RENDER").toLowerCase();
  if (renderValue && !["true", "false"].includes(renderValue)) {
    throw new Error("RENDER must be true or false when configured.");
  }
  const plaidEnvironment = requiredValue(env, "PLAID_ENV").toLowerCase();
  if (!["sandbox", "development", "production"].includes(plaidEnvironment)) {
    throw new Error("PLAID_ENV must be sandbox, development, or production.");
  }
  const hasDeploymentSignal = renderValue === "true" || Boolean(value(env, "RENDER_SERVICE_ID")) ||
    nodeEnvironment === "production";
  const isDeployed = hasDeploymentSignal || plaidEnvironment === "production";
  if (!isDeployed && !["development", "test"].includes(nodeEnvironment)) {
    throw new Error("Backend identity is unknown; explicitly configure NODE_ENV for local development or deployment.");
  }

  // Keep the lower-level legacy resolvers usable by isolated local tooling,
  // but never use their missing-value defaults in the HTTP server.
  const authMode = resolveAuthMode({ AUTH_MODE: requiredValue(env, "AUTH_MODE").toLowerCase() });
  const tokenStoreDriver = resolveTokenStoreDriver({
    TOKEN_STORE_DRIVER: requiredValue(env, "TOKEN_STORE_DRIVER").toLowerCase(),
  });
  if (isDeployed && authMode !== "required") {
    throw new Error("AUTH_MODE must be required for deployed or production operation.");
  }
  if (isDeployed && tokenStoreDriver !== "postgres") {
    throw new Error("TOKEN_STORE_DRIVER must be postgres for deployed or production operation.");
  }
  const developmentAuthEnabled = booleanValue(env, "DEV_AUTH_ENABLED");
  if (isDeployed && developmentAuthEnabled) {
    throw new Error("DEV_AUTH_ENABLED must be disabled for deployed or production operation.");
  }

  // A configured session store is also used with a local JSON Item store.
  const databaseURL = value(env, "DATABASE_URL");
  if (tokenStoreDriver === "postgres" || authMode !== "personal" || databaseURL) {
    let parsed;
    try {
      parsed = new URL(requiredValue(env, "DATABASE_URL"));
    } catch {
      throw new Error("DATABASE_URL must be configured as a valid Postgres URL.");
    }
    if (!["postgres:", "postgresql:"].includes(parsed.protocol) ||
        !parsed.hostname || parsed.pathname.length <= 1 || parsed.hash) {
      throw new Error("DATABASE_URL must be configured as a valid Postgres URL.");
    }
  }
  if (tokenStoreDriver === "postgres") {
    decodeEncryptionKey(requiredValue(env, "TOKEN_ENCRYPTION_KEY"));
  }
  if (isDeployed) {
    // These were already required to use the protected/provider/Apple routes.
    // Reject at startup instead of advertising a healthy but unusable service.
    for (const name of ["APP_API_KEY", "PLAID_CLIENT_ID", "PLAID_SECRET", "APPLE_CLIENT_ID"]) {
      requiredValue(env, name);
    }
  }

  return Object.freeze({
    deploymentClass: isDeployed ? "deployed" : "local",
    isDeployed,
    hasDeploymentSignal,
    plaidEnvironment,
    authMode,
    tokenStoreDriver,
    developmentAuthEnabled,
  });
}

module.exports = { resolveBackendStartupPolicy };
