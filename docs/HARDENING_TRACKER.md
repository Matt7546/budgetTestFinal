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
integrated at `feddfd1` without a push or deployment. F7–F10 were accepted and
locally integrated at `ad084715` without push/deployment. F12 was accepted and
locally checkpointed at `f4d91f5`; F13 is accepted/checkpointed at `cf075d8`.
F14-A/V11 is accepted and checkpointed at `7301b821`; F14-B is accepted and
checkpointed at `79d8cf32`. This runtime branch starts from that exact accepted
local commit, not from `origin/main`. The intended F11 implementation and direct
tests are mechanically ported from the pending nine-path diff in the separate
environment-scoped-sessions worktree. Runtime Hardening Slice 1 is accepted and
checkpointed. F11 and V12 are accepted and V13 is closed. V14's ordinary
production-graph crash evidence is checkpointed at `eb599d1`. The authorized
Dashboard ambient-animation removal is accepted and V14 is closed for simulator
compatibility after the final 26.1 and 26.5 matrix and RC arm64 build passed.
Physical 26.1 release evidence remains outstanding. V15's mounted-fixture
lifetime correction is ACCEPTED/CLOSED and included in this checkpoint.
Both original worktrees and their existing pending work remain preserved.

| ID | Priority | Finding and evidence qualification | Status |
| --- | --- | --- | --- |
| F1 | P1 | Resolved Bills could still accept Set Aside; pre-fix defect was source-confirmed, not rendered-UI reproduced. `EventAllocationDetailView.swift`, `UpcomingExpenseActionPersistence.swift`. | Accepted by focused review. Ordinary Add, Cover in Full, and unified-editor funding reject resolved occurrences and failed status reads at the synchronous persistence boundary. Rejections make zero saves; valid $40 + $20 persists $60 once. Reviewer inspected the 137-test result and RC build; neither was rerun for acceptance. Fresh-context assertions used in-memory stores, not disk reopening or rendered UI. Accepted implementation is included in this checkpoint. |
| F2 | P1 | Backend Item removal races with a new link; production function reproduced in memory, no real provider contacted. `accountLifecycle.js`, `index.js`. | Accepted by focused corrective review and included in this checkpoint. Production exchange/removal fencing and exact Item cleanup remain in place; unresolved exchanges and recovery obligations block deletion success. Committed, definitely-not-committed, and uncertain save outcomes are distinguished before compensation. Exact durable Item/token/operation verification protects lost-acknowledgment handling. The reviewer inspected passing focused backend and isolated Postgres evidence, including a real COMMIT followed by lost acknowledgment; the earlier separate-count defect was source-confirmed, not rerun. The reviewer independently ran syntax and diff checks, not the full suites. JSON supports one writer process; Plaid calls in F2 tests were intercepted; an unestablished provider outcome remains blocked rather than automatically cleared. Full backend-chain and release validation remain outstanding milestone gates. |
| F3 | P2 | Partial refresh preserves a missing account from a successfully refreshed Item; source confirmed. `PlaidService.swift`. | Accepted by focused review and included in this checkpoint. Only verified successful Items receive membership replacement; failed/unknown Item caches remain preserved. Missing evidence does not authorize pruning, and contradictory evidence is rejected. The regression removed obsolete A/$200 while preserving B/$900; eligible cash and Available to Spend were $2,000 using the unchanged calculator. Owner/session/generation and account-collision protections remain intact. Reviewer inspected saved 44/44, 90/90, 6/6, and 22/22 results, backend Item-recovery/Express evidence, and RC build; did not rerun those suites, and counts overlap. The pre-fix simulator attempt stalled and was not a completed reproduction. Cache reload was same-process UserDefaults loading, not app relaunch or disk-migration evidence. |
| F4 | P2 | Display metadata can deduplicate distinct account identities; conditional source defect, no live collision demonstrated. `FinancialSummaryHelpers.swift`. | Accepted by focused corrective review and included in this checkpoint. Exact case-sensitive provider account IDs are authoritative; display metadata does not establish identity. Two distinct lookalike accounts survive and total $1,600 in either order; exact duplicate representations are retained once, while conflicting same-ID records are rejected rather than arbitrarily selected. F3 selective membership and failed-Item cache behavior remain intact; account inclusion preferences remain scoped to exact identity. Known rejected current-owner cache data is distinct from absent and valid cache data: it preserves original bytes, yields unavailable Bank Sync, and prevents an authoritative numeric Available to Spend. Valid zero balances and valid empty snapshots retain their normal zero behavior. A complete verified same-owner refresh restores the normal $1,600 presentation; transaction automation stays ineligible while bank data is rejected. The reviewer inspected the 89/89 and later 16/16 results (overlapping counts) and the final-source RC build, and independently ran `git diff --check`. Tests used intercepted transport and same-process cache state. They do not establish live Plaid behavior, app-relaunch persistence, migration, or rendered-UI behavior. Owner-unidentifiable corrupt bytes remain a separate limitation. Distinct real-world duplicate links across Items are not inferred from display metadata. No preference or payment-decision transfer is inferred from display metadata. |
| F5 | P2 | Handled Credit & Loans cycle may accept hidden protected money; reachable source inconsistency. `PaymentPlanUpdateState.swift`, `SetAsidePagerSnapshotBuilder.swift`. | Accepted by focused corrective review and included in this checkpoint. Handled-only plans cannot receive increased protection; valid active cycles and explicitly established next cycles can still receive funding. Final authorization uses current persisted owner/readiness/generation/cycle state, and any actual increase in the value to be persisted requires authorization; the old `> $0.005` tolerance is removed. $0.004/$0.005/$0.006 handled-cycle attempts reject before save. Unchanged-protection detail edits remain valid, and the legacy editor preserves an untouched existing fractional value. The $40 → Handle → attempted $20 case remains rejected. Set Aside and Available to Spend remain consistent with the unchanged formula. Reviewer inspected final 40/40 passing, zero-skip focused tests and the final-source RC simulator build, and independently ran `git diff --check`. The pre-fix fractional bypass was source-confirmed, not runtime-reproduced. Tests use production boundaries with in-memory persistence, not rendered UI or disk relaunch. Two-decimal presentation can still obscure a valid stored fractional-cent value; this non-blocking limitation is not fixed by F5. |
| F6 | P2 | Duplicate Bill allocation/status records have conflicting selection policies; source confirmed, new duplicate creation not established. `EventAllocationTotals.swift`, `ExpenseOccurrenceStatus.swift`. | Accepted and included in this checkpoint. Allocation and occurrence-status readers resolve by exact owner + occurrence identity. Equivalent duplicates count once; conflicting amounts, lifecycle values, source events, or dates are explicit conflicts rather than first/newest wins. Conflicts make planning and ATS non-authoritative rather than zero. Set Aside, Plan Ahead, Dashboard, mutation, reset/Undo, and Bill-payment decision paths use the same resolver policy. Ambiguous physical rows are preserved and cannot be arbitrarily edited, reset, deleted, or used for funding/release; confirmed Bill-payment provenance remains preserved. No uniqueness annotation, schema migration, occurrence-ID change, or automatic duplicate repair was introduced. Reviewer inspected the saved final-source 265/265 passing, zero-skip result and successful RC simulator build, and independently ran `git diff --check`. File-backed reopen proved the tested contradictory rows survive reopen; it is not a historical migration. The pre-fix divergence was source-confirmed, not runtime-reproduced. No rendered-UI, live-user duplicate-provenance, or in-app repair proof. The MainActor traversal-counter correction is test-only. |
| F7 | P2 | Corrupt recommendation history becomes empty and can be overwritten; source confirmed. `RecurringExpenseRecommendationHistory.swift`. | Accepted by focused corrective review and included in this checkpoint. History distinguishes absent, valid, corrupt/unavailable, unsupported-version, and wrong-owner states. Unavailable history preserves its original bytes and cannot be overwritten as empty; suggestions fail closed when prior decision state is unknown. Payment matching requires exact `.added` provenance. Pending acceptance is reconciled against a fresh authoritative planning read: exact Bill presence completes pending → added; authoritative absence releases only that pending record for explicit retry; read failure, unavailable planning, conflicting identity, or owner change leaves pending fenced. Dismiss and Review Again remain bound to the owner/session that created them and cannot retarget to a newly signed-in owner. Pending history cannot authorize payment matching or Set Aside release. Reviewer inspected saved 97/97 passing, zero-skip focused tests and the successful RC simulator build, and independently ran `git diff --check`. Tests use isolated UserDefaults and fresh in-memory SwiftData contexts; no rendered callback/UI, app relaunch, crash-durable UserDefaults, or live provider proof. SwiftData and UserDefaults are not atomic. |
| F8 | P2 | Missing card-payment amounts become zero; production sanitizer reproduced in memory. `cardPaymentDetails.js`. | Accepted and included in this checkpoint. The backend accepts only finite JavaScript numbers: real zero remains numeric zero; null, omitted values, strings (including numeric strings), booleans, arrays/objects, NaN, and infinities become explicit null across all five affected card-payment fields. Serialized responses preserve null versus zero. iOS DTOs decode the fields as optional Double; nil and zero do not become provider payment targets under current rules, unavailable details do not overwrite a saved user target, and Cover in Full remains based on saved plan/cycle state. |
| F9 | P2 | Reachable legacy Income editor reports completion without explicit save; source-level persistence gap, autosave failure not runtime reproduced. `AddPlannerEventView.swift`. | Accepted by focused review and included in this checkpoint. The reachable legacy Income editor explicitly saves before success. Edit and delete validate owner, planning readiness/generation, prepared event identity, and exact persisted row before mutation. Each action performs one explicit `ModelContext.save()`; success callback/dismissal follows only after save succeeds. Edit failure restores original persisted fields and rolls back; delete failure rolls back the Income event and related `EventAllocation` / `ExpenseOccurrenceStatus` records. Stale owner/generation, failed reads, and repeated completed actions reject. Recommendation-creation persistence and F7 history ordering remain unchanged. Reviewer inspected saved 42/42 focused tests and overlapping final 4/4 F9 rerun, successful final-source RC build, and file-backed reopen evidence; reviewer independently ran Swift parsing and `git diff --check`. Tests exercise the production coordinator, not rendered/tapped UI. Save failures were injected, not caused by a storage-device fault. |
| F10 | P2 | Invalid persisted monetary values can appear as zero/unavailable funding; integrity risk, ordinary valid-input corruption path not shown. `SavingsGoalPersistence.swift`, `EventAllocationTotals.swift`. | Accepted and included in this checkpoint. Persisted Cushion and Goal protection reject invalid values before planning becomes available; negative Bill allocations are integrity conflicts under F6. Corrupt rows remain stored, reads do not repair or delete them, financial mutations fail closed, and ATS / Set Aside / Plan Ahead suppress authoritative presentation. Legacy adoption does not normalize invalid protection. Legacy `reserve_balance` imports only numeric, non-Boolean, finite, nonnegative values; negative input is rejected before any write, no ownerless/owned $0 row replaces it, and the original key/value remains. Positive and real-zero values import unchanged; the key retires only after a successful valid import. Owner B's valid owned Cushion remains available, while an explicit valid owned Cushion can restore A without silently removing the invalid legacy key. Reviewer inspected saved 7/7 legacy and 25/25 Cushion/presentation results and the successful corrected-source RC build, and independently ran `git diff --check`. The prior 224/224 focused run remains supporting evidence. The pre-fix negative legacy defect was source-confirmed, not runtime-reproduced. Reload used a second in-memory context/service; no app-relaunch, raw UserDefaults-byte, rendered-UI, NaN-on-disk, or in-app repair-flow proof. |
| F11 | P2 | Saved sessions lack backend-environment binding; source gap, credential delivery not demonstrated and ATS may block current Debug HTTP. `KeychainSessionStore.swift`, `AuthManager.swift`. | ACCEPTED in Runtime Hardening Slice 1. Stable backend-environment identity, scoped Keychain namespace, legacy-token quarantine, scoped restore/sign-in/sign-out, stale environment/operation/session rejection, and deletion durability remain intact. Final focused execution passed 26 auth/configuration, 24 deletion, two auth/owner-expiry, and one real Security.framework sentinel case without skips. Exact auth tasks settle and ten repeated weak-reference checks prove manager/store release. V14 simulator compatibility and V15 mounted-fixture lifetime correction are accepted; physical iOS 26.1 release qualification remains open. |
| F12 | P2 | Backend defaults to personal auth/JSON storage; configuration risk, current production variables not inspected. `authConfig.js`, `plaidItemStore.js`. | Accepted by focused review and checkpointed at `f4d91f5`. Deployed operation fails closed unless explicitly configured; Render, production NODE_ENV, and production Plaid signals cannot be weakened by local flags, and unclassified Sandbox operation rejects. Deployed startup requires `AUTH_MODE=required`, `TOKEN_STORE_DRIVER=postgres`, disabled development auth, and valid database, encryption, app/API, provider, and Apple authentication configuration. Missing or malformed prerequisites fail before server composition/listen and diagnostics do not log secret values. Personal/JSON compatibility remains available only for explicitly classified development/test use. Existing migrated Postgres databases remain supported; fresh/empty database restrictions apply only to the guarded test harness. Reviewer inspected saved 31/31 startup and 6/6 Postgres guard results, both zero-skip, plus passing affected auth, crypto, user-scope, deletion, lifecycle, and rate-limit evidence. Reviewer independently ran malformed-key and explicit/unknown-identity policy checks, syntax checks, source-hash verification, and `git diff --check`; no database was provisioned during acceptance. Live Render variables, credential validity, full backend-chain, and release validation remain unverified. |
| F13 | P2 | Webhook verification can call the provider before signature validation without route-specific bounding; source confirmed, edge protection unknown. `index.js`, `plaidWebhook.js`. | Accepted by focused corrective review and included in this checkpoint. Admission precedes expensive verification; raw request/header bounds, ES256, JWT age, verified raw-body SHA-256, and exact JWK validation remain required. The public-key cache is bounded to 16 entries with a five-minute TTL or earlier provider expiration. Same-kid calls share one fetch; provider fetches are bounded to two, with a three-second timeout, 16 KiB response cap, redirects disabled, and no internal retries. The admission budget remains 300 attempts/minute and 32 open requests. A separate pool caps retained verification callers at 32; client disconnect does not release its permit, which releases exactly once when verification settles. Saturation queues neither verification nor key work and cannot mutate readiness. Already-started valid disconnected deliveries retain existing idempotent behavior. Prior review reproduced 33 retained callers before correction. Corrected default-limit Express regression ran eight disconnect/replacement rounds: peak retained work 32, each replacement rejected with 503, same-kid provider fetch count one, invalid requests caused zero readiness writes, and final retained verification/provider-fetch/open-request counts were all zero. Reviewer inspected the earlier 29/29 zero-skip webhook result and passing rate-limit/readiness evidence, independently reran the exact churn regression, and ran seven syntax checks plus `git diff --check`. The selected rerun's 28 name-filter skips are not passing coverage. Prior startup evidence was reused, not rerun. No live Plaid, database, iOS, full backend chain, or deployment validation. All bounds remain per process; Render edge and slow-body protections remain unverified. |
| F14 | P2 | Build-only validation, false-success wrapper, and skippable Postgres check; wrapper false success reproduced, absent release gates source confirmed. `validate-summary.sh`, `validate.sh`, `postgres-store-check.js`. | Validation-script and Postgres-test-safety slice checkpointed at `a9cbeb2`; F14-A/V11 closed and checkpointed at `7301b821`; tracked CI and exact-candidate infrastructure accepted/checkpointed in F14-B at `79d8cf32`. Runtime Slice 1 is accepted/checkpointed: F11 and V12 accepted and V13 closed. V14's production crash regression is checkpointed at `eb599d1`; production ambient-animation removal is accepted and V14 is closed for simulator compatibility after the 26.1/26.5 matrix and RC arm64 build passed. V15 mounted-fixture lifetime correction is accepted/closed. Physical iOS 26.1 release qualification remains open. Hosted CI and final exact-candidate aggregate release execution remain open. F14 is PARTLY OPEN. |
| F15 | P2 | Release financial error diagnostics are sparse; source-confirmed operational gap. `AppLogger.swift`, `budgetTestApp.swift`. | Open |
| F16 | P3 | Xcode scheme/product identity and hard-coded test dylib paths are fragile; preexisting scheme churn observed, clean Release test failure not demonstrated. `project.pbxproj`, UI Validation scheme. | Open |
| F17 | P3 | Large views mix domain decisions, persistence, and presentation; source organization issue. Bill and Payment Plan editors. | Open |
| F18 | P3 | Historical audit, product rules, and readiness runbook contain stale or broader claims; source/documentation comparison. | Open |
| F19 | P3 | `SummaryViewModel` computes an incomplete available metric yet appears unconsumed in production; reference-tracing removal candidate, not a current Dashboard calculation defect. | Open |

