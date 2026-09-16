const assert = require("node:assert/strict");
const Module = require("node:module");
const {
  createAccountsHandler,
  fetchAccountSnapshot,
} = require("../accountSnapshot");
const {
  RECOVERY_CATEGORIES,
  createItemRecoveryLinkTokenHandler,
  normalizedItemOutcome,
} = require("../itemRecovery");

function item(id, institutionName = `Institution ${id}`) {
  return {
    accessToken: `access-${id}`,
    itemId: id,
    institutionName,
    institutionId: `institution-${id}`,
  };
}

function account(id) {
  return {
    account_id: id,
    name: `Account ${id}`,
    official_name: null,
    type: "depository",
    subtype: "checking",
    mask: "1234",
    balances: {
      available: 100,
      current: 100,
    },
  };
}

function plaidError(errorCode, status = 400) {
  const error = new Error("provider detail must stay private");
  error.response = {
    status,
    data: {
      error_code: errorCode,
      error_message: "sensitive provider message",
      request_id: "sensitive-request-id",
    },
  };
  return error;
}

function loadRateLimitWithStub() {
  const originalLoad = Module._load;

  Module._load = function stubbedLoad(request, parent, isMain) {
    if (request === "express-rate-limit") {
      return {
        ipKeyGenerator: (value) => value,
        rateLimit: (options) => {
          const middleware = (req, res, next) => next();
          middleware.options = options;
          return middleware;
        },
      };
    }

    return originalLoad.call(this, request, parent, isMain);
  };

  try {
    const modulePath = require.resolve("../rateLimit");
    delete require.cache[modulePath];
    return require(modulePath);
  } finally {
    Module._load = originalLoad;
  }
}

function fakeAccountsClient(resultsByToken) {
  return {
    async accountsGet({ access_token: accessToken }) {
      const result = resultsByToken[accessToken];

      if (result instanceof Error) {
        throw result;
      }

      return {
        data: {
          accounts: result,
        },
      };
    },
  };
}

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

async function testBothHealthyIsComplete() {
  const snapshot = await fetchAccountSnapshot({
    client: fakeAccountsClient({
      "access-a": [account("account-a")],
      "access-b": [account("account-b")],
    }),
    items: [item("a", "Chase"), item("b", "Amex")],
  });

  assert.equal(snapshot.accounts.length, 2);
  assert.equal(snapshot.partialFailure, false);
  assert.deepEqual(snapshot.itemErrors, []);
  assert.deepEqual(snapshot.refreshedItemIDs, ["a", "b"]);
  assert.deepEqual(snapshot.evaluatedItemIDs, ["a", "b"]);
}

async function testHealthyAndReconnectRequiredPreserveIdentity() {
  const snapshot = await fetchAccountSnapshot({
    client: fakeAccountsClient({
      "access-a": [account("account-a")],
      "access-b": plaidError("ITEM_LOGIN_REQUIRED"),
    }),
    items: [item("a", "Chase"), item("b", "Amex")],
  });

  assert.deepEqual(snapshot.accounts.map((value) => value.account_id), ["account-a"]);
  assert.equal(snapshot.partialFailure, true);
  assert.deepEqual(snapshot.itemErrors, [{
    error: "accounts_fetch_failed",
    item_id: "b",
    institution_id: "institution-b",
    institution_name: "Amex",
    recovery_category: RECOVERY_CATEGORIES.reconnectRequired,
  }]);
}

