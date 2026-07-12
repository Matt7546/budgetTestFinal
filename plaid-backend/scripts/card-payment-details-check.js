const assert = require("assert");
const {
  sanitizedCardPaymentDetail,
  sanitizedCardPaymentDetailsFromPlaidResponse,
} = require("../cardPaymentDetails");

const refreshedAt = "2026-07-12T12:00:00.000Z";
const account = {
  account_id: "account-1",
  name: "Card",
  official_name: "Card Preferred",
  mask: "1234",
  balances: {
    current: 210.25,
    available: 789.75,
  },
};
const item = {
  institutionName: "Example Bank",
};

function detailFor(liability) {
  return sanitizedCardPaymentDetail({
    liability: {
      account_id: "account-1",
      last_statement_balance: 175.5,
      ...liability,
    },
    account,
    item,
    refreshedAt,
  });
}

assert.strictEqual(
  detailFor({ last_statement_issue_date: "2026-07-03" })
    .last_statement_issue_date,
  "2026-07-03"
);
assert.strictEqual(
  detailFor({ last_statement_issue_date: null }).last_statement_issue_date,
  null
);
assert.strictEqual(
  detailFor({}).last_statement_issue_date,
  null
);

const mapped = sanitizedCardPaymentDetailsFromPlaidResponse(
  {
    accounts: [account],
    liabilities: {
      credit: [{
        account_id: "account-1",
        last_statement_balance: 175.5,
        last_statement_issue_date: "2026-07-03",
      }],
    },
  },
  item,
  refreshedAt
);

assert.strictEqual(mapped.length, 1);
assert.strictEqual(mapped[0].account_id, "account-1");
assert.strictEqual(mapped[0].last_statement_issue_date, "2026-07-03");
assert.strictEqual(mapped[0].last_refreshed_at, refreshedAt);

console.log("Card payment details checks passed.");