No P0 finding was established in the baseline audit. Keep the source-confirmed,
controlled-reproduction, and runtime-unverified qualifiers when planning work.
See `VALIDATION_GUIDE.md` for what a green check can actually establish.

## V15 mounted-fixture lifetime correction — ACCEPTED / CLOSED

Correction baseline: `4265b721d4df3576b2d0a112f546c39acb296251`, on
`hardening/v15-swiftdata-model-lifetime`. Only mounted test/support code and
this tracker changed. The pure fatal diagnostic remains unchanged. Production
source, financial assertions, ownership/generation rules, editor routes,
SwiftData schemas, and persistence behavior did not change. No F15 work.

The defective teardown merely hid its UIWindow and let local fixture owners
expire while the actual SavingsGoalsView editor/sheet still retained a
main-context DebtPayoffBucket. The owning ModelContainer died first; later
legacy `bucket.id` or modern `protectedAmount` access trapped. Production-like
fixtures retaining storage through graph destruction did not reproduce that
invalidation.

One structured MainActor fixture owner now retains container, mainContext,
AuthManager, PlaidService, navigation, validation control, and sentinel session
store through the complete host lifetime. Its single cleanup path:

1. Dismisses the actual presented UIKit sheet and observes completion plus the
   editor's real disappearance trace (or already-completed disappearance).
2. Cancels/settles outstanding controlled Hold tasks after disappearance; an
   unreleased callback must make no persistence attempt during cleanup.
3. Detaches the root/host, then awaits explicit graph disappearance,
   dismantling/coordinator destruction, actual host/sheet destruction, and weak
   nil while container/context are still retained. Hiding the window or clearing
   its root alone is not considered completion.
4. Releases window and editor/view references, then service/auth/navigation
   dependencies, then context/container references last. All expected weak
   references, including captured editor models, must clear without reading an
   invalidated model property.

The body executes in a separate awaited frame so its local references finish
before final cleanup. Success, rejected callback/persistence results, failed
financial assertions, thrown errors, and possible timeout/cancellation exits
use this same cleanup. Errors are rethrown after cleanup; assertion failures are
not cleared. Lifecycle waits are bounded to ten seconds and observe real events,
not sleeps, fixed queue turns, yield loops, or indefinite retention. An unmet
cleanup precondition fails the isolated process while storage is retained rather
than releasing live storage and calling that safe.

### Executed correction evidence

Evidence is retained outside Git at
`/private/tmp/caldera-v15-correction-0GKDoWPs/`, including the contained runner,
logs, XCResults and exported summaries, exact test-source copies/hashes,
`correction-summary.json`, and the supplied diagnostic crash report. Toolchain:
Xcode 27.0 (27A266a); disposable iPhone 17 Pro Max / iOS 26.1 (23B86),
UUID `00955D4E-83BA-4D5B-B01D-68D75A0A201B`.
Only that task-created simulator was shut down/deleted after evidence collection;
other simulators, protected worktrees, and the preserved scheme stash were not changed.

| Selection / log label | Result and qualification |
| --- | --- |
| `legacy-individual-build` | Original legacy callback-before-observer regression passed; PID 25396. Original rejection/persisted-$275 assertions and weak-release checks retained. This built the contained Debug test binary, not RC. |
| `modern-individual` | Original modern verified-command/view-only-failure regression passed; PID 25574. Original persisted-$900 / one-save assertions retained. |
| `combined-same-process` | Both original regressions passed in one process, PID 25711; 2 executions. |
| `five-same-process` | Each original regression passed five times, 10 executions with relaunch disabled, all PID 25766. Repeated coverage, not ten unique behaviors. |
| `fresh-process-1`, `-2`, `-3` | Both originals passed in each fresh process: PIDs 25984, 25998, 26024; 2 executions per process. |
| `affected-mounted` | Five additional directly affected mounted tests passed, including healthy legacy one-save, query failure/recovery/fresh Hold, uncontrolled callback ordering, modern rejection, and every required command-read failure. The last test exercises six required-read domains. |
| `cleanup-contracts` | Four contracts completed: thrown error with queued Hold, cancellation, strict expected financial-assertion failure, and strict expected body timeout. XCResult reports 2 ordinary passes + 2 verified expected-failure contracts, zero unexpected failures/skips; runner exit 0. The deliberate 0.1-second unfulfilled body expectation tests a timeout exit, not teardown timing. |
| `retained-controls` | All nine unchanged production-like controls passed: both editor routes with ordinary context saves; both owner replacements; dismiss-before-owner; both required-read rollback/recovery routes; Cover save-failure rollback; exact delete-before-dismiss store-order probe. |

Every non-diagnostic selection returned zero, with no unexpected failure/skip or
network request and no V15 invalid-model or V14 isolated-deinit / TaskLocal crash.
The evidence collector checked actual destruction-event order, weak-release
completion, source hashes, and process identity. The actual SavingsGoalsView and
both editor routes remain in use; no synthetic replacement view weakened the
original regressions. Repetition counts overlap and are not added to unique
coverage.

