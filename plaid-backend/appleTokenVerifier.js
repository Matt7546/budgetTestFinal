const crypto = require("crypto");

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
const JWKS_CACHE_MS = 60 * 60 * 1000;

let cachedJWKS = null;
let cachedJWKSExpiresAt = 0;

function base64UrlDecode(input) {
  if (!input || typeof input !== "string") {
    throw new Error("Invalid base64url value.");
  }

  return Buffer.from(input, "base64url");
}

function parseJSONSegment(segment) {
  return JSON.parse(base64UrlDecode(segment).toString("utf8"));
}

function parseAppleIdentityToken(identityToken) {
  if (!identityToken || typeof identityToken !== "string") {
    throw new Error("identity_token is required.");
  }

  const parts = identityToken.split(".");

  if (parts.length !== 3) {
    throw new Error("identity_token must be a JWT.");
  }

  return {
    header: parseJSONSegment(parts[0]),
    payload: parseJSONSegment(parts[1]),
    signingInput: `${parts[0]}.${parts[1]}`,
    signature: base64UrlDecode(parts[2]),
  };
}

async function fetchAppleJWKS(fetchImpl = global.fetch) {
  if (!fetchImpl) {
    throw new Error("Fetch API is required to verify Apple identity tokens.");
  }

  const now = Date.now();

  if (cachedJWKS && cachedJWKSExpiresAt > now) {
    return cachedJWKS;
  }

  const response = await fetchImpl(APPLE_JWKS_URL);

  if (!response.ok) {
    throw new Error("Unable to fetch Apple public keys.");
  }

  const jwks = await response.json();

  if (!Array.isArray(jwks.keys)) {
    throw new Error("Apple public key response is invalid.");
  }

  cachedJWKS = jwks;
  cachedJWKSExpiresAt = now + JWKS_CACHE_MS;

  return jwks;
}

function verifyAudience(audience, appleClientId) {
  if (Array.isArray(audience)) {
    return audience.includes(appleClientId);
  }

  return audience === appleClientId;
}

function verifySignature({ header, signingInput, signature }, jwks) {
  if (header.alg !== "RS256") {
    throw new Error("Unsupported Apple identity token algorithm.");
  }

  if (!header.kid) {
    throw new Error("Apple identity token key id is missing.");
  }

  const jwk = jwks.keys.find((key) => key.kid === header.kid);

  if (!jwk) {
    throw new Error("Apple public key not found for identity token.");
  }

  const publicKey = crypto.createPublicKey({
    key: jwk,
    format: "jwk",
  });

  const isValid = crypto.verify(
    "RSA-SHA256",
    Buffer.from(signingInput, "utf8"),
    publicKey,
    signature
  );

  if (!isValid) {
    throw new Error("Apple identity token signature is invalid.");
  }
}

async function verifyAppleIdentityToken(identityToken, {
  appleClientId = process.env.APPLE_CLIENT_ID,
  nonce = null,
  fetchImpl = global.fetch,
  now = Math.floor(Date.now() / 1000),
} = {}) {
  if (!appleClientId) {
    throw new Error("APPLE_CLIENT_ID is required for Apple authentication.");
  }

  const parsedToken = parseAppleIdentityToken(identityToken);
  const jwks = await fetchAppleJWKS(fetchImpl);

  verifySignature(parsedToken, jwks);

  const { payload } = parsedToken;

  if (payload.iss !== APPLE_ISSUER) {
    throw new Error("Apple identity token issuer is invalid.");
  }

  if (!verifyAudience(payload.aud, appleClientId)) {
    throw new Error("Apple identity token audience is invalid.");
  }

  if (!payload.exp || Number(payload.exp) <= now) {
    throw new Error("Apple identity token is expired.");
  }

  if (nonce && payload.nonce !== nonce) {
    throw new Error("Apple identity token nonce is invalid.");
  }

  if (!payload.sub) {
    throw new Error("Apple identity token subject is missing.");
  }

  return {
    appleSub: payload.sub,
    email: payload.email || null,
    emailVerified: payload.email_verified,
    isPrivateEmail: payload.is_private_email,
  };
}

module.exports = {
  parseAppleIdentityToken,
  verifyAppleIdentityToken,
};
