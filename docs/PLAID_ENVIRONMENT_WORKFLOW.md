# Caldera Plaid Capability and Testing Workflow

This document covers Plaid capabilities, cost awareness, and focused testing.
Use [ENVIRONMENT_WORKFLOW.md](ENVIRONMENT_WORKFLOW.md) for backend selection,
credentials, and environment-switch procedures.

## Current Architecture

- **Accounts:** `/accounts/get`, account metadata, and cached eligible
  balances support Available to Spend.
- **Transactions:** transaction access is capability-gated. Complete,
  authenticated-user-scoped snapshots can provide evidence for review-first
  recurring-expense recommendations and likely posted Payment Plan detection.
- **Card payment details:** Plaid liabilities access is separately
  capability-gated and consent-aware. When available, it may provide statement
  balance, minimum payment, due-date, balance, and recent payment context for
  Payment Plans.

Institution coverage, account coverage, consent, history, and field
completeness vary. Missing or incomplete data must produce fewer or no
suggestions, never unsupported inference. Plaid-derived information must not
silently create, update, resolve, or delete a plan.

Caldera remains review-first. It does not move money or make payments.

## Transaction Snapshot Integrity

Caldera requests a 90-day transaction window by default. The backend override
is clamped from 30 through 730 days, and each snapshot reports the effective
window and completeness metadata.

New Items that initialize Transactions through Link explicitly request 90
days. Existing Items continue without relinking, but Plaid may limit history
according to how the Item was originally initialized and what the institution
returns.

Automation must use only a complete current snapshot for the authenticated
user and request scope. A partial Item failure, incomplete pagination, stale or
unknown metadata, session change, or insufficient history must suppress
unsupported Review Updates rather than fill gaps with assumptions.

## Cost Awareness

Do not rely on hard-coded Plaid prices in this repository. Before enabling a
new product, expanding an existing product, or changing Link configuration,
verify current pricing, billing triggers, and consent requirements in the
Plaid dashboard or the active Plaid agreement.

Treat Accounts, Transactions, liabilities, Link updates, and refresh frequency
as separate cost and capability decisions.

## Local Sandbox Safety

Use Plaid mode scripts only against the local backend and Sandbox. Before any
change, verify the active environment with `./scripts/task-start.sh`.

Accounts-only local test:

```sh
./scripts/set-local-plaid-mode.sh accounts-only
./scripts/run-local-backend.sh
./scripts/check-local-backend.sh
```

Confirm `/api/capabilities` reports Transactions disabled, transaction calls
fail calmly without replacing valid cached data, and the app continues to load
Dashboard, Set Aside, Plan Ahead, Payment Plans, and Settings.

Restore local Transactions mode:

```sh
./scripts/set-local-plaid-mode.sh transactions
./scripts/run-local-backend.sh
```

Do not make the equivalent Render change until Accounts-only Link support,
billing effects, reconnect behavior, and existing Item behavior are confirmed.
Render changes affect Release and TestFlight.

## Focused Testing

- Accounts and transaction records from multiple Items deduplicate by their
  Plaid identifiers.
- One Item's failure preserves usable cached data from other institutions and
  reports partial freshness.
- Incomplete transaction snapshots do not create recurring-expense or likely
  payment suggestions.
- Card-payment details fail calmly when the capability, institution data, or
  consent is unavailable.
- Plaid suggestions require review and do not silently overwrite user plans.
- Disconnect clears the intended backend Items and local linked-bank display
  data.
- Logs do not expose access or public tokens, account details, balances, or
  transaction descriptions.

Use [plaid-multi-institution-qa.md](plaid-multi-institution-qa.md) for the
specialized multi-institution manual checklist.

## Questions to Verify with Plaid

- Is productless Accounts-only Link supported under the active agreement?
- Which Link configuration or endpoint calls trigger billing for Transactions
  and liabilities?
- How are existing Items affected when a capability is disabled or expanded?
- Which account, transaction, and card-payment fields vary by institution?
- What consent or Link-update flow is required for card-payment details?
- Can account filters narrow eligible account types without enabling another
  product?
