const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { resolveAuthMode, personalUserID, sessionTTLDays } = require("../authConfig");
const { createAuthMiddleware, requestUserIDForMode } = require("../authMiddleware");
const { generateSessionToken, hashSessionToken } = require("../sessionCrypto");
const {
  parseAppleIdentityToken,
  verifyAppleIdentityToken,
} = require("../appleTokenVerifier");

function fakeResponse() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

async function runMiddleware(middleware, req) {
  const res = fakeResponse();
  let nextCalled = false;

  await middleware(req, res, () => {
    nextCalled = true;
  });

  return {
    res,
    nextCalled,
  };
}


function createSignedAppleTestToken({ privateKey, kid, payload }) {
  const headerSegment = Buffer.from(JSON.stringify({
    alg: "RS256",
    kid,
  })).toString("base64url");
  const payloadSegment = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signingInput = `${headerSegment}.${payloadSegment}`;
  const signature = crypto
    .sign("RSA-SHA256", Buffer.from(signingInput, "utf8"), privateKey)
    .toString("base64url");

  return `${signingInput}.${signature}`;
}

async function run() {
  assert.strictEqual(resolveAuthMode({}), "personal");
  assert.strictEqual(resolveAuthMode({ AUTH_MODE: "optional" }), "optional");
  assert.strictEqual(resolveAuthMode({ AUTH_MODE: "required" }), "required");
  assert.throws(() => resolveAuthMode({ AUTH_MODE: "public" }), /AUTH_MODE/);
  assert.strictEqual(personalUserID({}), "personal");
  assert.strictEqual(personalUserID({ PLAID_PERSONAL_USER_KEY: "owner" }), "owner");
  assert.strictEqual(sessionTTLDays({ SESSION_TTL_DAYS: "7" }), 7);
  assert.throws(() => sessionTTLDays({ SESSION_TTL_DAYS: "0" }), /SESSION_TTL_DAYS/);

  assert.strictEqual(
    requestUserIDForMode({
      authMode: "personal",
      req: { user: { id: "user_a" } },
      personalUserID: "personal",
    }),
    "personal"
  );
  assert.strictEqual(
    requestUserIDForMode({
      authMode: "optional",
      req: { user: { id: "user_a" } },
      personalUserID: "personal",
    }),
    "user_a"
  );
  assert.strictEqual(
    requestUserIDForMode({
      authMode: "optional",
      req: {},
      personalUserID: "personal",
    }),
    "personal"
  );
  assert.throws(
    () => requestUserIDForMode({ authMode: "required", req: {}, personalUserID: "personal" }),
    /Authenticated user/
  );

  const sessionToken = generateSessionToken();
  const sessionHash = hashSessionToken(sessionToken);
  assert.notStrictEqual(sessionHash, sessionToken);
  assert.strictEqual(sessionHash, hashSessionToken(sessionToken));
  assert.throws(() => hashSessionToken(""), /Session token/);

  const fakeSessionStore = {
    async getSessionByToken(token) {
      if (token === "valid") {
        return {
          user: { id: "user_valid", email: null, full_name: null },
          session: { id: "session_valid", user_id: "user_valid" },
        };
      }

      return null;
    },
  };

  const optionalAuth = createAuthMiddleware({
    authMode: "optional",
    personalUserID: "personal",
    sessionStore: fakeSessionStore,
  });

  let result = await runMiddleware(optionalAuth.resolvePlaidAuth, { headers: {} });
  assert.strictEqual(result.nextCalled, true);
  assert.strictEqual(result.res.statusCode, 200);

  result = await runMiddleware(optionalAuth.resolvePlaidAuth, {
    headers: { authorization: "Bearer valid" },
  });
  assert.strictEqual(result.nextCalled, true);
  assert.strictEqual(result.res.statusCode, 200);

  result = await runMiddleware(optionalAuth.resolvePlaidAuth, {
    headers: { authorization: "Bearer revoked" },
  });
  assert.strictEqual(result.nextCalled, false);
  assert.strictEqual(result.res.statusCode, 401);

  const requiredAuth = createAuthMiddleware({
    authMode: "required",
    personalUserID: "personal",
    sessionStore: fakeSessionStore,
  });

  result = await runMiddleware(requiredAuth.resolvePlaidAuth, { headers: {} });
  assert.strictEqual(result.nextCalled, false);
  assert.strictEqual(result.res.statusCode, 401);

  result = await runMiddleware(requiredAuth.resolvePlaidAuth, {
    headers: { authorization: "Bearer expired" },
  });
  assert.strictEqual(result.nextCalled, false);
  assert.strictEqual(result.res.statusCode, 401);

  result = await runMiddleware(requiredAuth.resolvePlaidAuth, {
    headers: { authorization: "Bearer valid" },
  });
  assert.strictEqual(result.nextCalled, true);
  assert.strictEqual(result.res.statusCode, 200);
  assert.strictEqual(result.nextCalled && result.res.statusCode, 200);

  const schema = fs.readFileSync(
    path.join(__dirname, "..", "migrations", "002_create_auth_tables.sql"),
    "utf8"
  );
  assert.match(schema, /CREATE TABLE IF NOT EXISTS user_sessions/);
  assert.match(schema, /ADD COLUMN IF NOT EXISTS apple_sub/);
  assert.match(schema, /CREATE INDEX IF NOT EXISTS/);

  const unsignedToken = [
    Buffer.from(JSON.stringify({ alg: "RS256", kid: "test" })).toString("base64url"),
    Buffer.from(JSON.stringify({ sub: "apple-sub" })).toString("base64url"),
    Buffer.from("signature").toString("base64url"),
  ].join(".");
  assert.strictEqual(parseAppleIdentityToken(unsignedToken).payload.sub, "apple-sub");
  assert.throws(() => parseAppleIdentityToken("not-a-jwt"), /JWT/);

  const { publicKey, privateKey } = crypto.generateKeyPairSync("rsa", {
    modulusLength: 2048,
  });
  const jwk = publicKey.export({ format: "jwk" });
  jwk.kid = "caldera-test-key";
  jwk.alg = "RS256";
  jwk.use = "sig";

  const now = Math.floor(Date.now() / 1000);
  const signedToken = createSignedAppleTestToken({
    privateKey,
    kid: jwk.kid,
    payload: {
      iss: "https://appleid.apple.com",
      aud: "com.matthewthomas.caldera",
      exp: now + 300,
      sub: "apple-user-sub",
      email: "tester@example.com",
      nonce: "nonce-value",
    },
  });
  const fakeFetch = async () => ({
    ok: true,
    json: async () => ({ keys: [jwk] }),
  });
  const verifiedIdentity = await verifyAppleIdentityToken(signedToken, {
    appleClientId: "com.matthewthomas.caldera",
    nonce: "nonce-value",
    fetchImpl: fakeFetch,
    now,
  });
  assert.strictEqual(verifiedIdentity.appleSub, "apple-user-sub");
  assert.strictEqual(verifiedIdentity.email, "tester@example.com");
  await assert.rejects(
    () => verifyAppleIdentityToken(signedToken, {
      appleClientId: "com.matthewthomas.caldera",
      nonce: "wrong-nonce",
      fetchImpl: fakeFetch,
      now,
    }),
    /nonce/
  );

  console.log("Auth scaffolding check passed.");
}

run().catch((error) => {
  console.error(`Auth scaffolding check failed: ${error.message}`);
  process.exit(1);
});
