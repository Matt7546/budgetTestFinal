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

        return AppBrand.accountName
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
    @Published private(set) var latestConfirmedAccountDeletion:
        PendingLocalAccountDeletion?

    private(set) var sessionToken: String?
    private var pendingAppleNonce: String?
    private var activeAuthOperationID = UUID()
    private let urlSession: URLSession
    private let pendingLocalAccountDeletionStore:
        PendingLocalAccountDeletionStore
    private let localStoreKind: CalderaSwiftDataStoreKind
    private let sessionTokenSaver:
        @MainActor (String) throws -> Void
    private let localDevelopmentSignInAllowed: @MainActor () -> Bool

    var isSignedIn: Bool {
        state == .signedIn && sessionToken != nil
    }

    var backendSessionToken: String? {
        isSignedIn ? sessionToken : nil
    }

    var isBusy: Bool {
        state == .signingIn
    }

    init(
        urlSession: URLSession = .shared,
        pendingDeletionDefaults: UserDefaults = .standard,
        pendingDeletionStore: PendingLocalAccountDeletionStore? = nil,
        localStoreKind: CalderaSwiftDataStoreKind = .production,
        restoreSavedSession: Bool = true,
        initialSessionToken: String? = nil,
        initialUser: AuthUserSummary? = nil,
        sessionTokenSaver:
            @escaping @MainActor (String) throws -> Void =
                KeychainSessionStore.saveSessionToken,
        localDevelopmentSignInAllowed: @escaping @MainActor () -> Bool = {
            AppConfig.isDebugLocal
        }
    ) {
        self.urlSession = urlSession
        self.pendingLocalAccountDeletionStore =
            pendingDeletionStore ?? PendingLocalAccountDeletionStore(
                defaults: pendingDeletionDefaults
            )
        self.localStoreKind = localStoreKind
        self.sessionTokenSaver = sessionTokenSaver
        self.localDevelopmentSignInAllowed = localDevelopmentSignInAllowed

        if let initialSessionToken,
           !initialSessionToken.isEmpty,
           let initialUser {
            sessionToken = initialSessionToken
            user = initialUser
            state = .signedIn
        } else if restoreSavedSession {
            restoreSession()
        }
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

            AppLogger.auth("Apple credential received")

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

    #if DEBUG
    func signInForLocalDevelopment() {
        guard localDevelopmentSignInAllowed() else {
            fail("Local development sign-in is available only in Caldera Debug Local.")
            return
        }

        Task {
            await signInWithDevelopmentAuth()
        }
    }

    func debugResetLocalSessionForUXResearch() {
        guard AppConfig.isDebugLocal else {
            return
        }

        _ = beginAuthOperation("UX research reset")
        statusMessage = nil
        clearLocalSession()
    }
    #endif

    @discardableResult
    func deleteAccount() async throws -> PendingLocalAccountDeletion {
        guard let token = sessionToken,
              !token.isEmpty,
              let deletingUser = user else {
            statusMessage = "Sign in with Apple before deleting your account."
            state = .signedOut
            throw AuthError.backendStatus(
                401,
                statusMessage
            )
        }

        guard let intent = pendingLocalAccountDeletionStore
            .beginDeletionIntent(
                userID: deletingUser.id,
                sessionToken: token,
                storeKind: localStoreKind
            ) else {
            statusMessage = "Couldn’t prepare account deletion safely. Try again."
            throw AuthError.localDeletionStateUnavailable
        }

        if intent.phase == .localCleanupRequired {
            latestConfirmedAccountDeletion = intent
            if sessionToken == token,
               user?.id == deletingUser.id {
                _ = beginAuthOperation("Resume deleted account cleanup")
                clearLocalSession()
                statusMessage = "Account deleted."
            }
            return intent
        }

        return try await performAccountDeletion(
            intent: intent,
            deletingUser: deletingUser,
            token: token
        )
    }

    @discardableResult
    func retryAccountDeletion(
        jobID: UUID
    ) async throws -> PendingLocalAccountDeletion {
        guard let token = sessionToken,
              !token.isEmpty,
              let deletingUser = user,
              let ownerScopeID = PlanningOwnerScope.authenticated(
                deletingUser.id
              ),
              case .available(let jobs) = pendingLocalAccountDeletionStore
                .readPendingDeletions(for: localStoreKind),
              let intent = jobs.first(where: {
                  $0.id == jobID &&
                      $0.planningOwnerScopeID == ownerScopeID &&
                      ($0.phase == .requestPending ||
                       $0.phase == .confirmationUncertain)
              }) else {
            statusMessage = "This account-deletion request can’t be retried from the current session."
            throw AuthError.localDeletionStateUnavailable
        }

        return try await performAccountDeletion(
            intent: intent,
            deletingUser: deletingUser,
            token: token
        )
    }

    private func performAccountDeletion(
        intent: PendingLocalAccountDeletion,
        deletingUser: AuthUserSummary,
        token: String
    ) async throws -> PendingLocalAccountDeletion {
        guard intent.storeKind == localStoreKind,
              intent.planningOwnerScopeID ==
                PlanningOwnerScope.authenticated(deletingUser.id),
              let attemptedJob = pendingLocalAccountDeletionStore
                .beginServerAttempt(matching: intent) else {
            statusMessage = "Couldn’t prepare account deletion safely. Try again."
            throw AuthError.localDeletionStateUnavailable
        }

        let operationID = beginAuthOperation("Delete account")
        state = .signingIn
        statusMessage = "Deleting your account…"

        do {
            let response = try await sendAccountDeletionRequest(
                bearerToken: token
            )

            guard response.isConfirmedSuccess else {
                throw AuthError.invalidResponse
            }

            guard let confirmedJob = pendingLocalAccountDeletionStore
                .markServerDeletionConfirmed(matching: attemptedJob) else {
                throw AuthError.localDeletionStateUnavailable
            }

            latestConfirmedAccountDeletion = confirmedJob
            if isCurrentAuthOperation(operationID),
               sessionToken == token,
               user?.id == deletingUser.id {
                clearLocalSession()
                statusMessage = "Account deleted."
            }
            AppLogger.auth("Account deletion confirmed by server")
            return confirmedJob
        } catch {
            _ = pendingLocalAccountDeletionStore
                .markServerConfirmationUncertain(
                    matching: attemptedJob
                )

            guard isCurrentAuthOperation(operationID),
                  sessionToken == token,
                  user?.id == deletingUser.id else {
                AppLogger.auth("Ignored stale account-deletion completion")
                throw error
            }

            if isUnauthorized(error) {
                clearLocalSession()
                statusMessage = "Account deletion couldn’t be confirmed. Your local data is still saved on this device. Sign in again before retrying."
            } else {
                state = sessionToken == nil ? .signedOut : .signedIn
                statusMessage = "Account deletion couldn’t be confirmed. Your local data is still saved on this device. Try again when you’re ready."
            }

            AppLogger.warning(
                "Account deletion failed",
                category: .auth
            )
            throw error
        }
    }

    func invalidateSessionIfCurrent(
        _ requestScope: BankDataRequestScope
    ) {
        guard requestScope.sessionToken == sessionToken,
              requestScope.userID == user?.id else {
            return
        }

        _ = beginAuthOperation("Authoritative session expiry")
        clearLocalSession()
        statusMessage = "Your session expired. Sign in again when you’re ready."
        AppLogger.auth("Authoritative server session expired; state=signedOut")
    }

    private func restoreSession() {
        do {
            guard let token = try KeychainSessionStore.loadSessionToken(),
                  !token.isEmpty else {
                state = .signedOut
                return
            }

            let operationID = beginAuthOperation("Session restore")
            sessionToken = token
            state = .signingIn
            statusMessage = "Restoring your session…"
            AppLogger.auth("Session restore started")

            Task {
                await validateRestoredSession(
                    token,
                    operationID: operationID
                )
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
        _ token: String,
        operationID: UUID
    ) async {
        do {
            let response: AuthMeResponse = try await sendBackendRequest(
                path: "/api/auth/me",
                method: "GET",
                bearerToken: token
            )

            guard isCurrentAuthOperation(operationID),
                  sessionToken == token else {
                AppLogger.auth("Ignored stale session restore success")
                return
            }

            sessionToken = token
            user = response.user
            state = .signedIn
            statusMessage = nil
            AppLogger.auth("Session restore succeeded; state=signedIn")
        } catch {
            guard isCurrentAuthOperation(operationID),
                  sessionToken == token else {
                AppLogger.auth("Ignored stale session restore failure")
                return
            }

            if isUnauthorized(error) {
                clearLocalSession()
                statusMessage = "Your session expired. Sign in again when you’re ready."
            } else {
                state = .signedOut
                statusMessage = authStatusMessage(
                    for: error,
                    fallback: "Couldn’t check your saved session. You can still use \(AppBrand.shortName)."
                )
            }

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
        let operationID = beginAuthOperation("Apple sign in")
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
            AppLogger.auth("Backend auth request started")

            let response: AuthSessionResponse = try await sendBackendRequest(
                path: "/api/auth/apple",
                method: "POST",
                bearerToken: nil,
                body: body
            )

            guard isCurrentAuthOperation(operationID) else {
                AppLogger.auth("Ignored stale sign-in success")
                return
            }

            try sessionTokenSaver(response.sessionToken)
            sessionToken = response.sessionToken
            user = response.user
            state = .signedIn
            statusMessage = "Signed in with Apple."
            AppLogger.auth("Session saved; state=signedIn")
        } catch {
            guard isCurrentAuthOperation(operationID) else {
                AppLogger.auth("Ignored stale sign-in failure")
                return
            }

            clearLocalSession()
            statusMessage = authStatusMessage(
                for: error,
                fallback: "Couldn’t sign in. Try again."
            )
            state = .failed
            AppLogger.warning(
                "Sign in failed",
                category: .auth
            )
        }
    }

    #if DEBUG
    private func signInWithDevelopmentAuth() async {
        let operationID = beginAuthOperation("Development sign in")
        state = .signingIn
        statusMessage = "Signing in for local development…"
        AppLogger.auth("Development sign-in started")

        do {
            let response: AuthSessionResponse = try await sendBackendRequest(
                path: "/api/auth/development",
                method: "POST",
                bearerToken: nil
            )

            guard isCurrentAuthOperation(operationID) else {
                AppLogger.auth("Ignored stale development sign-in success")
                return
            }

            try sessionTokenSaver(response.sessionToken)
            sessionToken = response.sessionToken
            user = response.user
            state = .signedIn
            statusMessage = "Signed in for local development."
            AppLogger.auth("Development session saved; state=signedIn")
        } catch {
            guard isCurrentAuthOperation(operationID) else {
                AppLogger.auth("Ignored stale development sign-in failure")
                return
            }

            clearLocalSession()
            statusMessage = developmentAuthStatusMessage(for: error)
            state = .failed
            AppLogger.warning(
                "Development sign-in failed",
                category: .auth
            )
        }
    }

    private func developmentAuthStatusMessage(
        for error: Error
    ) -> String {
        if case AuthError.backendStatus(let statusCode, let message) = error,
           [403, 404, 409].contains(statusCode) {
            if let message,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }

            return "Local dev sign-in is disabled. Add DEV_AUTH_ENABLED=true to plaid-backend/.env and restart the backend."
        }

        if error is URLError {
            return "Couldn’t reach the local backend. Make sure plaid-backend is running on \(AppConfig.backendBaseURL.host ?? "the configured host") and try again."
        }

        return authStatusMessage(
            for: error,
            fallback: "Couldn’t use local development sign-in. Add DEV_AUTH_ENABLED=true to plaid-backend/.env and restart the backend."
        )
    }
    #endif

    private func signOutFromBackend() async {
        let operationID = beginAuthOperation("Sign out")
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

        guard isCurrentAuthOperation(operationID) else {
            AppLogger.auth("Ignored stale logout completion")
            return
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

        AppLogger.auth("Auth backend request: \(method) \(path)")

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

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let backendError = try? JSONDecoder().decode(
                AuthBackendErrorResponse.self,
                from: data
            )

            AppLogger.warning(
                "Auth backend request failed with status \(httpResponse.statusCode)",
                category: .auth
            )

            if httpResponse.statusCode == 429,
               backendError?.error == "rate_limited" {
                let retryAfterHeader = httpResponse.value(
                    forHTTPHeaderField: "Retry-After"
                ).flatMap(Int.init)
                throw AuthError.rateLimited(
                    backendError?.retry_after_seconds ?? retryAfterHeader
                )
            }

            throw AuthError.backendStatus(
                httpResponse.statusCode,
                backendError?.message
            )
        }

        do {
            let decodedResponse = try JSONDecoder().decode(
                T.self,
                from: data
            )
            AppLogger.auth("Auth backend request succeeded: \(method) \(path)")
            return decodedResponse
        } catch {
            AppLogger.warning(
                "Auth backend decode failed for \(path)",
                category: .auth
            )
            throw AuthError.decodingFailed
        }
    }

    private func sendAccountDeletionRequest(
        bearerToken: String
    ) async throws -> AuthDeleteAccountResponse {
        let path = "/api/account"
        let url = AppConfig.plaidEndpoint(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        AppConfig.configureBackendRequest(
            &request,
            bearerToken: bearerToken
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let failure = try? JSONDecoder().decode(
                AuthBackendErrorResponse.self,
                from: data
            )

            if httpResponse.statusCode == 429 {
                let retryAfterHeader = httpResponse.value(
                    forHTTPHeaderField: "Retry-After"
                ).flatMap(Int.init)
                throw AuthError.rateLimited(
                    failure?.retry_after_seconds ?? retryAfterHeader
                )
            }

            throw AuthError.backendStatus(
                httpResponse.statusCode,
                failure?.message
            )
        }

        do {
            return try JSONDecoder().decode(
                AuthDeleteAccountResponse.self,
                from: data
            )
        } catch {
            throw AuthError.decodingFailed
        }
    }

    @discardableResult
    private func beginAuthOperation(
        _ name: String
    ) -> UUID {
        let operationID = UUID()
        activeAuthOperationID = operationID
        AppLogger.auth("\(name) operation started")
        return operationID
    }

    private func isCurrentAuthOperation(
        _ operationID: UUID
    ) -> Bool {
        activeAuthOperationID == operationID
    }

    private func isUnauthorized(
        _ error: Error
    ) -> Bool {
        if case AuthError.backendStatus(let statusCode, _) = error {
            return statusCode == 401
        }

        return false
    }

    private func authStatusMessage(
        for error: Error,
        fallback: String,
        rateLimitSubject: String = "Sign in"
    ) -> String {
        if case AuthError.rateLimited(let retryAfter) = error {
            guard let retryAfter,
                  retryAfter >= 60 else {
                return "\(rateLimitSubject) is briefly paused. Please try again in a moment."
            }

            let minutes = max(1, Int(ceil(Double(retryAfter) / 60)))
            let unit = minutes == 1 ? "minute" : "minutes"

            return "\(rateLimitSubject) is briefly paused. Please try again in about \(minutes) \(unit)."
        }

        if case AuthError.backendStatus(_, let message) = error,
           let message,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }
        if error is URLError {
            return "Couldn’t reach \(AppBrand.shortName) auth. Check your connection and try again."
        }

        if case AuthError.decodingFailed = error {
            return "\(AppBrand.shortName) could not read the auth response. Try again."
        }

        return fallback
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

private struct AuthDeleteAccountResponse: Decodable {
    let success: Bool
    let removedItems: Int
    let failedItems: Int
    let sessionsRevoked: Int
    let userDeleted: Bool

    var isConfirmedSuccess: Bool {
        success &&
            removedItems >= 0 &&
            failedItems == 0 &&
            sessionsRevoked >= 0
    }

    enum CodingKeys: String, CodingKey {
        case success
        case removedItems = "removed_items"
        case failedItems = "failed_items"
        case sessionsRevoked = "sessions_revoked"
        case userDeleted = "user_deleted"
    }
}

private struct AuthBackendErrorResponse: Decodable {
    let error: String?
    let message: String?
    let retry_after_seconds: Int?
}

private enum AuthError: Error {
    case invalidResponse
    case backendStatus(Int, String?)
    case rateLimited(Int?)
    case decodingFailed
    case localDeletionStateUnavailable
}
