import Foundation

struct AppEnvironment {
    let apiBaseURL: URL
    let displayName: String
    let expectedPlaidEnvironment: String
    let isDebug: Bool
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
        isDebug: true
    )
    #else
    static let environment = AppEnvironment(
        apiBaseURL: URL(string: "https://plaid-backend-2wqb.onrender.com")!,
        displayName: "Render Production",
        expectedPlaidEnvironment: "production",
        isDebug: false
    )
    #endif

    static var backendBaseURL: URL {
        environment.apiBaseURL
    }

    static var environmentDisplayName: String {
        environment.displayName
    }

    static var expectedPlaidEnvironment: String {
        environment.expectedPlaidEnvironment
    }

    static let requiresAuthenticatedBankData = true
    static let plaidRefreshPolicy: PlaidRefreshPolicy = .manualOnly

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
