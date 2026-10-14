# Privacy-safe release diagnostics — F15

Implementation is awaiting corrective acceptance. It starts from accepted candidate
`a0939d1`; no release-ready claim or logging transport is added. Apple Unified
Logging stores diagnostics locally under the app bundle identifier (fallback:
`com.caldera.money`) and the existing category strings. No telemetry SDK, remote
request, custom log database, consent change, or financial change is involved.

## Baseline inventory

At `a0939d1`, all ten `AppLogger` methods existed in every configuration but
their bodies were conditional on `DEBUG`. RC/Release did nothing and evaluated
none of their message autoclosures. Debug used the private `log` helper's `print`.

| API | Previous Debug behavior | F15 RC/Release behavior |
| --- | --- | --- |
| `error` | Always printed error details | Unified error with public metadata only; message is not evaluated |
| `warning` | Always printed warning details | Unified native `.error` level with explicit `warning` severity; message is not evaluated |
| `environment` | Disabled by `showsEnvironmentInfo = false` | Unchanged no-op |
| `plaidVerbose` | Disabled by `showsPlaidVerbose = false` | Unchanged no-op |
| `plaidOAuth` | Disabled by `showsPlaidOAuthDiagnostics = false` | Unchanged no-op |
| `plaidOAuthDiagnostic` | Same disabled OAuth switch | Unchanged no-op |
| `plaidAccountSnapshot` | Always Debug-only | Unchanged no-op |
| `developerQA` | Enabled Debug-only QA switch | Unchanged no-op |
| `auth` | Enabled Debug-only auth switch | Unchanged no-op |
| `performance` | Controlled by `AppPerformanceSettings.logsPerformanceDiagnostics` | Unchanged no-op |

Debug error/warning details now use explicitly **private** unified-log
interpolation. They remain available to development tooling subject to Apple's
private-data policy; public metadata remains useful without them. The remaining
Debug verbose/QA APIs and their switches are unchanged, outside this bounded
critical-diagnostic contract.

