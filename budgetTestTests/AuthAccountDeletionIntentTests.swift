import Foundation
import XCTest
@testable import Caldera_Money

@MainActor
final class AuthAccountDeletionIntentTests: XCTestCase {

    private let userID = "deletion-intent-user"

    override func setUp() {
        super.setUp()
        AccountDeletionURLProtocol.reset()
    }

    override func tearDown() {
        AccountDeletionURLProtocol.reset()
        super.tearDown()
    }

    func testDurableIntentExistsBeforeRequestAndTransportFailureBecomesUncertain() async throws {
        let defaults = try isolatedDefaults()
        let store = PendingLocalAccountDeletionStore(defaults: defaults)
        let auth = manager(defaults: defaults)
        let deletion = Task { try await auth.deleteAccount() }

        try await waitForPendingRequest()
        let intent = try XCTUnwrap(jobs(in: store).first)
        XCTAssertEqual(intent.phase, .confirmationUncertain)
        XCTAssertEqual(intent.storeKind, .production)

        XCTAssertTrue(
            AccountDeletionURLProtocol.respond(
                path: "/api/account",
                error: URLError(.networkConnectionLost)
            )
        )
        await assertDeletionThrows(deletion)

        let recoverable = try XCTUnwrap(jobs(in: store).first)
        XCTAssertEqual(recoverable.id, intent.id)
        XCTAssertEqual(recoverable.phase, .confirmationUncertain)
        XCTAssertTrue(auth.isSignedIn)
        XCTAssertTrue(
            auth.statusMessage?.contains("local data is still saved") == true
        )
    }

