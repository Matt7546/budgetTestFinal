const assert = require("node:assert/strict");
const crypto = require("crypto");
const { decryptToken, encryptToken } = require("../tokenCrypto");

const key = crypto.randomBytes(32).toString("base64");
const wrongKey = crypto.randomBytes(32).toString("base64");
const plaintext = "access-sandbox-test-token";

const encrypted = encryptToken(plaintext, key);

assert.equal(decryptToken(encrypted, key), plaintext);
assert.notEqual(encrypted.ciphertext, plaintext);

assert.throws(() => decryptToken(encrypted, wrongKey));
assert.throws(() => decryptToken({
  ...encrypted,
  ciphertext: Buffer.from("tampered").toString("base64"),
}, key));

console.log("Token crypto check passed.");
