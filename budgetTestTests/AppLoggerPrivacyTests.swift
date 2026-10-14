import Foundation
import OSLog
import XCTest
@testable import Caldera_Money

@MainActor
final class AppLoggerPrivacyTests: ContainedNetworkTestCase {
    func testNativeEmissionLevelsPreserveWarningSemantics() throws {
        // Both production logger.log branches consume record.severity.logType.
        // Inspect that exact mapping, rather than only its public text label.
        let cases: [(AppLogger.Event, String, OSLogType)] = [
            (.legacyWarning, "warning", .error),
            (.applicationSupportPreparationFailed, "warning", .error),
            (.legacyError, "error", .error),
            (.modelContainerInitializationFailed, "fault", .fault),
            (.uiValidationInitializationFailed, "fault", .fault)
        ]
        for (event, label, nativeLevel) in cases {
            let record = AppLogger.makeRecord(event: event, category: .persistence)
            XCTAssertEqual(record.severity.rawValue, label)
            XCTAssertEqual(record.severity.logType, nativeLevel)
            if label == "warning" {
                XCTAssertNotEqual(record.severity.logType, .default)
            }
            try DiagnosticPrivacyAssertions.assertSafe(record)
        }
    }

    func testReleaseErrorHasUsefulPublicCallSiteMetadata() throws {
        let diagnostic = AppLogger.makeLegacyDiagnostic(
            DiagnosticPrivacyAssertions.sentinels.joined(separator: " "),
            event: .legacyError, category: .persistence,
            messagePolicy: .metadataOnly, buildContext: .release,
            fileID: "Caldera/PlanPersistence.swift", function: "savePlan()", line: 247
        )
        XCTAssertEqual(diagnostic.publicRecord.event, .legacyError)
        XCTAssertEqual(diagnostic.publicRecord.severity, .error)
        XCTAssertEqual(diagnostic.publicRecord.category, .persistence)
        XCTAssertEqual(diagnostic.publicRecord.buildContext, .release)
        XCTAssertEqual(diagnostic.publicRecord.fileID, "Caldera/PlanPersistence.swift")
        XCTAssertEqual(diagnostic.publicRecord.function, "savePlan()")
        XCTAssertEqual(diagnostic.publicRecord.line, 247)
        XCTAssertEqual(diagnostic.publicRecord.callSiteID, "Caldera/PlanPersistence.swift:savePlan():247")
        XCTAssertNil(diagnostic.privateDetails)
        try DiagnosticPrivacyAssertions.assertSafe(diagnostic.publicRecord)
    }

    func testReleaseWarningPreservesEveryExistingCategory() throws {
        for category in AppLogger.Category.allCases {
            let diagnostic = AppLogger.makeLegacyDiagnostic(
                DiagnosticPrivacyAssertions.sentinels.joined(separator: " "),
                event: .legacyWarning, category: category,
                messagePolicy: .metadataOnly, buildContext: .release
            )
            XCTAssertEqual(diagnostic.publicRecord.severity, .warning)
            XCTAssertEqual(diagnostic.publicRecord.category, category)
            XCTAssertTrue(diagnostic.publicRecord.publicMessage.contains("event=legacy.warning"))
            XCTAssertTrue(diagnostic.publicRecord.publicMessage.contains("category=\(category.rawValue)"))
            XCTAssertNil(diagnostic.privateDetails)
            try DiagnosticPrivacyAssertions.assertSafe(diagnostic.publicRecord)
        }
    }

    func testReleaseModeNeverEvaluatesArbitraryMessageOrItsSideEffects() throws {
        var evaluations = 0
        func message() -> String {
            evaluations += 1
            return DiagnosticPrivacyAssertions.sentinels.joined(separator: " ")
        }
        for event in [AppLogger.Event.legacyError, .legacyWarning] {
            let diagnostic = AppLogger.makeLegacyDiagnostic(
                message(), event: event, category: .auth,
                messagePolicy: .metadataOnly, buildContext: .release
            )
            XCTAssertNil(diagnostic.privateDetails)
            try DiagnosticPrivacyAssertions.assertSafe(diagnostic.publicRecord)
        }
        XCTAssertEqual(evaluations, 0)
    }

    func testEverySensitiveLegacySentinelIsAbsentFromEveryPublicField() throws {
        for sentinel in DiagnosticPrivacyAssertions.sentinels {
            for event in [AppLogger.Event.legacyError, .legacyWarning] {
                let diagnostic = AppLogger.makeLegacyDiagnostic(
                    sentinel, event: event, category: .plaid,
                    messagePolicy: .metadataOnly, buildContext: .release
                )
                XCTAssertNil(diagnostic.privateDetails)
                try DiagnosticPrivacyAssertions.assertSafe(diagnostic.publicRecord)
            }
        }
    }