The unchanged `testFMainContextContainerReleaseInMemory` diagnostic ran alone in
a fresh process (PID 26080). It observed owning-container destruction with exact
mainContext/model still retained, then deliberately read `DebtPayoffBucket.id`:
the expected SwiftData invalidation trap returned runner exit 65. The supplied
crash report identifies the exact diagnostic probe, not a corrected editor
failure. This is failing diagnostic evidence, never ordinary passing or release
coverage; Xcode's subsequent empty recovery launch is not a test pass.

Swift parsing of all three V15 test/support files and `git diff --check` passed.
The initial external runner attempts failed before XCTest (unsupported
`-test-iterations 1`, then system-Bash empty-array handling); neither is a
production failure or passing execution. No RC build, backend/Postgres,
migration, broad unrelated suite, or live provider check ran. Ordinary production
compatibility uses separate private host infrastructure, unchanged here, so it
was not rerun. No 26.5 comparison was needed: corrected 26.1 behavior did not
differ.

### Remaining acceptance and release qualifications

V15 is ACCEPTED/CLOSED and included in this checkpoint.
Evidence is simulator-only and includes in-memory persistence, not physical
device or disk-relaunch certification. The retained delete control exercises the
store operations, not the private production Delete button callback. These
controls reduce but do not mathematically exclude every future stale-model path.
Production still retains ModelContainer for app lifetime; no production routing
or lifetime correction is justified by this reproduced test-harness defect.

F11/V12 remain ACCEPTED; V13 CLOSED; V14 ACCEPTED/CLOSED for simulator
compatibility. Physical iOS 26.1 smoke, hosted CI, and final exact-candidate
aggregate release validation remain open. F14 remains PARTLY OPEN and F15
blocked. No stage/commit/push/merge/deployment was performed by this correction.

## V15 SwiftData model lifetime — diagnostic root cause established; OPEN

The following section preserves the diagnosis checkpoint's pre-correction
evidence and historical status; the current correction status is above.

Diagnostic baseline: accepted V14 checkpoint
`aacabec8b143b62d97e26616b70a4d368b2a910c`, on the separate
`hardening/v15-swiftdata-model-lifetime` branch. Only test diagnostics and this
tracker changed. No production correction, schema/migration change, commit,
release certification, or F15 work is part of this slice.

**Classification: A — TEST HARNESS ONLY, high confidence for the observed V15
failure.** Controlled reproduction identifies premature ModelContainer
destruction while SwiftUI still owns the sheet and its main-context model.
Retaining the model or even its exact mainContext does not preserve valid
backing data after the container dies. This finding is bounded to the tested
transitions; it is not a claim that every future production transition is safe.

Historical evidence inspected in
`/private/tmp/caldera-runtime-slice1-7lO1RPne/`:

- iOS 26.5 legacy callback-first test, PID 5290: final rejection/persisted-$275
  assertions preceded a `DebtPayoffBucket.id` trap in
  `DebtPayoffBucketEditorView.activeCycle` (line 609).
- iOS 26.5 healthy command-input test, PID 5320: authorized one-save/$900
  assertions preceded a `DebtPayoffBucket.protectedAmount` trap in
  `EditPaymentPlanView.body` (line 247). A preceding modern case used that same
  process; the original artifact did not identify the crashing model instance.
- Both were SwiftData `BackingData` / `ModelContext.reset` SIGTRAP crashes,
  not V14's isolated-deinit / TaskLocal invalid-free signature. Historical
  destruction ordering was not instrumented; controlled reproduction below
  establishes the sufficient trigger and strongly explains those failures,
  rather than pretending the old logs directly recorded container deinit.

Ownership traced in unchanged production source: `budgetTestApp` owns its
`private let modelContainer` for app lifetime; `PlaidService` stores its context
once. AppRoot owner/query-generation identity changes do not replace that
container. `SavingsGoalsView.activeDebtPayoffSheet.edit` retains the bucket;
route identity reads `bucket.id`. Both editors retain bucket/cycle models,
alongside value drafts and exact-record mutation authorization. Undo also
retains model references. The historical local test harness hid its window but
did not establish sheet/graph destruction before releasing storage.

### Contained iOS 26.1 diagnostic results

Evidence root: `/private/tmp/caldera-v15-diagnosis-5vh6A1af/`. Each potentially
fatal selection ran in a fresh XCTest process with the existing fail-closed
network configuration. UUID, persistent identifier, owner, object/context/
container identities were captured before transitions. Passive destruction
witnesses do not read persisted properties; the pure test's deliberately named
getter is an explicit probe, not diagnostic logging after invalidation.

| Pure transition | In-memory and file-backed results |
| --- | --- |
| A: ordinary save | Passed; retained model remained readable. |
| B: saved edit then rollback, including process-pending variant | Getter survived, but value-restoration assertions failed ($66 / edited name remained instead of $40 / original name). These are failures, not passes or V15 invalidation reproductions. The production save-failure coordinator's explicit restore control passed separately. |
| B: rollback unsaved insertion | Named ID probe returned. Diagnostic-only; not permission to use a rolled-back insertion as a persisted record. |
| C / D: delete without save / delete and save | Named ID probes returned. Does not certify arbitrary later use of deleted models. |
| E: release/replace independent context while retaining container | Original context stayed alive in plain, autorelease-pool, and observed-release variants. Failed release preconditions/timeouts; unsafe getter deliberately not attempted. |
| F: release independent context/container | Same unmet destruction precondition; inconclusive, not safe-release evidence. |
| F: retain exact mainContext and model, destroy only container | Fatal V15 trap in both stores: container destruction observed, mainContext still alive, then `DebtPayoffBucket.id` failed. In-memory PID 22867; file-backed PID 23076; both runner exit 65, not passes. |
| G: refetch through context B, including release of B | Passed; original context-A model remained readable. Overlapping variants are not additional independent coverage. |
| H: synthetic owner/generation value replacement | Passed as a pure value control only; real owner/query transitions are covered by hosted tests below. |

Nine distinct app-scoped hosted controls passed: retained legacy/modern editors;
owner replacement while presented in each editor; legacy dismissal before owner
replacement; required-read failure/rollback/recovery in each editor; actual
production Cover action/coordinator save-failure rollback; and the supported
delete-before-dismiss store-operation order. That delete probe reproduces the
private callback's store operations, **not a rendered/tapped Delete callback**.
These cases keep storage through actual sheet, graph, and host destruction,
then release dependencies and assert weak references clear. No indefinite
retention, sleeps, queue-turn workaround, or weakened authorization was added.

Both short-lived hidden-window-only fixtures instead reproduced the historical
fatal getters: legacy `id -> activeCycle`, modern `protectedAmount -> body`.
Final identity-instrumented runs (PIDs 23285 / 23331) record container destroyed
with **bucket, cycle, sheet, and mainContext still alive**, then a fatal getter
with the exact pre-captured persistent identifier. Host teardown had started;
neither explicit delete, rollback, nor owner change was needed. Both runner
exits were 65, not passing tests. Final-source retained legacy/modern reruns
passed (PIDs 23247 / 23259); reruns do not add new test identities.

The two original historical selections were also independently rerun in fresh
26.1 processes with passive lifetime instrumentation and their original
actions/assertions/hidden-window teardown unchanged. Legacy PID 23377 and
modern PID 23409 both logged destruction of the fixture host/window and then
the exact container before the corresponding historical getter trapped. The
fatal persistent identifier matches each pre-captured bucket. Fresh assertion
context B had already been destroyed without a trap while the container was
alive. Both original reruns exited 65; they remain failing regressions, not
passing callback/teardown certification.

No new 26.5 comparison was justified: historical 26.5 already exhibits the same
V15 getters, and 26.1 isolates the lifetime cause with passing valid-lifetime
controls. No OS-upgrade remedy or valid-usage SwiftData runtime defect is
established. No backend, Postgres, live provider, physical-device test, broad
iOS suite, or new RC certification was performed.

Infrastructure/negative evidence remains explicit: initial simulator launch
stalled before XCTest and was interrupted (exit 75), then the built retry
passed. The original file-backed saved-edit rollback run completed failing
assertions; its diagnostic-collection interruption/runner artifact ended 126.
Neither is a pass. Release-precondition timeouts and intentional fatal child
selections also remain failed/inconclusive diagnostic evidence, not a green
aggregate suite. Logs, XCResults, source snapshots and file-backed diagnostic
stores are retained outside Git. These crash-expected diagnostic selections
must not be mistaken for ordinary release-gate passing regressions.

Final evidence index is `diagnosis-summary.json` under the evidence root above.
All 17 synthetic file-backed store trios were copied and compared before cleanup;
eight task-specific crash reports were preserved. The single task-created
iOS 26.1 simulator `FF45BD41-F932-4E40-B7CF-E93CD1F21794` was shut down and deleted.
Swift parsing and `git diff --check` passed. Production source and project files
have no diff; HEAD is unchanged, nothing is staged, and protected worktrees and
stash `c498f27ec591400fb578b0a64e3189ed6be70e45` were not modified.

### Smallest correction recommended, not implemented

Correct the mounted test fixture's lifetime only: one awaited MainActor cleanup
path must dismiss the actual sheet, detach the host, and observe real sheet/
subgraph/host destruction while retaining container/context/auth/service; only
then release dependencies and assert weak nil. Apply the same cleanup to thrown
errors and failed assertions. A cleanup timeout must fail, not leak indefinitely
or release live storage and call that safe. Keep original financial, owner,
generation and callback-order assertions and preserve the failing diagnostic.

Likely implementation files are `MountedPlanningValidationTests.swift` and
narrow test-support lifecycle code. No production file is currently justified.
Stable owner/UUID route identity would remove one model getter but not editors'
other retained-model reads; refetch on appearance likewise cannot protect a
later destroyed container. Snapshot-only editors or blanket production
dismissal would expand F5/Undo/rollback/UX scope without evidence requiring it.
No schema/migration, stored identity, financial formula, F11 auth, F13 webhook,
or F14 containment change is required by the established cause.

Correction acceptance should rerun both historical selections in fresh and
same-process sequences, both editor lifetime controls, owner/query replacement,
required-read recovery, and save-failure cleanup, retaining original assertions
and bounded weak-release checks. Stop for a crash while the app-scoped container
is provably alive, a V14 signature, an unknown invalidation event, or any need to
alter schemas, finances, or owner/generation protection. V15 is **ROOT CAUSE
ESTABLISHED**, but remains **OPEN, unimplemented and unaccepted**. F11/V12 remain
ACCEPTED; V13 CLOSED; V14 ACCEPTED/CLOSED for simulator compatibility. Physical
iOS 26.1 smoke, hosted CI, and final aggregate release validation remain open;
F14 remains PARTLY OPEN and F15 blocked.

## V14 Dashboard ambient-animation removal — ACCEPTED / CLOSED for simulator compatibility

Implementation baseline: V14 regression checkpoint
`eb599d123657dea4019702edc65c1367fb2dcf3e`. These are targeted working-tree
results, not clean committed-candidate or release certification.

