# Caldera hardening baseline

Baseline: `81c3285` on `main`. This is the backlog from the completed
read-only production-hardening audit, not a new audit or a claim that these
conditions were reproduced in production. Severity and evidence limitations
are preserved. F14's validation-script/Postgres-safety checkpoint is `a9cbeb2`;
F1's accepted checkpoint is `7acb107`; F2's accepted checkpoint is `a56c7ab`;
F3's accepted checkpoint is `8e623f7`. F1–F3 and the F14 tooling slice
were integrated into local `main` at `e2b2274` without a push or deployment.
F4's accepted checkpoint is `0a5771a`; F5's accepted checkpoint is
`78386a8`; F6's accepted checkpoint is `b31b9b8`. F1–F6 are locally
integrated at `feddfd1` without a push or deployment. This branch is the
separate F7 slice.

| ID | Priority | Finding and evidence qualification | Status |
| --- | --- | --- | --- |
| F1 | P1 | Resolved Bills could still accept Set Aside; pre-fix defect was source-confirmed, not rendered-UI reproduced. `EventAllocationDetailView.swift`, `UpcomingExpenseActionPersistence.swift`. | Accepted by focused review. Ordinary Add, Cover in Full, and unified-editor funding reject resolved occurrences and failed status reads at the synchronous persistence boundary. Rejections make zero saves; valid $40 + $20 persists $60 once. Reviewer inspected the 137-test result and RC build; neither was rerun for acceptance. Fresh-context assertions used in-memory stores, not disk reopening or rendered UI. Accepted implementation is included in this checkpoint. |
| F2 | P1 | Backend Item removal races with a new link; production function reproduced in memory, no real provider contacted. `accountLifecycle.js`, `index.js`. | Accepted by focused corrective review and included in this checkpoint. Production exchange/removal fencing and exact Item cleanup remain in place; unresolved exchanges and recovery obligations block deletion success. Committed, definitely-not-committed, and uncertain save outcomes are distinguished before compensation. Exact durable Item/token/operation verification protects lost-acknowledgment handling. The reviewer inspected passing focused backend and isolated Postgres evidence, including a real COMMIT followed by lost acknowledgment; the earlier separate-count defect was source-confirmed, not rerun. The reviewer independently ran syntax and diff checks, not the full suites. JSON supports one writer process; Plaid calls in F2 tests were intercepted; an unestablished provider outcome remains blocked rather than automatically cleared. Full backend-chain and release validation remain outstanding milestone gates. |
| F3 | P2 | Partial refresh preserves a missing account from a successfully refreshed Item; source confirmed. `PlaidService.swift`. | Accepted by focused review and included in this checkpoint. Only verified successful Items receive membership replacement; failed/unknown Item caches remain preserved. Missing evidence does not authorize pruning, and contradictory evidence is rejected. The regression removed obsolete A/$200 while preserving B/$900; eligible cash and Available to Spend were $2,000 using the unchanged calculator. Owner/session/generation and account-collision protections remain intact. Reviewer inspected saved 44/44, 90/90, 6/6, and 22/22 results, backend Item-recovery/Express evidence, and RC build; did not rerun those suites, and counts overlap. The pre-fix simulator attempt stalled and was not a completed reproduction. Cache reload was same-process UserDefaults loading, not app relaunch or disk-migration evidence. |
| F4 | P2 | Display metadata can deduplicate distinct account identities; conditional source defect, no live collision demonstrated. `FinancialSummaryHelpers.swift`. | Accepted by focused corrective review and included in this checkpoint. Exact case-sensitive provider account IDs are authoritative; display metadata does not establish identity. Two distinct lookalike accounts survive and total $1,600 in either order; exact duplicate representations are retained once, while conflicting same-ID records are rejected rather than arbitrarily selected. F3 selective membership and failed-Item cache behavior remain intact; account inclusion preferences remain scoped to exact identity. Known rejected current-owner cache data is distinct from absent and valid cache data: it preserves original bytes, yields unavailable Bank Sync, and prevents an authoritative numeric Available to Spend. Valid zero balances and valid empty snapshots retain their normal zero behavior. A complete verified same-owner refresh restores the normal $1,600 presentation; transaction automation stays ineligible while bank data is rejected. The reviewer inspected the 89/89 and later 16/16 results (overlapping counts) and the final-source RC build, and independently ran `git diff --check`. Tests used intercepted transport and same-process cache state. They do not establish live Plaid behavior, app-relaunch persistence, migration, or rendered-UI behavior. Owner-unidentifiable corrupt bytes remain a separate limitation. Distinct real-world duplicate links across Items are not inferred from display metadata. No preference or payment-decision transfer is inferred from display metadata. |
| F5 | P2 | Handled Credit & Loans cycle may accept hidden protected money; reachable source inconsistency. `PaymentPlanUpdateState.swift`, `SetAsidePagerSnapshotBuilder.swift`. | Accepted by focused corrective review and included in this checkpoint. Handled-only plans cannot receive increased protection; valid active cycles and explicitly established next cycles can still receive funding. Final authorization uses current persisted owner/readiness/generation/cycle state, and any actual increase in the value to be persisted requires authorization; the old `> $0.005` tolerance is removed. $0.004/$0.005/$0.006 handled-cycle attempts reject before save. Unchanged-protection detail edits remain valid, and the legacy editor preserves an untouched existing fractional value. The $40 → Handle → attempted $20 case remains rejected. Set Aside and Available to Spend remain consistent with the unchanged formula. Reviewer inspected final 40/40 passing, zero-skip focused tests and the final-source RC simulator build, and independently ran `git diff --check`. The pre-fix fractional bypass was source-confirmed, not runtime-reproduced. Tests use production boundaries with in-memory persistence, not rendered UI or disk relaunch. Two-decimal presentation can still obscure a valid stored fractional-cent value; this non-blocking limitation is not fixed by F5. |
| F6 | P2 | Duplicate Bill allocation/status records have conflicting selection policies; source confirmed, new duplicate creation not established. `EventAllocationTotals.swift`, `ExpenseOccurrenceStatus.swift`. | Accepted and included in this checkpoint. Allocation and occurrence-status readers resolve by exact owner + occurrence identity. Equivalent duplicates count once; conflicting amounts, lifecycle values, source events, or dates are explicit conflicts rather than first/newest wins. Conflicts make planning and ATS non-authoritative rather than zero. Set Aside, Plan Ahead, Dashboard, mutation, reset/Undo, and Bill-payment decision paths use the same resolver policy. Ambiguous physical rows are preserved and cannot be arbitrarily edited, reset, deleted, or used for funding/release; confirmed Bill-payment provenance remains preserved. No uniqueness annotation, schema migration, occurrence-ID change, or automatic duplicate repair was introduced. Reviewer inspected the saved final-source 265/265 passing, zero-skip result and successful RC simulator build, and independently ran `git diff --check`. File-backed reopen proved the tested contradictory rows survive reopen; it is not a historical migration. The pre-fix divergence was source-confirmed, not runtime-reproduced. No rendered-UI, live-user duplicate-provenance, or in-app repair proof. The MainActor traversal-counter correction is test-only. |
| F7 | P2 | Corrupt recommendation history becomes empty and can be overwritten; source confirmed. `RecurringExpenseRecommendationHistory.swift`. | Accepted by focused corrective review and included in this checkpoint. History distinguishes absent, valid, corrupt/unavailable, unsupported-version, and wrong-owner states. Unavailable history preserves its original bytes and cannot be overwritten as empty; suggestions fail closed when prior decision state is unknown. Payment matching requires exact `.added` provenance. Pending acceptance is reconciled against a fresh authoritative planning read: exact Bill presence completes pending → added; authoritative absence releases only that pending record for explicit retry; read failure, unavailable planning, conflicting identity, or owner change leaves pending fenced. Dismiss and Review Again remain bound to the owner/session that created them and cannot retarget to a newly signed-in owner. Pending history cannot authorize payment matching or Set Aside release. Reviewer inspected saved 97/97 passing, zero-skip focused tests and the successful RC simulator build, and independently ran `git diff --check`. Tests use isolated UserDefaults and fresh in-memory SwiftData contexts; no rendered callback/UI, app relaunch, crash-durable UserDefaults, or live provider proof. SwiftData and UserDefaults are not atomic. |
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