    func testExpectedBackendSuccessAdvancesExactJobToLocalCleanup() async throws {
        let defaults = try isolatedDefaults()
        let store = PendingLocalAccountDeletionStore(defaults: defaults)
        let auth = manager(defaults: defaults)
        let deletion = Task { try await auth.deleteAccount() }

        try await waitForPendingRequest()
        XCTAssertEqual(jobs(in: store).first?.phase, .confirmationUncertain)
        XCTAssertTrue(respondWithConfirmedSuccess())

        let confirmed = try await deletion.value
        XCTAssertEqual(confirmed.phase, .localCleanupRequired)
        XCTAssertEqual(jobs(in: store).first, confirmed)
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.user)
        XCTAssertEqual(auth.latestConfirmedAccountDeletion?.id, confirmed.id)
    }

    func testIncompleteSuccessContractRemainsUncertain() async throws {
        try await assertAmbiguousDeletionResultPreservesIntent(
            data: Data(#"{"success":true}"#.utf8)
        )
    }

    func testSuccessFalseRemainsUncertain() async throws {
        try await assertAmbiguousDeletionResultPreservesIntent(
            data: Data(
                #"{"success":false,"removed_items":0,"failed_items":0,"sessions_revoked":0,"user_deleted":false}"#.utf8
            )
        )
    }

    func testMalformedEmptyAndInvalidSuccessResponsesRemainUncertain() async throws {
        for payload in [Data(), Data("not-json".utf8), Data(#"{"success":"yes"}"#.utf8)] {
            try await assertAmbiguousDeletionResultPreservesIntent(data: payload)
        }
    }

    func testEveryHTTPFailureRemainsUncertain() async throws {
        for statusCode in [401, 403, 409, 429, 500, 502, 503] {
            try await assertAmbiguousDeletionResultPreservesIntent(
                statusCode: statusCode,
                data: Data(#"{"error":"request_failed"}"#.utf8),
                expectsSignedIn: statusCode != 401
            )
        }
    }

    func testTimeoutAndConnectionLossRemainUncertain() async throws {
        for code in [URLError.timedOut, URLError.networkConnectionLost] {
            try await assertAmbiguousDeletionResultPreservesIntent(
                error: URLError(code)
            )
        }
    }

    func testDurableFileStoreSurvivesRelaunchReinstantiation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = PendingLocalAccountDeletionStore.defaultStorageURL(
            applicationSupportDirectory: directory
        )

        let writtenJob = try XCTUnwrap(
            PendingLocalAccountDeletionStore(fileURL: fileURL)
                .beginDeletionIntent(
                    userID: userID,
                    sessionToken: "session-a",
                    storeKind: .production
                )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let relaunchedStore = PendingLocalAccountDeletionStore(fileURL: fileURL)
        XCTAssertEqual(jobs(in: relaunchedStore), [writtenJob])
    }

    func testIntentWriteFailurePreventsBackendDeleteRequest() async throws {
        var writeAttemptCount = 0
        let failingStore = PendingLocalAccountDeletionStore(
            readData: { nil },
            replaceData: { _ in
                writeAttemptCount += 1
                throw AccountDeletionTestError.forcedWriteFailure
            }
        )
        let auth = manager(
            defaults: try isolatedDefaults(),
            pendingDeletionStore: failingStore
        )

        do {
            _ = try await auth.deleteAccount()
            XCTFail("Deletion must fail before the request when intent persistence fails.")
        } catch {
            // Expected.
        }

        XCTAssertEqual(writeAttemptCount, 1)
        XCTAssertEqual(AccountDeletionURLProtocol.pendingRequestCount(path: "/api/account"), 0)
        XCTAssertTrue(auth.isSignedIn)
    }

    func testAttemptWriteFailurePreventsBackendDeleteRequest() async throws {
        var storedData: Data?
        var writeAttemptCount = 0
        let failingStore = PendingLocalAccountDeletionStore(
            readData: { storedData },
            replaceData: { replacement in
                writeAttemptCount += 1
                guard writeAttemptCount == 1 else {
                    throw AccountDeletionTestError.forcedWriteFailure
                }
                storedData = replacement
            }
        )
        let auth = manager(
            defaults: try isolatedDefaults(),
            pendingDeletionStore: failingStore
        )

        do {
            _ = try await auth.deleteAccount()
            XCTFail("Deletion must not start until the attempt is durable.")
        } catch {
            // Expected.
        }

        XCTAssertEqual(writeAttemptCount, 2)
        XCTAssertEqual(AccountDeletionURLProtocol.pendingRequestCount(path: "/api/account"), 0)
        XCTAssertEqual(jobs(in: failingStore).first?.phase, .requestPending)
    }

    func testUncertainJobSurvivesRelaunchWithoutAutomaticDelete() async throws {
        let defaults = try isolatedDefaults()
        let store = PendingLocalAccountDeletionStore(defaults: defaults)
        let intent = try makeUncertainJob(in: store)

        let relaunched = manager(
            defaults: defaults,
            sessionToken: "replacement-session"
        )
        await Task.yield()

        XCTAssertTrue(relaunched.isSignedIn)
        XCTAssertEqual(AccountDeletionURLProtocol.pendingRequestCount(path: "/api/account"), 0)
        XCTAssertEqual(jobs(in: store), [intent])
    }

    func testDifferentUserDoesNotRetryOrTakeOwnershipOfUncertainJob() async throws {
        let defaults = try isolatedDefaults()
        let store = PendingLocalAccountDeletionStore(defaults: defaults)
        let userAJob = try makeUncertainJob(in: store)
        let userB = manager(
            defaults: defaults,
            sessionToken: "session-b",
            authenticatedUserID: "replacement-user"
        )

        do {
            _ = try await userB.retryAccountDeletion(jobID: userAJob.id)
            XCTFail("Another identity must not retry this job.")
        } catch {
            // Expected.
        }

        XCTAssertEqual(AccountDeletionURLProtocol.pendingRequestCount(path: "/api/account"), 0)
        XCTAssertEqual(jobs(in: store), [userAJob])
    }

    func testExplicitRetryUsesSameJobUUIDForOriginalIdentity() async throws {
        let defaults = try isolatedDefaults()
        let store = PendingLocalAccountDeletionStore(defaults: defaults)
        let intent = try makeUncertainJob(in: store)
        let auth = manager(
            defaults: defaults,
            sessionToken: "replacement-session"
        )
        let retry = Task {
            try await auth.retryAccountDeletion(jobID: intent.id)
        }

        try await waitForPendingRequest()
        XCTAssertEqual(jobs(in: store).first?.id, intent.id)
        XCTAssertTrue(respondWithConfirmedSuccess())
        let confirmed = try await retry.value

        XCTAssertEqual(confirmed.id, intent.id)
        XCTAssertEqual(confirmed.phase, .localCleanupRequired)
    }

    func testStaleAttemptCannotDowngradeConfirmedJob() throws {
        let store = PendingLocalAccountDeletionStore(defaults: try isolatedDefaults())
        let job = try XCTUnwrap(
            store.beginDeletionIntent(
                userID: userID,
                sessionToken: "session-a",
                storeKind: .production
            )
        )
        let attemptOne = try XCTUnwrap(store.beginServerAttempt(matching: job))
        let attemptTwo = try XCTUnwrap(store.beginServerAttempt(matching: attemptOne))
        let confirmed = try XCTUnwrap(
            store.markServerDeletionConfirmed(matching: attemptTwo)
        )

        XCTAssertNil(store.markServerConfirmationUncertain(matching: attemptOne))
        XCTAssertEqual(jobs(in: store), [confirmed])
        XCTAssertEqual(jobs(in: store).first?.phase, .localCleanupRequired)
    }

    func testUnreadableDeletionQueuesAreTypedUnavailableAndPreserveBytes() {
        let unreadablePayloads = [
            Data("{malformed".utf8),
            Data(#"{"formatVersion":999,"jobs":[]}"#.utf8),
            Data(#"{"formatVersion":1,"jobs":[{"id":"partial"}]}"#.utf8)
        ]

        for originalBytes in unreadablePayloads {
            var storedBytes = originalBytes
            var replacementCount = 0
            let store = PendingLocalAccountDeletionStore(
                readData: { storedBytes },
                replaceData: { replacement in
                    replacementCount += 1
                    storedBytes = replacement
                }
            )

            XCTAssertEqual(store.readPendingDeletions(), .unavailable)
            XCTAssertNil(
                store.beginDeletionIntent(
                    userID: userID,
                    sessionToken: "session-a",
                    storeKind: .production
                )
            )
            XCTAssertEqual(replacementCount, 0)
            XCTAssertEqual(storedBytes, originalBytes)
        }
    }

    func testDelayedConfirmedSuccessDoesNotOverwriteNewerAuthState() async throws {
        let defaults = try isolatedDefaults()
        let store = PendingLocalAccountDeletionStore(defaults: defaults)
        let auth = manager(defaults: defaults)
        let deletion = Task { try await auth.deleteAccount() }

        try await waitForPendingRequest()
        auth.invalidateSessionIfCurrent(
            BankDataRequestScope(
                userID: userID,
                sessionToken: "session-a",
                lifecycleGeneration: 0
            )
        )
        let expiryMessage = auth.statusMessage
        XCTAssertTrue(respondWithConfirmedSuccess())

        let confirmed = try await deletion.value
        XCTAssertEqual(confirmed.phase, .localCleanupRequired)
        XCTAssertEqual(jobs(in: store).first?.phase, .localCleanupRequired)
        XCTAssertEqual(auth.statusMessage, expiryMessage)
        XCTAssertFalse(auth.isSignedIn)
    }
}

private extension AuthAccountDeletionIntentTests {

    static let confirmedSuccessData = Data(
        #"{"success":true,"removed_items":1,"failed_items":0,"sessions_revoked":1,"user_deleted":true}"#.utf8
    )

    func manager(
        defaults: UserDefaults,
        sessionToken: String = "session-a",
        authenticatedUserID: String? = nil,
        pendingDeletionStore: PendingLocalAccountDeletionStore? = nil
    ) -> AuthManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountDeletionURLProtocol.self]
        return AuthManager(
            urlSession: URLSession(configuration: configuration),
            pendingDeletionDefaults: defaults,
            pendingDeletionStore: pendingDeletionStore,
            localStoreKind: .production,
            restoreSavedSession: false,
            initialSessionToken: sessionToken,
            initialUser: AuthUserSummary(
                id: authenticatedUserID ?? userID,
                email: nil,
                fullName: nil
            ),
            sessionTokenSaver: { _ in },
            localDevelopmentSignInAllowed: { true }
        )
    }

    func jobs(
        in store: PendingLocalAccountDeletionStore
    ) -> [PendingLocalAccountDeletion] {
        guard case .available(let jobs) = store.readPendingDeletions() else {
            XCTFail("Expected a readable account-deletion queue.")
            return []
        }
        return jobs
    }

    func makeUncertainJob(
        in store: PendingLocalAccountDeletionStore
    ) throws -> PendingLocalAccountDeletion {
        let intent = try XCTUnwrap(
            store.beginDeletionIntent(
                userID: userID,
                sessionToken: "session-a",
                storeKind: .production
            )
        )
        // Simulate termination after the durable attempt transition but before
        // any response can be classified.
        return try XCTUnwrap(store.beginServerAttempt(matching: intent))
    }

    func assertAmbiguousDeletionResultPreservesIntent(
        statusCode: Int = 200,
        data: Data? = nil,
        error: Error? = nil,
        expectsSignedIn: Bool = true
    ) async throws {
        AccountDeletionURLProtocol.reset()
        let defaults = try isolatedDefaults()
        let store = PendingLocalAccountDeletionStore(defaults: defaults)
        let auth = manager(defaults: defaults)
        let deletion = Task { try await auth.deleteAccount() }

        try await waitForPendingRequest()
        let originalID = try XCTUnwrap(jobs(in: store).first?.id)
        XCTAssertTrue(
            AccountDeletionURLProtocol.respond(
                path: "/api/account",
                statusCode: statusCode,
                data: data,
                error: error
            )
        )
        await assertDeletionThrows(deletion)

        let pending = try XCTUnwrap(jobs(in: store).first)
        XCTAssertEqual(pending.id, originalID)
        XCTAssertEqual(pending.phase, .confirmationUncertain)
        XCTAssertEqual(auth.isSignedIn, expectsSignedIn)
        XCTAssertTrue(auth.statusMessage?.contains("local data is still saved") == true)
    }

    func assertDeletionThrows(
        _ deletion: Task<PendingLocalAccountDeletion, Error>
    ) async {
        do {
            _ = try await deletion.value
            XCTFail("An ambiguous deletion result must be surfaced.")
        } catch {
            // Expected.
        }
    }

    func respondWithConfirmedSuccess() -> Bool {
        AccountDeletionURLProtocol.respond(
            path: "/api/account",
            statusCode: 200,
            data: Self.confirmedSuccessData
        )
    }

    func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "AuthAccountDeletionIntentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func waitForPendingRequest(
        path: String = "/api/account"
    ) async throws {
        for _ in 0..<200 {
            if AccountDeletionURLProtocol.pendingRequestCount(path: path) > 0 {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for account-deletion request.")
    }
}

private enum AccountDeletionTestError: Error {
    case forcedWriteFailure
}

private final class AccountDeletionURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    private static var pendingProtocols: [AccountDeletionURLProtocol] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.pendingProtocols.append(self)
        Self.lock.unlock()
    }

    override func stopLoading() {
        Self.lock.lock()
        Self.pendingProtocols.removeAll { $0 === self }
        Self.lock.unlock()
    }

    static func pendingRequestCount(path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingProtocols.filter { $0.request.url?.path == path }.count
    }

    @discardableResult
    static func respond(
        path: String,
        statusCode: Int = 200,
        data: Data? = nil,
        error: Error? = nil
    ) -> Bool {
        let protocolInstance: AccountDeletionURLProtocol?

        lock.lock()
        if let index = pendingProtocols.firstIndex(where: {
            $0.request.url?.path == path
        }) {
            protocolInstance = pendingProtocols.remove(at: index)
        } else {
            protocolInstance = nil
        }
        lock.unlock()

        guard let protocolInstance else { return false }
        if let error {
            protocolInstance.client?.urlProtocol(
                protocolInstance,
                didFailWithError: error
            )
            return true
        }

        let response = HTTPURLResponse(
            url: protocolInstance.request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        protocolInstance.client?.urlProtocol(
            protocolInstance,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        if let data {
            protocolInstance.client?.urlProtocol(
                protocolInstance,
                didLoad: data
            )
        }
        protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
        return true
    }

    static func reset() {
        lock.lock()
        pendingProtocols = []
        lock.unlock()
    }
}
