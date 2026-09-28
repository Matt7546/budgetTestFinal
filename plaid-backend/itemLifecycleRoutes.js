const {
  deleteAccountForUser,
  removePlaidItemsForUser,
} = require("./accountLifecycle");

async function exchangePublicTokenForUser({
  userId, publicToken, institutionName, institutionId, linkSessionId,
  plaidItemStore, plaidClient,
}) {
  // Register before the provider await. A disconnect/deletion refuses to begin
  // while this lease exists; separate Postgres writers see the same gate.
  const lease = await plaidItemStore.beginItemExchange(userId,
    { publicToken, linkSessionId });
  // Durable before dispatch. A crash or timeout from here is provider-unknown,
  // not proof that no Item was created.
  await plaidItemStore.markItemExchangeDispatched(userId, lease);
  const response = await plaidClient.itemPublicTokenExchange({
    public_token: publicToken,
  });
  const item = {
    accessToken: response.data?.access_token,
    itemId: response.data?.item_id,
    institutionName,
    institutionId,
  };
  if (!item.accessToken || !item.itemId) {
    throw new Error("Invalid provider exchange response.");
  }
  let resultRecorded = false;
  try {
    await plaidItemStore.recordItemExchangeResult(userId, lease, item,
      response.data?.request_id || null);
    resultRecorded = true;
  } catch {
    // The in-memory token is not crash recovery. Continue to a durable Item,
    // recovery record, or confirmed provider removal; otherwise keep the lease.
  }
  let linkedItemCount;
  try {
    linkedItemCount = await plaidItemStore.saveUserItem(userId, item, lease);
  } catch {
    let saveOutcome;
    try {
      saveOutcome = await plaidItemStore.inspectItemExchangeSave(userId, lease, item);
    } catch {
      saveOutcome = { outcome: "unknown" };
    }
    if (saveOutcome.outcome === "saved" &&
        Number.isSafeInteger(saveOutcome.linkedItemCount) &&
        saveOutcome.linkedItemCount > 0) {
      await plaidItemStore.finishItemExchange(userId, lease,
        { kind: "saved", item });
      return { itemId: item.itemId,
        linkedItemCount: saveOutcome.linkedItemCount };
    }
    if (saveOutcome.outcome !== "not_saved") {
      const failure = new Error("Exchange Item save outcome is uncertain.");
      failure.code = "exchange_save_outcome_unknown";
      throw failure;
    }
    // Persist the exact token before the compensating provider call. If the
    // call is uncertain, the owner-scoped record remains for manual recovery.
    let recoveryId = null;
    try {
      recoveryId = await plaidItemStore.recordRemovalRecovery(userId, item, lease);
    } catch {
      // Still attempt provider removal; unresolved responsibility stays fenced.
    }
    if (!recoveryId) {
      // A failed recovery write may be independent of lifecycle storage, but
      // a changed lease or an unreadable store must not authorize removal.
      let currentOutcome;
      try {
        currentOutcome = await plaidItemStore.inspectItemExchangeSave(
          userId, lease, item);
      } catch {
        currentOutcome = { outcome: "unknown" };
      }
      if (currentOutcome.outcome !== "not_saved") {
        const failure = new Error("Exchange Item save outcome is uncertain.");
        failure.code = "exchange_save_outcome_unknown";
        throw failure;
      }
    }
    let removed = false;
    let removalRequestId = null;
    try {
      const removal = await plaidClient.itemRemove({ access_token: item.accessToken });
      if (typeof removal?.data?.request_id !== "string" ||
          !removal.data.request_id) {
        throw new Error("Invalid provider removal response.");
      }
      removed = true;
      removalRequestId = removal.data.request_id;
    } catch {
      // Keep the recovery record; never claim a successful link.
    }
    if (removed && (resultRecorded || recoveryId)) {
      await plaidItemStore.markItemExchangeRemovalConfirmed(userId, lease,
        item, removalRequestId, recoveryId);
      await plaidItemStore.finishItemExchange(userId, lease,
        { kind: "removed", item });
      if (recoveryId) await plaidItemStore.clearRemovalRecovery(userId, recoveryId);
    } else if (recoveryId) {
      await plaidItemStore.finishItemExchange(userId, lease,
        { kind: "recovery", item, recoveryId });
    } else {
      const failure = new Error("Exchange cleanup and recovery persistence failed.");
      failure.code = "exchange_cleanup_unrecoverable";
      throw failure;
    }
    const failure = new Error("Exchanged Item was not saved.");
    failure.code = "exchange_save_rejected";
    throw failure;
  }
  // A failed local acknowledgment leaves the lease in place, but must never
  // trigger provider compensation for an already durable linked Item.
  await plaidItemStore.finishItemExchange(userId, lease, { kind: "saved", item });
  return { itemId: item.itemId, linkedItemCount };
}