The native warning level is `.error`, matching Apple's
[`Logger.warning(_:)`](https://developer.apple.com/documentation/os/logger/warning%28_%3A%29),
which is functionally equivalent to `Logger.error(_:)`. The structured semantic
label remains `warning`. The focused native-level regression inspects the same
`Severity.logType` mapping consumed by both production emission branches and
also verifies ordinary errors use `.error` and faults use `.fault`.

All 66 direct baseline error/warning call sites were inspected before editing.
These are source line numbers at `a0939d1`, not post-change line references:

| File under `budgetTest/` | Baseline lines |
| --- | --- |
| `Services/Plaid/PlaidService.swift` | 913, 922, 951, 968, 1180, 1218, 1259, 1928, 1994, 2170, 2284, 2316, 2351, 2386, 2497, 2614, 2730, 2886, 2996, 3019, 3036, 3055, 3174, 3357, 3413, 3422, 3488, 3611, 3620, 3629, 3644, 3676, 3889, 3931, 4094, 4528, 4631, 4842, 5322 |
| `Services/Plaid/PlaidLocalCache.swift` | 115, 122, 302, 324 |
| `Services/Auth/AuthManager.swift` | 408, 458, 509, 600, 646, 705, 728, 779, 825, 854 |
| `Models/Planning/PlanningDataOwnership.swift` | 631, 703, 749 |
| `Views/Planner/RecurringExpenseRecommendationHistory.swift` | 412, 430, 443 |
| `Views/Planner/PlannerView.swift` | 1025 |
| `Views/Goals/SavingsGoalsView.swift` | 1272, 1341 |
| `Views/Settings/DeveloperQASection.swift` | 715, 798 |
| `App/budgetTestApp.swift` | 79, 145 |

Expressions are literals, values, or error-description/property reads; no
explicit mutation, provider request, or save was found inside a message
autoclosure. Custom getter purity is not assumed: RC/Release still evaluates
**none** of the legacy messages. Existing decoder/provider/status text cannot
enter a public release record. No broad call-site rewrite was needed.

## Public record and startup behavior

`AppLogger.PublicRecord` is an encodable value constructed only in the logger
file from closed event/category/build enums, source `StaticString` values, and
line number. Its public fields are event, severity, category, build context,
`#fileID`, `#function`, and `#line`; derived call-site identity/message contain
only those values. `#filePath` is not used by production diagnostics. There is
no arbitrary metadata dictionary, underlying error, NSError domain/code, URL,
path, identity, provider payload, or financial amount in this record.

`LegacyDiagnostic.privateDetails` is separate from the public record, is never
serialized as a whole, and is nil in release. Debug's existing free-form
error/warning details are interpolated with `.private`. The default release
policy does not evaluate the message just to redact it later.

| Stable event code | Severity/category | Production boundary |
| --- | --- | --- |
| `legacy.error` | error / original category | Existing error API; source identity identifies the call site |
| `legacy.warning` | warning / original category | Existing warning API |
| `startup.application-support.failed` | warning / Persistence | Directory preparation failed; startup continues as before |
| `startup.model-container.failed` | fault / Persistence | Initialization failed; reports before rethrow and existing termination |
| `startup.ui-validation.failed` | fault / Environment | Only the `CALDERA_UI_VALIDATION` startup branch; validation build context |

Previously the directory warning disappeared in release, and both initialization
fatal messages interpolated `error.localizedDescription`. The initialization
callers now use exactly `Unable to initialize Caldera SwiftData.` or
`Unable to initialize isolated UI validation.` No error/path text enters either
fatal message; both fatal calls explicitly use `file: #fileID` so their source
prefix cannot expose a compiler file-system user path. The same store configuration, operation, thrown error, and
fail-fast/continue behavior are preserved; no fallback, recovery, deletion, or
schema change is introduced.

The synchronous `AppStartupDiagnostics` operations accept immediate test
reporters, never retained references in the SwiftUI graph. A failed attempt
reports once before returning false/rethrowing; successful or nil results report
nothing. These functions run during initialization/directory preparation, not
view rendering. The logger has no recursion, retries, or deduplication framework.
Existing error frequency is unchanged.

## Focused validation

`AppLoggerPrivacyTests` and `AppStartupDiagnosticsTests` inherit the existing
contained test base. They declare no HTTP work; any host/default-session request
is a test failure. Public-record tests recursively inspect encoded keys/values,
including numbers, plus every derived public output against unique synthetic
credential, identity, account/name, monetary, URL/path, provider, and localized
error sentinels. Startup failures are injected at the actual synchronous
production boundary; no real startup store failure or rendered crash is needed.

Use the same contained-host invocation as `scripts/test-contained-ios.sh`, with
only these two new selectors. The wrapper's existing accepted-class allowlist
is intentionally unchanged. Create one disposable simulator and a fresh external
evidence directory; copy an existing locked Plaid 6.4.2 `SourcePackages` tree
offline. Do not use the ordinary configured app host or resolve packages online.

```sh
xcodebuild -project budgetTest.xcodeproj -scheme budgetTest -configuration Debug \
  -destination 'platform=iOS Simulator,id=<disposable-uuid>' \
  -derivedDataPath <evidence>/DerivedData -resultBundlePath <evidence>/F15.xcresult \
  -clonedSourcePackagesDirPath <offline-SourcePackages> \
  -disableAutomaticPackageResolution -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG CALDERA_UI_VALIDATION CALDERA_TEST_NETWORK_CONTAINMENT' \
  'TEST_HOST=$(BUILT_PRODUCTS_DIR)/Caldera Money.app/Caldera Money' APP_API_KEY= \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  -only-testing:budgetTestTests/AppLoggerPrivacyTests \
  -only-testing:budgetTestTests/AppStartupDiagnosticsTests test

bash scripts/build-release.sh -derivedDataPath <fresh-RC-evidence> \
  -clonedSourcePackagesDirPath <offline-SourcePackages> \
  -disableAutomaticPackageResolution -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES APP_API_KEY=
```

Swift parsing, the focused result, the final RC arm64 binary's stable event
strings/sentinel absence, and an optimized non-DEBUG executable compiled from
the actual `AppLogger.swift` provide separate evidence. The executable checks
zero evaluation through the production error/warning APIs. It is macOS source
evidence, not inspection of Console.app or physical-device unified logs. The
RC build proves the iOS release implementation compiles. Focused dirty-tree
checks do not certify a future committed candidate or remove release blockers.

Initial implementation evidence: the selected two classes passed 16/16 with zero
failures/skips on Xcode 27.0 / iOS 26.1. The final RC arm64 simulator build
passed; both production startup codes are present in its binary, with zero
matches for the 20 synthetic privacy sentinels. The optimized non-DEBUG actual
logger probe passed with zero message evaluations. Parsing/type-checking and
diff checks passed. Evidence, source hashes, and binary inspection remain under
`/private/tmp/caldera-f15-diagnostics-ZWumKr/`; its only disposable simulator was
removed. Console.app/physical-device logs were not inspected. Startup failures
were injected at the production boundary, not caused by a real storage fault.

The prior hosted run `38491788968` passed all required candidate gates for
`a0939d1` / PR merge `854c139`; its finalized aggregate reports checks passed,
release not ready. This new source awaits focused acceptance and checkpoint.
F15 remains open in `scripts/release-gates.json`; physical iOS 26.1 smoke remains
open. No merge, deployment, or next hardening slice is authorized by this work.

Corrected-source evidence: the native-level regression and existing F15 suite
passed **17/17**, zero failures/expected failures/skips, on contained iOS 26.1.
The optimized non-DEBUG production logger probe again recorded zero message
evaluations. Final RC arm64 build, Swift parsing/non-Debug logger typechecking,
source hashes, and diff checks passed. All three startup event strings remain
in the RC binary, with zero matches for the 20 privacy sentinels. Evidence is
retained at `/private/tmp/caldera-f15-warning-H4vkuN/`; its disposable simulator
was removed. The reviewed actor-isolation warnings remain unchanged. This
corrects the sole native-warning defect found at acceptance; F15 still awaits
corrective acceptance and checkpoint. These tests do not certify operating-system
log retrieval, physical-device behavior, or a future committed candidate.
