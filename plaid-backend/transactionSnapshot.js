const { stableLegacyItemID } = require("./plaidItemUtils");
const { normalizedItemOutcome } = require("./itemRecovery");
const { unknownEvidence } = require("./transactionEvidence");

const TRANSACTIONS_PAGE_SIZE = 500;

function dedupeByScopedID(records, fields) {
  const byID = new Map();

  records.forEach((record) => {
    const values = fields.map((field) => record?.[field]);

    if (values.every((value) => typeof value === "string" && value.length > 0)) {
      byID.set(JSON.stringify(values), record);
    }
  });

  return Array.from(byID.values());
}

function hasAmbiguousAccountOwnership(records) {
  const itemByAccountID = new Map();

  for (const record of records) {
    const accountID = record?.account_id;
    const itemID = record?.item_id;
    if (!accountID || !itemID) {
      continue;
    }

    const previousItemID = itemByAccountID.get(accountID);
    if (previousItemID && previousItemID !== itemID) {
      return true;
    }
    itemByAccountID.set(accountID, itemID);
  }

  return false;
}

function withInstitutionMetadata(record, item) {
  return {
    ...record,
    item_id: stableLegacyItemID(item),
    institution_name: item.institutionName,
    institution_id: item.institutionId,
  };
}

function paginationError(message) {
  const error = new Error(message);
  error.code = "transactions_pagination_incomplete";
  return error;
}

async function fetchCompleteItemTransactions({
  client,
  item,
  startDate,
  endDate,
  pageSize = TRANSACTIONS_PAGE_SIZE,
}) {
  if (!Number.isInteger(pageSize) || pageSize <= 0) {
    throw new Error("Transaction page size must be a positive integer.");
  }

  const transactions = [];
  const accounts = [];
  let expectedTotal = null;
  let offset = 0;

  while (expectedTotal === null || offset < expectedTotal) {
    const response = await client.transactionsGet({
      access_token: item.accessToken,
      start_date: startDate,
      end_date: endDate,
      options: {
        count: pageSize,
        offset,
      },
    });
    const responseData = response?.data;
    const pageTransactions = responseData?.transactions;
    const reportedTotal = responseData?.total_transactions;

    if (!Array.isArray(pageTransactions) ||
        !Number.isInteger(reportedTotal) ||
        reportedTotal < 0) {
      throw paginationError("Plaid returned invalid transaction pagination metadata.");
    }
    if (!Array.isArray(responseData.accounts)) {
      throw paginationError("Plaid returned invalid transaction accounts metadata.");
    }
    if (responseData.accounts.some((account) =>
      typeof account?.account_id !== "string" ||
      account.account_id.trim().length === 0
    )) {
      throw paginationError("Plaid returned an invalid transaction account identity.");
    }

    if (expectedTotal === null) {
      expectedTotal = reportedTotal;
    } else if (reportedTotal !== expectedTotal) {
      throw paginationError("Plaid transaction total changed during pagination.");
    }

    if (offset + pageTransactions.length > expectedTotal) {
      throw paginationError("Plaid returned more transactions than reported.");
    }

    transactions.push(
      ...pageTransactions.map((transaction) =>
        withInstitutionMetadata(transaction, item)
      )
    );

    accounts.push(
      ...responseData.accounts.map((account) =>
        withInstitutionMetadata(account, item)
      )
    );

    offset += pageTransactions.length;

    if (offset < expectedTotal && pageTransactions.length === 0) {
      throw paginationError("Plaid returned an empty transaction page before completion.");
    }
  }

  const accountIDs = new Set(accounts.map((account) => account?.account_id));
  if (transactions.some((transaction) =>
    !accountIDs.has(transaction?.account_id)
  )) {
    throw paginationError("Plaid returned a transaction without account coverage.");
  }

  // A repeated or unidentified ID makes the offset-paginated result unsafe
  // to call complete, even when every requested page returned successfully.
  if (dedupeByScopedID(
    transactions, ["item_id", "account_id", "transaction_id"]
  ).length !== expectedTotal) {
    throw paginationError("Plaid returned duplicate or unidentified transactions.");
  }

  return {
    transactions,
    accounts: dedupeByScopedID(accounts, ["item_id", "account_id"]),
    totalTransactions: expectedTotal ?? 0,
  };
}

