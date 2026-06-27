# Plaid Multi-Institution QA

Use this checklist before an internal TestFlight build that includes multi-item Plaid linking.

## Expected Behavior

- Linking a new institution appends a Plaid Item on the backend.
- Existing linked institutions remain connected.
- `/api/accounts` returns accounts from every stored Plaid Item.
- `/api/transactions` returns transactions from every stored Plaid Item.
- iOS upserts accounts by `account_id` and transactions by `transaction_id`.
- Refreshing does not duplicate accounts or transactions.

## Manual Test Steps

1. Fresh install or disconnect existing bank data.
2. Open Accounts and confirm the app shows the not-connected/connect-bank state.
3. Link a Chase-like institution with multiple accounts.
4. Confirm Chase checking, savings, and credit accounts appear.
5. Close and reopen the app.
6. Confirm Chase accounts still appear from local cache, then refresh successfully.
7. Link an Amex-like second institution.
8. Confirm Chase accounts remain visible.
9. Confirm Amex accounts are added.
10. Confirm account rows do not duplicate after refreshing.
11. Confirm transactions from both institutions appear where transactions are surfaced.
12. Close and reopen the app again.
13. Confirm both institutions remain visible.
14. Link a third institution.
15. Confirm the first two institutions remain visible and the third institution is added.
16. Use Settings > Disconnect Bank.
17. Confirm all linked account display data clears and reconnecting works.

## Regression Checks

- New institution linking must not clear previous account cache.
- Refresh failure for one Plaid Item should not wipe all visible accounts.
- Disconnect should clear every stored Plaid Item on the backend and cached Plaid display data on iOS.
- No Plaid access token, public token, account identifier, balance, or transaction detail should be printed to logs.