The authorized product decision removes the production ambient blob entirely.
`NewDashboardView` retains its existing static `CalderaPageBackground` gradients,
content/ScrollView geometry, safe-area padding, navigation, refresh, privacy,
and accessibility behavior. Its activity `@State`, animated overlay,
scroll-phase mutation, and animation-only presentation helper are removed.
`DashboardAmbientBlobActivity` is deleted, including all activity parameters and
reads. No replacement controller, retention, isolated-deinit workaround,
runtime-specific branch, financial formula, persistence, schema, authentication,
owner identity, or deployment-target change was introduced. The remaining
value-state `DashboardAmbientBlobView` prototype is guarded by `DEBUG` and has
only its existing Lab consumer; ordinary Dashboard composition never mounts it.

The permanent production regression retains the original host/window and every
lifecycle, ownership, persistence, transport, and weak-reference assertion.
Each phase now also checks that the compiled activity type is absent; a positive
AuthManager type-lookup control verifies module metadata lookup is functioning.
Source search and built-symbol inspection find no production activity type or
construction. There is no synthetic scheduler, sleep, queue-turn loop, added
retention, weakened release assertion, crash suppression, or V15 path.

Final-source Xcode 27.0 / Swift 6.4 arm64 iPhone 17 Pro Max results:

| Execution | XCTest result | Completed lifecycle iterations |
| --- | --- | --- |
| iOS 26.1 (23B86), individual | 1/1 pass, zero failures/skips, exit 0 | 1 |
| iOS 26.1, five in one process | 1/1 pass, zero failures/skips, exit 0 | 5, PID 15971 |
| iOS 26.1, fresh process 1 | 1/1 pass, zero failures/skips, exit 0 | 1, PID 16032 |
| iOS 26.1, fresh process 2 | 1/1 pass, zero failures/skips, exit 0 | 1, PID 16045 |
| iOS 26.1, fresh process 3 | 1/1 pass, zero failures/skips, exit 0 | 1, PID 16058 |
| iOS 26.5 (23F77), individual | 1/1 pass, zero failures/skips, exit 0 | 1 |
| iOS 26.5, five in one process | 1/1 pass, zero failures/skips, exit 0 | 5, PID 16752 |

Repeated iterations are not additional XCTest methods. All phases complete:
ordinary mounting/navigation, A -> B owner replacement, B query generation
0 -> 1 unavailable -> 2 available, real host/subgraph destruction, and all
weak app-service/context/container releases. Validation-control construction
stays zero. A/$125 and B/$250 Cushion rows remain unchanged in a fresh in-memory
context; each declared synthetic auth request is consumed and unexpected HTTP
count is zero. No timeout, isolated-deinit/TaskLocal invalid free, or invalidated
SwiftData model failure occurred in the final matrix. The 26.5 runs use
`test-without-building` on the same binary; all 273 application/project/test
hashes remained unchanged throughout the matrix.

The selected affected Dashboard/PrivacyShield suites passed 42/42, zero
failures/skips: ATS presentation 8, refresh 8, grid layout 4, widget routing 10,
privacy 12. The final-source Release Candidate simulator build passed, exit 0,
and its product is arm64. Swift parsing and `git diff --check` pass.

Visual inspection of `static-dashboard.png` shows the ordinary signed-out
Dashboard in the existing contained, in-memory app host: intentional static
gradients, full hero/card spacing, safe-area/tab clearance, and no unexpected
request diagnostic. This is not a healthy linked-account, tapped interaction,
or VoiceOver walkthrough. Background hit-testing and existing privacy/
accessibility code are unchanged; the removed decorative layer adds no
replacement interception surface.

Three preliminary screenshot-instrumented test attempts are retained as failed
evidence, not passing coverage: one screenshot assertion failed because the
window had no foreground scene; a foreground-window capture and a later layer
capture each failed six existing immediate weak-reference assertions. Neither
reproduced the runtime crash. Screenshot instrumentation was removed entirely
from the permanent lifecycle test, restoring its original fixture. Visual
inspection uses the separate contained app-host capture; no timing or retention
accommodation was used to pass the final regression.

Runner, per-run logs/XCResults/summaries, source/binary hashes, preliminary
failures, screenshot, and verified evidence manifest remain outside Git at
`/private/tmp/caldera-v14-removal-R8KtlYCp/`. Both task-created simulators were
shut down and deleted; prior evidence remains preserved.

V14 is ACCEPTED/CLOSED for simulator compatibility. Keep the minimum at iOS
26.1. Before final release supporting 26.1, perform a contained physical-device
smoke test of the same owner-transition and Dashboard lifecycle; no physical
device certification is claimed. F11/V12 remain ACCEPTED, V13 remains CLOSED,
V15 remains OPEN and unstarted, hosted CI/aggregate validation remain OPEN,
F14 remains PARTLY OPEN until those gates are complete, and F15 remains blocked.
No staging, commit, push, merge, or deployment.

## V14 ordinary production-path compatibility — historical BLOCKED evidence

Tested production checkpoint: `19f12d31692f3d751c598a989363102ea64f4739`.
At that evidence pass, only the new test and this tracker were pending;
production source and project configuration were unchanged. All
216 tracked application/project files matched their pre-test hashes.

The test mounts real `ContentView` and its normal TabView, including
`SavingsGoalsView()` with nil validation support and `NewDashboardView`.
A thin test root bypasses onboarding and applies the same owner/query-generation
identity and synchronous owner-change handler as `AppRootView`; it is not a
test of onboarding or AppRootView's automatic Bank Sync loading. The full
production schema is in-memory with stable A/$125 and B/$250 Cushion records
and no Payment Plan/cycle models. App-owned AuthManager, PlaidService,
SummaryViewModel, AppNavigation, ModelContainer and ModelContext remain retained
through host teardown. The sentinel session store makes no Keychain calls.

Normal tab navigation reevaluates the graph. An exactly declared/intercepted
production `signInWithAppleToken` backend request changes synthetic owner A to B.
The real `retryPlanningSnapshot` method then replaces query generation 0 -> 1
with an injected required reserve-read failure, and 1 -> 2 after recovery.
No PlanningViewValidationControl or synthetic callback scheduler is injected.
Passive nonisolated witnesses observe real appearance, disappearance,
UIViewRepresentable dismantling/coordinator destruction and host destruction.
They do not schedule or delay cleanup. Final resource release executes in an
actual MainActor Task and checks weak references, not merely Thread.isMainThread.
There are no sleeps, queue-turn/yield loops, detached cleanup, retention delays,
new empty deinits, model deletion/rollback/invalidation, or Payment Plan editors.

### Minimum-runtime execution and exact signature

Xcode 27.0 (27A266a), Swift 6.4 (`swiftlang-6.4.0.34.1`), arm64 iPhone 17 Pro Max.
The first iOS 26.1 (23B86) individual execution crashed: XCResult reports one
failed test, zero passes and zero skips; runner exit 65. Process 10662,
iteration 1, crashed at 2026-10-09 23:33:41 -0400 while replacing B's query
generation 0 with generation 1, after the old observer was dismantled/destroyed
and before host detachment. All app dependencies/container were still retained.
Initial construction, normal navigation and A -> B replacement had verified zero
validation-control constructions. The failure prevented later 26.1 assertions.

The crashing object is the **production** `DashboardAmbientBlobActivity`, created
by `NewDashboardView`'s `@State`, not ActorLifetimeProbe or the passive test
witness. The main-thread stack is:

`DashboardAmbientBlobActivity.__deallocating_deinit` ->
`swift_task_deinitOnExecutorImpl` ->
`swift::TaskLocal::StopLookupScope::~StopLookupScope()` ->
`___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED` -> SIGABRT.

This matches the earlier independent actor signature and establishes a
production-class/ordinary-graph reachable failure in controlled simulator
execution. It is not live-user/device evidence. The test root uses the real
AppRootView identity policy; the required-read failure is deliberately injected.
Per the stop-on-crash instruction, the five-iteration and three fresh-process
26.1 runs were NOT executed. Xcode's automatic empty restart is NOT a pass.

### Identical-source comparison and disposition

The same already-built test/binary passed once on iOS 26.5 (23F77), process 11147:
1/1 passing, zero failures/skips, runner exit 0, no timeout/crash. All phases
verified zero validation controls. B loaded $250; failure was unavailable;
recovery restored available/$250. Both persisted A/$125 and B/$250 Cushions were
unchanged in a fresh in-memory context. All identity-subgraph and host destruction
signals arrived, and all weak app-service/context/container references cleared
after MainActor-task release. The one expected auth request was positively
consumed; the catch-all host guard recorded zero unexpected requests. This is
declared fixture HTTP containment, not a claim about every simulator OS service.

Test source SHA-256 before/after the runtime comparison:
`4f92428c415ce5fbc811729983921d11c39f8c1ba5b3eb1d78e4ebc74fb5ec0b`.
No source changed between runtimes. iOS 27.0 comparison was unnecessary.
Both task-created disposable simulators were shut down and removed. Swift
parsing and `git diff --check` passed. No shared containment support changed;
no containment suite, RC build, broad suite, backend or database check was rerun.

Complete crash report, user-supplied translated report, command runner, logs and
both XCResults remain outside Git at
`/private/tmp/caldera-v14-production-5d4KdTha/`.
The ordinary-path command selected only
`OrdinaryProductionCompatibilityTests/testOrdinaryProductionGraphOneIteration`
under `CALDERA_UI_VALIDATION CALDERA_TEST_NETWORK_CONTAINMENT`, with offline
SourcePackages and no package updates. Comparison used `test-without-building`.

At this historical evidence checkpoint, V14 was BLOCKED. The minimum remained 26.1 unchanged,
but this production graph cannot be certified there with the tested toolchain.
The next decision must authorize a narrow compatibility correction for this
production lifetime path or separately choose/revalidate a higher supported
minimum. A single 26.5 comparison does not certify all production lifetime paths
or a new minimum. No workaround or minimum-version change was made.
F11/V12 remain ACCEPTED; V13 remains CLOSED; V15 remains OPEN and unstarted.
Hosted CI and final exact-candidate aggregate execution remain open; F15 remains
blocked behind F14. Other finding statuses and protected worktrees are unchanged.

## Runtime Hardening Slice 1 — accepted and checkpointed (prior evidence)

Source is the nine-path assembled F11 baseline at `79d8cf32` plus the narrow
query-health/validation seam, deterministic Hold-task signals, V12 fixture
correction, and independent diagnostics. Original worktrees/stash remain
untouched. No financial formula, SwiftData schema, ownership, editor routing,
deletion protocol, backend, release configuration, or deployment change.

### Minimal destruction and compatibility result

Runtime Hardening Slice 1 is ACCEPTED and included in this checkpoint. Using
Xcode 27.0 (`27A266a`), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), arm64
simulator. The independent `ActorLifetimeProbe` has an implicit MainActor
destructor and a nonisolated destruction witness; it contains no Caldera
auth/planning/service graph. On iOS 26.1 (`23B86`), actor-task release passes,
but synchronous non-task release and synchronous TaskLocal/autorelease release
both crash. Preserved stacks contain `ActorLifetimeProbe.__deallocating_deinit`
→ `swift_task_deinitOnExecutorImpl` → `TaskLocal::StopLookupScope` → invalid free.
The isolated three-case run reports one pass/two crashes, runner exit 65. This
supports a Swift/SwiftUI runtime compatibility classification; it does not
establish identity with a particular upstream issue or fix.

