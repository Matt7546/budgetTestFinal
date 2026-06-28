function safePlaidRemovalError(error) {
  const plaidError = error?.response?.data || {};

  return {
    error: "item_remove_failed",
    status: error?.response?.status || "unknown",
    error_type: plaidError.error_type || "unknown",
    error_code: plaidError.error_code || error?.code || "unknown",
  };
}

async function removePlaidItemsForUser({
  userId,
  plaidItemStore,
  plaidClient,
}) {
  if (!userId) {
    throw new Error("userId is required for Plaid item removal.");
  }

  const items = await plaidItemStore.getUserItems(userId);
  const removedItemIds = [];
  const removalErrors = [];

  for (const item of items) {
    try {
      await plaidClient.itemRemove({
        access_token: item.accessToken,
      });

      if (item.itemId) {
        removedItemIds.push(item.itemId);
      } else {
        removalErrors.push({
          error: "missing_item_id",
          status: "unknown",
          error_type: "store_error",
          error_code: "missing_item_id",
        });
      }
    } catch (error) {
      removalErrors.push(safePlaidRemovalError(error));
    }
  }

  if (removedItemIds.length === items.length && removalErrors.length === 0) {
    await plaidItemStore.removeAllUserItems(userId);
  } else {
    for (const itemId of removedItemIds) {
      await plaidItemStore.removeUserItem(userId, itemId);
    }
  }

  return {
    total_items: items.length,
    removed_items: removedItemIds.length,
    failed_items: removalErrors.length,
    removal_errors: removalErrors,
  };
}

async function deleteAccountForUser({
  userId,
  plaidItemStore,
  plaidClient,
  sessionStore,
}) {
  const removalResult = await removePlaidItemsForUser({
    userId,
    plaidItemStore,
    plaidClient,
  });

  if (removalResult.failed_items > 0) {
    return {
      success: false,
      retryable: true,
      ...removalResult,
      sessions_revoked: 0,
      user_deleted: false,
    };
  }

  const sessionsRevoked = await sessionStore.revokeAllSessionsForUser(userId);
  const userDeleted = await sessionStore.softDeleteUser(userId);

  return {
    success: true,
    retryable: false,
    ...removalResult,
    sessions_revoked: sessionsRevoked,
    user_deleted: userDeleted,
  };
}

module.exports = {
  deleteAccountForUser,
  removePlaidItemsForUser,
  safePlaidRemovalError,
};
