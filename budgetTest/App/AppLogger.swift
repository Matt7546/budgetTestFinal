import Foundation

enum AppLogger {

    enum Category: String {
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

    #if DEBUG
    private static let showsEnvironmentInfo = false
    private static let showsPlaidVerbose = false
    private static let showsPlaidOAuthDiagnostics = false
    private static let showsDeveloperQADiagnostics = true
    private static let showsAuthDiagnostics = true
    #endif

    static func error(
        _ message: @autoclosure () -> String,
        category: Category
    ) {
        #if DEBUG
        log(
            "Error",
            message(),
            category: category
        )
        #endif
    }

    static func warning(
        _ message: @autoclosure () -> String,
        category: Category
    ) {
        #if DEBUG
        log(
            "Warning",
            message(),
            category: category
        )
        #endif
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
