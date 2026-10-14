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

// Plaid's monetary fields are number | null. Coercion would turn unavailable
// values (including null, empty strings, and false) into a fabricated zero.
const monetaryFields = [
  { source: "current", output: "current_balance", onAccount: true },
  { source: "available", output: "available_credit", onAccount: true },
  { source: "last_statement_balance", output: "last_statement_balance" },
  { source: "minimum_payment_amount", output: "minimum_payment_amount" },
  { source: "last_payment_amount", output: "last_payment_amount" },
];
const monetaryCases = [
  { name: "real zero", value: 0, expected: 0 },
  { name: "positive", value: 125.37, expected: 125.37 },
  { name: "negative", value: -12.5, expected: -12.5 },
  { name: "null", value: null, expected: null },
  { name: "omitted", expected: null },
  { name: "empty string", value: "", expected: null },
  { name: "whitespace", value: "   ", expected: null },
  { name: "true", value: true, expected: null },
  { name: "false", value: false, expected: null },
  { name: "NaN", value: NaN, expected: null },
  { name: "Infinity", value: Infinity, expected: null },
  { name: "negative Infinity", value: -Infinity, expected: null },
  { name: "object", value: {}, expected: null },
  { name: "array", value: [], expected: null },
  { name: "numeric string", value: "125.37", expected: null },
];

for (const field of monetaryFields) {
  for (const testCase of monetaryCases) {
    const candidateAccount = { account_id: "account-1", balances: {} };
    const candidateLiability = { account_id: "account-1" };
    if (Object.hasOwn(testCase, "value")) {
      if (field.onAccount) {
        candidateAccount.balances[field.source] = testCase.value;
      } else {
        candidateLiability[field.source] = testCase.value;
      }
    }

    const detail = sanitizedCardPaymentDetail({
      liability: candidateLiability,
      account: candidateAccount,
      item,
      refreshedAt,
    });
    assert.strictEqual(
      detail[field.output],
      testCase.expected,
      `${field.output}: ${testCase.name}`
    );
    assert.strictEqual(
      JSON.parse(JSON.stringify(detail))[field.output],
      testCase.expected,
      `serialized ${field.output}: ${testCase.name}`
    );
  }
}

const nullableResponse = sanitizedCardPaymentDetailsFromPlaidResponse(
  {
    accounts: [{ account_id: "account-1", balances: { current: null, available: 0 } }],
    liabilities: { credit: [{ account_id: "account-1", last_statement_balance: null }] },
  },
  item,
  refreshedAt
);
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(nullableResponse)).map((card) => ({
    current: card.current_balance,
    available: card.available_credit,
    statement: card.last_statement_balance,
    minimum: card.minimum_payment_amount,
  })),
  [{ current: null, available: 0, statement: null, minimum: null }]
);

console.log("Card payment details checks passed.");
