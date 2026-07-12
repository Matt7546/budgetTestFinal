const TRANSACTIONS_PAGE_SIZE = 500;

function dedupeByID(records, key) {
  const byID = new Map();

  records.forEach((record) => {
    const id = record?.[key];

    if (id) {
      byID.set(id, record);
    }
  });

  return Array.from(byID.values());
}

function withInstitutionMetadata(record, item) {
  return {
    ...record,
    item_id: item.itemId,
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

    if (Array.isArray(responseData.accounts)) {
      accounts.push(
        ...responseData.accounts.map((account) =>
          withInstitutionMetadata(account, item)
        )
      );
    }

    offset += pageTransactions.length;

    if (offset < expectedTotal && pageTransactions.length === 0) {
      throw paginationError("Plaid returned an empty transaction page before completion.");
    }
  }

  return {
    transactions,
    accounts: dedupeByID(accounts, "account_id"),
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
}) {
  const transactions = [];
  const accounts = [];
  const itemErrors = [];
  let successfulItems = 0;
  let expectedTransactions = 0;

  for (const item of items) {
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
    } catch (error) {
      itemErrors.push({
        error: "transactions_fetch_failed",
      });
      onItemError(error);
    }
  }

  const returnedTransactions = dedupeByID(
    transactions,
    "transaction_id"
  );
  const complete = successfulItems === items.length && itemErrors.length === 0;

  return {
    transactions: returnedTransactions,
    accounts: dedupeByID(accounts, "account_id"),
    itemErrors,
    successfulItems,
    totalTransactions: complete ? expectedTransactions : null,
    returnedTransactions: returnedTransactions.length,
    complete,
    partialFailure: itemErrors.length > 0,
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
