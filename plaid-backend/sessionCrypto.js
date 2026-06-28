const crypto = require("crypto");

const SESSION_TOKEN_BYTES = 32;

function generateSessionToken() {
  return crypto.randomBytes(SESSION_TOKEN_BYTES).toString("base64url");
}

function hashSessionToken(token) {
  if (!token || typeof token !== "string") {
    throw new Error("Session token is required.");
  }

  return crypto
    .createHash("sha256")
    .update(token, "utf8")
    .digest("hex");
}

function safeUserID() {
  return `user_${crypto.randomUUID()}`;
}

function safeSessionID() {
  return `session_${crypto.randomUUID()}`;
}

module.exports = {
  generateSessionToken,
  hashSessionToken,
  safeSessionID,
  safeUserID,
};
