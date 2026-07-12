const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  createTransactionsHandler,
  fetchTransactionSnapshot,
} = require("../transactionSnapshot");
const {
  DEFAULT_TRANSACTIONS_LOOKBACK_DAYS,
  MAX_TRANSACTIONS_LOOKBACK_DAYS,
  MIN_TRANSACTIONS_LOOKBACK_DAYS,
  TRANSACTIONS_LINK_DAYS_REQUESTED,
  resolveTransactionsLookbackDays,
  transactionsLinkInitialization,
} = require("../transactionConfiguration");

function item(id) {
  return {
    accessToken: `access-${id}`,
    itemId: id,
    institutionName: `Institution ${id}`,
    institutionId: `institution-${id}`,
  };
}

function transaction(id, accountID = "account-1") {
  return {
    transaction_id: id,
    account_id: accountID,
    name: `Transaction ${id}`,
    amount: 10,
    date: "2026-07-01",
    pending: false,
  };
}

function account(id) {
  return {
    account_id: id,
    name: `Account ${id}`,
  };
}

function fakeClient(pagesByToken) {
  const calls = [];

  return {
    calls,
    async transactionsGet(request) {
      calls.push(request);
      const tokenPages = pagesByToken[request.access_token];
      const page = tokenPages?.[request.options.offset];

      if (page instanceof Error) {
        throw page;
      }

      if (!page) {
        throw new Error(
          `Unexpected page request token=${request.access_token} offset=${request.options.offset}`
        );
      }

      return {
        data: page,
      };
    },
  };
}