async function fetchTransactionSnapshot({
  client,
  items,
  startDate,
  endDate,
  pageSize = TRANSACTIONS_PAGE_SIZE,
  onItemError = () => {},
  itemEvidenceFor = async (item) => unknownEvidence(stableLegacyItemID(item)),
  now = () => new Date(),
}) {
  const transactions = [];
  const accounts = [];
  const itemEvidence = [];
  const itemErrors = [];
  let successfulItems = 0;
  let expectedTransactions = 0;

  for (const item of items) {
    let evidence;
    try {
      evidence = await itemEvidenceFor(item);
    } catch {
      evidence = unknownEvidence(stableLegacyItemID(item));
    }
    try {
      const itemSnapshot = await fetchCompleteItemTransactions({
        client,
        item,
        startDate,
        endDate,
        pageSize,
      });

      successfulItems += 1;
      expectedTransactions += itemSnapshot.totalTransactions;
      transactions.push(...itemSnapshot.transactions);
      accounts.push(...itemSnapshot.accounts);
      itemEvidence.push({
        ...evidence,
        item_id: stableLegacyItemID(item),
        snapshot_fetched_at: now().toISOString(),
      });
    } catch (error) {
      itemErrors.push(
        normalizedItemOutcome(
          item,
          error,
          "transactions_fetch_failed"
        )
      );
      onItemError(error);
    }
  }

  const returnedTransactions = dedupeByScopedID(
    transactions,
    ["item_id", "account_id", "transaction_id"]
  );
  const identitiesComplete = returnedTransactions.length === expectedTransactions;
  const ambiguousAccountOwnership = hasAmbiguousAccountOwnership([
    ...accounts,
    ...transactions,
  ]);
  const complete = successfulItems === items.length &&
    itemErrors.length === 0 && identitiesComplete &&
    !ambiguousAccountOwnership;

  return {
    transactions: returnedTransactions,
    accounts: dedupeByScopedID(accounts, ["item_id", "account_id"]),
    itemEvidence,
    evaluatedItemIDs: items.map(stableLegacyItemID),
    itemErrors,
    successfulItems,
    totalTransactions: complete ? expectedTransactions : null,
    returnedTransactions: returnedTransactions.length,
    complete,
    partialFailure: itemErrors.length > 0 || !identitiesComplete ||
      ambiguousAccountOwnership,
  };
}

function createTransactionsHandler({
  client,
  plaidItemStore,
  getRequestUserID,
  transactionsEnabled,
  lookbackDays,
  capabilitiesResponse,
  logStoreError,
  logPlaidError,
  now = () => new Date(),
  pageSize = TRANSACTIONS_PAGE_SIZE,
  itemEvidenceFor = async (userID, item) =>
    unknownEvidence(stableLegacyItemID(item)),
}) {
  return async function transactionsHandler(req, res) {
    if (!transactionsEnabled) {
      return res.status(409).json({
        error: "transactions_disabled",
        message: "Transactions are disabled for this backend.",
        transactions: [],
        accounts: [],
        partial_failure: false,
        ...capabilitiesResponse(),
      });
    }

    const userId = getRequestUserID(req);
    let items;

    try {
      items = await plaidItemStore.getUserItems(userId);
    } catch (error) {
      logStoreError("Transactions Item Store Error", error);

      return res.status(500).json({
        error: "Failed to fetch transactions",
      });
    }

    if (items.length === 0) {
      return res.status(409).json({
        error: "not_linked",
        message: "No linked Plaid item found.",
      });
    }

    const windowEndDate = now();
    const windowStartDate = new Date(windowEndDate);
    windowStartDate.setDate(windowEndDate.getDate() - lookbackDays);
    const windowStart = windowStartDate.toISOString().split("T")[0];
    const windowEnd = windowEndDate.toISOString().split("T")[0];
    const snapshot = await fetchTransactionSnapshot({
      client,
      items,
      startDate: windowStart,
      endDate: windowEnd,
      pageSize,
      now,
      itemEvidenceFor: (item) => itemEvidenceFor(userId, item),
      onItemError: (error) => {
        logPlaidError("Transactions Item Error", error);
      },
    });
    const responseMetadata = {
      window_start: windowStart,
      window_end: windowEnd,
      lookback_days: lookbackDays,
      total_transactions: snapshot.totalTransactions,
      returned_transactions: snapshot.returnedTransactions,
      item_evidence: snapshot.itemEvidence,
      evaluated_item_ids: snapshot.evaluatedItemIDs,
      complete: snapshot.complete,
      partial_failure: snapshot.partialFailure,
    };

    if (snapshot.successfulItems === 0 && snapshot.itemErrors.length > 0) {
      return res.status(500).json({
        error: "Failed to fetch transactions",
        transactions: [],
        accounts: [],
        item_errors: snapshot.itemErrors,
        ...responseMetadata,
      });
    }

    return res.json({
      transactions: snapshot.transactions,
      accounts: snapshot.accounts,
      item_errors: snapshot.itemErrors,
      ...responseMetadata,
    });
  };
}

module.exports = {
  TRANSACTIONS_PAGE_SIZE,
  createTransactionsHandler,
  fetchCompleteItemTransactions,
  fetchTransactionSnapshot,
};
