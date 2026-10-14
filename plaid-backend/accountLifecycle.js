function safePlaidRemovalError(error) {
  const plaidError = error?.response?.data || {};

  return {
    error: "item_remove_failed",
    status: error?.response?.status || "unknown",
    error_type: plaidError.error_type || "unknown",
    error_code: plaidError.error_code || error?.code || "unknown",
  };
}

async function removeSnapshotItems({
  userId,
  plaidItemStore,
  plaidClient,
}) {
  if (!userId) {
    throw new Error("userId is required for Plaid item removal.");
  }

  const items = await plaidItemStore.getUserItems(userId);
  let removedCount = 0;
  const removalErrors = [];

  for (const item of items) {
    if (!item.itemId || !item.accessToken) {
      removalErrors.push({ error: "missing_item_identity", status: "unknown",
        error_type: "store_error", error_code: "missing_item_identity" });
      continue;
    }
    try {
      await plaidClient.itemRemove({
        access_token: item.accessToken,
      });

      if (await plaidItemStore.removeUserItemIfMatching(userId, item)) {
        removedCount += 1;
      } else {
        removalErrors.push({
          error: "item_changed_during_removal", status: "unknown",
          error_type: "store_error", error_code: "item_changed_during_removal",
        });
      }
    } catch (error) {
      removalErrors.push(error?.response
        ? safePlaidRemovalError(error)
        : { error: "item_store_remove_failed", status: "unknown",
          error_type: "store_error", error_code: "item_store_remove_failed" });
    }
  }

  return {
    total_items: items.length,
    removed_items: removedCount,
    failed_items: removalErrors.length,
    removal_errors: removalErrors,
  };
}

async function removePlaidItemsForUser({ userId, plaidItemStore, plaidClient }) {
  const generation = await plaidItemStore.beginItemRemoval(userId, "disconnecting");
  try {
    return await removeSnapshotItems({ userId, plaidItemStore, plaidClient });
  } finally {
    await plaidItemStore.finishItemRemoval(
      userId, generation, "disconnecting"
    );
  }
}

async function deleteAccountForUser({
  userId,
  plaidItemStore,
  plaidClient,
  sessionStore,
}) {
  const generation = await plaidItemStore.beginItemRemoval(userId, "deleting");
  let deleted = false;
  try {
    const removalResult = await removeSnapshotItems({
      userId, plaidItemStore, plaidClient,
    });
    if (removalResult.failed_items > 0 ||
        await plaidItemStore.getUserItemCount(userId) > 0) {
      return { success: false, retryable: true, ...removalResult,
        sessions_revoked: 0, user_deleted: false };
    }
    // The lifecycle gate remains closed until the authoritative owner row is
    // soft-deleted. Releasing it earlier would permit a new Item in the gap.
    const finalization = await sessionStore.finalizeAccountDeletion(userId);
    deleted = finalization.userDeleted;
    if (!deleted) {
      return { success: false, retryable: true, ...removalResult,
        sessions_revoked: 0, user_deleted: false };
    }
    return { success: true, retryable: false, ...removalResult,
      sessions_revoked: finalization.sessionsRevoked, user_deleted: true };
  } finally {
    await plaidItemStore.finishItemRemoval(userId, generation, "deleting", deleted);
  }
}

module.exports = {
  deleteAccountForUser,
  removePlaidItemsForUser,
  safePlaidRemovalError,
};
