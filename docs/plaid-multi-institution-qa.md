# Plaid Multi-Institution QA

Use this specialized checklist before an internal TestFlight build that
changes multi-Item Plaid behavior. Follow
[ENVIRONMENT_WORKFLOW.md](ENVIRONMENT_WORKFLOW.md) for environment safety.

## Expected Behavior

- Linking another institution through Settings appends a Plaid Item.
- Existing linked institutions remain connected.
- Accounts and complete transaction snapshots include every successful Item.
- iOS deduplicates accounts by `account_id` and transactions by
  `transaction_id`.
- One Item's refresh failure does not erase cached institutions that remain
  usable.
- Partial or incomplete transaction snapshots do not create unsupported
  Review Updates.
- Card-payment details fail calmly when the capability, consent, or
  institution data is unavailable.

## Manual Test

1. In the approved QA environment, open More → Account & Bank Sync → Linked
   Accounts.
2. Connect a test institution with multiple account types.
3. Confirm its accounts appear once, persist after relaunch, and refresh.
4. Connect a second test institution from the same Settings destination.
5. Confirm the first institution remains connected and the second appears.
6. Refresh and confirm accounts and any complete transaction snapshot do not
   duplicate.
7. Simulate or observe one Item failing to refresh. Confirm other cached
   institutions remain visible and freshness is communicated.
8. Confirm a partial or incomplete transaction snapshot produces no
   unsupported recurring-expense or likely-payment Review Updates.
9. Where enabled, open linked-card payment details. Confirm missing details or
   consent fail calmly without changing the Payment Plan.
10. Disconnect from Linked Accounts. Confirm all intended backend-linked Items
    and local linked-bank display data clear, without changing unrelated user
    plans.

## Privacy and Regression Checks

- Multiple Plaid Items remain connected until the user disconnects them.
- Repeated refreshes do not duplicate accounts or transactions.
- A failed Item does not erase other cached institutions.
- Disconnect removes the intended account, balance, transaction, and
  card-payment display data locally and on the linked backend scope.
- Logs never print access tokens, public tokens, account identifiers, account
  details, balances, or transaction names/descriptions.

Do not use this checklist as a general release checklist.