On iOS 26.5 (`23F77`) the same actor cases, tiny StateObject host, and tiny
cancellation host all pass (5/5). The final selection repeats those cases
successfully. Incoming StateObject identities 10 and 11 are both constructed;
installed identity remains 10 after replacement. SwiftUI may retain the unused
incoming initializer object until graph teardown; the corrected diagnostic
waits on both actual destruction signals and verifies both weak references
become nil. The first diagnostic wrongly expected earlier incoming destruction;
its timeout is not an app defect or a pass. Its subsequent tiny-host teardown
also produced the independent isolated-deinit runtime signature on 26.1.

No production retention delay, empty deinit, actor-isolation weakening, queue
turn, or detached teardown workaround was added. Related speculative lifecycle
patches stopped. The supported deployment minimum remains 26.1, unchanged.
The specific eager validation-control construction that motivated the runtime
investigation is absent from ordinary production construction. Passing 26.5
does not certify 26.1. At Slice 1 acceptance, V14 was BLOCKED pending one focused
ordinary production-path iOS 26.1 replacement/teardown test. The subsequent
production regression and animation-removal matrix are recorded above; no
minimum-version change follows from the synthetic diagnostic alone. iOS 27.0 was
available but not needed/tested for this comparison.

### Production seam and V13 ordering

Production query failures now live in `SavingsGoalsView`'s value `@State`,
independent of the injected test control. `@Query.fetchError` is still read
only during body evaluation; command authorization still rereads persisted
inputs synchronously. Optional Observation-based validation injection replaces
the eager default StateObject/ObservedObject controls in SavingsGoalsView,
both payment-plan editors, and Hold. Ordinary constructors use nil: a 100-fold
construction test verifies no validation-control instance is created. Real
query-health availability and the existing generation/dismissal bridge remain.

Hold exposes explicit task-start, cancellation-request, release, settlement,
and disappearance traces only through injection. Tests await the exact commit
Task's `.value` and reject missing task registration; observer/generation
changes are not cancellation or settlement proof. The old mounted cancel-first
case now waits for actual cancellation and settlement instead of expecting
authorization from a callback that correctly exits on cancellation.

V13 ordering is CLOSED at the production Hold/action-factory boundary:
three cancel-first rounds observe Task.cancel before callback release; three
callback-first rounds force the actual callback before disappearance/observer
handling, without requiring later cancellation. Fresh required-read failure
rejects the latter at the persisted authorization boundary. Both leave $275
and make zero save attempts. Recovery cannot revive the old action; a freshly
prepared action persists $900 with exactly one explicit save. Tests use retained
in-memory containers and intercepted transport, not rendered editor/model
lifetime proof or an observed live interleaving. Direct adjacent owner,
generation, exact-record/cycle and stale/valid Undo tests pass. No timing
heuristics establish correctness; the Hold's preexisting yield/hold duration
is not used as a test completion signal. Tiny hosted teardown observes actual
destruction and verifies weak release after exact task completion.

### V12 fixture and historical crash disposition

V12 is ACCEPTED, not release certification. Ordinary sign-out seeds
card data and owned plans, invokes the production auth-loss/owner handlers, and
rejects the stale response while preserving plans. Destructive clear retains
a real ModelContainer/context, seeds A/B plans and Cushions, requires `.cleared`,
observes one successful save while A's credentials are still current, removes
only A, preserves B/$125, then invalidates credentials. Missing-context clear
requires `.failed` and preserves meaningful $420 card data, metadata and
credentials. These three contracts plus the real contained card-request control
pass in the final 26.5 selection. The corrected historical sign-out selection
also passes separately on 26.1 (1/1).

Before correction, the exact historical sign-out selection reproduced invalid
free in `Credentials.__deallocating_deinit` during PlaidService release on 26.1,
matching the independent actor repro. The crash is not attributed to financial
cleanup or to the backend sanitizer. The historical runner stalled after its
crash/empty restart and was terminated (exit 143); it is not passing coverage.
Passing the corrected fixture does not prove that missing context caused the
allocator crash, or prove all credential destruction paths safe on 26.1. V14's
compatibility gate remains, separately from V12's corrected behavior contract.

### F11 security, validation and remaining gates

Direct F11 security is ACCEPTED. Stable environment
identity, origin-bound scoped Keychain, legacy quarantine, scoped restore/
sign-in/sign-out, stale environment/operation/session rejection, and F2 deletion
durability remain unchanged. Real Security.framework sentinels pass with no
skip. The auth scheduler waits on exact task completion; ten production auth
lifecycles release both AuthManager and the sentinel store through weak checks.

Final focused 26.5 XCResult: **77 total, 72 ordinary passes, five verified
expected-failure containment contracts, zero failures/skips, runner exit 0**.
Breakdown: auth/config 26; deletion 24; real Keychain 1; six direct owner/
generation/record/cycle/Undo cases; four hosted Hold/construction cases; four
card-detail cases; one query adapter; five independent diagnostics; six transport
contracts. Earlier 5/5 and 8/8 selections overlap and are not summed. The
final-source ordinary arm64 Release Candidate simulator build passed; Swift
parsing and diff checks passed. The preflight's sandbox cache/simulator exit 74
is an environment failure, not passing validation. One initial focused build
failed on a test's access to a private diagnostic property; that assertion was
removed without changing production visibility, and the final build/tests pass.

A separate three-case mounted seam run passed the linked-card callback-first
case, but crashed in the legacy-editor and view-only healthy-command cases with
SwiftData `BackingData` invalidated-model errors. This is V15's distinct
signature, not the actor/TaskLocal signature; none is counted as passing.
No V15 repair, retention/routing change, or further model-lifetime probe was
undertaken. V15 remains OPEN for Slice 2. Full mounted editor teardown is not
certified by the tiny Hold tests.

Evidence: `/private/tmp/caldera-runtime-slice1-7lO1RPne/` contains runner/logs,
XCResults, preserved crash reports, and a SHA-256 source manifest. Both
task-created simulators are removed after validation; evidence is retained.
Dependencies were an offline cache copy, not a new installation or proof of
independent provisioning. No live backend/provider, database, broad unrelated
suite, hosted CI, or aggregate release execution. At this Slice 1 checkpoint,
F14 remained PARTLY OPEN and V14 compatibility, V15, hosted CI, and aggregate
execution remained open. V14 was subsequently accepted for simulator
compatibility; physical 26.1 qualification remains a release gate. F15 stays
blocked after F14. No push/merge/deployment.

## Runtime baseline assembly — preserved provenance

`hardening/runtime-lifecycle-cluster` combines accepted source/validation through
`79d8cf32` with the intended pending F11 implementation from
`hardening/environment-scoped-sessions` at `ad084715`. This is mechanical
reconciliation, not a new runtime correction or release certification.
F1–F10 remain accepted/integrated, F12/F13 and F14-A/F14-B checkpointed, V11
closed, F11 blocked, and V12–V15 open. Runtime Slice 1 is next; F15 remains
blocked until the remaining F14 work is resolved.

### F11 semantics and prior evidence

The production AppConfig, AuthManager, and KeychainSessionStore files have no
intervening accepted-base changes and are ported byte-for-byte from the pending
F11 source. Explicit identities are `development-local` for Debug/Lab and
`render-production` for RC/production. The credential account includes the
contract ID and SHA-256 of the validated normalized origin. Unknown/contradictory
configuration cannot select credentials. The historical global credential is
preserved and quarantined: no fallback, migration, overwrite, or deletion.
Restore, sign-in, sign-out, session expiry, and account deletion retain exact
environment/operation/token/owner controls. Existing durable deletion behavior,
planning ownership, financial formulas, and persisted schemas are unchanged.

The source tracker reports an earlier 55/55 zero-skip direct selection and RC
build, followed by a 28/28 focused selection and failed teardown repetitions.
Those overlapping historical results are not summed or claimed as rerun here.
Their referenced F11 temporary log/XCResult locations now contain empty shells;
the Astra investigation could inspect recorded findings and source, but could
not reconstruct the original crash reports. Mounted validation is not accepted.

### Nine-path reconciliation inventory

| Path | F11 source hunks | Accepted-base/F14 hunks | Resolution / behavior preserved |
| --- | --- | --- | --- |
| `budgetTest/App/AppConfig.swift` | Core production identity/origin/namespace contract | No intervening change | Exact pending-source port. |
| `budgetTest/Services/Auth/AuthManager.swift` | Core scoped store and environment-bound operations/deletion guards | No intervening change | Exact pending-source port; existing deletion machinery retained. |
| `budgetTest/Services/Auth/KeychainSessionStore.swift` | Scoped protocol/store and legacy quarantine | No intervening change | Exact pending-source port. |
| `budgetTestTests/AuthEnvironmentSessionTests.swift` | New direct auth/configuration tests, sentinel store/task tracking, unique-service Keychain test | New file | Exact pending-source port. Existing request-observation polling is retained; it is not a hosted teardown delay. |
| `budgetTestTests/AuthAccountDeletionIntentTests.swift` | Scoped sentinel-store fixture adapter | No intervening change | Exact pending-source port. |
| `budgetTest/Support/UIValidationBootstrap.swift` | No-Keychain scoped store adapter | Fail-closed host/default/ephemeral containment | Apply only scoped adapter atop accepted bootstrap; all containment retained. |
| `budgetTestTests/CorePlanningUserIsolationTests.swift` | Sentinel store injection plus older offline-session additions | Declared fail-closed transport and all session injections | Add only three sentinel stores; retain accepted transport rather than older helpers. |
| `budgetTestTests/MountedPlanningValidationTests.swift` | Scoped store adapter plus later teardown experiments | ContainedNetworkTestCase and declared transport | Apply only AuthManager adapter. Existing accepted-base test body and transport remain; unstable probes are not run. |
| `docs/HARDENING_TRACKER.md` | Older F11 status, evidence, and investigation history | F12/F13/F14-A/F14-B checkpoint/evidence history | Preserve accepted-base document; add this inventory and qualified F11/runtime findings. |

### Hosted investigative hunks intentionally omitted

The original F11 worktree retains all of these hunks. They are not needed for
the scoped security implementation and are not imported here:

- The added mounted cancellation/fixture-teardown test, helper extraction,
  fixture observer, weak-reference assertions, retained auth/store/container/
  navigation/control variables, and ten main-queue turns.
- Autorelease-pool mounting, host root replacement, layout/detachment, and
  explicit window/controller release ordering.
- The replacement assertion that the callback must already be cancelled,
  removal of the prior final-authorization expectation, associated auth/trace
  assertions, and conditional fresh-hold path. Astra identified insufficient
  synchronization for that cancellation assumption; neither version is certified.
