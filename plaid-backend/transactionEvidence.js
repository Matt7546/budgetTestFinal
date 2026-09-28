const { stableLegacyItemID } = require("./plaidItemUtils");

const RECOVERY_RETRY_MS = 24 * 60 * 60 * 1000;
const EXISTING_ITEM_AGE_MS = 24 * 60 * 60 * 1000;

function validProviderDate(value, noLaterThan) {
  const parts = typeof value === "string" && value.match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|([+-])(\d{2}):(\d{2}))$/
  );
  if (!parts) {
    return null;
  }
  const [, year, month, day, hour, minute, second, , offsetHour,
    offsetMinute] = parts;
  const calendarDay = new Date(Date.UTC(+year, +month - 1, +day));
  if (calendarDay.getUTCFullYear() !== +year ||
      calendarDay.getUTCMonth() !== +month - 1 ||
      calendarDay.getUTCDate() !== +day || +hour > 23 ||
      +minute > 59 || +second > 59 ||
      (offsetHour !== undefined && (+offsetHour > 14 ||
        +offsetMinute > 59 || (+offsetHour === 14 && +offsetMinute !== 0)))) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) &&
    parsed.getTime() <= noLaterThan.getTime()
    ? parsed.toISOString()
    : null;
}

function configuredWebhookURL(raw) {
  if (typeof raw !== "string" || !raw) {
    return null;
  }
  try {
    const url = new URL(raw);
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function unknownEvidence(itemID) {
  return {
    item_id: itemID,
    historical_ready: false,
    historical_ready_at: null,
    provider_last_successful_update: null,
    provider_observed_at: null,
    snapshot_fetched_at: null,
  };
}

function createItemEvidenceProvider({
  client,
  plaidItemStore,
  webhookURL,
  now = () => new Date(),
}) {
  return async function itemEvidenceFor(userID, item) {
    const itemID = stableLegacyItemID(item);
    const unknown = unknownEvidence(itemID);
    if (!userID || !itemID || !item.itemId) {
      return unknown;
    }

    let itemResponse;
    let readiness;
    try {
      [itemResponse, readiness] = await Promise.all([
        client.itemGet({ access_token: item.accessToken }),
        plaidItemStore.getUserItemReadiness(userID, itemID),
      ]);
    } catch {
      return unknown;
    }

    const observedAt = now();
    if (itemResponse?.data?.item?.item_id !== itemID || !readiness ||
        !Number.isFinite(observedAt.getTime())) {
      return unknown;
    }

    const historicalReadyAt = validProviderDate(
      readiness.historicalReadyAt, observedAt
    );
    const providerLastUpdate = validProviderDate(
      itemResponse?.data?.status?.transactions?.last_successful_update,
      observedAt
    );

    const evidence = {
      ...unknown,
      historical_ready: historicalReadyAt !== null,
      historical_ready_at: historicalReadyAt,
      provider_last_successful_update: providerLastUpdate,
      provider_observed_at: observedAt.toISOString(),
    };

    // Older /transactions/get Items may have linked before this webhook was
    // configured or before its historical callback was recorded. Subscribe to
    // documented completion webhooks without using Sync data as a snapshot.
    // A successful probe is never itself evidence that history is ready.
    const linkedAt = validProviderDate(item.linkedAt, observedAt);
    const lastProbe = validProviderDate(
      readiness.historicalRecoveryStartedAt, observedAt
    );
    if (!historicalReadyAt && webhookURL && linkedAt &&
        observedAt.getTime() - new Date(linkedAt).getTime() >= EXISTING_ITEM_AGE_MS &&
        (!lastProbe || observedAt.getTime() - new Date(lastProbe).getTime() >=
          RECOVERY_RETRY_MS)) {
      try {
        if (itemResponse.data.item.webhook !== webhookURL) {
          await client.itemWebhookUpdate({
            access_token: item.accessToken,
            webhook: webhookURL,
          });
        }
        await client.transactionsSync({
          access_token: item.accessToken,
          cursor: "now",
          count: 1,
        });
        await plaidItemStore.markHistoricalRecoveryStarted(
          userID, itemID, observedAt.toISOString()
        );
      } catch {
        // Unknown remains unknown. A later refresh may retry; never infer
        // readiness from the probe or from /item/get's update timestamp.
      }
    }

    return evidence;
  };
}

module.exports = {
  configuredWebhookURL,
  createItemEvidenceProvider,
  unknownEvidence,
  validProviderDate,
};
