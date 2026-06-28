const supportedAuthModes = new Set(["personal", "optional", "required"]);

function resolveAuthMode(env = process.env) {
  const mode = (env.AUTH_MODE || "personal").toLowerCase();

  if (!supportedAuthModes.has(mode)) {
    throw new Error("AUTH_MODE must be personal, optional, or required.");
  }

  return mode;
}

function personalUserID(env = process.env) {
  return env.PLAID_PERSONAL_USER_KEY || "personal";
}

function sessionTTLDays(env = process.env) {
  const rawValue = env.SESSION_TTL_DAYS || "30";
  const parsedValue = Number.parseInt(rawValue, 10);

  if (!Number.isFinite(parsedValue) || parsedValue <= 0) {
    throw new Error("SESSION_TTL_DAYS must be a positive integer.");
  }

  return parsedValue;
}

module.exports = {
  personalUserID,
  resolveAuthMode,
  sessionTTLDays,
};
