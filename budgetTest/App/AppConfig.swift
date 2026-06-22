import Foundation

enum AppConfig {

    // DEBUG uses the local iMac backend. RELEASE/TestFlight uses the hosted
    // Render backend. Plaid secrets must stay on the backend, never in the iOS app.
    #if DEBUG
    static let backendBaseURL = URL(string: "http://10.0.0.244:3001")!
    #else
    static let backendBaseURL = URL(string: "https://plaid-backend-2wqb.onrender.com")!
    #endif

    // Provide APP_API_KEY through an Xcode build setting / Info.plist value for
    // Release/TestFlight. The DEBUG fallback is a local placeholder only.
    static let backendAPIKey: String = {
        if let bundledKey = Bundle.main.object(
            forInfoDictionaryKey: "APP_API_KEY"
        ) as? String,
           !bundledKey.isEmpty,
           !bundledKey.contains("$(") {
            return bundledKey
        }

        #if DEBUG
        return "local-dev-app-api-key-change-me"
        #else
        return ""
        #endif
    }()

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
        _ request: inout URLRequest
    ) {
        guard !backendAPIKey.isEmpty else {
            return
        }

        request.setValue(
            backendAPIKey,
            forHTTPHeaderField: "x-app-api-key"
        )
    }
}