- The extra harness-owned sentinel-store field used by that experiment. The
  fixture injects the same store type directly; AuthManager owns it.

No production deinit workaround, actor weakening, hosted teardown sleep/release
delay, model lifetime fix, or new callback synchronization is introduced.

### Astra runtime investigation disposition

- V13: confirmed test-ordering gap. Availability/generation observation does
  not establish disappearance/cancellation or callback settlement. Synchronize
  those events explicitly in the future slice while retaining callback-first
  final persistence authorization.
- V14: ordinary view construction creates PlanningViewValidationControl, which
  also holds actual production query-failure state. Separate optional validation
  controls only while preserving that fail-closed production state. Recorded
  isolated-deinit/TaskLocal failure attribution remains unresolved.
- V12: the existing sign-out fixture lacks a persistence context, ignores failed
  destructive cleanup, and starts with empty card data. This is a coverage gap;
  its original crash phase remains unknown and no fix is made here.
- V15: editors retain main-context DebtPayoffBucket references. The exact
  invalidation event remains unknown; context/host teardown is a hypothesis,
  not proof of a production defect or a shared allocator root cause.
- F11: security boundaries can be validated directly; production-reachable
  runtime concerns remain release blockers. Similar upstream Swift reports do
  not certify a runtime/toolchain remedy. V11 containment and accepted F14-B
  infrastructure remain authoritative and unchanged.

### Focused assembly validation

The combined working source passed Swift parsing and `git diff --check`.
Exact-file comparisons verified the three production files and two direct-test
files against original pending F11 source. Adapter-only comparisons verified
the three overlapping Swift files; accepted CI/release policy, containment
helpers/runner, validation guide, and implicated production lifecycle files
remain byte-identical to `79d8cf32`. All nine pending paths are expected.

One contained selection passed on a newly created disposable iPhone 17 Pro Max /
iOS 26.1 simulator with Xcode 27.0: 26 AuthEnvironmentSessionTests,
24 AuthAccountDeletionIntentTests, two current/stale owner-session tests,
one unique-service Security.framework Keychain test, and six unchanged
ContainedTestTransportTests. XCResult reports 59 total, 54 ordinary passes,
five verified expected-failure contract tests, zero unexpected failures,
zero skips, and runner exit 0. The six transport contracts include one ordinary
positive pass and five expected-failure cases; intentional child failures are
verified by the enclosing tests and are not extra coverage. The real Keychain
case executed without an entitlement skip and used only exact sentinel accounts.

The direct selection used the ordinary unit scheme with
`DEBUG CALDERA_UI_VALIDATION CALDERA_TEST_NETWORK_CONTAINMENT`, the accepted
fail-closed host/default/ephemeral guard, explicit intercepted fixture sessions,
ad-hoc simulator signing, and locked offline packages. Auth/deletion selectors
are outside the narrow F14-A runner allowlist, so xcodebuild was invoked with
the same reviewed host/containment/package settings and explicit selectors;
the runner itself was not broadened or edited. The ordinary arm64 Release
Candidate simulator build also passed (exit 0), without test-host flags or app
launch. Its only warning was skipped AppIntents metadata extraction because
there is no AppIntents dependency. No financial/schema behavior was changed.

`task-start.sh` was attempted and exited 74 at sandboxed Xcode/cache access;
it is not a passing preflight. Separately approved test/build access succeeded.
Dependencies came from a task-owned offline copy of the existing locked Plaid
cache, not a newly provisioned dependency tree. Logs, source hashes, build
products, and `Assembly.xcresult` are retained outside Git in
`/private/tmp/caldera-runtime-assembly-RqKADWuD/`. The task-created simulator
was shut down/deleted; no existing simulator or database was changed.

This one successful assembly run does not close F11 or runtime repetition.
Runtime Slice 1, unstable mounted probes, V12–V15 reproduction, backend/Postgres,
hosted CI, and final exact-candidate release execution were not run. F11 stays
BLOCKED, V12–V15 open, and F15 blocked. The combined baseline is ready for the
separately authorized Runtime Slice 1 implementation.

Historical checkpoint sections below describe their original slices. Their
statements that F11 was excluded apply to those checkpoints; the intended F11
implementation is now present only in this combined uncommitted runtime branch.

## Accepted F14-B checkpoint

F14-B CI and exact-candidate validation infrastructure is accepted and included
in this checkpoint. It starts from F14-A
`7301b821` on `hardening/f14-ci-release-gate`. The tracked-workflow candidate has
PR/manual triggers, no push/deploy step, no production secrets, and independent
backend/iOS jobs with retained filtered evidence. No GitHub runner execution is
claimed. Remote main remains behind; Render Auto-Deploy On Commit is unchanged.

The operator command composes the accepted backend and F14-A scripts, rejects
dirty candidates, checks exact SHA/cleanliness before and after execution, records
manifest version/ref/time/results, verifies matching platform evidence, and rejects
skipped/missing required Postgres or iOS execution. Full backend-chain and separate
real Express/Postgres-startup commands use distinct fresh guarded loopback clusters.
Production migrated-database startup is unchanged. Debug/RC simulator builds remain
separate from the six network contracts and four named stable contained tests.
Actual archives, broad iOS tests and live provider behavior are not certified.

`scripts/release-gates.json` requires explicit F11/V12/V13/V14/V15 status. All are
open. A passing validation summary still reports release readiness blocked;
the operator release command exits 2. Missing/unreadable/omitted blocker status
fails closed. The tracked CI, candidate-contract, required-gate, and durable
evidence definitions are accepted in F14-B; hosted CI execution and final
exact-candidate aggregate execution remain open. F11 work is untouched and
blocked. F15 remains after F14.

Local F14-B checks passed 25/25 with zero skips: 16 new candidate tests, the
existing 3 wrapper tests and 6 Postgres guard tests. Production orchestration is
tested with controlled command outcomes and synthetic temporary Git repositories;
the actual CLI also rejects dirty source and a real missing-authorization wrapper
result. YAML/workflow checks, shell/Node syntax, static and diff checks passed.
Xcode argument regressions substitute a recording command, not an actual build.
F14-A evidence is reused; no iOS runtime/build, V12–V15 or F11 probe ran here.

The focused F14-B review found two source-confirmed blockers: dependency
failure skipped the combined summary, and complete passing gate evidence was
published before final source verification. Both corrections were accepted.
The summary now runs with `always()`, inspects actual backend/iOS job results and
artifact-download outcome, and requires every state to be `success`. Failed,
skipped, cancelled, missing or unexpected states cannot become successful
validation, even with otherwise passing artifacts. Missing/corrupt/incomplete
inputs yield an explicitly failed diagnostic report and exit 1; failure uploads
remain enabled with 14-day retention, without `continue-on-error` for required work.

Platform progress is explicitly unfinalized. Only successful final source/Git
verification plus all passing gates permits finalization. Manifest replacement
uses a complete temporary-file write, file fsync/close, and atomic rename;
power-loss-durable directory metadata is not claimed. Aggregation rejects absent,
false, missing or corrupt finalization and rechecks candidate identity before
finalizing its own successful result. No force flag or handwritten upgrade exists.

Corrective static/contract validation passed 32/32 with zero failures/skips:
23 candidate tests, the unchanged 3 wrapper tests, and unchanged 6 Postgres guard
tests. The prior 25-test run overlaps this selection. Regressions exercise the
production CLI with each non-success backend/iOS result, missing dependency
results, failed/skipped/cancelled artifact retrieval, and missing/malformed/
incomplete evidence; successful inputs still retain all five release blockers.
A controlled production-executor fault after passing gate persistence but before
final source verification leaves rejected unfinalized evidence. A final dirty-source
failure remains rejected even after the temporary fixture is cleaned. These are
controlled test faults, not observed GitHub cancellation or process/power-loss
reproductions. Node syntax, YAML parsing and summary-condition validation,
source-hash verification, and `git diff --check` passed. The task-start preflight
again exited 74 on sandboxed Xcode/cache access, not success or a production
defect.
Evidence is outside Git in `/private/tmp/caldera-f14b-correction-DF3sczJg/`.
No full backend chain, real Postgres, iOS build/test, F11 or V12–V15 probe was rerun;
their previously qualified evidence is reused because only reporting/finalization
infrastructure changed. F14-B is accepted and checkpointed; F14 remains partly
open. Hosted GitHub execution, F11, V12–V15, and final exact-candidate aggregate
release execution remain open. F15 follows F14; this checkpoint does not authorize
deployment.

The complete backend npm test chain passed through the new connection guard and
disposable launcher, including 31/31 startup and 29/29 webhook tests, real
Express/lifecycle checks and non-skipped Postgres storage. Separate real
index/Express/Postgres startup and normal migrations passed on another fresh
cluster/database. Both successful clusters were stopped and removed. Local
Node 20.11.0/PostgreSQL 17 and existing worktree-local dependencies were used;
this does not establish CI Node 22/PostgreSQL 16 or a clean install here.

Earlier attempts remain failures: cleared Mac startup needed an explicit locale,
the connection guard needed the contained child listener's exact IPC port, and
cleared TMPDIR failed the unchanged cluster-identity guard. These were corrected
without weakening the guard. A caught-error stderr test assertion was corrected
to verify the refusal message/nonzero exit; final static checks passed.
Evidence is outside Git in `/private/tmp/caldera-f14b-validation-ptzLl3za/`.
These working-tree checks do not certify application HEAD: the dirty candidate
command correctly refuses execution. Preflight exited 74 on sandboxed Xcode/cache
access and is not passing evidence. No GitHub run, live provider/customer data,
production DB, archive, push, merge, deployment or Render change is claimed.

## Accepted F14-A checkpoint

F14-A — Release-evidence network containment, accepted and checkpointed. V11 is
CLOSED. F1–F10 remain accepted and locally integrated, F11 BLOCKED in its
untouched separate worktree, and F12/F13 accepted/checkpointed. F15 follows F14.

V11's declared fixture contract is implemented and accepted; this is not a claim
about all repository tests:
`BankDataRequestCacheIsolationTests`, `CardPaymentDetailsSessionIsolationTests`,
`CorePlanningUserIsolationTests`, and the shared transport of
`MountedPlanningValidationTests` use `ContainedTestTransport`. Expected HTTP
actions declare exact origin/method/route/synthetic authorization/response.
Requests are recorded; only an exact declaration is consumed; response
completion and the exact count are asserted. Undeclared/mismatched requests
record a real XCTest failure and return `URLError.unsupportedURL`; they never
fall through or receive generic success. Local-only fixtures declare zero
requests. All service/auth constructors in these named fixtures explicitly use
the injected session. No financial assertions were changed.