async function testRecoveryCategoryMappings() {
  assert.equal(
    normalizedItemOutcome(
      item("a"),
      plaidError("INSTITUTION_DOWN", 503),
      "accounts_fetch_failed"
    ).recovery_category,
    RECOVERY_CATEGORIES.retryable
  );
  assert.equal(
    normalizedItemOutcome(
      item("a"),
      plaidError("ADDITIONAL_CONSENT_REQUIRED"),
      "accounts_fetch_failed"
    ).recovery_category,
    RECOVERY_CATEGORIES.additionalConsentRequired
  );
  assert.equal(
    normalizedItemOutcome(
      item("a"),
      plaidError("PRODUCTS_NOT_SUPPORTED"),
      "accounts_fetch_failed"
    ).recovery_category,
    RECOVERY_CATEGORIES.capabilityUnavailable
  );
  assert.equal(
    normalizedItemOutcome(
      item("a"),
      plaidError("NEW_UNRECOGNIZED_ERROR"),
      "accounts_fetch_failed"
    ).recovery_category,
    RECOVERY_CATEGORIES.unknownFailure
  );
}

async function testResponseDoesNotExposeRawProviderPayload() {
  const outcome = normalizedItemOutcome(
    item("a", "Safe Bank"),
    plaidError("ITEM_LOGIN_REQUIRED"),
    "accounts_fetch_failed"
  );
  const serialized = JSON.stringify(outcome);

  assert.doesNotMatch(serialized, /provider detail|sensitive provider|request-id/i);
  assert.doesNotMatch(serialized, /ITEM_LOGIN_REQUIRED/);
}

async function testHandlerKeepsUserScope() {
  let requestedUserID = null;
  const handler = createAccountsHandler({
    client: fakeAccountsClient({
      "access-a": [account("account-a")],
    }),
    plaidItemStore: {
      async getUserItems(userID) {
        requestedUserID = userID;
        return [item("a")];
      },
    },
    getRequestUserID: () => "user-a",
    logStoreError: () => {},
    logPlaidError: () => {},
  });
  const response = responseRecorder();

  await handler({}, response);

  assert.equal(requestedUserID, "user-a");
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.partial_failure, false);
  assert.deepEqual(response.body.refreshed_item_ids, ["a"]);
  assert.deepEqual(response.body.evaluated_item_ids, ["a"]);
}

async function testAllFailedStillReturnsRecoveryIdentity() {
  const handler = createAccountsHandler({
    client: fakeAccountsClient({
      "access-b": plaidError("ITEM_LOGIN_REQUIRED"),
    }),
    plaidItemStore: {
      async getUserItems() {
        return [item("b", "Amex")];
      },
    },
    getRequestUserID: () => "user-a",
    logStoreError: () => {},
    logPlaidError: () => {},
  });
  const response = responseRecorder();

  await handler({}, response);

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.body.accounts, []);
  assert.equal(response.body.partial_failure, true);
  assert.equal(response.body.item_errors[0].item_id, "b");
  assert.deepEqual(response.body.refreshed_item_ids, []);
  assert.deepEqual(response.body.evaluated_item_ids, ["b"]);
}

async function accountsHandlerResponse(resultsByToken, items) {
  const handler = createAccountsHandler({
    client: fakeAccountsClient(resultsByToken),
    plaidItemStore: {
      async getUserItems() {
        return items;
      },
    },
    getRequestUserID: () => "user-a",
    logStoreError: () => {},
    logPlaidError: () => {},
  });
  const response = responseRecorder();
  await handler({}, response);
  return response;
}

async function testSystemicAccountFailuresStayNon200AndSanitized() {
  const cases = [
    plaidError("INVALID_API_KEYS", 400),
    { not_accounts: [] },
    new TypeError("private internal exception detail"),
  ];

  for (const failure of cases) {
    const response = await accountsHandlerResponse(
      { "access-a": failure },
      [item("a")]
    );
    const serialized = JSON.stringify(response.body);

    assert.equal(response.statusCode, 502);
    assert.deepEqual(response.body, {
      error: "accounts_unavailable",
      message: "Bank Sync could not refresh accounts right now.",
    });
    assert.doesNotMatch(serialized, /INVALID_API_KEYS|private internal|request_id|stack/i);
  }
}

