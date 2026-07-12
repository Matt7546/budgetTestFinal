function finiteNumberOrNull(value) {
  const number = Number(value);

  return Number.isFinite(number) ? number : null;
}

function stringOrNull(value) {
  if (typeof value !== "string") {
    return null;
  }

  const trimmedValue = value.trim();

  return trimmedValue.length > 0 ? trimmedValue : null;
}

function boolOrNull(value) {
  if (typeof value === "boolean") {
    return value;
  }

  return null;
}

function sanitizedCardPaymentDetail({
  liability,
  account,
  item,
  refreshedAt,
}) {
  const accountID = stringOrNull(liability?.account_id);

  if (!accountID) {
    return null;
  }

  return {
    account_id: accountID,
    account_name: stringOrNull(account?.official_name) ||
      stringOrNull(account?.name) ||
      "Credit card",
    institution_name: stringOrNull(item?.institutionName),
    mask: stringOrNull(account?.mask),
    current_balance: finiteNumberOrNull(account?.balances?.current),
    available_credit: finiteNumberOrNull(account?.balances?.available),
    last_statement_balance: finiteNumberOrNull(liability?.last_statement_balance),
    last_statement_issue_date: stringOrNull(liability?.last_statement_issue_date),
    minimum_payment_amount: finiteNumberOrNull(liability?.minimum_payment_amount),
    next_payment_due_date: stringOrNull(liability?.next_payment_due_date),
    last_payment_amount: finiteNumberOrNull(liability?.last_payment_amount),
    last_payment_date: stringOrNull(liability?.last_payment_date),
    is_overdue: boolOrNull(liability?.is_overdue),
    last_refreshed_at: refreshedAt,
  };
}

function sanitizedCardPaymentDetailsFromPlaidResponse(responseData, item, refreshedAt) {
  const accountsByID = new Map();

  (responseData?.accounts || []).forEach((account) => {
    const accountID = stringOrNull(account?.account_id);

    if (accountID) {
      accountsByID.set(accountID, account);
    }
  });

  return (responseData?.liabilities?.credit || [])
    .map((liability) =>
      sanitizedCardPaymentDetail({
        liability,
        account: accountsByID.get(liability?.account_id),
        item,
        refreshedAt,
      })
    )
    .filter(Boolean);
}

module.exports = {
  sanitizedCardPaymentDetail,
  sanitizedCardPaymentDetailsFromPlaidResponse,
};