function page(transactions, totalTransactions, accounts = []) {
  return {
    transactions,
    total_transactions: totalTransactions,
    accounts,
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

function handlerFor({
  client,
  items,
  transactionsEnabled = true,
  lookbackDays = DEFAULT_TRANSACTIONS_LOOKBACK_DAYS,
  userID = "user-1",
  onUserID = () => {},
  onPlaidError = () => {},
}) {
  return createTransactionsHandler({
    client,
    plaidItemStore: {
      async getUserItems(requestedUserID) {
        onUserID(requestedUserID);
        return items;
      },
    },
    getRequestUserID: () => userID,
    transactionsEnabled,
    lookbackDays,
    capabilitiesResponse: () => ({
      accounts_enabled: true,
      transactions_enabled: transactionsEnabled,
      liabilities_enabled: false,
      liabilities_link_enabled: false,
    }),
    logStoreError: () => {},
    logPlaidError: onPlaidError,
    now: () => new Date("2026-07-12T12:00:00.000Z"),
    pageSize: 2,
  });
}

async function testOneItemMultiplePages() {
  const client = fakeClient({
    "access-item-1": {
      0: page(
        [transaction("transaction-1"), transaction("transaction-2")],
        3,
        [account("account-1")]
      ),
      2: page(
        [transaction("transaction-3")],
        3,
        [account("account-1")]
      ),
    },
  });
  const snapshot = await fetchTransactionSnapshot({
    client,
    items: [item("item-1")],
    startDate: "2026-06-12",
    endDate: "2026-07-12",
    pageSize: 2,
  });

  assert.deepEqual(
    client.calls.map((call) => call.options),
    [
      { count: 2, offset: 0 },
      { count: 2, offset: 2 },
    ]
  );
  assert.equal(snapshot.totalTransactions, 3);
  assert.equal(snapshot.returnedTransactions, 3);
  assert.equal(snapshot.complete, true);
  assert.equal(snapshot.partialFailure, false);
  assert.equal(snapshot.transactions[0].item_id, "item-1");
  assert.equal(snapshot.accounts.length, 1);
}

async function testMultipleItemsMultiplePages() {
  const client = fakeClient({
    "access-item-1": {
      0: page([transaction("transaction-1")], 2),
      1: page([transaction("transaction-2")], 2),
    },
    "access-item-2": {
      0: page([transaction("transaction-3", "account-2")], 2),
      1: page([transaction("transaction-4", "account-2")], 2),
    },
  });
  const snapshot = await fetchTransactionSnapshot({
    client,
    items: [item("item-1"), item("item-2")],
    startDate: "2026-06-12",
    endDate: "2026-07-12",
    pageSize: 1,
  });

  assert.equal(snapshot.successfulItems, 2);
  assert.equal(snapshot.totalTransactions, 4);
  assert.equal(snapshot.returnedTransactions, 4);
  assert.equal(snapshot.complete, true);
  assert.deepEqual(
    snapshot.transactions.map((value) => value.item_id),
    ["item-1", "item-1", "item-2", "item-2"]
  );
}

async function testZeroTransactions() {
  const client = fakeClient({
    "access-item-1": {
      0: page([], 0, [account("account-1")]),
    },
  });
  const snapshot = await fetchTransactionSnapshot({
    client,
    items: [item("item-1")],
    startDate: "2026-06-12",
    endDate: "2026-07-12",
  });

  assert.equal(client.calls.length, 1);
  assert.equal(snapshot.totalTransactions, 0);
  assert.equal(snapshot.returnedTransactions, 0);
  assert.equal(snapshot.complete, true);
  assert.equal(snapshot.accounts.length, 1);
}

async function testDuplicateTransactionIDsAcrossPages() {
  const client = fakeClient({
    "access-item-1": {
      0: page(
        [transaction("transaction-1"), transaction("transaction-2")],
        3
      ),
      2: page([transaction("transaction-2")], 3),
    },
  });
  const snapshot = await fetchTransactionSnapshot({
    client,
    items: [item("item-1")],
    startDate: "2026-06-12",
    endDate: "2026-07-12",
    pageSize: 2,
  });

  assert.equal(snapshot.totalTransactions, 3);
  assert.equal(snapshot.returnedTransactions, 2);
  assert.equal(snapshot.complete, true);
  assert.deepEqual(
    snapshot.transactions.map((value) => value.transaction_id),
    ["transaction-1", "transaction-2"]
  );
}

async function testLaterPageFailureDiscardsIncompleteItem() {
  const laterPageError = new Error("later page failed");
  const errors = [];
  const client = fakeClient({
    "access-item-1": {
      0: page(
        [transaction("transaction-1"), transaction("transaction-2")],
        3
      ),
      2: laterPageError,
    },
  });
  const snapshot = await fetchTransactionSnapshot({
    client,
    items: [item("item-1")],
    startDate: "2026-06-12",
    endDate: "2026-07-12",
    pageSize: 2,
    onItemError: (error) => errors.push(error),
  });

  assert.equal(snapshot.successfulItems, 0);
  assert.equal(snapshot.transactions.length, 0);
  assert.equal(snapshot.totalTransactions, null);
  assert.equal(snapshot.returnedTransactions, 0);
  assert.equal(snapshot.complete, false);
  assert.equal(snapshot.partialFailure, true);
  assert.deepEqual(snapshot.itemErrors, [
    { error: "transactions_fetch_failed" },
  ]);
  assert.deepEqual(errors, [laterPageError]);
}

async function testOneItemSucceedsWhileAnotherFails() {
  const client = fakeClient({
    "access-item-1": {
      0: page([transaction("transaction-1")], 1),
    },
    "access-item-2": {
      0: new Error("item failed"),
    },
  });
  const snapshot = await fetchTransactionSnapshot({
    client,
    items: [item("item-1"), item("item-2")],
    startDate: "2026-06-12",
    endDate: "2026-07-12",
  });

  assert.equal(snapshot.successfulItems, 1);
  assert.equal(snapshot.totalTransactions, null);
  assert.equal(snapshot.returnedTransactions, 1);
  assert.equal(snapshot.complete, false);
  assert.equal(snapshot.partialFailure, true);
  assert.equal(snapshot.transactions[0].item_id, "item-1");
}

async function testHandlerMetadataAndUserScope() {
  const client = fakeClient({
    "access-item-1": {
      0: page(
        [transaction("transaction-1"), transaction("transaction-2")],
        3
      ),
      2: page([transaction("transaction-3")], 3),
    },
  });
  let requestedUserID = null;
  const handler = handlerFor({
    client,
    items: [item("item-1")],
    userID: "user-scoped",
    onUserID: (value) => {
      requestedUserID = value;
    },
  });
  const res = responseRecorder();

  await handler({}, res);

  assert.equal(requestedUserID, "user-scoped");
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.window_start, "2026-04-13");
  assert.equal(res.body.window_end, "2026-07-12");
  assert.equal(
    res.body.lookback_days,
    DEFAULT_TRANSACTIONS_LOOKBACK_DAYS
  );
  assert.equal(res.body.total_transactions, 3);
  assert.equal(res.body.returned_transactions, 3);
  assert.equal(res.body.complete, true);
  assert.equal(res.body.partial_failure, false);
}

async function testHandlerReportsExplicitLookbackOverride() {
  const client = fakeClient({
    "access-item-1": {
      0: page([transaction("transaction-1")], 1),
    },
  });
  const handler = handlerFor({
    client,
    items: [item("item-1")],
    lookbackDays: 45,
  });
  const res = responseRecorder();

  await handler({}, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.window_start, "2026-05-28");
  assert.equal(res.body.window_end, "2026-07-12");
  assert.equal(res.body.lookback_days, 45);
}

async function testHandlerPartialAndFailedResponsesAreTruthful() {
  const partialClient = fakeClient({
    "access-item-1": {
      0: page([transaction("transaction-1")], 1),
    },
    "access-item-2": {
      0: new Error("item failed"),
    },
  });
  const partialHandler = handlerFor({
    client: partialClient,
    items: [item("item-1"), item("item-2")],
  });
  const partialResponse = responseRecorder();

  await partialHandler({}, partialResponse);

  assert.equal(partialResponse.statusCode, 200);
  assert.equal(partialResponse.body.total_transactions, null);
  assert.equal(partialResponse.body.returned_transactions, 1);
  assert.equal(partialResponse.body.complete, false);
  assert.equal(partialResponse.body.partial_failure, true);

  const failedClient = fakeClient({
    "access-item-1": {
      0: page(
        [transaction("transaction-1"), transaction("transaction-2")],
        3
      ),
      2: new Error("later page failed"),
    },
  });
  const failedHandler = handlerFor({
    client: failedClient,
    items: [item("item-1")],
  });
  const failedResponse = responseRecorder();

  await failedHandler({}, failedResponse);

  assert.equal(failedResponse.statusCode, 500);
  assert.equal(failedResponse.body.total_transactions, null);
  assert.equal(failedResponse.body.returned_transactions, 0);
  assert.equal(failedResponse.body.complete, false);
  assert.equal(failedResponse.body.partial_failure, true);
}

async function testDisabledBehaviorIsUnchanged() {
  let storeCalled = false;
  const handler = createTransactionsHandler({
    client: {
      async transactionsGet() {
        throw new Error("Plaid should not be called while disabled.");
      },
    },
    plaidItemStore: {
      async getUserItems() {
        storeCalled = true;
        return [];
      },
    },
    getRequestUserID: () => "user-1",
    transactionsEnabled: false,
    lookbackDays: DEFAULT_TRANSACTIONS_LOOKBACK_DAYS,
    capabilitiesResponse: () => ({
      accounts_enabled: true,
      transactions_enabled: false,
      liabilities_enabled: false,
      liabilities_link_enabled: false,
    }),
    logStoreError: () => {},
    logPlaidError: () => {},
  });
  const res = responseRecorder();

  await handler({}, res);

  assert.equal(storeCalled, false);
  assert.equal(res.statusCode, 409);
  assert.deepEqual(res.body, {
    error: "transactions_disabled",
    message: "Transactions are disabled for this backend.",
    transactions: [],
    accounts: [],
    partial_failure: false,
    accounts_enabled: true,
    transactions_enabled: false,
    liabilities_enabled: false,
    liabilities_link_enabled: false,
  });
}

function testTransactionHistoryConfiguration() {
  const warnings = [];
  const warn = (message) => warnings.push(message);

  assert.equal(
    resolveTransactionsLookbackDays(undefined, warn),
    DEFAULT_TRANSACTIONS_LOOKBACK_DAYS
  );
  assert.equal(resolveTransactionsLookbackDays("120", warn), 120);
  assert.equal(
    resolveTransactionsLookbackDays("29", warn),
    MIN_TRANSACTIONS_LOOKBACK_DAYS
  );
  assert.equal(
    resolveTransactionsLookbackDays("731", warn),
    MAX_TRANSACTIONS_LOOKBACK_DAYS
  );
  assert.equal(
    resolveTransactionsLookbackDays("not-a-number", warn),
    DEFAULT_TRANSACTIONS_LOOKBACK_DAYS
  );
  assert.equal(warnings.length, 3);
}

function testTransactionsLinkInitializationIsScoped() {
  assert.deepEqual(
    transactionsLinkInitialization(true),
    {
      products: ["transactions"],
      transactions: {
        days_requested: TRANSACTIONS_LINK_DAYS_REQUESTED,
      },
    }
  );
  assert.equal(TRANSACTIONS_LINK_DAYS_REQUESTED, 90);
  assert.deepEqual(
    transactionsLinkInitialization(false),
    {
      products: [],
    }
  );

  const indexSource = fs.readFileSync(
    path.join(__dirname, "..", "index.js"),
    "utf8"
  );
  const normalRouteStart = indexSource.indexOf(
    'app.post("/api/create_link_token"'
  );
  const normalRouteEnd = indexSource.indexOf(
    "// Exchange Public Token",
    normalRouteStart
  );
  const normalRouteSource = indexSource.slice(
    normalRouteStart,
    normalRouteEnd
  );
  const updateRouteStart = indexSource.indexOf(
    'app.post("/api/card-payment-details/update-link-token"'
  );
  const updateRouteEnd = indexSource.indexOf(
    "// Get Card Payment Details",
    updateRouteStart
  );
  const updateRouteSource = indexSource.slice(
    updateRouteStart,
    updateRouteEnd
  );

  assert.ok(normalRouteStart >= 0);
  assert.ok(normalRouteEnd > normalRouteStart);
  assert.match(
    normalRouteSource,
    /transactionsLinkInitialization\(\s*plaidTransactionsEnabled\s*\)/
  );
  assert.match(
    normalRouteSource,
    /linkTokenRequest\.transactions\s*=\s*transactionInitialization\.transactions/
  );
  assert.ok(updateRouteStart >= 0);
  assert.ok(updateRouteEnd > updateRouteStart);
  assert.match(
    updateRouteSource,
    /additional_consented_products:\s*\["liabilities"\]/
  );
  assert.doesNotMatch(
    updateRouteSource,
    /days_requested|transactionsLinkInitialization/
  );
}

function testProtectedMiddlewareOrderIsUnchanged() {
  const indexSource = fs.readFileSync(
    path.join(__dirname, "..", "index.js"),
    "utf8"
  );

  assert.match(
    indexSource,
    /app\.get\(\s*"\/api\/transactions",\s*requireAppApiKey,\s*resolvePlaidAuth,\s*transactionsRateLimiter,\s*transactionsHandler\s*\)/
  );
}

async function run() {
  await testOneItemMultiplePages();
  await testMultipleItemsMultiplePages();
  await testZeroTransactions();
  await testDuplicateTransactionIDsAcrossPages();
  await testLaterPageFailureDiscardsIncompleteItem();
  await testOneItemSucceedsWhileAnotherFails();
  await testHandlerMetadataAndUserScope();
  await testHandlerReportsExplicitLookbackOverride();
  await testHandlerPartialAndFailedResponsesAreTruthful();
  await testDisabledBehaviorIsUnchanged();
  testTransactionHistoryConfiguration();
  testTransactionsLinkInitializationIsScoped();
  testProtectedMiddlewareOrderIsUnchanged();

  console.log("Transaction snapshot checks passed.");
}

run().catch((error) => {
  console.error(`Transaction snapshot checks failed: ${error.stack || error.message}`);
  process.exit(1);
});