async function testMixedHealthyAndLegitimateItemFailureStaysStructured() {
  const response = await accountsHandlerResponse(
    {
      "access-a": [account("account-a")],
      "access-b": plaidError("ITEM_LOGIN_REQUIRED"),
    },
    [item("a", "Chase"), item("b", "Amex")]
  );

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.partial_failure, true);
  assert.deepEqual(response.body.refreshed_item_ids, ["a"]);
  assert.deepEqual(response.body.evaluated_item_ids, ["a", "b"]);
  assert.equal(response.body.item_errors[0].item_id, "b");
}

function testRecoveryRouteUsesOnlyUserSpecificLimiterForTrustedRequests() {
  const { createRateLimiters } = loadRateLimitWithStub();
  const settings = {
    enabled: true,
    windowMs: 60_000,
    generalMax: 1,
    authMax: 1,
    linkTokenMax: 2,
    tokenExchangeMax: 1,
    accountsMax: 1,
    transactionsMax: 1,
    liabilitiesMax: 1,
  };
  const limiters = createRateLimiters(settings, {
    isTrustedAppRequest: (req) => req.get("x-app-api-key") === "test-app-key",
  });
  const request = {
    method: "POST",
    originalUrl: "/api/items/update-link-token?source=settings",
    ip: "127.0.0.1",
    user: { id: "user-a" },
    get(name) {
      return name === "x-app-api-key" ? "test-app-key" : undefined;
    },
  };

  assert.equal(limiters.general.options.skip(request), true);
  assert.equal(limiters.linkToken.options.keyGenerator(request), "user:user-a");
  assert.equal(
    limiters.general.options.skip({
      ...request,
      originalUrl: "/api/unrelated",
    }),
    false
  );
  assert.equal(
    limiters.general.options.skip({
      ...request,
      get: () => undefined,
    }),
    false
  );
}

async function testRecoveryLinkTargetsExactUserOwnedItem() {
  const linkRequests = [];
  const requestedUsers = [];
  const handler = createItemRecoveryLinkTokenHandler({
    client: {
      async linkTokenCreate(request) {
        linkRequests.push(request);
        return { data: { link_token: "link-token-b" } };
      },
    },
    plaidItemStore: {
      async getUserItems(userID) {
        requestedUsers.push(userID);
        return [item("a", "Chase"), item("b", "Amex")];
      },
    },
    getRequestUserID: () => "user-a",
    redirectUri: "https://example.com/plaid/oauth",
    logStoreError: () => {},
    logPlaidError: () => {},
  });
  const response = responseRecorder();

  await handler({ body: { item_id: "b" } }, response);

  assert.deepEqual(requestedUsers, ["user-a"]);
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.item_id, "b");
  assert.equal(response.body.institution_name, "Amex");
  assert.equal(linkRequests.length, 1);
  assert.equal(linkRequests[0].access_token, "access-b");
  assert.notEqual(linkRequests[0].access_token, "access-a");
  assert.equal(linkRequests[0].products, undefined);
  assert.equal(linkRequests[0].additional_consented_products, undefined);

  const missingResponse = responseRecorder();
  await handler({ body: { item_id: "other-user-item" } }, missingResponse);
  assert.equal(missingResponse.statusCode, 404);
  assert.equal(linkRequests.length, 1);
}

async function run() {
  await testBothHealthyIsComplete();
  await testHealthyAndReconnectRequiredPreserveIdentity();
  await testRecoveryCategoryMappings();
  await testResponseDoesNotExposeRawProviderPayload();
  await testHandlerKeepsUserScope();
  await testAllFailedStillReturnsRecoveryIdentity();
  await testSystemicAccountFailuresStayNon200AndSanitized();
  await testMixedHealthyAndLegitimateItemFailureStaysStructured();
  await testRecoveryLinkTargetsExactUserOwnedItem();
  testRecoveryRouteUsesOnlyUserSpecificLimiterForTrustedRequests();

  console.log("Bank Sync Item recovery checks passed.");
}

run().catch((error) => {
  console.error(`Bank Sync Item recovery checks failed: ${error.stack || error.message}`);
  process.exit(1);
});
