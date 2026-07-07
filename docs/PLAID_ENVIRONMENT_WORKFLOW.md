# Caldera Plaid Environment Workflow

This doc keeps Plaid testing, billing risk, and environment switches clear.

## Known Plaid Rates

Current known contract rates:

- Balance: `$0.10` per call.
- Transactions: `$0.30` per connected account per month.
- Liabilities: `$0.20` per connected account per month.

## Current App Needs

Caldera's MVP needs:

- `/accounts/get`.
- Account labels.
- Account type and subtype.
- Cached balances from linked accounts.
- Account masks and institution names.

Caldera does not currently need:

- Transaction UI.
- Real-time Balance.
- Liabilities.
- Due dates or minimum payments from Plaid.
- Full debt or loan management.

## Current Product Rule

Caldera uses Bank Sync to estimate Available to Spend from linked balances. Set Aside money stays in the user's bank account and is managed inside the app.

## Local Accounts-Only Test

Use this only with the local backend and Plaid Sandbox.

1. Set local mode:

   ```sh
   ./scripts/set-local-plaid-mode.sh accounts-only
   ```

2. Restart the local backend:

   ```sh
   ./scripts/run-local-backend.sh
   ```

3. Check capabilities:

   ```sh
   ./scripts/check-local-backend.sh
   ```

4. Confirm:

   - `/api/capabilities` reports `transactions_enabled=false`.
   - `/api/transactions` returns a disabled/no-op response.
   - The app still loads Dashboard, Savings, Timeline, Debt Payoff, and Linked Accounts.

## Restore Local Transactions Mode

```sh
./scripts/set-local-plaid-mode.sh transactions
```

Then restart the local backend.

## Render Production Rule

Keep `PLAID_TRANSACTIONS_ENABLED` unset on Render until Plaid confirms Accounts-only Link is supported for this app and contract.

Do not change Render Plaid mode casually. A Render env var change affects Release and TestFlight.

## Questions For Plaid Support

- Can Caldera create Link tokens with no paid products and still use `/accounts/get`?
- Does `products: ["transactions"]` trigger monthly billing even if `/transactions/get` is never called?
- How do we stop Transactions billing for existing Items already linked with Transactions?
- Is `/accounts/get` cached balance data included without Balance product fees under this contract?
- Are account `limit`, `subtype`, and institution metadata available without extra products?
- Can account filters limit users to depository and credit card accounts without adding paid products?

