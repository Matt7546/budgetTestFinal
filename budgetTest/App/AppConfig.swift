import CryptoKit
import Foundation

/// Explicit auth contract plus normalized origin. Labels/schemes never select
/// credentials. A different origin is a different namespace, even in local QA.
struct AuthBackendEnvironment: Equatable {
    enum ID: String {
        case developmentLocal = "development-local"
        case renderProduction = "render-production"
    }

    let id: ID
    let baseURL: URL
    let credentialNamespace: String

    init?(id: ID, baseURL: URL) {
        guard var origin = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = origin.scheme?.lowercased(),
              let host = origin.host?.lowercased(),
              !host.isEmpty,
              origin.user == nil, origin.password == nil,
              origin.query == nil, origin.fragment == nil,
              origin.path.isEmpty || origin.path == "/",
              origin.percentEncodedHost?.contains("%") == false else { return nil }

        switch id {
        case .developmentLocal:
            let parts = host.split(separator: ".", omittingEmptySubsequences: false)
            let octets = parts.compactMap { Int($0) }
            let privateIPv4 = parts.count == 4 && octets.count == 4 &&
                zip(parts, octets).allSatisfy { String($0.1) == $0.0 && (0...255).contains($0.1) } &&
                (octets[0] == 10 || octets[0] == 127 ||
                 (octets[0] == 192 && octets[1] == 168) ||
                 (octets[0] == 172 && (16...31).contains(octets[1])))
            guard ["http", "https"].contains(scheme), origin.port == 3001,
                  host == "localhost" || privateIPv4 else { return nil }
        case .renderProduction:
            guard scheme == "https", host == "plaid-backend-2wqb.onrender.com",
                  origin.port == nil || origin.port == 443 else { return nil }
        }

        origin.scheme = scheme
        origin.host = host
        origin.path = ""
        if (scheme == "https" && origin.port == 443) ||
            (scheme == "http" && origin.port == 80) {
            origin.port = nil
        }
        guard let normalizedURL = origin.url else { return nil }
        let digest = SHA256.hash(data: Data(normalizedURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        self.id = id
        self.baseURL = normalizedURL
        credentialNamespace = "v1.\(id.rawValue).\(digest)"
    }

    func endpoint(_ path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { $0.appendingPathComponent(String($1)) }
    }
}

struct AppEnvironment {
    let apiBaseURL: URL
    let displayName: String
    let expectedPlaidEnvironment: String
    let isDebug: Bool
    var authEnvironmentID: AuthBackendEnvironment.ID? = nil

    var authEnvironment: AuthBackendEnvironment? {
        guard let authEnvironmentID,
              (authEnvironmentID == .developmentLocal && isDebug && expectedPlaidEnvironment == "sandbox") ||
                (authEnvironmentID == .renderProduction && !isDebug && expectedPlaidEnvironment == "production") else {
            return nil
        }
        return AuthBackendEnvironment(id: authEnvironmentID, baseURL: apiBaseURL)
    }
}

enum AppConfig {

    // DEBUG uses the local iMac backend with Plaid Sandbox.
    // RELEASE/TestFlight uses the hosted Render backend with Plaid Production.
    // Plaid secrets must stay on the backend, never in the iOS app.
    #if DEBUG
    static let environment = AppEnvironment(
        apiBaseURL: URL(string: "http://10.0.0.244:3001")!,
        displayName: "Local Sandbox",
        expectedPlaidEnvironment: "sandbox",
        isDebug: true,
        authEnvironmentID: .developmentLocal
    )
    #else
    static let environment = AppEnvironment(
        apiBaseURL: URL(string: "https://plaid-backend-2wqb.onrender.com")!,
        displayName: "Render Production",
        expectedPlaidEnvironment: "production",
        isDebug: false,
        authEnvironmentID: .renderProduction
    )
    #endif

    static var backendBaseURL: URL {
        environment.apiBaseURL
    }

    static let authEnvironment = environment.authEnvironment

    static var environmentDisplayName: String {
        environment.displayName
    }

    static var expectedPlaidEnvironment: String {
        environment.expectedPlaidEnvironment
    }

    static let requiresAuthenticatedBankData = true
    static let plaidRefreshPolicy: PlaidRefreshPolicy = .manualOnly

    // Keep Apple Wallet access unavailable until Apple assigns the managed
    // FinanceKit entitlement to this bundle ID and signing is configured.
    static let appleWalletFinanceEnabled = false

    #if DEBUG
    static var isDebugLocal: Bool {
        DebugLocalFeatureGate.isEnabled(
            explicitLocalValue: ProcessInfo.processInfo.environment["CALDERA_DEBUG_LOCAL"],
            labValue: ProcessInfo.processInfo.environment["CALDERA_LAB"],
            environment: environment
        )
    }
    #else
    static let isDebugLocal = false
    #endif

    #if DEBUG
    static var isLabEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        let rawValue = environment["CALDERA_LAB"] ?? environment["CALDERA_LAB_ENABLED"] ?? ""

        return [
            "1",
            "true",
            "yes",
            "enabled"
        ].contains(rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    #else
    static let isLabEnabled = false
    #endif

    // Provide APP_API_KEY through Config/Secrets.xcconfig -> Info.plist.
    // The same build-setting path is used for Debug and Release so local and
    // Render backends can both require x-app-api-key without fallback keys.
    static let backendAPIKey: String = {
        guard let bundledKey = Bundle.main.object(
            forInfoDictionaryKey: "APP_API_KEY"
        ) as? String,
              !bundledKey.isEmpty,
              !bundledKey.contains("$(") else {
            return ""
        }

        return bundledKey
    }()

    static var isBackendAPIKeyConfigured: Bool {
        !backendAPIKey.isEmpty
    }

    #if DEBUG
    static var debugConfigurationWarnings: [String] {
        var warnings: [String] = []

        if backendBaseURL.host != "10.0.0.244" {
            warnings.append("DEBUG is not pointing at the local backend.")
        }

        if expectedPlaidEnvironment != "sandbox" {
            warnings.append("DEBUG is not configured for Plaid Sandbox.")
        }

        if backendAPIKey.isEmpty {
            warnings.append("APP_API_KEY is missing. Add it to Config/Secrets.xcconfig.")
        }

        return warnings
    }
    #endif

    static func plaidEndpoint(
        _ path: String
    ) -> URL {
        let pathComponents = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .map(String.init)

        return pathComponents.reduce(backendBaseURL) { url, component in
            url.appendingPathComponent(component)
        }
    }

    static func configureBackendRequest(
        _ request: inout URLRequest,
        bearerToken: String? = nil
    ) {
        if !backendAPIKey.isEmpty {
            request.setValue(
                backendAPIKey,
                forHTTPHeaderField: "x-app-api-key"
            )
        }

        if let bearerToken = bearerToken?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
           !bearerToken.isEmpty {
            request.setValue(
                "Bearer \(bearerToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
    }
}

enum DebugLocalFeatureGate {

    static func isEnabled(
        explicitLocalValue: String?,
        labValue: String?,
        environment: AppEnvironment
    ) -> Bool {
        environment.isDebug &&
            environment.expectedPlaidEnvironment == "sandbox" &&
            isTruthy(explicitLocalValue) &&
            !isTruthy(labValue)
    }

    private static func isTruthy(
        _ value: String?
    ) -> Bool {
        guard let value else {
            return false
        }

        return [
            "1",
            "true",
            "yes",
            "enabled"
        ].contains(
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }
}