The existing isolated validation host is selected before XCTest with
`CALDERA_UI_VALIDATION` plus `CALDERA_TEST_NETWORK_CONTAINMENT`. Its own HTTP
actions are undeclared and fail closed. Global URLProtocol registration covers
shared-session fallback; the gated default/ephemeral configuration-factory hook
covers fresh sessions as well. Missing hook installation fails host startup;
missing compile flags now fail compilation before the configured host can launch,
with a defensive setup check as well. This bootstrap change is wholly
excluded from RC/production and does not change actors, hosted disappearance /
cancellation, PlanningViewValidationControl, SwiftData lifetime, or F11 code.
AppConfig is unchanged. `.invalid` transport probes use no configured endpoint;
generated service URLs are contained by the injected protocol. Diagnostics omit
credentials, headers and request bodies. The command and limits are documented
in `VALIDATION_GUIDE.md`; this is not containment of background sessions, WebKit,
Apple authorization UI, arbitrary network APIs, or unnamed test fixtures.

Corrected runtime-source focused execution passed 11/11 with zero skips on a task-created
iPhone 17 Pro Max / iOS 26.1 simulator using Xcode 27.0: four transport tests,
the exact disconnect regression, card-detail transport control, four selected
owner/planning cases, and the existing query-adapter case. A separate existing
mounted account-control fixture passed 1/1 and asserted zero HTTP requests.
These selections are not broad iOS or F11 teardown/runtime execution. The
last source addition was a compile-only missing-flag `#error`; the active runtime
helper body remained identical to this selection. Final helper type-checking
against already-built local modules passed with both flags (exit 0) and failed
only at the expected missing-containment guard without that flag (exit 1).
Parser-only success is not guard execution, and the runtime selection is not
claimed rerun after that compile-only directive.
The final-source arm64 Release Candidate simulator build passed, as did Swift
parsing, shell syntax and `git diff --check`. The only app-source edit is the
compile-gated validation bootstrap; RC/production runtime, AppConfig, financial
formulas and persisted schemas are unchanged. The startup preflight was attempted
but exited 74 on sandboxed simulator/cache access; approved contained test/build
execution succeeded separately. This is not a successful preflight claim.
Runner checks for missing arguments and inherited Debug Local mode each rejected
with exit 64 before Xcode execution. The task-created simulator was removed;
logs and xcresults remain outside Git.
The disconnect test proves exactly one authenticated POST `/api/disconnect` was
consumed and its fixture response handled; the card control proves exactly one
authenticated GET `/api/card-payment-details` through the real service handler.
Strict negative self-tests exercise the real failure hooks and independently
assert deterministic errors for undeclared/wrong-origin/method/authorization
requests and shared/default/ephemeral fallbacks. Only those specific guard
failures are expected; financial assertions remain ordinary assertions.

The earlier F14-A acceptance review identified two missing negative regressions, not a
demonstrated network escape. The corrective test-only slice adds an independent
wrong-path case with otherwise matching origin/method/authentication: it requires
the real XCTest failure hook and unsupported-URL error, then consumes the original
declaration with a correct request to prove the mismatch did not consume it.
A second case leaves a declaration unconsumed and returns from the test body;
the existing inherited teardown must record the actual missing-fixture XCTest
failure against that test. Its strict expected-failure matcher cannot pass if
the failure is absent, and no HTTP action is made. The transport helper,
bootstrap, positive disconnect/card fixtures, and runtime guards are unchanged.
Both new tests and the helper type-check with the required flags (exit 0);
the missing-containment flag fails only at the existing guard (exit 1).
Swift parsing and diff checks pass. After explicit disposable-simulator
authorization, only the six `ContainedTestTransportTests` ran successfully with
zero skips and no unexpected failures on iPhone 17 Pro Max / iOS 26.1, using
the existing contained runner and offline locked dependencies (command exit 0).
XCResult reports six total tests: one ordinary pass and five verified
expected-failure tests, zero failed tests, and overall `Passed`.
The wrong-path test recorded its real expected XCTest failure and unsupported-URL
error, then successfully consumed the original declaration with the exact path.
The unconsumed test recorded `Declared HTTP fixtures were not consumed` from
the inherited teardown against that exact test, without issuing HTTP. Strict
expected-failure matching verifies these real XCTest issues; it does not count
intentional negative issues as unexpected suite failures or as extra tests.
The existing correct-request, origin/method/auth rejection, undeclared-request,
and shared/default/ephemeral cases also passed in this six-test selection.
The new disposable simulator was shut down/deleted; logs and xcresult remain
outside Git in `/private/tmp/caldera-f14a-contract-runtime-RTB4xYO1/`.
Compile-check evidence remains in `/private/tmp/caldera-f14a-regressions-38FkdKGV/`.
No helper or app-source correction was needed. No configured backend, live
provider, database, card-detail crash, mounted/F11 probe, broad suite, or F14-B
work was exercised. V11 is CLOSED and F14-A is accepted/checkpointed. CI,
V12–V15, exact-candidate aggregate release execution and F11 remain open.

Earlier attempts are not passing evidence: the first disconnect completion
expectation overfulfilled and crashed XCTest; the fixture was corrected to
observe only the final completion message. The registration-only fallback probe
contained shared HTTP but a fresh ephemeral session attempted DNS resolution of
the `.invalid` sentinel and returned cannot-find-host rather than the required
guard error. That failed attempt is not zero-egress proof. The corrected
configuration-factory guard passed all three fallback probes without URL-loading
fallthrough. No configured backend, Plaid/Apple endpoint, or database was contacted
by the test requests.
Dependencies were an offline copy of an existing locked package cache, not
proof this worktree is independently provisioned. Logs/xcresults are outside Git
in `/private/tmp/caldera-f14a-containment-CznzF39e/`.

Card-detail fixture containment is established independently of its existing
sign-out `xctest.main()` crash. The sign-out test directly supplies a callback,
now uses the same isolated fixture, and declares no HTTP action; its lifecycle
logic was not changed or rerun in this slice. V12 is still open. The historical
F3 Debug Local configured-Sandbox disconnect attempt's receipt and side effects
remain unknown; current positive interception cannot establish that it did not
escape. CI, V12–V15 and aggregate release gates remain open; no Slice B work,
backend chain, database, Sandbox, or deployment validation is claimed here.

## Accepted F13 checkpoint

F13 webhook verification abuse protection and its retained-work correction are
accepted by focused corrective review and included in this checkpoint.
Before the initial F13 implementation, the raw route preceded the general API limiter and each
plausible JWT launched a separate SDK key fetch with no aggregate bound or
configured timeout. A controlled invocation of
the old production verifier with 20 plausible invalid JWTs caused 20 provider
stub calls with peak concurrency 20 and no accepted signatures. This was a
verifier-seam reproduction, not an HTTP/live-provider production incident.

The actual route now admits through an always-enabled, constant-memory global
process bucket (300 attempts per 60 seconds / 32 open HTTP requests), checks a
4 KiB verification header, parses at most 64 KiB uncompressed raw JSON, and
rejects malformed/unsupported JWTs and mismatched body hashes before key work.
A single process-lifetime verifier uses pinned JOSE and an exact case-sensitive
`kid` cache of at most 16 validated provider public keys, with monotonic
five-minute TTL and earlier provider-expiration enforcement. LRU eviction and
opportunistic expiry keep memory bounded. Same-kid misses coalesce; at most two
distinct key jobs run, with no queue. The actual SDK receives a three-second
timeout/abort deadline, a 16 KiB response bound, and disabled redirects; no
internal retry is added. Failures/saturation return retryable 503, invalid
signatures return 401, and excess ingress returns 429 with `Retry-After`.
Failed verification never executes readiness mutation. An abort-ignoring
transport keeps its slot until settlement and cannot cache a late result.

Earlier focused tests passed 23/23 with zero skips: cache hits/TTL/eviction,
expiration/rotation, many distinct kids, same-key concurrency, malformed keys
and JWTs, signature/hash rejection, timeout and failure cleanup, body/header
bounds, budget refill, real Express admission, and actual `index.js`/SDK/store
composition. In the real-index timeout case, three requests shared one
intercepted fetch, all failed closed without readiness changes, and a later
healthy retry updated the exact active Item. Actual-index signed/duplicate
deliveries affected only the intended owner/Item, and ordinary API limiting
remained separate. Startup/index checks passed 31/31 with zero skips, including
unsafe-deployment rejection before app/store/provider/listen. Declared
`test:evidence`, `test:transactions`, and `test:rate-limit` checks passed.
Node syntax checks and `git diff --check` passed. Evidence is saved outside
Git in `/private/tmp/caldera-f13-validation-477jXwna/`.

The initial sandboxed HTTP run could not bind loopback (`EPERM`); the contained
checks passed after normal tool approval. A fixture initially issued its event
before its link timestamp and was correctly rejected by the existing stale
event fence; the test fixture was corrected without relaxing that fence.
Provider calls use generated signed fixtures and intercepted SDK responses;
no live key/webhook service, database, Render setting, iOS test/build, or
production rollout was exercised. Earlier accepted real-Sandbox evidence is
not replaced or claimed rerun. The cache/bucket are per process, reset on
restart, and do not establish hosting/edge DDoS or slow-body protection.
An attacker may consume the shared budget and delay legitimate delivery;
source IP/forwarded headers are never trust or identity evidence. F12 startup,
F2 lifecycle/storage, and financial/iOS behavior are not redesigned. F1–F10
remain accepted/integrated, F11 blocked, F12 checkpointed, and F14 partly open.

The independent F13 acceptance review then reproduced the remaining lifetime
gap under production defaults through actual Express and production verifier /
key modules: 32 open requests held 32 verification waiters on one intercepted
fetch; disconnect reduced open requests to 31 without settling that caller;
a replacement joined as retained waiter 33. Provider concurrency remained one,
and readiness mutation remained zero. This was a controlled HTTP interleaving,
not a live Plaid or production incident; that pre-fix review reproduction was
not rerun during this correction.

A separate shared verification-work pool now caps retained callers at 32.
After cheap JWT/age/claimed-hash rejection, acquisition precedes every key
lookup, same-key join, and cache-hit cryptographic path. Saturation returns the
existing 503 / `Retry-After: 30` without queuing or joining key work. A structured
`finally` releases only when that caller's verification settles; HTTP close
continues to release only the separate open-request slot. A valid disconnected
delivery can finish the existing exact Item/owner, idempotent business handling.
Verification failure or overload cannot mutate readiness. Provider jobs remain
separately bounded at two, and abort-ignoring late jobs still cannot cache.

Corrected-source `npm run test:webhook` passed 29/29 with zero skips. The exact
production-default Express regression held 32 callers, then performed eight
disconnect/replacement rounds: first open count 31, retained count 32,
each replacement 503, one provider call, peak retained 32, final permits and
in-flight jobs zero, and invalid-fixture readiness writes zero. Only the
independently validated public key was cached, not invalid keys or payloads.
Tests also cover cache-hit saturation, same-key coalescing, distinct-key fetch
saturation, all 32 timeout waiters releasing, expiry during verification,
malformed/early hash rejection without permits, exactly-once/nonnegative
release, admission rejection without acquisition, and storage error cleanup.
A valid disconnected callback committed only A's readiness in a disposable JSON
store before its duplicate was sent; reopened production reads kept B unchanged.

