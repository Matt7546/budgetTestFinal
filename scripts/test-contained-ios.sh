#!/usr/bin/env bash
set -euo pipefail

# Narrow F14-A gate, not a general test/release certification command.
# Arguments are an already-created disposable simulator UUID, a task-created
# evidence directory, and an offline copy of existing SourcePackages.
if [[ $# -lt 3 ]]; then
  echo "Usage: bash scripts/test-contained-ios.sh <simulator-uuid> <evidence-dir> <offline-source-packages> [TestClass/testMethod ...]" >&2
  exit 64
fi
CONTAINED_SIMULATOR_ID="$1"
CONTAINED_EVIDENCE_DIR="$2"
CONTAINED_PACKAGES_DIR="$3"
shift 3
if [[ ! "$CONTAINED_SIMULATOR_ID" =~ ^[0-9A-Fa-f-]{36}$ || ! -d "$CONTAINED_EVIDENCE_DIR" || ! -d "$CONTAINED_PACKAGES_DIR/artifacts" || ! -d "$CONTAINED_PACKAGES_DIR/checkouts/plaid-link-ios" ]]; then
  echo "Required disposable simulator/evidence/offline dependency inputs are missing." >&2
  exit 64
fi
if [[ "${CALDERA_DEBUG_LOCAL:-0}" != 0 || "${CALDERA_LAB:-0}" != 0 || "${CALDERA_LAB_ENABLED:-0}" != 0 ]]; then
  echo "Contained gate must not inherit Debug Local or Lab feature overrides." >&2
  exit 64
fi
CONTAINED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CONTAINED_SCRIPT_DIR/.."
if [[ $# -eq 0 ]]; then
  set -- ContainedTestTransportTests \
    BankDataRequestCacheIsolationTests/testDisconnectDuringRefreshRejectsLateSuccessAndFailureCallbacks \
    CardPaymentDetailsSessionIsolationTests/testCardDetailFixtureInterceptsAuthenticatedRefresh \
    CorePlanningUserIsolationTests/testCurrentBackendSessionExpiryInvalidatesAuthAndPlanningScope \
    CorePlanningUserIsolationTests/testStaleBackendSessionExpiryCannotInvalidateNewerUser
fi
CONTAINED_SELECTION=()
for CONTAINED_TEST in "$@"; do
  case "$CONTAINED_TEST" in
    ContainedTestTransportTests|ContainedTestTransportTests/*|BankDataRequestCacheIsolationTests/*|CardPaymentDetailsSessionIsolationTests/*|CorePlanningUserIsolationTests/*|MountedPlanningValidationTests/*) ;;
    *) echo "Test selection is outside the declared F14-A fixture scope." >&2; exit 64 ;;
  esac
  CONTAINED_SELECTION+=("-only-testing:budgetTestTests/$CONTAINED_TEST")
done

# CALDERA_UI_VALIDATION selects the existing in-memory, no-keychain-restore,
# catch-all-intercepted app host BEFORE XCTest starts. No project/scheme edit.
# Keep the ordinary Debug product name for this unit target's existing dylib path.
exec xcodebuild -project budgetTest.xcodeproj -scheme budgetTest -configuration Debug \
  -destination "platform=iOS Simulator,id=$CONTAINED_SIMULATOR_ID" \
  -derivedDataPath "$CONTAINED_EVIDENCE_DIR/DerivedData" \
  -resultBundlePath "$CONTAINED_EVIDENCE_DIR/Contained.xcresult" \
  -clonedSourcePackagesDirPath "$CONTAINED_PACKAGES_DIR" \
  -disableAutomaticPackageResolution -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG CALDERA_UI_VALIDATION CALDERA_TEST_NETWORK_CONTAINMENT' \
  'TEST_HOST=$(BUILT_PRODUCTS_DIR)/Caldera Money.app/Caldera Money' \
  APP_API_KEY= \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  "${CONTAINED_SELECTION[@]}" test
