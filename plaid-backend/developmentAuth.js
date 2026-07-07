const {
  generateSessionToken,
  safeSessionID,
} = require("./sessionCrypto");
const { sessionTTLDays } = require("./authConfig");

function normalizeString(value, fallback) {
  if (typeof value !== "string") {
    return fallback;
  }

  const trimmedValue = value.trim();

  return trimmedValue.length > 0 ? trimmedValue : fallback;
}

function createDevelopmentAuth({
  enabled = false,
  userID = "dev_local_user",
  email = "debug@local.caldera",
  fullName = "Local Debug User",
  ttlDays = sessionTTLDays(),
} = {}) {
  const sessionsByToken = new Map();
  const publicUser = {
    id: normalizeString(userID, "dev_local_user"),
    email: normalizeString(email, "debug@local.caldera"),
    full_name: normalizeString(fullName, "Local Debug User"),
  };

  function isEnabled() {
    return Boolean(enabled);
  }

  function pruneExpiredSessions() {
    const now = Date.now();

    for (const [token, record] of sessionsByToken.entries()) {
      if (record.expiresAtMs <= now) {
        sessionsByToken.delete(token);
      }
    }
  }

  async function createSession({ userAgent = null } = {}) {
    if (!isEnabled()) {
      throw new Error("Development auth is disabled.");
    }

    pruneExpiredSessions();

    const token = generateSessionToken();
    const expiresAt = new Date(Date.now() + ttlDays * 24 * 60 * 60 * 1000);
    const record = {
      session: {
        id: safeSessionID(),
        user_id: publicUser.id,
        expires_at: expiresAt.toISOString(),
        user_agent: userAgent,
      },
      user: publicUser,
      expiresAtMs: expiresAt.getTime(),
    };

    sessionsByToken.set(token, record);

    return {
      token,
      user: record.user,
      expiresAt: record.session.expires_at,
    };
  }

  async function getSessionByToken(token) {
    if (!isEnabled() || !token) {
      return null;
    }

    pruneExpiredSessions();

    const record = sessionsByToken.get(token);

    if (!record) {
      return null;
    }

    return {
      session: record.session,
      user: record.user,
      isDevelopmentSession: true,
    };
  }

  async function revokeSessionToken(token) {
    if (!token) {
      return;
    }

    sessionsByToken.delete(token);
  }

  return {
    isEnabled,
    createSession,
    getSessionByToken,
    revokeSessionToken,
  };
}

module.exports = {
  createDevelopmentAuth,
};
