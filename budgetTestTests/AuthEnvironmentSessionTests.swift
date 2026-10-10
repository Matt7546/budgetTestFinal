import AuthenticationServices
import Foundation
import Security
import XCTest
@testable import Caldera_Money

/// No Keychain call is possible through this logic-test store. The legacy
/// sentinel is deliberately outside the scoped protocol and never returned.
@MainActor
final class SentinelAuthSessionStore: AuthSessionStore {
    var tokens: [String: String] = [:]
    var legacySentinel = "QUARANTINED-LEGACY-SENTINEL"
    var loads: [String] = []
    var saves: [String] = []
    var clears: [String] = []
    var failLoad = false
    var failSave = false

    func loadSessionToken(for environment: AuthBackendEnvironment) throws -> String? {
        loads.append(environment.credentialNamespace)
        if failLoad { throw URLError(.cannotOpenFile) }
        return tokens[environment.credentialNamespace]
    }
    func saveSessionToken(_ token: String, for environment: AuthBackendEnvironment) throws {
        saves.append(environment.credentialNamespace)
        if failSave { throw URLError(.cannotWriteToFile) }
        tokens[environment.credentialNamespace] = token
    }
    func clearSessionToken(for environment: AuthBackendEnvironment) throws {
        clears.append(environment.credentialNamespace)
        tokens.removeValue(forKey: environment.credentialNamespace)
    }
}

