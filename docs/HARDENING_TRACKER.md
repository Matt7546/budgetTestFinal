# Caldera hardening baseline

Baseline: `81c3285` on `main`. This is the backlog from the completed
read-only production-hardening audit, not a new audit or a claim that these
conditions were reproduced in production. Severity and evidence limitations
are preserved. F14 is the scoped validation-contract work in this branch.

| ID | Priority | Finding and evidence qualification | Status |
| --- | --- | --- | --- |
| F1 | P1 | Resolved Bills can still accept Set Aside; confirmed reachable source path, not simulator reproduced. `EventAllocationDetailView.swift`, `UpcomingExpenseActionPersistence.swift`. | Open |
| F2 | P1 | Backend Item removal races with a new link; production function reproduced in memory, no real provider contacted. `accountLifecycle.js`, `index.js`. | Open |
| F3 | P2 | Partial refresh preserves a missing account from a successfully refreshed Item; source confirmed. `PlaidService.swift`. | Open |
| F4 | P2 | Display metadata can deduplicate distinct account identities; conditional source defect, no live collision demonstrated. `FinancialSummaryHelpers.swift`. | Open |
| F5 | P2 | Handled Credit & Loans cycle may accept hidden protected money; reachable source inconsistency. `PaymentPlanUpdateState.swift`, `SetAsidePagerSnapshotBuilder.swift`. | Open |
| F6 | P2 | Duplicate Bill allocation/status records have conflicting selection policies; source confirmed, new duplicate creation not established. `EventAllocationTotals.swift`, `ExpenseOccurrenceStatus.swift`. | Open |
| F7 | P2 | Corrupt recommendation history becomes empty and can be overwritten; source confirmed. `RecurringExpenseRecommendationHistory.swift`. | Open |
| F8 | P2 | Missing card-payment amounts become zero; production sanitizer reproduced in memory. `cardPaymentDetails.js`. | Open |
| F9 | P2 | Reachable legacy Income editor reports completion without explicit save; source-level persistence gap, autosave failure not runtime reproduced. `AddPlannerEventView.swift`. | Open |
| F10 | P2 | Invalid persisted monetary values can appear as zero/unavailable funding; integrity risk, ordinary valid-input corruption path not shown. `SavingsGoalPersistence.swift`, `EventAllocationTotals.swift`. | Open |
| F11 | P2 | Saved sessions lack backend-environment binding; source gap, credential delivery not demonstrated and ATS may block current Debug HTTP. `KeychainSessionStore.swift`, `AuthManager.swift`. | Open |
| F12 | P2 | Backend defaults to personal auth/JSON storage; configuration risk, current production variables not inspected. `authConfig.js`, `plaidItemStore.js`. | Open |
| F13 | P2 | Webhook verification can call the provider before signature validation without route-specific bounding; source confirmed, edge protection unknown. `index.js`, `plaidWebhook.js`. | Open |
| F14 | P2 | Build-only validation, false-success wrapper, and skippable Postgres check; wrapper false success reproduced, absent release gates source confirmed. `validate-summary.sh`, `validate.sh`, `postgres-store-check.js`. | Validation-script and Postgres-test-safety implementation accepted by focused review. Wrapper regressions 3/3 and guard regressions 6/6 independently rerun successfully. Checkpoint commit pending; F14 remains open for later release hardening. |
| F15 | P2 | Release financial error diagnostics are sparse; source-confirmed operational gap. `AppLogger.swift`, `budgetTestApp.swift`. | Open |
| F16 | P3 | Xcode scheme/product identity and hard-coded test dylib paths are fragile; preexisting scheme churn observed, clean Release test failure not demonstrated. `project.pbxproj`, UI Validation scheme. | Open |
| F17 | P3 | Large views mix domain decisions, persistence, and presentation; source organization issue. Bill and Payment Plan editors. | Open |
| F18 | P3 | Historical audit, product rules, and readiness runbook contain stale or broader claims; source/documentation comparison. | Open |
| F19 | P3 | `SummaryViewModel` computes an incomplete available metric yet appears unconsumed in production; reference-tracing removal candidate, not a current Dashboard calculation defect. | Open |

No P0 finding was established in the baseline audit. Keep the source-confirmed,
controlled-reproduction, and runtime-unverified qualifiers when planning work.
See `VALIDATION_GUIDE.md` for what a green check can actually establish.

## Current slice

F14 validation-script and Postgres-test-safety implementation: accepted by
focused review. Wrapper regressions 3/3 and guard regressions 6/6 independently
rerun successfully. Checkpoint commit remains pending.

## Next implementation order

1. F1 — Reject Set Aside contributions to resolved Bill occurrences.
2. F2 — Correct concurrent linking versus unlink/account-deletion races. F2
   remains a separate backend slice.

## F14 remaining work

CI is not implemented; no tracked GitHub Actions workflow currently exists.
This remains an open F14 condition for later release hardening, outside the
current validation-script slice. F14 is not closed.

Complete backend-chain, real Express-composition, and iOS release execution
remain open validation gates. This slice did not mark them passed.
