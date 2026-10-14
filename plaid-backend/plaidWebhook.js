const crypto = require("node:crypto");
const { createWebhookVerificationKeys, VerificationUnavailableError, validKeyID } = require("./plaidWebhookVerificationKeys");
const { WEBHOOK_LIMITS, createWebhookVerificationWork } = require("./plaidWebhookProtection");

async function verifyPlaidWebhook({
  verificationHeader,
  rawBody,
  verificationKeys,
  verificationWork,
  now = () => new Date(),
}) {
  if (typeof verificationHeader !== "string" ||
      Buffer.byteLength(verificationHeader) > WEBHOOK_LIMITS.headerBytes ||
      !Buffer.isBuffer(rawBody) || rawBody.length === 0 || rawBody.length > WEBHOOK_LIMITS.bodyBytes) {
    return false;
  }

  try {
    const parts = verificationHeader.split(".");
    if (parts.length !== 3 || parts[2].length !== 86 ||
        !parts.every((part) => /^[A-Za-z0-9_-]+$/.test(part))) {
      return false;
    }
    const { decodeProtectedHeader, decodeJwt, jwtVerify } = await import("jose");
    const header = decodeProtectedHeader(verificationHeader);
    const payload = decodeJwt(verificationHeader);
    if (header.alg !== "ES256" || !validKeyID(header.kid) ||
        (header.typ !== undefined && header.typ !== "JWT") ||
        ["crit", "b64", "jwk", "jku", "x5u"].some((name) => header[name] !== undefined) ||
        !Number.isSafeInteger(payload.iat) || payload.iat < 0 ||
        typeof payload.request_body_sha256 !== "string" ||
        !/^[a-f0-9]{64}$/i.test(payload.request_body_sha256)) {
      return false;
    }

    const currentSeconds = Math.floor(now().getTime() / 1000);
    if (!Number.isFinite(currentSeconds) ||
        payload.iat > currentSeconds ||
        currentSeconds - payload.iat > 300) {
      return false;
    }

    // A claimed hash can reject early; it cannot establish authenticity.
    const actualHash = crypto.createHash("sha256").update(rawBody).digest();
    const expectedHash = Buffer.from(payload.request_body_sha256, "hex");
    if (!crypto.timingSafeEqual(actualHash, expectedHash)) return false;
    // Acquire before every key lookup (including shared misses and cache hits).
    // No socket event releases this lease; only this caller settling does.
    const release = verificationWork.tryAcquire();
    if (!release) throw new VerificationUnavailableError();
    try {
      const key = await verificationKeys.get(header.kid);
      const verificationTime = now();
      if (key.expiredAt !== null && key.expiredAt <= Math.floor(verificationTime.getTime() / 1000)) return false;
      const { payload: verified } = await jwtVerify(verificationHeader, key.publicKey, {
        algorithms: ["ES256"], currentDate: verificationTime, maxTokenAge: 300,
        requiredClaims: ["iat", "request_body_sha256"], clockTolerance: 0,
      });
      return crypto.timingSafeEqual(actualHash, Buffer.from(verified.request_body_sha256, "hex"))
        ? new Date(verified.iat * 1000).toISOString()
        : null;
    } finally {
      release();
    }
  } catch (error) {
    if (error instanceof VerificationUnavailableError) throw error;
    return false;
  }
}

function historicalCompletionItemID(body, environment) {
  if (!body || body.webhook_type !== "TRANSACTIONS" ||
      body.environment !== environment ||
      typeof body.item_id !== "string" ||
      !body.item_id.trim()) {
    return null;
  }

  if (body.webhook_code === "HISTORICAL_UPDATE" && body.error == null) {
    return body.item_id;
  }
  if (body.webhook_code === "SYNC_UPDATES_AVAILABLE" &&
      body.error == null &&
      body.historical_update_complete === true) {
    return body.item_id;
  }
  return null;
}

function createPlaidWebhookHandler({
  client,
  plaidItemStore,
  environment,
  logStoreError = () => {},
  now = () => new Date(),
  verificationKeys = createWebhookVerificationKeys({ client, now }),
  verificationWork = createWebhookVerificationWork(),
}) {
  return async function plaidWebhookHandler(req, res) {
    let verifiedIssuedAt;
    try {
      verifiedIssuedAt = await verifyPlaidWebhook({
        verificationHeader: req.get("Plaid-Verification"), rawBody: req.body,
        verificationKeys, verificationWork, now,
      });
    } catch {
      return res.set("Retry-After", "30").status(503).json({ error: "verification_unavailable" });
    }
    if (!verifiedIssuedAt) {
      return res.status(401).json({ error: "invalid_webhook" });
    }

    let body;
    try {
      body = JSON.parse(req.body.toString("utf8"));
    } catch {
      return res.status(400).json({ error: "invalid_webhook_body" });
    }
    const itemID = historicalCompletionItemID(body, environment);
    if (!itemID) {
      return res.sendStatus(204);
    }
    try {
      await plaidItemStore.markHistoricalReadyByItemID(
        itemID, verifiedIssuedAt
      );
      return res.sendStatus(204);
    } catch (error) {
      logStoreError("Historical readiness webhook", error);
      return res.status(503).json({ error: "readiness_unavailable" });
    }
  };
}

module.exports = {
  verifyPlaidWebhook,
  historicalCompletionItemID,
  createPlaidWebhookHandler,
};