@MainActor
final class AuthEnvironmentSessionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: SentinelAuthSessionStore!
    private var session: URLSession!
    private var currentEnvironment: AuthBackendEnvironment?
    private var tasks: SentinelAuthTaskTracker!

    private var dev: AuthBackendEnvironment {
        AuthBackendEnvironment(id: .developmentLocal, baseURL: URL(string: "http://127.0.0.1:3001")!)!
    }
    private var prod: AuthBackendEnvironment {
        AuthBackendEnvironment(id: .renderProduction, baseURL: URL(string: "https://plaid-backend-2wqb.onrender.com")!)!
    }

    override func setUp() {
        super.setUp()
        suite = "AuthEnvironmentSessionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = SentinelAuthSessionStore()
        currentEnvironment = dev
        tasks = SentinelAuthTaskTracker()
        ContainedAuthURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContainedAuthURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        ContainedAuthURLProtocol.reset()
        defaults.removePersistentDomain(forName: suite)
        session = nil
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testDevelopmentCredentialCannotRestoreOrTransmitInProduction() async {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        currentEnvironment = prod
        let auth = manager()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertEqual(store.loads, [prod.credentialNamespace])
        XCTAssertTrue(ContainedAuthURLProtocol.requests.isEmpty)
        XCTAssertEqual(store.tokens[dev.credentialNamespace], "DEV-SENTINEL")
    }

    func testProductionCredentialCannotRestoreOrTransmitInDevelopment() async {
        store.tokens[prod.credentialNamespace] = "PROD-SENTINEL"
        let auth = manager()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertEqual(store.loads, [dev.credentialNamespace])
        XCTAssertTrue(ContainedAuthURLProtocol.requests.isEmpty)
    }

    func testIndependentScopedCredentialsRestoreOnlyToTheirOwnOrigin() async throws {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        store.tokens[prod.credentialNamespace] = "PROD-SENTINEL"
        let auth = manager()
        try await waitForRequest("/api/auth/me")
        XCTAssertEqual(ContainedAuthURLProtocol.requests.last?.url?.host, dev.baseURL.host)
        XCTAssertEqual(ContainedAuthURLProtocol.headers, ["Bearer DEV-SENTINEL"])
        respondMe(user: "dev-owner")
        try await waitUntil { auth.isSignedIn }
        currentEnvironment = prod
        // Even before a change notification, A cannot be exposed as B's owner/token.
        XCTAssertNil(auth.backendSessionToken)
        XCTAssertNil(auth.user)
        auth.handleBackendEnvironmentChange()
        try await waitForRequest("/api/auth/me", count: 2)
        XCTAssertEqual(ContainedAuthURLProtocol.requests.last?.url?.host, prod.baseURL.host)
        XCTAssertEqual(ContainedAuthURLProtocol.headers, ["Bearer DEV-SENTINEL", "Bearer PROD-SENTINEL"])
        respondMe(user: "prod-owner")
        try await waitUntil { auth.isSignedIn }
        XCTAssertEqual(auth.user?.id, "prod-owner")
        XCTAssertEqual(store.loads, [dev.credentialNamespace, prod.credentialNamespace])
        XCTAssertTrue(store.clears.isEmpty)
    }

    func testSignOutRemovesOnlyDevelopmentAndPreservesProductionAndLegacy() async throws {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        store.tokens[prod.credentialNamespace] = "PROD-SENTINEL"
        let auth = manager(restore: false, token: "DEV-SENTINEL")
        auth.signOut()
        try await waitForRequest("/api/auth/logout")
        XCTAssertEqual(ContainedAuthURLProtocol.headers, ["Bearer DEV-SENTINEL"])
        respond("/api/auth/logout", payload: #"{"success":true}"#)
        try await waitUntil { auth.state == .signedOut }
        XCTAssertNil(store.tokens[dev.credentialNamespace])
        XCTAssertEqual(store.tokens[prod.credentialNamespace], "PROD-SENTINEL")
        XCTAssertEqual(store.clears, [dev.credentialNamespace])
        assertLegacyUntouched()
    }

    func testLegacyCredentialIsQuarantinedInDevelopmentAndProduction() async {
        for environment in [dev, prod] {
            currentEnvironment = environment
            let auth = manager()
            XCTAssertEqual(auth.state, .signedOut)
            XCTAssertNil(auth.sessionToken)
            XCTAssertNil(auth.user)
        }
        XCTAssertEqual(store.loads, [dev.credentialNamespace, prod.credentialNamespace])
        XCTAssertTrue(ContainedAuthURLProtocol.requests.isEmpty)
        assertLegacyUntouched()
    }

    func testFreshAppleSignInWritesProductionOnlyAndPreservesLegacy() async throws {
        currentEnvironment = prod
        let auth = manager()
        let signIn = Task { await auth.signInWithAppleToken("APPLE-IDENTITY-SENTINEL", nonce: nil, fullName: nil, email: nil) }
        try await waitForRequest("/api/auth/apple")
        XCTAssertTrue(ContainedAuthURLProtocol.headers.isEmpty)
        respondSignIn("/api/auth/apple", token: "NEW-PROD-SENTINEL", user: "prod-owner")
        await signIn.value
        XCTAssertTrue(auth.isSignedIn)
        XCTAssertEqual(store.tokens, [prod.credentialNamespace: "NEW-PROD-SENTINEL"])
        XCTAssertEqual(store.saves, [prod.credentialNamespace])
        assertLegacyUntouched()
    }

    #if DEBUG
    func testFreshDevelopmentSignInWritesDevelopmentOnlyAndPreservesLegacy() async throws {
        let auth = manager()
        auth.signInForLocalDevelopment()
        try await waitForRequest("/api/auth/development")
        respondSignIn("/api/auth/development", token: "NEW-DEV-SENTINEL", user: "dev-owner")
        try await waitUntil { auth.isSignedIn }
        XCTAssertEqual(store.tokens, [dev.credentialNamespace: "NEW-DEV-SENTINEL"])
        XCTAssertTrue(ContainedAuthURLProtocol.headers.isEmpty)
        assertLegacyUntouched()
    }
    #endif

    func testRCAndProductionShareTheConfiguredReleaseAuthContract() throws {
        let configURL = try repositoryRoot().appendingPathComponent("budgetTest/App/AppConfig.swift")
        let source = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(source.contains("authEnvironmentID: .renderProduction"))
        let scheme = try String(contentsOf: repositoryRoot().appendingPathComponent("budgetTest.xcodeproj/xcshareddata/xcschemes/Caldera Release Candidate.xcscheme"), encoding: .utf8)
        XCTAssertTrue(scheme.contains("buildConfiguration = \"Release\""))
        let rc = AppEnvironment(apiBaseURL: prod.baseURL, displayName: "RC", expectedPlaidEnvironment: "production", isDebug: false, authEnvironmentID: .renderProduction)
        let release = AppEnvironment(apiBaseURL: prod.baseURL, displayName: "TestFlight", expectedPlaidEnvironment: "production", isDebug: false, authEnvironmentID: .renderProduction)
        XCTAssertEqual(rc.authEnvironment, release.authEnvironment)
        let local = AppEnvironment(apiBaseURL: dev.baseURL, displayName: "Debug Local", expectedPlaidEnvironment: "sandbox", isDebug: true, authEnvironmentID: .developmentLocal)
        let lab = AppEnvironment(apiBaseURL: dev.baseURL, displayName: "Lab Local", expectedPlaidEnvironment: "sandbox", isDebug: true, authEnvironmentID: .developmentLocal)
        XCTAssertEqual(local.authEnvironment, lab.authEnvironment)
        #if DEBUG
        XCTAssertEqual(AppConfig.authEnvironment?.id, .developmentLocal)
        #else
        XCTAssertEqual(AppConfig.authEnvironment, prod)
        #endif
    }

    func testExplicitMappingRejectsUnknownOrContradictoryConfiguration() async {
        let unknown = AppEnvironment(apiBaseURL: dev.baseURL, displayName: "Production", expectedPlaidEnvironment: "sandbox", isDebug: true)
        XCTAssertNil(unknown.authEnvironment)
        let wrongMode = AppEnvironment(apiBaseURL: prod.baseURL, displayName: "Local", expectedPlaidEnvironment: "sandbox", isDebug: true, authEnvironmentID: .renderProduction)
        XCTAssertNil(wrongMode.authEnvironment)
        currentEnvironment = unknown.authEnvironment
        let auth = manager()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertTrue(store.loads.isEmpty)
        XCTAssertTrue(ContainedAuthURLProtocol.requests.isEmpty)
        XCTAssertTrue(store.clears.isEmpty)
    }

    func testMalformedOrUnrecognizedOriginsNeverSelectCredentials() async {
        let urls = ["https://unknown.example", "http://plaid-backend-2wqb.onrender.com", "https://user:password@plaid-backend-2wqb.onrender.com", "https://plaid-backend-2wqb.onrender.com/api", "https://plaid-backend-2wqb.onrender.com?env=prod", "https://plaid-backend-2wqb.onrender.com#prod", "https://plaid-backend-2wqb.onrender.com:3001"]
        for url in urls {
            currentEnvironment = AuthBackendEnvironment(id: .renderProduction, baseURL: URL(string: url)!)
            XCTAssertNil(currentEnvironment)
            XCTAssertEqual(manager().state, .signedOut)
        }
        XCTAssertNil(AuthBackendEnvironment(id: .developmentLocal, baseURL: prod.baseURL))
        XCTAssertNil(AuthBackendEnvironment(id: .developmentLocal, baseURL: URL(string: "http://999.0.0.1:3001")!))
        XCTAssertTrue(store.loads.isEmpty)
        XCTAssertTrue(ContainedAuthURLProtocol.requests.isEmpty)
    }

    func testNormalizedOriginsAreStableButDifferentOriginsNeverShareNamespace() throws {
        let normalized = try XCTUnwrap(AuthBackendEnvironment(id: .renderProduction, baseURL: URL(string: "HTTPS://PLAID-BACKEND-2WQB.ONRENDER.COM:443/")!))
        XCTAssertEqual(normalized, prod)
        let otherDev = try XCTUnwrap(AuthBackendEnvironment(id: .developmentLocal, baseURL: URL(string: "http://10.0.0.244:3001")!))
        XCTAssertNotEqual(otherDev.credentialNamespace, dev.credentialNamespace)
        XCTAssertNotEqual(prod.credentialNamespace, dev.credentialNamespace)
        XCTAssertEqual(dev, AuthBackendEnvironment(id: .developmentLocal, baseURL: dev.baseURL))
    }

    func testUnreadableScopedStoreDoesNotDeleteCredentialsOrSendRequest() async {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        store.failLoad = true
        let auth = manager()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertEqual(store.tokens[dev.credentialNamespace], "DEV-SENTINEL")
        XCTAssertTrue(store.clears.isEmpty)
        XCTAssertTrue(ContainedAuthURLProtocol.requests.isEmpty)
        assertLegacyUntouched()
    }

    func testStaleRestoreSuccessCannotOverwriteProductionRestore() async throws {
        try await assertStaleRestore(status: 200)
    }

    func testStaleUnauthorizedRestoreCannotClearProductionRestore() async throws {
        try await assertStaleRestore(status: 401)
    }

    func testEnvironmentChangeWithoutNewOperationRejectsOldRestore() async throws {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        let auth = manager()
        try await waitForRequest("/api/auth/me")
        currentEnvironment = prod
        respondMe(user: "dev-owner")
        try await settle()
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.backendSessionToken)
        XCTAssertNil(auth.user)
        XCTAssertTrue(store.saves.isEmpty)
        XCTAssertTrue(store.clears.isEmpty)
    }

    func testQueuedRestoreNeverSendsAfterEnvironmentChanges() async throws {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        let scheduler = SentinelAuthScheduler()
        let auth = manager(scheduler: scheduler.enqueue)
        XCTAssertEqual(scheduler.count, 1)
        currentEnvironment = prod
        auth.handleBackendEnvironmentChange()
        await scheduler.run(at: 0)
        XCTAssertTrue(ContainedAuthURLProtocol.requests.isEmpty)
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertEqual(store.loads, [dev.credentialNamespace, prod.credentialNamespace])
    }

    #if DEBUG
    func testStaleRestoreCannotClearNewerSignInInSameEnvironment() async throws {
        store.tokens[dev.credentialNamespace] = "OLD-DEV-SENTINEL"
        let auth = manager()
        try await waitForRequest("/api/auth/me")
        auth.signInForLocalDevelopment()
        try await waitForRequest("/api/auth/development")
        respondSignIn("/api/auth/development", token: "NEW-DEV-SENTINEL", user: "new-owner")
        try await waitUntil { auth.isSignedIn }
        respond("/api/auth/me", payload: #"{"error":"unauthorized"}"#, status: 401)
        try await settle()
        XCTAssertEqual(auth.user?.id, "new-owner")
        XCTAssertEqual(auth.backendSessionToken, "NEW-DEV-SENTINEL")
        XCTAssertEqual(store.tokens[dev.credentialNamespace], "NEW-DEV-SENTINEL")
        XCTAssertEqual(store.saves.count, 1)
        XCTAssertTrue(store.clears.isEmpty)
    }
    #endif

    func testStaleAppleSignInCannotWriteIntoNewEnvironment() async throws {
        let auth = manager(restore: false)
        let signIn = Task { await auth.signInWithAppleToken("APPLE-IDENTITY-SENTINEL", nonce: nil, fullName: nil, email: nil) }
        try await waitForRequest("/api/auth/apple")
        currentEnvironment = prod
        auth.handleBackendEnvironmentChange()
        respondSignIn("/api/auth/apple", token: "STALE-DEV-SENTINEL", user: "dev-owner")
        await signIn.value
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertTrue(store.saves.isEmpty)
        XCTAssertTrue(store.tokens.isEmpty)
        assertLegacyUntouched()
    }

    func testStaleLogoutFailureCannotClearOrChangeNewEnvironment() async throws {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        store.tokens[prod.credentialNamespace] = "PROD-SENTINEL"
        let auth = manager(restore: false, token: "DEV-SENTINEL")
        auth.signOut()
        try await waitForRequest("/api/auth/logout")
        currentEnvironment = prod
        auth.handleBackendEnvironmentChange()
        try await waitForRequest("/api/auth/me")
        respondMe(user: "prod-owner")
        try await waitUntil { auth.isSignedIn }
        respond("/api/auth/logout", payload: #"{"error":"failed"}"#, status: 500)
        try await settle()
        XCTAssertEqual(auth.user?.id, "prod-owner")
        XCTAssertEqual(auth.backendSessionToken, "PROD-SENTINEL")
        XCTAssertNil(auth.statusMessage)
        XCTAssertTrue(store.clears.isEmpty)
        XCTAssertEqual(store.tokens.count, 2)
    }

    func testConfirmedDeletionClearsOnlyItsScopedCredentialAndKeepsDurableJob() async throws {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        store.tokens[prod.credentialNamespace] = "PROD-SENTINEL"
        let auth = manager(restore: false, token: "DEV-SENTINEL")
        let deletion = Task { try await auth.deleteAccount() }
        try await waitForRequest("/api/account")
        XCTAssertEqual(ContainedAuthURLProtocol.headers, ["Bearer DEV-SENTINEL"])
        respond("/api/account", payload: #"{"success":true,"removed_items":1,"failed_items":0,"sessions_revoked":1,"user_deleted":true}"#)
        let job = try await deletion.value
        XCTAssertEqual(job.phase, .localCleanupRequired)
        XCTAssertEqual(PendingLocalAccountDeletionStore(defaults: defaults).readPendingDeletions(), .available([job]))
        XCTAssertNil(store.tokens[dev.credentialNamespace])
        XCTAssertEqual(store.tokens[prod.credentialNamespace], "PROD-SENTINEL")
        assertLegacyUntouched()
    }

    func testStaleAppleAuthorizationFailureCannotChangeNewEnvironmentSession() async throws {
        let auth = manager(restore: false)
        // Constructing/configuring a request does not contact Apple.
        auth.configureAppleRequest(ASAuthorizationAppleIDProvider().createRequest())
        currentEnvironment = prod
        store.tokens[prod.credentialNamespace] = "PROD-SENTINEL"
        auth.handleBackendEnvironmentChange()
        try await waitForRequest("/api/auth/me")
        respondMe(user: "prod-owner")
        try await waitUntil { auth.isSignedIn }
        auth.handleAppleCompletion(.failure(URLError(.cancelled)))
        XCTAssertTrue(auth.isSignedIn)
        XCTAssertEqual(auth.user?.id, "prod-owner")
        XCTAssertNil(auth.statusMessage)
        XCTAssertTrue(store.clears.isEmpty)
        XCTAssertTrue(store.saves.isEmpty)
    }

    func testTransientRestoreFailurePreservesScopedCredentialForRetry() async throws {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        let auth = manager()
        try await waitForRequest("/api/auth/me")
        respond("/api/auth/me", payload: #"{"error":"temporarily_unavailable"}"#, status: 503)
        try await waitUntil { auth.state == .signedOut }
        XCTAssertEqual(store.tokens[dev.credentialNamespace], "DEV-SENTINEL")
        XCTAssertTrue(store.clears.isEmpty)
        auth.handleBackendEnvironmentChange()
        try await waitForRequest("/api/auth/me", count: 2)
        respondMe(user: "dev-owner")
        try await waitUntil { auth.isSignedIn }
    }

    func testDelayedDeletionConfirmationDoesNotClearNewEnvironment() async throws {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        store.tokens[prod.credentialNamespace] = "PROD-SENTINEL"
        let auth = manager(restore: false, token: "DEV-SENTINEL")
        let deletion = Task { try await auth.deleteAccount() }
        try await waitForRequest("/api/account")
        currentEnvironment = prod
        auth.handleBackendEnvironmentChange()
        try await waitForRequest("/api/auth/me")
        respondMe(user: "prod-owner")
        try await waitUntil { auth.isSignedIn }
        respond("/api/account", payload: #"{"success":true,"removed_items":1,"failed_items":0,"sessions_revoked":1,"user_deleted":true}"#)
        let job = try await deletion.value
        XCTAssertEqual(job.phase, .localCleanupRequired)
        XCTAssertEqual(PendingLocalAccountDeletionStore(defaults: defaults).readPendingDeletions(), .available([job]))
        XCTAssertEqual(auth.user?.id, "prod-owner")
        XCTAssertEqual(auth.backendSessionToken, "PROD-SENTINEL")
        XCTAssertNil(auth.latestConfirmedAccountDeletion)
        XCTAssertTrue(store.clears.isEmpty)
        XCTAssertEqual(store.tokens.count, 2)
    }

    func testAccountDeletionAfterConfigurationChangeCannotSendOldToken() async throws {
        let auth = manager(restore: false, token: "DEV-SENTINEL")
        currentEnvironment = prod
        do { _ = try await auth.deleteAccount(); XCTFail("Expected rejection") } catch {}
        XCTAssertTrue(ContainedAuthURLProtocol.requests.isEmpty)
        XCTAssertTrue(store.clears.isEmpty)
    }

    func testScopedFixturesReleaseAfterStaleRestoreAndScopedSignOut() async throws {
        // Repeated production AuthManager lifecycles, with observable weak
        // references. No retained fixture, sleep, or detached cleanup task.
        for _ in 0..<10 {
            ContainedAuthURLProtocol.reset()
            store = SentinelAuthSessionStore()
            store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
            store.tokens[prod.credentialNamespace] = "PROD-SENTINEL"
            currentEnvironment = dev
            var auth: AuthManager? = manager()
            weak var releasedAuth = auth
            weak var releasedStore = store

            try await waitForRequest("/api/auth/me")
            currentEnvironment = prod
            auth?.handleBackendEnvironmentChange()
            try await waitForRequest("/api/auth/me", count: 2)
            respondMe(user: "prod-owner", index: 1)
            try await waitUntil { auth?.isSignedIn == true }
            respond("/api/auth/me", payload: #"{"error":"unauthorized"}"#, status: 401)
            await tasks.finishExistingTasks()
            XCTAssertEqual(auth?.user?.id, "prod-owner")
            XCTAssertEqual(auth?.backendSessionToken, "PROD-SENTINEL")
            XCTAssertTrue(store.clears.isEmpty)

            auth?.signOut()
            try await waitForRequest("/api/auth/logout")
            respond("/api/auth/logout", payload: #"{"success":true}"#)
            await tasks.finishExistingTasks()
            XCTAssertEqual(auth?.state, .signedOut)
            XCTAssertEqual(store.tokens, [dev.credentialNamespace: "DEV-SENTINEL"])
            XCTAssertEqual(store.clears, [prod.credentialNamespace])
            XCTAssertEqual(ContainedAuthURLProtocol.headers, [
                "Bearer DEV-SENTINEL", "Bearer PROD-SENTINEL", "Bearer PROD-SENTINEL"
            ])
            assertLegacyUntouched()

            auth = nil
            XCTAssertNil(releasedAuth, "The completed production auth tasks must not retain AuthManager")
            store = nil
            XCTAssertNil(releasedStore, "The injected value-only store must actually deallocate")
        }
    }

    func testUnauthorizedCurrentRestoreClearsOnlyCurrentNamespace() async throws {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        store.tokens[prod.credentialNamespace] = "PROD-SENTINEL"
        let auth = manager()
        try await waitForRequest("/api/auth/me")
        respond("/api/auth/me", payload: #"{"error":"unauthorized"}"#, status: 401)
        try await waitUntil { auth.state == .signedOut }
        XCTAssertEqual(store.clears, [dev.credentialNamespace])
        XCTAssertEqual(store.tokens[prod.credentialNamespace], "PROD-SENTINEL")
        assertLegacyUntouched()
    }

    private func manager(restore: Bool = true, token: String? = nil, scheduler: ((@escaping @MainActor () async -> Void) -> Void)? = nil) -> AuthManager {
        AuthManager(urlSession: session, pendingDeletionDefaults: defaults, restoreSavedSession: restore,
                    initialSessionToken: token, initialUser: token.map { _ in AuthUserSummary(id: "dev-owner", email: nil, fullName: nil) },
                    sessionStore: store, environmentProvider: { [weak self] in self?.currentEnvironment },
                    localDevelopmentSignInAllowed: { true }, authTaskScheduler: scheduler ?? tasks.enqueue)
    }

    private func assertStaleRestore(status: Int) async throws {
        store.tokens[dev.credentialNamespace] = "DEV-SENTINEL"
        store.tokens[prod.credentialNamespace] = "PROD-SENTINEL"
        let auth = manager()
        try await waitForRequest("/api/auth/me")
        currentEnvironment = prod
        auth.handleBackendEnvironmentChange()
        try await waitForRequest("/api/auth/me", count: 2)
        respondMe(user: "prod-owner", index: 1)
        try await waitUntil { auth.isSignedIn }
        respond("/api/auth/me", payload: #"{"user":{"id":"dev-owner"}}"#, status: status)
        try await settle()
        XCTAssertEqual(auth.user?.id, "prod-owner")
        XCTAssertEqual(auth.backendSessionToken, "PROD-SENTINEL")
        XCTAssertNil(auth.statusMessage)
        XCTAssertTrue(store.saves.isEmpty)
        XCTAssertTrue(store.clears.isEmpty)
        XCTAssertEqual(store.tokens.count, 2)
        XCTAssertEqual(ContainedAuthURLProtocol.headers, ["Bearer DEV-SENTINEL", "Bearer PROD-SENTINEL"])
    }

    private func assertLegacyUntouched() {
        XCTAssertEqual(store.legacySentinel, "QUARANTINED-LEGACY-SENTINEL")
        XCTAssertFalse(ContainedAuthURLProtocol.headers.contains { $0.contains("LEGACY") })
    }

    private func respondMe(user: String, index: Int = 0) {
        respond("/api/auth/me", payload: "{\"user\":{\"id\":\"\(user)\"}}", index: index)
    }
    private func respondSignIn(_ path: String, token: String, user: String) {
        respond(path, payload: "{\"session_token\":\"\(token)\",\"user\":{\"id\":\"\(user)\"},\"expires_at\":\"2030-01-01\"}")
    }
    private func respond(_ path: String, payload: String, status: Int = 200, index: Int = 0) {
        XCTAssertTrue(ContainedAuthURLProtocol.respond(path: path, status: status, data: Data(payload.utf8), index: index))
    }
    private func waitForRequest(_ path: String, count: Int = 1) async throws {
        try await waitUntil { ContainedAuthURLProtocol.requests.filter { $0.url?.path == path }.count >= count }
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Contained auth operation did not finish")
        throw URLError(.timedOut)
    }
    private func settle() async throws {
        // Await completion of the actual queued production tasks, not a timer.
        await tasks.finishExistingTasks()
    }
    private func repositoryRoot() throws -> URL {
        // #filePath is the compiled source path, not a simulator filesystem path.
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
}

@MainActor
private final class SentinelAuthTaskTracker {
    private var tasks: [Task<Void, Never>] = []
    func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        tasks.append(Task { @MainActor in await operation() })
    }
    func finishExistingTasks() async {
        for task in tasks { await task.value }
    }
}

@MainActor
private final class SentinelAuthScheduler {
    private var operations: [@MainActor () async -> Void] = []
    var count: Int { operations.count }
    func enqueue(_ operation: @escaping @MainActor () async -> Void) { operations.append(operation) }
    func run(at index: Int) async { await operations.remove(at: index)() }
}

/// Catch-all interception: unrecognized paths fail locally, never fall through
/// to a default URLSession or actual backend. Only test-supplied replies exist.
private final class ContainedAuthURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var pending: [ContainedAuthURLProtocol] = []
    private static var recorded: [URLRequest] = []
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    static var headers: [String] { requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let allowed = ["/api/auth/me", "/api/auth/apple", "/api/auth/development", "/api/auth/logout", "/api/account"].contains(request.url?.path ?? "")
        if allowed { Self.pending.append(self) }
        Self.lock.unlock()
        if !allowed { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)) }
    }
    override func stopLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        Self.pending.removeAll { $0 === self }
    }
    static func reset() { lock.lock(); defer { lock.unlock() }; pending = []; recorded = [] }
    static func respond(path: String, status: Int, data: Data, index: Int) -> Bool {
        lock.lock()
        let indices = pending.indices.filter { pending[$0].request.url?.path == path }
        let instance = indices.indices.contains(index) ? pending.remove(at: indices[index]) : nil
        lock.unlock()
        guard let instance else { return false }
        let response = HTTPURLResponse(url: instance.request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        instance.client?.urlProtocol(instance, didReceive: response, cacheStoragePolicy: .notAllowed)
        instance.client?.urlProtocol(instance, didLoad: data)
        instance.client?.urlProtocolDidFinishLoading(instance)
        return true
    }
}

@MainActor
final class KeychainEnvironmentSessionTests: XCTestCase {
    func testSecurityFrameworkScopedIsolationAndLegacyQuarantine() throws {
        #if targetEnvironment(simulator)
        let service = "com.caldera.F11.sentinel.\(UUID().uuidString)"
        let dev = try XCTUnwrap(AuthBackendEnvironment(id: .developmentLocal, baseURL: URL(string: "http://127.0.0.1:3001")!))
        let prod = try XCTUnwrap(AuthBackendEnvironment(id: .renderProduction, baseURL: URL(string: "https://plaid-backend-2wqb.onrender.com")!))
        let keychain = KeychainSessionStore(service: service)
        let legacy: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "caldera_session_token"]
        var legacyItem = legacy
        legacyItem[kSecValueData as String] = Data("LEGACY-TEST-SENTINEL".utf8)
        legacyItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        defer {
            // Exact sentinel accounts only. No enumeration or service-wide delete.
            try? keychain.clearSessionToken(for: dev)
            try? keychain.clearSessionToken(for: prod)
            SecItemDelete(legacy as CFDictionary)
        }
        let initialStatus = SecItemAdd(legacyItem as CFDictionary, nil)
        if initialStatus == errSecMissingEntitlement {
            throw XCTSkip("Unhosted unsigned XCTest agent lacks Keychain entitlement; real integration requires an entitled simulator test host")
        }
        XCTAssertEqual(initialStatus, errSecSuccess)
        XCTAssertNil(try keychain.loadSessionToken(for: dev))
        XCTAssertNil(try keychain.loadSessionToken(for: prod))
        try keychain.saveSessionToken("DEV-TEST-SENTINEL", for: dev)
        try keychain.saveSessionToken("PROD-TEST-SENTINEL", for: prod)
        XCTAssertEqual(try keychain.loadSessionToken(for: dev), "DEV-TEST-SENTINEL")
        XCTAssertEqual(try keychain.loadSessionToken(for: prod), "PROD-TEST-SENTINEL")
        try keychain.saveSessionToken("PROD-UPDATED-SENTINEL", for: prod)
        try keychain.clearSessionToken(for: dev)
        XCTAssertNil(try keychain.loadSessionToken(for: dev))
        XCTAssertEqual(try keychain.loadSessionToken(for: prod), "PROD-UPDATED-SENTINEL")
        var query = legacy
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        XCTAssertEqual(result as? Data, Data("LEGACY-TEST-SENTINEL".utf8))
        #else
        throw XCTSkip("Sentinel Security.framework integration is simulator-only")
        #endif
    }
}
