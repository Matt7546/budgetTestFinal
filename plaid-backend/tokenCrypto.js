const crypto = require("crypto");

const ALGORITHM = "aes-256-gcm";
const KEY_BYTES = 32;
const IV_BYTES = 12;

function decodeEncryptionKey(encodedKey) {
  if (!encodedKey || typeof encodedKey !== "string") {
    throw new Error("TOKEN_ENCRYPTION_KEY is required for Postgres token storage.");
  }

  const trimmedKey = encodedKey.trim();
  const decodedKey = Buffer.from(trimmedKey, "base64");

  if (decodedKey.length !== KEY_BYTES) {
    throw new Error("TOKEN_ENCRYPTION_KEY must be a 32-byte base64 value.");
  }

  const normalizedInput = trimmedKey.replace(/=+$/, "");
  const normalizedRoundTrip = decodedKey.toString("base64").replace(/=+$/, "");

  if (normalizedInput !== normalizedRoundTrip) {
    throw new Error("TOKEN_ENCRYPTION_KEY must be valid base64.");
  }

  return decodedKey;
}

function encryptToken(accessToken, encodedKey) {
  if (!accessToken || typeof accessToken !== "string") {
    throw new Error("accessToken is required for encryption.");
  }

  const key = decodeEncryptionKey(encodedKey);
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(accessToken, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  return {
    ciphertext: ciphertext.toString("base64"),
    iv: iv.toString("base64"),
    tag: tag.toString("base64"),
  };
}

function decryptToken(encryptedToken, encodedKey) {
  const key = decodeEncryptionKey(encodedKey);

  if (!encryptedToken?.ciphertext || !encryptedToken?.iv || !encryptedToken?.tag) {
    throw new Error("Encrypted token payload is incomplete.");
  }

  const decipher = crypto.createDecipheriv(
    ALGORITHM,
    key,
    Buffer.from(encryptedToken.iv, "base64")
  );

  decipher.setAuthTag(Buffer.from(encryptedToken.tag, "base64"));

  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(encryptedToken.ciphertext, "base64")),
    decipher.final(),
  ]);

  return plaintext.toString("utf8");
}

module.exports = {
  decodeEncryptionKey,
  encryptToken,
  decryptToken,
};
