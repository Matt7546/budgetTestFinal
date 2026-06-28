import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

struct AuthUserSummary: Codable, Equatable {
    let id: String
    let email: String?
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
    }

    var displayName: String {
        if let fullName,
           !fullName.isEmpty {
            return fullName
        }

        if let email,
           !email.isEmpty {
            return email
        }

        return "Caldera Account"
    }
}

enum AuthState: Equatable {
    case signedOut
    case signingIn
    case signedIn
    case failed
}

@MainActor
final class AuthManager: ObservableObject {

    @Published private(set) var state: AuthState = .signedOut
    @Published private(set) var user: AuthUserSummary?
    @Published private(set) var statusMessage: String?

    private(set) var sessionToken: String?
    private var pendingAppleNonce: String?

    var isSignedIn: Bool {
        state == .signedIn && sessionToken != nil
    }

    var isBusy: Bool {
        state == .signingIn
    }

    init() {
        restoreSession()
    }

    func configureAppleRequest(
        _ request: ASAuthorizationAppleIDRequest
    ) {
        let nonce = Self.randomNonceString()
        let hashedNonce = Self.sha256(nonce)
        pendingAppleNonce = hashedNonce

        request.requestedScopes = [
            .fullName,
            .email
        ]
        request.nonce = hashedNonce

        AppLogger.auth("Sign in with Apple request configured")
    }

    func handleAppleCompletion(
        _ result: Result<ASAuthorization, Error>
    ) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                fail("Couldn’t read your Apple sign-in result.")
                return
            }

            guard let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                fail("Apple did not return an identity token. Try again.")
                return
            }

            let fullName = credential.fullName.map {
                PersonNameComponentsFormatter.localizedString(
                    from: $0,
                    style: .medium,
                    options: []
                )
            }

            let nonce = pendingAppleNonce
            pendingAppleNonce = nil

            Task {
                await signInWithAppleToken(
                    identityToken,
                    nonce: nonce,
                    fullName: fullName,
                    email: credential.email
                )
            }

        case .failure(let error):
            pendingAppleNonce = nil

            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                state = sessionToken == nil ? .signedOut : state
                statusMessage = nil
                AppLogger.auth("Sign in with Apple canceled")
                return
            }

            fail("Sign in failed. Try again.")
        }
    }

    func signOut() {
        Task {
            await signOutFromBackend()
        }
    }

    private func restoreSession() {
        do {
            guard let token = try KeychainSessionStore.loadSessionToken(),
                  !token.isEmpty else {
                state = .signedOut
                return
            }

            sessionToken = token
            state = .signingIn
            statusMessage = "Restoring your session…"
            AppLogger.auth("Session restore started")

            Task {
                await validateRestoredSession(token)
            }
        } catch {
            clearLocalSession()
            statusMessage = "Couldn’t restore your saved session."
            AppLogger.warning(
                "Session restore failed: \(error.localizedDescription)",
                category: .auth
            )
        }
    }

    private func validateRestoredSession(
        _ token: String
    ) async {
        do {
            let response: AuthMeResponse = try await sendBackendRequest(
                path: "/api/auth/me",
                method: "GET",
                bearerToken: token
            )

            sessionToken = token
            user = response.user
            state = .signedIn
            statusMessage = nil
            AppLogger.auth("Session restored")
        } catch {
            clearLocalSession()
            statusMessage = "Your session expired. Sign in again when you’re ready."
            AppLogger.warning(
                "Session restore failed",
                category: .auth
            )
        }
    }

    private func signInWithAppleToken(
        _ identityToken: String,
        nonce: String?,
        fullName: String?,
        email: String?
    ) async {
        state = .signingIn
        statusMessage = "Signing in…"
        AppLogger.auth("Sign in started")

        do {
            var payload: [String: String] = [
                "identity_token": identityToken
            ]

            if let nonce,
               !nonce.isEmpty {
                payload["nonce"] = nonce
            }

            if let fullName,
               !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["full_name"] = fullName
            }

            if let email,
               !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["email"] = email
            }

            let body = try JSONEncoder().encode(payload)
            let response: AuthSessionResponse = try await sendBackendRequest(
                path: "/api/auth/apple",
                method: "POST",
                bearerToken: nil,
                body: body
            )

            try KeychainSessionStore.saveSessionToken(response.sessionToken)
            sessionToken = response.sessionToken
            user = response.user
            state = .signedIn
            statusMessage = "Signed in with Apple."
            AppLogger.auth("Sign in succeeded")
        } catch {
            clearLocalSession()
            statusMessage = "Couldn’t sign in. Try again."
            state = .failed
            AppLogger.warning(
                "Sign in failed",
                category: .auth
            )
        }
    }

    private func signOutFromBackend() async {
        let token = sessionToken
        state = .signingIn
        statusMessage = "Signing out…"

        if let token,
           !token.isEmpty {
            do {
                let _: AuthLogoutResponse = try await sendBackendRequest(
                    path: "/api/auth/logout",
                    method: "POST",
                    bearerToken: token
                )
                AppLogger.auth("Logout completed")
            } catch {
                statusMessage = "Signed out locally. Your server session will expire automatically."
                AppLogger.warning(
                    "Logout request failed",
                    category: .auth
                )
            }
        }

        clearLocalSession()
    }

    private func clearLocalSession() {
        KeychainSessionStore.clearSessionToken()
        sessionToken = nil
        user = nil
        state = .signedOut

        if statusMessage == "Signing out…" {
            statusMessage = "Signed out."
        }
    }

    private func fail(
        _ message: String
    ) {
        state = .failed
        statusMessage = message
        AppLogger.warning(
            message,
            category: .auth
        )
    }

    private func sendBackendRequest<T: Decodable>(
        path: String,
        method: String,
        bearerToken: String?,
        body: Data? = nil
    ) async throws -> T {
        let url = AppConfig.plaidEndpoint(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        AppConfig.configureBackendRequest(
            &request,
            bearerToken: bearerToken
        )

        if let body {
            request.httpBody = body
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            AppLogger.warning(
                "Auth backend request failed with status \(httpResponse.statusCode)",
                category: .auth
            )
            throw AuthError.backendStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(
            T.self,
            from: data
        )
    }

    private static func randomNonceString(
        length: Int = 32
    ) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomByte: UInt8 = 0
            let status = SecRandomCopyBytes(
                kSecRandomDefault,
                1,
                &randomByte
            )

            if status != errSecSuccess {
                fatalError("Unable to generate secure random nonce.")
            }

            if Int(randomByte) < charset.count {
                result.append(charset[Int(randomByte)])
                remainingLength -= 1
            }
        }

        return result
    }

    private static func sha256(
        _ input: String
    ) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)

        return hashedData.map {
            String(format: "%02x", $0)
        }.joined()
    }
}

private struct AuthSessionResponse: Decodable {
    let sessionToken: String
    let user: AuthUserSummary
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case sessionToken = "session_token"
        case user
        case expiresAt = "expires_at"
    }
}

private struct AuthMeResponse: Decodable {
    let user: AuthUserSummary
}

private struct AuthLogoutResponse: Decodable {
    let success: Bool
}

private enum AuthError: Error {
    case invalidResponse
    case backendStatus(Int)
}
