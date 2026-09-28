const crypto = require("node:crypto");

function decodePart(part) {
  if (!/^[A-Za-z0-9_-]+$/.test(part)) {
    throw new Error("Invalid webhook signature encoding.");
  }
  return Buffer.from(part, "base64url");
}

async function verifyPlaidWebhook({
  verificationHeader,
  rawBody,
  client,
  now = () => new Date(),
}) {
  if (typeof verificationHeader !== "string" ||
      !Buffer.isBuffer(rawBody) || rawBody.length === 0) {
    return false;
  }

  try {
    const parts = verificationHeader.split(".");
    if (parts.length !== 3) {
      return false;
    }
    const header = JSON.parse(decodePart(parts[0]).toString("utf8"));
    const payload = JSON.parse(decodePart(parts[1]).toString("utf8"));
    const signature = decodePart(parts[2]);
    if (header.alg !== "ES256" || typeof header.kid !== "string" ||
        !header.kid || signature.length !== 64 ||
        !Number.isInteger(payload.iat) ||
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

    const response = await client.webhookVerificationKeyGet({
      key_id: header.kid,
    });
    const key = response?.data?.key;
    if (key?.kid !== header.kid || key?.alg !== "ES256" ||
        key?.kty !== "EC" || key?.crv !== "P-256" ||
        key?.use !== "sig" ||
        (key.expired_at != null && key.expired_at <= currentSeconds)) {
      return false;
    }

    const publicKey = crypto.createPublicKey({ key, format: "jwk" });
    const signatureValid = crypto.verify(
      "sha256",
      Buffer.from(`${parts[0]}.${parts[1]}`),
      { key: publicKey, dsaEncoding: "ieee-p1363" },
      signature
    );
    if (!signatureValid) {
      return false;
    }

    const actualHash = crypto.createHash("sha256").update(rawBody).digest();
    const expectedHash = Buffer.from(payload.request_body_sha256, "hex");
    return crypto.timingSafeEqual(actualHash, expectedHash)
      ? new Date(payload.iat * 1000).toISOString()
      : null;
  } catch {
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
}) {
  return async function plaidWebhookHandler(req, res) {
    const verifiedIssuedAt = await verifyPlaidWebhook({
      verificationHeader: req.get("Plaid-Verification"),
      rawBody: req.body,
      client,
      now,
    });
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
