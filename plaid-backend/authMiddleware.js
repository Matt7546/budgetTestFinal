function extractBearerToken(req) {
  const header = req.get?.("authorization") || req.headers?.authorization;

  if (!header || typeof header !== "string") {
    return null;
  }

  const match = header.match(/^Bearer\s+(.+)$/i);

  return match ? match[1].trim() : null;
}

function unauthorized(res, message = "Authentication required.") {
  return res.status(401).json({
    error: "unauthorized",
    message,
  });
}

function requestUserIDForMode({ authMode, req, personalUserID }) {
  if (authMode === "personal") {
    return personalUserID;
  }

  if (authMode === "optional") {
    return req.user?.id || personalUserID;
  }

  if (req.user?.id) {
    return req.user.id;
  }

  throw new Error("Authenticated user is required.");
}

function createAuthMiddleware({
  authMode,
  personalUserID,
  sessionStore,
  developmentAuth = null,
}) {
  async function attachUserFromBearer(req, res, next, { required }) {
    const token = extractBearerToken(req);

    if (!token) {
      if (required) {
        return unauthorized(res);
      }

      return next();
    }

    try {
      const developmentSession = await developmentAuth?.getSessionByToken?.(token);

      if (developmentSession?.user?.id) {
        req.user = developmentSession.user;
        req.session = developmentSession.session;
        req.sessionToken = token;
        req.isDevelopmentSession = true;
        return next();
      }

      if (!sessionStore) {
        if (developmentAuth?.isEnabled?.()) {
          return unauthorized(res, "Invalid or expired development session.");
        }

        return res.status(503).json({
          error: "auth_not_configured",
          message: "Authentication is not configured.",
        });
      }

      const result = await sessionStore.getSessionByToken(token);

      if (!result?.user?.id) {
        return unauthorized(res, "Invalid or expired session.");
      }

      req.user = result.user;
      req.session = result.session;
      req.sessionToken = token;
      return next();
    } catch {
      return res.status(500).json({
        error: "auth_failed",
        message: "Authentication failed.",
      });
    }
  }

  function resolvePlaidAuth(req, res, next) {
    if (authMode === "personal") {
      return next();
    }

    return attachUserFromBearer(req, res, next, {
      required: authMode === "required",
    });
  }

  function requireSessionAuth(req, res, next) {
    return attachUserFromBearer(req, res, next, {
      required: true,
    });
  }

  function getRequestUserID(req) {
    return requestUserIDForMode({
      authMode,
      req,
      personalUserID,
    });
  }

  return {
    getRequestUserID,
    requireSessionAuth,
    resolvePlaidAuth,
  };
}

module.exports = {
  createAuthMiddleware,
  extractBearerToken,
  requestUserIDForMode,
};