The directly affected rate-limit and transaction-evidence composition checks
passed; Node syntax and diff checks passed. Evidence is saved outside Git in
`/private/tmp/caldera-f13-retained-work-76UPJk46/`. The first selected six-case
run overlaps the full 29-case result; its 23 name-filter skips are not passing
coverage. No `index.js` composition or startup-policy edit was made by this
correction, so prior 31/31 startup evidence was reused, not claimed rerun;
actual-index webhook composition was executed in the updated suite. No full
backend chain, database, iOS, live Plaid, or deployment validation was run.
All four limits are per process; Render edge/slow-body protection remains
unverified. F1–F10 stay accepted/integrated, F11 blocked, F12 checkpointed,
F13 accepted/checkpointed at `cf075d8`, and F14 partly open.

## Accepted F12 checkpoint

F12's safe deployed-backend defaults were accepted by focused review and are
checkpointed at `f4d91f5`. The pure startup policy runs after dotenv loading
and before Express app creation, store/session-store creation, provider-client
construction, development-auth initialization, or listening. Render identity,
production `NODE_ENV`, or production Plaid makes the operation deployed; these
signals cannot be overridden by local settings. A Sandbox process without a
recognized deployment signal still rejects unless it explicitly declares
`NODE_ENV=development` or `test`; missing deployment signals alone do not
classify it as local. Deployed operation requires `AUTH_MODE=required`,
`TOKEN_STORE_DRIVER=postgres`, development auth disabled, valid Postgres and
32-byte encryption configuration, and the required app/API, provider, and
Apple-auth configuration. Missing or malformed prerequisites reject before
server composition or listen, and diagnostics omit credential values.

Explicit development/test operation with non-production Plaid retains
personal/optional/required authentication and JSON/Postgres compatibility
under the existing database and key requirements. The HTTP server requires
explicit auth mode and store driver in every environment; lower-level helper
defaults remain for isolated local tooling. Startup does not enable JSON import
automatically. Production Postgres startup runs the existing migrations before
listening and supports an existing migrated application database. The fresh
empty-database restriction exists only in the separately guarded Postgres test
harness. No financial or iOS behavior, persisted app schema, or Render setting
changed in F12.

The reviewer inspected the saved 31/31 startup-policy/actual-index results and
6/6 Postgres target-guard results, both with zero skips, plus passing affected
auth, crypto, user-scope, deletion, lifecycle, and rate-limit checks. The real
isolated Postgres startup and expected missing-authorization/nonempty-target
rejections were inspected, not rerun during acceptance. The reviewer
independently ran malformed-key and explicit/unknown-identity policy checks,
Node syntax checks, final-source hash verification, and `git diff --check`.
No database was provisioned during acceptance. The saved evidence and runner
are in `/private/tmp/caldera-f12-validation-wzE6JpyM/`, outside the repository;
they are not checkpoint paths. The repository's `task-start.sh` was attempted,
but Xcode project listing stopped on unavailable simulator services and denied
cache access; no build or test was run for this documentation-only checkpoint.

Live Render environment variables and credential validity were not checked.
The full backend chain, iOS/release validation, and production rollout remain
unverified gates. F11 remains blocked and isolated in its separate worktree;
no F11 implementation is included here. F1-F10 remain accepted/integrated;
F14 remains partly open.

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

F8 is accepted and included in this checkpoint. Plaid's
installed SDK declares credit liability amounts and account balances as
`number | null` (with no numeric-string contract); its account-balance typing
allows negative credit current balances. The previous `Number(value)` sanitizer
was directly reproduced converting `null`, empty/whitespace strings, `false`,
`true`, arrays, and numeric strings into fabricated finite money. The five
monetary DTO fields now accept only finite JavaScript numbers, preserving real
zero and negative amounts, and otherwise serialize explicit `null`. The
existing per-Item failure and partial-response contract is unchanged. iOS
already decodes these fields as optional `Double`s and excludes nil and zero
from provider target suggestions; this slice adds decoding/selection tests
without changing its production source. The focused backend sanitizer/DTO
composition check passed; Node syntax, Swift parse, and `git diff --check`
passed independently in acceptance. The reviewer inspected the saved
final-source Payment Plan target/decoder class result: 24/24 with zero skips
on an iOS 26.1 simulator. The combined two-class run had 33 passing tests and
one XCTest crash; the crash is not counted as a pass. The pre-fix behavior was
reproduced from production sanitizer source. No iOS production file changed,
so no RC rebuild was needed. Express middleware, live Plaid, and rendered UI
were not exercised. F14's CI and exact-candidate release execution conditions
remain open; V11 containment is closed by F14-A.

## Remaining hardening order

1. Complete the contained physical iOS 26.1 lifecycle smoke test as a final
   release qualification; the deployment minimum remains unchanged. V14's
   simulator compatibility gate is accepted and closed.
2. Runtime Slice 3 — complete hosted CI and exact-candidate aggregate release
   validation after F11/V12–V15 disposition; F15 remains blocked until F14's
   required validation gates close.

F11 and V12 are ACCEPTED in this checkpoint; V13 ordering is CLOSED; V14 and
V15 are ACCEPTED/CLOSED for simulator compatibility and mounted-fixture
lifetime, respectively. Physical iOS 26.1 release qualification, hosted CI,
and aggregate release execution remain open.

F9 is accepted and included in this checkpoint. The pre-fix Income
success-before-save path was source-confirmed, not runtime reproduced. No Income
model migration, recurrence change, or recommendation-history redesign is part
of F9.

F9 final-source focused tests passed 42/42 with zero skips on the iPhone 17 Pro
Max iOS 26.1 simulator. They cover explicit edit/delete save ordering, injected
save failure and rollback, exact owner/event/generation and read-failure
rejection, repeated-action suppression, F7 recommendation history, and selected
owner/Income presentation paths. A fresh context checks both edit outcomes;
a disposable file-backed store was reopened after one successful and one failed
delete, including related occurrence records. The final-source Release Candidate
simulator build and `git diff --check` passed. After a legacy-Income route
assertion was added, the affected F9 class reran 4/4 with zero skips; those
four tests overlap the 42-test run. Save failures were injected at
the production action boundary; no rendered editor interaction, real storage
failure, live network request, or provider behavior was tested. The reviewer
independently ran Swift parsing and `git diff --check`. F14's separate
test-network-containment and release gates remain open.

F10 is accepted and included in this checkpoint. The pre-fix Cushion zeroing
and single-negative-allocation omission were
source-confirmed rather than run against the old revision. Current persisted
ReserveSettings and SavingsGoalRecord protection is validated before the
owner's planning snapshot can become available; invalid or duplicate Cushion
rows leave that owner unavailable without changing stored rows. Explicit
legacy adoption rejects invalid Cushion candidates instead of normalizing
them to zero and deleting an original row. A single negative allocation now
has the same non-authoritative conflict outcome as the existing F6 non-finite
and duplicate cases. The contribution persistence boundary rejects a prepared
action against that row before saving. Dashboard numeric ATS and Set Aside
presentation use the existing unavailable gate; the ATS formula is unchanged.

The legacy UserDefaults `reserve_balance` import now accepts only a numeric,
non-Boolean, finite, nonnegative value. A finite negative value is unreadable integrity
evidence: no ownerless or owned zero is inserted, planning stays unavailable,
numeric Available to Spend remains suppressed, and the original key/value is
preserved across retry and a fresh context/service load. An owner with a valid
owned Cushion remains available. An explicit valid same-owner ReserveSettings
save restores planning through retry; when that owned row is used, the invalid
legacy key is still retained. Valid positive and real-zero legacy values keep
the existing import contract: an ownerless recovery row is saved first, then
the legacy key is removed, and a distinct owned zero is initialized if needed.
The negative legacy import defect was source-confirmed, not reproduced against
the old revision.

The pre-legacy-correction focused Debug Local simulator run passed 224/224
with zero skips on iPhone 17 Pro Max / iOS 26.1. It covered Cushion, Goal
protection, Bill funding and mutation, F6 conflicts, financial calculation, ATS, Set
Aside, and Plan Ahead presentation. A disposable file-backed SwiftData store
preserved both a negative and a positive-infinite Cushion across reopen;
negative and positive-infinite allocations also survived reopen and remained
non-authoritative.
The tests changed those same-owner records to valid amounts with explicit
ModelContext saves and verified Cushion recovery after reload and allocation
snapshot recovery after correction; they did not exercise an in-app repair UI.
Owner switching kept the unaffected owner's Cushion available. F10 service
fixtures used catch-all offline URL-protocol sessions; no bank request was
intentionally exercised. The earlier Release Candidate simulator build and
`git diff --check` passed. No historical migration, rendered UI,
NaN-on-disk representation, live provider, backend, or production environment
was tested. F14's containment and release-execution gates remain open.

After the legacy correction, seven selected production-service legacy import,
reload, owner-isolation, and recovery tests passed with zero skips. A separate
25-test Cushion integrity and Available to Spend presentation run passed with
zero skips; these are focused corrected-source runs and do not repeat the
earlier 224-test selection. The corrected-source Release Candidate simulator
build passed. The fresh import reload used a second in-memory SwiftData context
and service, not a process relaunch or historical store migration. The test
compared the original UserDefaults numeric value before and after; no raw
UserDefaults serialization-byte comparison or rendered Set Aside UI was made.

## F14 remaining work

Historical F11 hosted-validation failures are now separated: Slice 1's direct
security contract is accepted, and V13's explicit cancellation/settlement
ordering is closed. V14's tiny actor and ordinary production graph reproduced
isolated-deinit/TaskLocal invalid-free behavior on 26.1. The authorized production
ambient-animation removal is accepted/closed for simulator compatibility after
the final 26.1/26.5 simulator matrix passed. Ordinary construction requires neither
PlanningViewValidationControl nor DashboardAmbientBlobActivity. Physical 26.1
release evidence remains outstanding, and the minimum stays unchanged.
V15's test-harness lifetime correction is accepted and closed. Physical iOS
26.1 release qualification remains outstanding.

The F14-B tracked CI implementation is accepted and checkpointed; actual
GitHub execution remains pending. F14 is not closed.

V11's named fixture containment and exact disconnect assertion are implemented,
accepted, and checkpointed in F14-A above; this does not certify unnamed
fixtures or broad release execution. The earlier Debug Local Sandbox request's
receipt and side effects remain unknown; no claim is made that no request escaped.

V12's corrected contracts/historical crash disposition are accepted;
V13 ordering is closed by Slice 1, not by containment. V14 simulator
compatibility and V15 mounted-fixture lifetime are accepted. Physical iOS
26.1 release qualification remains open. No aggregate release pass.

The historical card-detail sign-out crash was reproduced in the fixture's
isolated Credentials destructor and matches the independent runtime repro;
it does not call the backend sanitizer changed for F8. The corrected selection
passes, without a claim that its previously invalid cleanup caused the crash.

Exact-candidate aggregate release execution remains open, including backend-chain,
Express/Postgres and iOS evidence on the same committed candidate after runtime
blockers are resolved. F14-B definitions or focused working-tree checks do not
mark that execution passed. V11 is closed; the remaining F14 gates stay open.
