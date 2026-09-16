const { stableLegacyItemID } = require("./plaidItemUtils");
const {
  isItemScopedPlaidError,
  normalizedItemOutcome,
} = require("./itemRecovery");

function withInstitutionMetadata(record, item) {
  return {
    ...record,
    item_id: stableLegacyItemID(item),
    institution_name: item.institutionName,
    institution_id: item.institutionId,
  };
}

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

async function fetchAccountSnapshot({
  client,
  items,
  onItemError = () => {},
}) {
  const accounts = [];
  const itemErrors = [];
  const refreshedItemIDs = [];
  const evaluatedItemIDs = items.map((item) => stableLegacyItemID(item));

  for (const item of items) {
    try {
      const response = await client.accountsGet({
        access_token: item.accessToken,
      });
      const responseAccounts = response?.data?.accounts;

      if (!Array.isArray(responseAccounts)) {
        throw new TypeError("Plaid returned an invalid accounts envelope.");
      }

      accounts.push(
        ...responseAccounts.map((account) =>
          withInstitutionMetadata(account, item)
        )
      );
      refreshedItemIDs.push(stableLegacyItemID(item));
    } catch (error) {
      if (!isItemScopedPlaidError(error)) {
        throw error;
      }

      itemErrors.push(
        normalizedItemOutcome(item, error, "accounts_fetch_failed")
      );
      onItemError(error);
    }
  }

  return {
    accounts: dedupeByID(accounts, "account_id"),
    itemErrors,
    successfulItems: items.length - itemErrors.length,
    partialFailure: itemErrors.length > 0,
    refreshedItemIDs,
    evaluatedItemIDs,
  };
}

function createAccountsHandler({
  client,
  plaidItemStore,
  getRequestUserID,
  logStoreError,
  logPlaidError,
}) {
  return async function accountsHandler(req, res) {
    const userID = getRequestUserID(req);
    let items;

    try {
      items = await plaidItemStore.getUserItems(userID);
    } catch (error) {
      logStoreError("Accounts Item Store Error", error);

      return res.status(500).json({
        error: "Failed to fetch accounts",
      });
    }

    if (items.length === 0) {
      return res.status(409).json({
        error: "not_linked",
        message: "No linked Plaid item found.",
      });
    }

    let snapshot;

    try {
      snapshot = await fetchAccountSnapshot({
        client,
        items,
        onItemError: (error) => {
          logPlaidError("Accounts Item Error", error);
        },
      });
    } catch (error) {
      logPlaidError("Accounts Snapshot Error", error);

      return res.status(502).json({
        error: "accounts_unavailable",
        message: "Bank Sync could not refresh accounts right now.",
      });
    }

    return res.json({
      accounts: snapshot.accounts,
      item_errors: snapshot.itemErrors,
      partial_failure: snapshot.partialFailure,
      refreshed_item_ids: snapshot.refreshedItemIDs,
      evaluated_item_ids: snapshot.evaluatedItemIDs,
    });
  };
}

module.exports = {
  createAccountsHandler,
  fetchAccountSnapshot,
};
