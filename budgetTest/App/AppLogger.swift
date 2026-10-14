import Foundation
import OSLog

enum AppLogger {

    enum Category: String, Codable, CaseIterable {
        case environment = "Environment"
        case plaid = "Plaid"
        case plaidOAuth = "PlaidOAuth"
        case plaidCache = "PlaidCache"
        case plaidAccounts = "PlaidAccounts"
        case developerQA = "DeveloperQA"
        case persistence = "Persistence"
        case auth = "Auth"
        case performance = "Performance"
    }

    enum Severity: String, Codable {
        case warning, error, fault

        var logType: OSLogType {
            switch self {
            case .warning: .error
            case .error: .error
            case .fault: .fault
            }
        }
    }

    enum BuildContext: String, Codable {
        case debug, release, uiValidation

        static var current: Self {
            #if CALDERA_UI_VALIDATION
            .uiValidation
            #elseif DEBUG
            .debug
            #else
            .release
            #endif
        }
    }

    enum Event: String, Codable, CaseIterable {
        case legacyError = "legacy.error"
        case legacyWarning = "legacy.warning"
        case applicationSupportPreparationFailed = "startup.application-support.failed"
        case modelContainerInitializationFailed = "startup.model-container.failed"
        case uiValidationInitializationFailed = "startup.ui-validation.failed"

        var severity: Severity {
            switch self {
            case .legacyError: .error
            case .legacyWarning, .applicationSupportPreparationFailed: .warning
            case .modelContainerInitializationFailed, .uiValidationInitializationFailed: .fault
            }
        }
    }

    /// Only compiler source identity and closed diagnostic enums are public.
    /// No message, error, URL, account, or financial value enters this record.
    struct PublicRecord: Encodable, Equatable {
        let event: Event
        let severity: Severity
        let category: Category
        let buildContext: BuildContext
        let fileID: String
        let function: String
        let line: UInt

        fileprivate init(event: Event, category: Category, buildContext: BuildContext,
                         fileID: StaticString, function: StaticString, line: UInt) {
            self.event = event
            severity = event.severity
            self.category = category
            self.buildContext = buildContext
            self.fileID = String(describing: fileID)
            self.function = String(describing: function)
            self.line = line
        }

        var callSiteID: String { "\(fileID):\(function):\(line)" }

        var publicMessage: String {
            "event=\(event.rawValue) severity=\(severity.rawValue) category=\(category.rawValue) build=\(buildContext.rawValue) source=\(callSiteID)"
        }
    }

    enum MessagePolicy {
        case metadataOnly, privateDebugDetails

        static var current: Self {
            #if DEBUG
            .privateDebugDetails
            #else
            .metadataOnly
            #endif
        }
    }

    /// This value is never serialized or publicly interpolated as a whole.
    struct LegacyDiagnostic {
        let publicRecord: PublicRecord
        let privateDetails: String?
    }

    static var subsystem: String {
        guard let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty else {
            return "com.caldera.money"
        }
        return identifier
    }

    static func makeRecord(
        event: Event,
        category: Category,
        buildContext: BuildContext = .current,
        fileID: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) -> PublicRecord {
        PublicRecord(event: event, category: category, buildContext: buildContext,
                     fileID: fileID, function: function, line: line)
    }

    // The same builder is used by the production APIs and privacy regressions.
    // Forwarding message() into another autoclosure does not evaluate it.
    static func makeLegacyDiagnostic(
        _ message: @autoclosure () -> String,
        event: Event,
        category: Category,
        messagePolicy: MessagePolicy = .current,
        buildContext: BuildContext = .current,
        fileID: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) -> LegacyDiagnostic {
        let record = makeRecord(event: event, category: category, buildContext: buildContext,
                                fileID: fileID, function: function, line: line)
        let details = messagePolicy == .privateDebugDetails ? message() : nil
        return LegacyDiagnostic(publicRecord: record, privateDetails: details)
    }

    static func emit(_ record: PublicRecord) {
        emit(LegacyDiagnostic(publicRecord: record, privateDetails: nil))
    }

    private static func emit(_ diagnostic: LegacyDiagnostic) {
        let record = diagnostic.publicRecord
        let logger = Logger(subsystem: subsystem, category: record.category.rawValue)
        let publicMessage = record.publicMessage
        if let details = diagnostic.privateDetails {
            logger.log(level: record.severity.logType,
                       "\(publicMessage, privacy: .public) details=\(details, privacy: .private)")
        } else {
            logger.log(level: record.severity.logType, "\(publicMessage, privacy: .public)")
        }
    }

    #if DEBUG
    private static let showsEnvironmentInfo = false
    private static let showsPlaidVerbose = false
    private static let showsPlaidOAuthDiagnostics = false
    private static let showsDeveloperQADiagnostics = true
    private static let showsAuthDiagnostics = true
    #endif

    static func error(
        _ message: @autoclosure () -> String,
        category: Category,
        fileID: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        emit(makeLegacyDiagnostic(message(), event: .legacyError, category: category,
                                  fileID: fileID, function: function, line: line))
    }

    static func warning(
        _ message: @autoclosure () -> String,
        category: Category,
        fileID: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        emit(makeLegacyDiagnostic(message(), event: .legacyWarning, category: category,
                                  fileID: fileID, function: function, line: line))
    }

    static func environment(
        _ message: @autoclosure () -> String
    ) {
        #if DEBUG
        guard showsEnvironmentInfo else {
            return
        }

        log(
            "Info",
            message(),
            category: .environment
        )
        #endif
    }

    static func plaidVerbose(
        _ message: @autoclosure () -> String
    ) {
        #if DEBUG
        guard showsPlaidVerbose else {
            return
        }

        log(
            "Verbose",
            message(),
            category: .plaid
        )
        #endif
    }

    static func plaidOAuth(
        _ message: @autoclosure () -> String
    ) {
        #if DEBUG
        guard showsPlaidOAuthDiagnostics else {
            return
        }

        log(
            "Verbose",
            message(),
            category: .plaidOAuth
        )
        #endif
    }

    static func plaidOAuthDiagnostic(
        _ message: @autoclosure () -> String
    ) {
        #if DEBUG
        guard showsPlaidOAuthDiagnostics else {
            return
        }

        log(
            "Diagnostic",
            message(),
            category: .plaidOAuth
        )
        #endif
    }

    static func plaidAccountSnapshot(
        _ message: @autoclosure () -> String
    ) {
        #if DEBUG
        log(
            "Debug",
            message(),
            category: .plaidAccounts
        )
        #endif
    }

    static func developerQA(
        _ message: @autoclosure () -> String
    ) {
        #if DEBUG
        guard showsDeveloperQADiagnostics else {
            return
        }

        log(
            "Info",
            message(),
            category: .developerQA
        )
        #endif
    }

    static func auth(
        _ message: @autoclosure () -> String
    ) {
        #if DEBUG
        guard showsAuthDiagnostics else {
            return
        }

        log(
            "Info",
            message(),
            category: .auth
        )
        #endif
    }

    static func performance(
        _ message: @autoclosure () -> String
    ) {
        #if DEBUG
        guard AppPerformanceSettings.logsPerformanceDiagnostics else {
            return
        }

        log(
            "Info",
            message(),
            category: .performance
        )
        #endif
    }

    #if DEBUG
    private static func log(
        _ level: String,
        _ message: String,
        category: Category
    ) {
        print("[\(category.rawValue)] \(level): \(message)")
    }
    #endif
}