F3 partial-refresh membership correction was accepted by focused review and
checkpointed at `8e623f7`. Only verified successful Items replace membership;
failed/unknown Item caches remain preserved. F1–F3 and the F14 tooling slice
are integrated in local `main` at `e2b2274`; this does not satisfy F14's
remaining CI, network-containment, or release gates.

F4 exact account-identity and rejected-cache presentation corrections are
accepted by focused review and included in this checkpoint. The pre-fix primary
service regression completed with the wrong total in either account order.
Focused tests cover same-Item and cross-Item lookalikes, case-distinct IDs,
duplicate/conflicting identity handling, malformed padded IDs, same-ID
updates, verified same-Item
replacement, cache reload, exclusions, F3 membership, and transaction
provenance. The final-source Item-recovery/malformed-account run passed 60/60;
the new replacement regression passed 1/1; selected cache/provenance checks
passed 11/11; the RC simulator build passed. Calculation and Bill-matching
checks passed 91/91 before the final decoder-only guard change, with the
directly affected malformed-account suite included in the final 60/60 run.
Counts overlap and are not additive coverage. Test evidence is synthetic and
same-process; it does not establish live-provider behavior, app-relaunch
persistence, or a verified relationship between distinct Items. No new
preference/history migration or display-based relink inference is part of F4.

