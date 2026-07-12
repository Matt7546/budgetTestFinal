const DEFAULT_TRANSACTIONS_LOOKBACK_DAYS = 90;
const MIN_TRANSACTIONS_LOOKBACK_DAYS = 30;
const MAX_TRANSACTIONS_LOOKBACK_DAYS = 730;
const TRANSACTIONS_LINK_DAYS_REQUESTED = 90;

function resolveTransactionsLookbackDays(
  rawValue,
  warn = console.warn
) {
  if (rawValue === undefined || rawValue === null || rawValue === "") {
    return DEFAULT_TRANSACTIONS_LOOKBACK_DAYS;
  }

  const parsedValue = Number(String(rawValue).trim());

  if (!Number.isInteger(parsedValue)) {
    warn(
      `PLAID_TRANSACTIONS_LOOKBACK_DAYS has unrecognized value "${rawValue}". Using default=${DEFAULT_TRANSACTIONS_LOOKBACK_DAYS}.`
    );
    return DEFAULT_TRANSACTIONS_LOOKBACK_DAYS;
  }

  if (parsedValue < MIN_TRANSACTIONS_LOOKBACK_DAYS) {
    warn(
      `PLAID_TRANSACTIONS_LOOKBACK_DAYS=${parsedValue} is below minimum ${MIN_TRANSACTIONS_LOOKBACK_DAYS}. Using ${MIN_TRANSACTIONS_LOOKBACK_DAYS}.`
    );
    return MIN_TRANSACTIONS_LOOKBACK_DAYS;
  }

  if (parsedValue > MAX_TRANSACTIONS_LOOKBACK_DAYS) {
    warn(
      `PLAID_TRANSACTIONS_LOOKBACK_DAYS=${parsedValue} is above maximum ${MAX_TRANSACTIONS_LOOKBACK_DAYS}. Using ${MAX_TRANSACTIONS_LOOKBACK_DAYS}.`
    );
    return MAX_TRANSACTIONS_LOOKBACK_DAYS;
  }

  return parsedValue;
}

function transactionsLinkInitialization(transactionsEnabled) {
  if (!transactionsEnabled) {
    return {
      products: [],
    };
  }

  return {
    products: ["transactions"],
    transactions: {
      days_requested: TRANSACTIONS_LINK_DAYS_REQUESTED,
    },
  };
}

module.exports = {
  DEFAULT_TRANSACTIONS_LOOKBACK_DAYS,
  MAX_TRANSACTIONS_LOOKBACK_DAYS,
  MIN_TRANSACTIONS_LOOKBACK_DAYS,
  TRANSACTIONS_LINK_DAYS_REQUESTED,
  resolveTransactionsLookbackDays,
  transactionsLinkInitialization,
};
