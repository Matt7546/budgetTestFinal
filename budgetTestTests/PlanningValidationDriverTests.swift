import XCTest
@testable import Caldera_Money

@MainActor
final class PlanningValidationDriverTests: ContainedNetworkTestCase {
    func testValueHooksDoNotRetainDriverAndMissingDriverDeniesCallback() async {
        var driver: PlanningValidationDriver? = PlanningValidationDriver(blocksDeferredCallbacks: true)
        weak var weakDriver = driver
        let hooks = driver!.makeHooks()
        await driver!.close()
        driver = nil
        XCTAssertTrue(weakDriver == nil)
        var callbackID: UInt64? = 1
        expectDiagnostic(.queue) {
            callbackID = hooks.queueDeferredCallback()
        }
        XCTAssertNil(callbackID)
        var mayExecute = true
        expectDiagnostic(.execution) {
            mayExecute = hooks.beginCallbackExecution(1)
        }
        XCTAssertFalse(mayExecute)
    }

    func testClosedHooksDenyCallbackAndFailRequiredReads() async {
        let driver = PlanningValidationDriver(blocksDeferredCallbacks: true)
        let hooks = driver.makeHooks()
        await driver.close()
        var mayExecute = true
        expectDiagnostic(.execution) {
            mayExecute = hooks.beginCallbackExecution(1)
        }
        XCTAssertFalse(mayExecute)
        var failedReads: Set<PlanningPersistenceReadDomain> = []
        expectDiagnostic(.read) {
            failedReads = hooks.currentReadFailures()
        }
        XCTAssertEqual(failedReads, Set(PlanningPersistenceReadDomain.allCases))
        XCTAssertEqual(driver.outstandingCollectionCount, 0)
    }

    func testReleaseBeforeWaitIsConsumedExactlyOnceAndCloseEmptiesState() async throws {
        let driver = PlanningValidationDriver(blocksDeferredCallbacks: true)
        let id = try XCTUnwrap(driver.queueDeferredCallback())
        XCTAssertTrue(driver.releaseDeferredCallback(id))
        XCTAssertFalse(driver.releaseDeferredCallback(id))
        let released = await driver.awaitDeferredCallbackRelease(id)
        XCTAssertTrue(released)
        XCTAssertEqual(driver.trace.filter { $0.event == .callbackReleased(id) }.count, 1)
        await driver.close()
        XCTAssertTrue(driver.isClosed)
        XCTAssertEqual(driver.outstandingCollectionCount, 0)
        let activation = driver.mountedHoldActivationGeneration
        let traceCount = driver.trace.count
        expectDiagnostic(.activation) {
            driver.requestMountedHoldCallback()
        }
        XCTAssertEqual(driver.mountedHoldActivationGeneration, activation)
        XCTAssertEqual(driver.trace.count, traceCount)
        XCTAssertEqual(driver.outstandingCollectionCount, 0)
    }

    func testDiagnosticMatcherRequiresExactCategoryMessageAndSource() {
        for diagnostic in Diagnostic.allCases {
            let options = diagnostic.options()
            XCTAssertTrue(options.isStrict)
            XCTAssertTrue(options.issueMatcher(diagnostic.issue()))
            XCTAssertFalse(options.issueMatcher(diagnostic.issue(type: .system)))
            XCTAssertFalse(options.issueMatcher(diagnostic.issue(file: #filePath)))
            XCTAssertFalse(options.issueMatcher(diagnostic.issue(description: "XCTAssertFalse failed")))
            XCTAssertFalse(options.issueMatcher(diagnostic.issue(description: "failed - \(diagnostic.rawValue) extra")))
        }
    }

    func testUnauthorizedReturnFailsOutsideDiagnosticScope() async {
        let driver = PlanningValidationDriver(blocksDeferredCallbacks: true)
        let hooks = driver.makeHooks()
        await driver.close()
        let marker = "Driver contract probe: unauthorized return outside diagnostic scope"
        var ordinaryFailures = 0
        let probe = XCTExpectedFailure.Options()
        probe.isStrict = true
        probe.issueMatcher = { issue in
            guard Self.isProbeAssertion(issue, marker: marker) else { return false }
            ordinaryFailures += 1
            return true
        }
        // Only this meta-test accepts its deliberately broken result assertion.
        // The real driver contracts above have no enclosing failure scope.
        XCTExpectFailure("Verify the broken return remains an ordinary assertion", options: probe) {
            var brokenReturn = false
            expectDiagnostic(.execution) {
                _ = hooks.beginCallbackExecution(1)
                brokenReturn = true
            }
            XCTAssertFalse(brokenReturn, marker)
        }
        XCTAssertEqual(ordinaryFailures, 1)
        XCTAssertEqual(driver.outstandingCollectionCount, 0)
    }

    func testUnrelatedAssertionCannotReplaceMissingDriverDiagnostic() {
        let marker = "Driver contract probe: unrelated denial assertion"
        let reason = "Driver contract probe: required diagnostic deliberately absent"
        let options = Diagnostic.execution.options()
        XCTAssertTrue(options.isStrict)
        XCTAssertFalse(options.issueMatcher(Diagnostic.execution.issue(
            file: #filePath, description: "XCTAssertFalse failed - \(marker)")))
        // XCTest never suppresses an unmatched expected failure. A separately
        // selected negative run sets this test-only environment value and must
        // exit 65 with BOTH the unrelated assertion and absent diagnostic.
        // The ordinary six-test selection has no intentional failing child.
        if ProcessInfo.processInfo.environment["CALDERA_DRIVER_MISSING_DIAGNOSTIC_PROBE"] == "1" {
            XCTExpectFailure(reason, options: options) {
                XCTAssertFalse(true, marker)
            }
        }
    }

    private enum Diagnostic: String, CaseIterable {
        case queue = "Validation driver missing or closed during callback queue"
        case execution = "Validation driver missing or closed before callback execution"
        case read = "Validation driver missing or closed during required read"
        case activation = "Validation command invoked after driver close began"

        func options() -> XCTExpectedFailure.Options {
            let options = XCTExpectedFailure.Options()
            options.isStrict = true
            options.issueMatcher = { issue in
                issue.type == .assertionFailure &&
                issue.compactDescription == "failed - \(rawValue)" &&
                issue.sourceCodeContext.location?.fileURL.lastPathComponent == "PlanningValidationDriver.swift"
            }
            return options
        }

        func issue(type: XCTIssue.IssueType = .assertionFailure,
                   file: String = "PlanningValidationDriver.swift",
                   description: String? = nil) -> XCTIssue {
            XCTIssue(type: type, compactDescription: description ?? "failed - \(rawValue)",
                     detailedDescription: nil,
                     sourceCodeContext: XCTSourceCodeContext(location:
                        XCTSourceCodeLocation(filePath: file, lineNumber: 1)),
                     associatedError: nil, attachments: [])
        }
    }

    private func expectDiagnostic(_ diagnostic: Diagnostic, body: () -> Void) {
        XCTExpectFailure(diagnostic.rawValue, options: diagnostic.options(), failingBlock: body)
    }

    private static func isProbeAssertion(_ issue: XCTIssue, marker: String) -> Bool {
        issue.type == .assertionFailure &&
        issue.compactDescription == "XCTAssertFalse failed - \(marker)" &&
        issue.sourceCodeContext.location?.fileURL.lastPathComponent == "PlanningValidationDriverTests.swift"
    }
}