The F4 rejected-cache corrective slice also exercises the actual cache-seeded
service initialization and Dashboard presentation decision. Known
current-owner cache conflicts and owner-identifiable unreadable snapshots are
unavailable, whereas
genuine absence, a valid zero balance, and a valid empty snapshot retain their
existing zero presentation. Failed and partial refreshes preserve raw bytes and
the unavailable state; verified complete same-owner recovery restores the
$1,600 result. Stale-generation and other-owner checks preserve isolation.
The affected Dashboard/cache suite passed 89/89, a later selected
cache/provenance/automation run passed 16/16 after the final test additions,
and the final-source RC simulator build passed. Test counts overlap and are
not additive. The reviewer independently ran `git diff --check`. The tests
used injected catch-all transport and same-process UserDefaults, not live
Plaid, app relaunch, migration, or a rendered Dashboard. Owner-unidentifiable
corrupt cache bytes remain a separate limitation; no cross-Item replacement
is inferred from display fields. F4 is accepted and included in this
checkpoint.

F5 is accepted and included in this checkpoint. Ordinary modern and legacy
editor Save actions require the existing persisted payment-plan snapshot
authorization before mutation. The update coordinator rejects increased
bucket protection when a handled cycle has no valid active replacement, while
allowing a genuinely cycleless legacy plan or an explicitly established valid
next cycle. Rejection returns failure before a save or mutation, leaving
existing handle/release semantics and the Available to Spend formula
unchanged. A same-period replacement is rejected even if calendar-dependent
cycle keys differ; explicit Plan Next Payment can establish a valid new cycle
and then accept funding. Earlier focused results were 54/54 and adjacent
Payment Plan, Set Aside, ATS, and stale/Undo checks were 196/196, both with no
skips; these are separate, overlapping runs, not an app-wide suite. The
fractional-increase correction also passed its final focused 40/40 test run
with no skips and final-source RC simulator build. The pre-fix lifecycle and
fractional bypasses were source-confirmed, not runtime-reproduced. Tests use
in-memory persistence and intercepted/no-network paths, not rendered UI or
disk migration. F5 is accepted and checkpointed here.