    func testPrivateDebugDetailsRemainAvailableWithoutEnteringPublicRecord() throws {
        var evaluations = 0
        func message() -> String {
            evaluations += 1
            return DiagnosticPrivacyAssertions.sentinels.joined(separator: " ")
        }
        let diagnostic = AppLogger.makeLegacyDiagnostic(
            message(), event: .legacyError, category: .persistence,
            messagePolicy: .privateDebugDetails, buildContext: .debug
        )
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(diagnostic.privateDetails, DiagnosticPrivacyAssertions.sentinels.joined(separator: " "))
        try DiagnosticPrivacyAssertions.assertSafe(diagnostic.publicRecord)
    }

    func testProductionErrorAndWarningUseCompiledMessagePolicy() {
        var evaluations = 0
        func message() -> String { evaluations += 1; return "Synthetic developer detail" }
        AppLogger.error(message(), category: .persistence)
        AppLogger.warning(message(), category: .auth)
        #if DEBUG
        XCTAssertEqual(evaluations, 2)
        XCTAssertEqual(AppLogger.MessagePolicy.current, .privateDebugDetails)
        #else
        XCTAssertEqual(evaluations, 0)
        XCTAssertEqual(AppLogger.MessagePolicy.current, .metadataOnly)
        #endif
    }

    func testStructuredStartupCodesArePublicAndFixed() throws {
        let cases: [(AppLogger.Event, String, AppLogger.Severity)] = [
            (.applicationSupportPreparationFailed, "startup.application-support.failed", .warning),
            (.modelContainerInitializationFailed, "startup.model-container.failed", .fault),
            (.uiValidationInitializationFailed, "startup.ui-validation.failed", .fault)
        ]
        for (event, code, severity) in cases {
            let record = AppLogger.makeRecord(event: event, category: .persistence, buildContext: .release)
            XCTAssertEqual(record.event.rawValue, code)
            XCTAssertEqual(record.severity, severity)
            XCTAssertTrue(record.publicMessage.contains("event=\(code)"))
            try DiagnosticPrivacyAssertions.assertSafe(record)
        }
    }

    func testDefaultSourceIdentityUsesFileIDRatherThanUserFilePath() throws {
        let record = AppLogger.makeRecord(event: .legacyWarning, category: .auth)
        XCTAssertEqual(record.fileID, #fileID)
        XCTAssertEqual(record.function, #function)
        XCTAssertFalse(record.fileID.hasPrefix("/"))
        XCTAssertFalse(record.fileID.contains("/Users/"))
        XCTAssertGreaterThan(record.line, 0)
        try DiagnosticPrivacyAssertions.assertSafe(record)
    }

    func testUnifiedLogSubsystemUsesBundleIdentifier() {
        XCTAssertEqual(AppLogger.subsystem, Bundle.main.bundleIdentifier ?? "com.caldera.money")
    }
}

@MainActor
enum DiagnosticPrivacyAssertions {
    static let sentinels = [
        "f15-access-token-E71942", "f15-session-jwt-0AC946", "f15-api-key-C10E32",
        "f15-plaid-client-secret-6BA241", "f15-encryption-key-930F7A",
        "f15-user-id-B897F0", "f15-person-70429@example.invalid",
        "f15-account-id-C86142", "F15 Private Institution 94572", "F15 Card Name 50419",
        "948271.63", "742916.28", "f15-transaction-description-80496",
        "https://f15-url.invalid/private?token=f15-query-91746#f15-fragment-80421",
        "postgresql://f15-user:f15-password@f15-db.invalid/private-db-84526",
        "/Users/f15-private-user-81392/Library/Application Support/private.store",
        "f15-raw-provider-response-30184", "f15-raw-backend-response-90162",
        "f15-raw-swiftdata-localized-error-58426", "f15-private-error-domain"
    ]

    static func assertSafe(_ record: AppLogger.PublicRecord,
                           file: StaticString = #filePath, line: UInt = #line) throws {
        // Codable covers every stored public field; computed output is scanned
        // separately. Recursion also covers any future nested public metadata.
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
        let values: [Any] = [encoded, record.callSiteID, record.publicMessage]
        func inspect(_ value: Any) {
            if let string = value as? String {
                for sentinel in sentinels {
                    XCTAssertFalse(string.contains(sentinel), "Sensitive sentinel entered public diagnostics",
                                   file: file, line: line)
                }
            } else if let fields = value as? [String: Any] {
                for (key, child) in fields { inspect(key); inspect(child) }
            } else if let children = value as? [Any] {
                children.forEach(inspect)
            } else if let number = value as? NSNumber {
                inspect(number.stringValue)
            } else if !(value is NSNull) {
                XCTFail("Uninspected public diagnostic field type", file: file, line: line)
            }
        }
        values.forEach(inspect)
    }
}