function createExchangePublicTokenHandler({
  getRequestUserID, plaidItemStore, plaidClient, logError = () => {},
}) {
  return async (req, res) => {
    const { public_token, institution_name, institution_id,
      link_session_id } = req.body || {};
    if (!public_token) {
      return res.status(400).json({ error: "missing_public_token",
        message: "A public token is required." });
    }
    try {
      const result = await exchangePublicTokenForUser({
        userId: getRequestUserID(req), publicToken: public_token,
        institutionName: institution_name, institutionId: institution_id,
        linkSessionId: typeof link_session_id === "string" &&
          link_session_id.length <= 256 &&
          !/[\x00-\x1f\x7f]/.test(link_session_id)
          ? link_session_id : null,
        plaidItemStore, plaidClient,
      });
      return res.json({ success: true, item_id: result.itemId,
        linked_items: result.linkedItemCount });
    } catch (error) {
      logError("Exchange Token Error", error);
      return res.status(500).json({ error: "Failed to exchange token" });
    }
  };
}

function createDisconnectHandler({
  getRequestUserID, plaidItemStore, plaidClient, logError = () => {},
}) {
  return async (req, res) => {
    try {
      const removalResult = await removePlaidItemsForUser({
        userId: getRequestUserID(req), plaidItemStore, plaidClient,
      });
      if (removalResult.failed_items > 0) {
        return res.status(502).json({ success: false, linked: true,
          retryable: true,
          message: "Some bank connections could not be disconnected. Try again.",
          ...removalResult });
      }
      return res.json({ success: true, linked: false, retryable: false,
        ...removalResult });
    } catch (error) {
      logError("Disconnect All Banks Error", error);
      return res.status(500).json({ success: false,
        error: "disconnect_failed",
        message: "Failed to disconnect bank connections." });
    }
  };
}

function createDeleteAccountHandler({
  sessionStore, plaidItemStore, plaidClient, logError = () => {},
}) {
  return async (req, res) => {
    if (!sessionStore) return res.status(503).json({ success: false,
      error: "auth_not_configured", message: "Authentication is not configured." });
    const userId = req.user?.id;
    if (!userId) return res.status(401).json({ success: false,
      error: "unauthorized", message: "Authentication required." });
    try {
      const result = await deleteAccountForUser({
        userId, plaidItemStore, plaidClient, sessionStore,
      });
      if (!result.success) return res.status(502).json({ success: false,
        retryable: true,
        message: "Some bank connections could not be removed. Try again.",
        removed_items: result.removed_items, failed_items: result.failed_items,
        removal_errors: result.removal_errors,
        sessions_revoked: result.sessions_revoked,
        user_deleted: result.user_deleted });
      return res.json({ success: true, removed_items: result.removed_items,
        failed_items: result.failed_items,
        sessions_revoked: result.sessions_revoked,
        user_deleted: result.user_deleted });
    } catch (error) {
      logError("Account Deletion Error", error);
      return res.status(500).json({ success: false,
        error: "delete_account_failed",
        message: "Failed to delete account." });
    }
  };
}

module.exports = { exchangePublicTokenForUser,
  createExchangePublicTokenHandler, createDisconnectHandler,
  createDeleteAccountHandler };