Credit & Loans `protectedAmount` is currently an unquantized
SwiftData `Double`: `MoneyAmountParser` accepts fractional cents, the editor
draft writes that value directly, and Set Aside/Available to Spend arithmetic
uses the stored value without cent rounding. Two-decimal UI formatting is not
a persistence contract. The previous `> $0.005` increase test therefore let
an actual $0.004 or $0.005 increase survive a handled cycle with no valid
replacement. The persistence boundary now authorizes against the exact
proposed stored `Double` versus the current stored `Double`; any positive
persisted delta requires the existing active/legacy/new-cycle authorization.
The modern editor recognizes a fractional Add when it actually changes the
projected stored value. An untouched legacy amount field retains its original
stored value during detail-only edits despite two-decimal display. Focused
regressions cover legacy and modern $0.004/$0.005/$0.006, cent-sized active
Add, unchanged-protection details, the existing $40 → Handle → attempted $20
case, and raw Set Aside/ATS arithmetic. This correction does not retroactively
repair fractional protection already stored by earlier builds, change the
global parser, or introduce cent quantization. The final-source focused Debug
Local simulator run passed 40/40 with no skips, including production action
authorization, the legacy editor's saved-value selection, Payment Plan editor
and persistence cases, and adjacent financial calculation. The reviewer
inspected this result and the final-source Release Candidate simulator build,
and independently ran `git diff --check`. These are focused
in-memory/intercepted checks, not rendered-UI, disk-migration, backend, or
release certification. The old sub-cent bypass was source-confirmed rather
than runtime-reproduced before correction. Two-decimal presentation can still
obscure a valid stored fractional-cent value; this remains a non-blocking
limitation outside the F5 correction. F5 is accepted and included in this
checkpoint.

F6 is accepted and included in this checkpoint. The implementation preserves
physical duplicate rows. Equivalent allocation rows count once; equivalent
status rows express one lifecycle state. Conflicting amount, status, source
event, or occurrence date is not resolved by collection order or `updatedAt`.
Planning presentation and financial mutation fail closed while contradictory
rows remain. No persisted model, property, or occurrence identity changed.
The final-source affected iOS suites passed 265/265 with zero skips on an
iOS 26.1 simulator, including production funding/action/transaction consumers,
Set Aside, ATS, Review Updates, and a disposable file-backed reopen of
contradictory rows. The Release Candidate simulator build and `git diff --check`
passed. Earlier attempts had two large lookup tests crash in a test-only
MainActor traversal-counter deinitializer; making that counter nonisolated
resolved the repeatable runtime crash, and both cases passed in the final run.
The pre-fix divergence was source-confirmed, not runtime-reproduced. The
file-backed reopen is not historical migration evidence; no rendered UI,
live-user duplicate provenance, or in-app repair flow was tested. No automatic
cleanup of persisted duplicates or user-facing repair UI is included.

F7 is accepted by focused corrective review and included in this checkpoint.
`absent` alone behaves as new-empty history; valid history is distinct from
corrupt/unavailable, unsupported-version, and wrong-owner states. Unavailable
history bytes are preserved and cannot be overwritten as empty. Recommendation
suggestions fail closed when prior decision state is unknown, and payment
matching requires exact `.added` provenance. Acceptance records the owner,
recommendation identity, and intended Bill UUID before saving the Bill. After
the synchronous save attempt settles, a fresh SwiftData context confirms an
exact owned expense as `added`; authoritative absence removes only that exact
pending record and permits an explicit retry. Read failure, unavailable
planning, conflicting identity, or owner change leaves pending fenced. Dismiss
and Review Again callbacks capture the presenting owner and session fingerprint
and cannot retarget a newly signed-in owner. Pending history does not authorize
payment matching or Set Aside release and receives attention presentation
rather than ordinary empty-state reassurance.

The reviewer inspected the saved final-source 97/97 passing, zero-skip focused
result and successful RC simulator build, and independently ran
`git diff --check`. Tests use isolated UserDefaults and fresh in-memory
SwiftData contexts. They do not establish rendered callback/UI behavior, app
relaunch, crash-durable UserDefaults behavior, or live provider behavior.
SwiftData and UserDefaults are not atomic. No backend, Sandbox, or production
environment was exercised. F14's containment and release gates remain open.

## Next implementation order

1. F8 — Keep missing card-payment amounts distinct from real zero.

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
