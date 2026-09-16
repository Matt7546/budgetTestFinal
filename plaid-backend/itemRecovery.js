const { stableLegacyItemID } = require("./plaidItemUtils");

const RECOVERY_CATEGORIES = Object.freeze({
  retryable: "retryable",
  reconnectRequired: "reconnectRequired",
  additionalConsentRequired: "additionalConsentRequired",
  capabilityUnavailable: "capabilityUnavailable",
  unknownFailure: "unknownFailure",
});

const retryableErrorCodes = new Set([
  "INSTITUTION_DOWN",
  "INSTITUTION_NOT_RESPONDING",
  "INTERNAL_SERVER_ERROR",
  "PRODUCT_NOT_READY",
  "RATE_LIMIT_EXCEEDED",
]);

const capabilityErrorCodes = new Set([
  "INSTITUTION_NOT_SUPPORTED",
  "PRODUCTS_NOT_SUPPORTED",
  "PRODUCT_NOT_SUPPORTED",
]);

const itemScopedErrorTypes = new Set([
  "INSTITUTION_ERROR",
  "ITEM_ERROR",
]);

const itemScopedErrorCodes = new Set([
  "ADDITIONAL_CONSENT_REQUIRED",
  "INSTITUTION_DOWN",
  "INSTITUTION_NOT_RESPONDING",
  "INSTITUTION_NOT_SUPPORTED",
  "ITEM_LOGIN_REQUIRED",
  "PRODUCT_NOT_READY",
  "PRODUCT_NOT_SUPPORTED",
  "PRODUCTS_NOT_SUPPORTED",
]);

const systemicErrorCodes = new Set([
  "INTERNAL_SERVER_ERROR",
  "INVALID_ACCESS_TOKEN",
  "INVALID_API_KEYS",
  "INVALID_CLIENT_ID",
  "INVALID_SECRET",
  "RATE_LIMIT_EXCEEDED",
]);

const retryableNetworkCodes = new Set([
  "ECONNABORTED",
  "ECONNRESET",
  "ENETDOWN",
  "ENETUNREACH",
  "ENOTFOUND",
  "ETIMEDOUT",
]);

function stringOrNull(value) {
  if (typeof value !== "string") {
    return null;
  }

  const trimmedValue = value.trim();
  return trimmedValue.length > 0 ? trimmedValue : null;
}

function plaidErrorCode(error) {
  return stringOrNull(error?.response?.data?.error_code) ||
    stringOrNull(error?.code) ||
    "unknown";
}

function plaidErrorType(error) {
  return stringOrNull(error?.response?.data?.error_type) ||
    stringOrNull(error?.error_type) ||
    "unknown";
}

function isItemScopedPlaidError(error) {
  const errorCode = plaidErrorCode(error);
  const responseStatus = error?.response?.status;

  if (systemicErrorCodes.has(errorCode) ||
      retryableNetworkCodes.has(errorCode) ||
      responseStatus === 429) {
    return false;
  }

  if (itemScopedErrorCodes.has(errorCode)) {
    return true;
  }

  if (responseStatus >= 500) {
    return false;
  }

  return itemScopedErrorTypes.has(plaidErrorType(error));
}

function recoveryCategoryForPlaidError(error) {
  const errorCode = plaidErrorCode(error);

  if (errorCode === "ITEM_LOGIN_REQUIRED") {
    return RECOVERY_CATEGORIES.reconnectRequired;
  }

  if (errorCode === "ADDITIONAL_CONSENT_REQUIRED") {
    return RECOVERY_CATEGORIES.additionalConsentRequired;
  }

  if (capabilityErrorCodes.has(errorCode)) {
    return RECOVERY_CATEGORIES.capabilityUnavailable;
  }

  const responseStatus = error?.response?.status;

  if (retryableErrorCodes.has(errorCode) ||
      retryableNetworkCodes.has(errorCode) ||
      responseStatus === 429 ||
      responseStatus >= 500) {
    return RECOVERY_CATEGORIES.retryable;
  }

  return RECOVERY_CATEGORIES.unknownFailure;
}

function normalizedItemOutcome(item, error, failureCode) {
  return {
    error: failureCode,
    item_id: stableLegacyItemID(item),
    institution_id: stringOrNull(item?.institutionId),
    institution_name: stringOrNull(item?.institutionName),
    recovery_category: recoveryCategoryForPlaidError(error),
  };
}

function createItemRecoveryLinkTokenHandler({
  client,
  plaidItemStore,
  getRequestUserID,
  redirectUri = null,
  logStoreError,
  logPlaidError,
}) {
  return async function itemRecoveryLinkTokenHandler(req, res) {
    const itemID = stringOrNull(req.body?.item_id);

    if (!itemID) {
      return res.status(400).json({
        error: "invalid_item_recovery_request",
        message: "A linked bank connection is required.",
        mode: "item_recovery",
      });
    }

    const userID = getRequestUserID(req);
    let items;

    try {
      items = await plaidItemStore.getUserItems(userID);
    } catch (error) {
      logStoreError("Item Recovery Item Store Error", error);

      return res.status(500).json({
        error: "item_recovery_unavailable",
        message: "This bank connection could not be opened for recovery.",
        mode: "item_recovery",
      });
    }

    const item = items.find(
      (storedItem) => stableLegacyItemID(storedItem) === itemID
    );

    if (!item) {
      return res.status(404).json({
        error: "item_not_found",
        message: "This linked bank connection could not be found.",
        mode: "item_recovery",
        item_id: itemID,
      });
    }

    try {
      const linkTokenRequest = {
        user: {
          client_user_id: userID,
        },
        client_name: "Caldera",
        access_token: item.accessToken,
        country_codes: ["US"],
        language: "en",
      };

      if (redirectUri) {
        linkTokenRequest.redirect_uri = redirectUri;
      }

      const response = await client.linkTokenCreate(linkTokenRequest);

      return res.json({
        link_token: response.data.link_token,
        mode: "item_recovery",
        item_id: itemID,
        institution_id: stringOrNull(item.institutionId),
        institution_name: stringOrNull(item.institutionName),
      });
    } catch (error) {
      logPlaidError("Item Recovery Link Token Error", error);

      return res.status(502).json({
        error: "item_recovery_unavailable",
        message: "This bank connection could not be opened for recovery.",
        mode: "item_recovery",
        item_id: itemID,
      });
    }
  };
}

module.exports = {
  RECOVERY_CATEGORIES,
  createItemRecoveryLinkTokenHandler,
  isItemScopedPlaidError,
  normalizedItemOutcome,
  plaidErrorCode,
  recoveryCategoryForPlaidError,
};
