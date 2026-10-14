import Foundation
import XCTest
@testable import Caldera_Money

@MainActor
final class AppStartupDiagnosticsTests: ContainedNetworkTestCase {
    private var sensitiveError: NSError {
        NSError(domain: "f15-private-error-domain", code: 42,
                userInfo: [NSLocalizedDescriptionKey: DiagnosticPrivacyAssertions.sentinels.joined(separator: " ")])
    }

    func testDirectoryFailureWarnsOnceAndPreservesContinueStartupBehavior() throws {
        var attempts = 0
        var records: [AppLogger.PublicRecord] = []
        let error = sensitiveError
        let result = AppStartupDiagnostics.prepareStoreDirectory(
            URL(fileURLWithPath: DiagnosticPrivacyAssertions.sentinels[15]),
            createDirectory: { _ in attempts += 1; throw error },
            report: { records.append($0) }
        )
        XCTAssertFalse(result)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.event, .applicationSupportPreparationFailed)
        XCTAssertEqual(record.severity, .warning)
        XCTAssertEqual(record.category, .persistence)
        try DiagnosticPrivacyAssertions.assertSafe(record)
    }

    func testSuccessfulDirectoryPreparationEmitsNoFailure() {
        var attempts = 0
        var records: [AppLogger.PublicRecord] = []
        XCTAssertTrue(AppStartupDiagnostics.prepareStoreDirectory(
            URL(fileURLWithPath: "/synthetic-unused-directory"),
            createDirectory: { _ in attempts += 1 }, report: { records.append($0) }
        ))
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(records.isEmpty)
    }

    func testInitializationFaultIsReportedBeforeOriginalFailureIsRethrown() throws {
        for kind in AppStartupDiagnostics.Initialization.allCases {
            var records: [AppLogger.PublicRecord] = []
            var attempts = 0
            let error = sensitiveError
            do {
                let _: Int = try AppStartupDiagnostics.initialize(
                    kind, operation: { attempts += 1; throw error }, report: { records.append($0) }
                )
                XCTFail("Initialization failure must propagate to the existing fail-fast caller")
            } catch let caught as NSError {
                XCTAssertTrue(caught === error)
                XCTAssertEqual(records.count, 1)
            }
            XCTAssertEqual(attempts, 1)
            let record = try XCTUnwrap(records.first)
            XCTAssertEqual(record.event, kind.event)
            XCTAssertEqual(record.severity, .fault)
            XCTAssertEqual(record.category, kind.category)
            try DiagnosticPrivacyAssertions.assertSafe(record)
        }
    }

    func testSuccessfulAndNilInitializationEmitNoFalseFault() throws {
        for kind in AppStartupDiagnostics.Initialization.allCases {
            var records: [AppLogger.PublicRecord] = []
            let value = try AppStartupDiagnostics.initialize(
                kind, operation: { 42 }, report: { records.append($0) }
            )
            let absent: Int? = try AppStartupDiagnostics.initialize(
                kind, operation: { nil }, report: { records.append($0) }
            )
            XCTAssertEqual(value, 42)
            XCTAssertNil(absent)
            XCTAssertTrue(records.isEmpty)
        }
    }

    func testFatalMessagesAreFixedAndContainNoUnderlyingErrorOrPath() {
        XCTAssertEqual(AppStartupDiagnostics.Initialization.modelContainer.fatalMessage,
                       "Unable to initialize Caldera SwiftData.")
        XCTAssertEqual(AppStartupDiagnostics.Initialization.uiValidation.fatalMessage,
                       "Unable to initialize isolated UI validation.")
        for kind in AppStartupDiagnostics.Initialization.allCases {
            for sentinel in DiagnosticPrivacyAssertions.sentinels {
                XCTAssertFalse(kind.fatalMessage.contains(sentinel))
            }
            XCTAssertFalse(kind.fatalMessage.contains(sensitiveError.localizedDescription))
            XCTAssertFalse(kind.fatalMessage.contains(sensitiveError.domain))
        }
    }

    func testEachFailedAttemptReportsOnceAndRecoveryAddsNoFault() throws {
        var records: [AppLogger.PublicRecord] = []
        var attempts = 0
        let error = sensitiveError
        for _ in 0..<2 {
            XCTAssertThrowsError(try AppStartupDiagnostics.initialize(
                .modelContainer, operation: { () throws -> Int in attempts += 1; throw error },
                report: { records.append($0) }
            ))
        }
        let value = try AppStartupDiagnostics.initialize(
            .modelContainer, operation: { attempts += 1; return 42 }, report: { records.append($0) }
        )
        XCTAssertEqual(value, 42)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.event == .modelContainerInitializationFailed })
        for record in records { try DiagnosticPrivacyAssertions.assertSafe(record) }
    }

    func testValidationFaultIsClearlyAttributedToValidationHost() throws {
        #if CALDERA_UI_VALIDATION
        var records: [AppLogger.PublicRecord] = []
        XCTAssertThrowsError(try AppStartupDiagnostics.initialize(
            .uiValidation, operation: { () throws -> Int in throw sensitiveError },
            report: { records.append($0) }
        ))
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.event, .uiValidationInitializationFailed)
        XCTAssertEqual(record.buildContext, .uiValidation)
        XCTAssertEqual(record.category, .environment)
        try DiagnosticPrivacyAssertions.assertSafe(record)
        #endif
    }
}
