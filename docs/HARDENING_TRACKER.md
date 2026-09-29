# Caldera hardening baseline

Baseline: `81c3285` on `main`. This is the backlog from the completed
read-only production-hardening audit, not a new audit or a claim that these
conditions were reproduced in production. Severity and evidence limitations
are preserved. F14's validation-script/Postgres-safety checkpoint is `a9cbeb2`;
F1's accepted checkpoint is `7acb107`; F2's accepted checkpoint is `a56c7ab`.
This branch is the separate F3 slice.

| ID | Priority | Finding and evidence qualification | Status |
| --- | --- | --- | --- |
| F1 | P1 | Resolved Bills could still accept Set Aside; pre-fix defect was source-confirmed, not rendered-UI reproduced. `EventAllocationDetailView.swift`, `UpcomingExpenseActionPersistence.swift`. | Accepted by focused review. Ordinary Add, Cover in Full, and unified-editor funding reject resolved occurrences and failed status reads at the synchronous persistence boundary. Rejections make zero saves; valid $40 + $20 persists $60 once. Reviewer inspected the 137-test result and RC build; neither was rerun for acceptance. Fresh-context assertions used in-memory stores, not disk reopening or rendered UI. Accepted implementation is included in this checkpoint. |
| F2 | P1 | Backend Item removal races with a new link; production function reproduced in memory, no real provider contacted. `accountLifecycle.js`, `index.js`. | Accepted by focused corrective review and included in this checkpoint. Production exchange/removal fencing and exact Item cleanup remain in place; unresolved exchanges and recovery obligations block deletion success. Committed, definitely-not-committed, and uncertain save outcomes are distinguished before compensation. Exact durable Item/token/operation verification protects lost-acknowledgment handling. The reviewer inspected passing focused backend and isolated Postgres evidence, including a real COMMIT followed by lost acknowledgment; the earlier separate-count defect was source-confirmed, not rerun. The reviewer independently ran syntax and diff checks, not the full suites. JSON supports one writer process; Plaid calls in F2 tests were intercepted; an unestablished provider outcome remains blocked rather than automatically cleared. Full backend-chain and release validation remain outstanding milestone gates. |
| F3 | P2 | Partial refresh preserves a missing account from a successfully refreshed Item; source confirmed. `PlaidService.swift`. | Accepted by focused review and included in this checkpoint. Only verified successful Items receive membership replacement; failed/unknown Item caches remain preserved. Missing evidence does not authorize pruning, and contradictory evidence is rejected. The regression removed obsolete A/$200 while preserving B/$900; eligible cash and Available to Spend were $2,000 using the unchanged calculator. Owner/session/generation and account-collision protections remain intact. Reviewer inspected saved 44/44, 90/90, 6/6, and 22/22 results, backend Item-recovery/Express evidence, and RC build; did not rerun those suites, and counts overlap. The pre-fix simulator attempt stalled and was not a completed reproduction. Cache reload was same-process UserDefaults loading, not app relaunch or disk-migration evidence. |
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
| F14 | P2 | Build-only validation, false-success wrapper, and skippable Postgres check; wrapper false success reproduced, absent release gates source confirmed. `validate-summary.sh`, `validate.sh`, `postgres-store-check.js`. | Validation-script and Postgres-test-safety implementation accepted by focused review and checkpointed at `a9cbeb2`. CI and release execution remain open. |
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
focused review and checkpointed at `a9cbeb2`. Wrapper regressions 3/3 and
guard regressions 6/6 independently reran successfully. F1's resolved-Bill
contribution correction was accepted by focused review and checkpointed at
`7acb107`. The reviewer inspected the 137-test result and RC build without
rerunning them. Fresh-context assertions used in-memory stores, not disk
reopening or rendered UI evidence.

F2 Item lifecycle race correction was accepted by focused corrective review
and checkpointed at `a56c7ab`. Its bounded implementation uses exact Item
removal, a persisted exchange lease and owner lifecycle gate, and encrypted
owner-scoped recovery for an exchanged token whose compensating provider
removal is uncertain. The committed-save correction verifies the exact durable
Item/token/operation before acknowledgment; a definitely uncommitted save may
use existing compensation, while unknown outcomes retain the lease and block
deletion. Acceptance inspected passing focused backend and isolated Postgres
evidence, including a real COMMIT followed by lost acknowledgment. The reviewer
independently ran syntax and diff checks, not the full suites. JSON supports one
writer process; F2 Plaid calls were intercepted; an unestablished provider
outcome remains blocked instead of automatically cleared. Full backend-chain
and release validation remain open milestone gates. The procedure does not
promise that Plaid can reconstruct an unrecorded access token.

## Next implementation order

1. F4 — Review display-based deduplication of distinct account identities.
   F4 follows the accepted F3 checkpoint.

## F14 remaining work

CI is not implemented; no tracked GitHub Actions workflow currently exists.
This remains an open F14 condition for later release hardening, outside the
current validation-script slice. F14 is not closed.

Test-network containment follow-up: add an explicit interception assertion to
the selected disconnect test and make test endpoint setup fail closed before
broad tests are relied on as network-containment evidence. Final selected tests
inject catch-all URL-protocol sessions, but the older disconnect test does not
explicitly assert interception. The earlier Debug Local Sandbox request's
receipt and side effects remain unknown; no claim is made that no request
escaped.

Complete backend-chain, broader Express-composition, and iOS release execution
remain open validation gates. The F2 route-level Express check is focused and
does not mark those release gates passed. CI, network containment, and release
execution work remain open under F14.
