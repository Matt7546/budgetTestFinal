import Combine
import Foundation
import XCTest
@testable import Caldera_Money

@MainActor
final class AuthenticatedBankSyncLoadingOwnershipTests: XCTestCase {

    private final class Credentials {
        var userID: String?
        var sessionToken: String?

        init(
            userID: String? = "user-a",
            sessionToken: String? = "session-a"
        ) {
            self.userID = userID
            self.sessionToken = sessionToken
        }
    }

    private enum DisconnectResult {
        case networkFailure
        case rateLimited
    }

    private var cacheDefaults: UserDefaults!
    private var cacheSuiteName: String!
    private var cancellables: Set<AnyCancellable> = []
    private var sessions: [URLSession] = []

    override func setUp() {
        super.setUp()
        cacheSuiteName = "AuthenticatedBankSyncLoadingOwnershipTests.\(UUID().uuidString)"
        cacheDefaults = UserDefaults(suiteName: cacheSuiteName)
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        AuthenticatedLoadingURLProtocol.reset()
    }

    override func tearDown() {
        sessions.forEach {
            $0.invalidateAndCancel()
        }
        sessions = []
        cancellables = []
        AuthenticatedLoadingURLProtocol.reset()
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        cacheDefaults = nil
        cacheSuiteName = nil
        super.tearDown()
    }

    func testInitialAuthenticatedLoadStartsAndFinishesWithItsRequestScope() async throws {
        let (service, _) = makeService()
        let owner = try await startInitialAuthenticatedLoad(on: service)

        XCTAssertTrue(service.isLoadingLinkedAccountsAfterAuthentication)
        XCTAssertEqual(service.authenticatedLoadingRequestScope, owner)

        let finished = loadingExpectation(
            service,
            isLoading: false,
            description: "Initial authenticated loading finished"
        )
        await completeRefresh(
            on: service,
            capabilitiesSelection: .first,
            accountID: "initial-account",
            transactionID: "initial-transaction",
            completionExpectation: finished
        )

        XCTAssertNil(service.authenticatedLoadingRequestScope)
        XCTAssertEqual(service.accounts.map(\.account_id), ["initial-account"])
        XCTAssertEqual(service.transactions.map(\.transaction_id), ["initial-transaction"])
        XCTAssertEqual(service.bankSyncRefreshState.phase, .fullyUpdated)
    }

    func testDisconnectSuccessAbandonsInitialLoadingAndExposesDisconnectedState() async throws {
        let (service, _) = makeService()
        let oldOwner = try await startInitialAuthenticatedLoad(on: service)
        let disconnectRequested = requestExpectation(path: "/api/disconnect")

        service.disconnectBank()

        XCTAssertFalse(service.isLoadingLinkedAccountsAfterAuthentication)
        XCTAssertNil(service.authenticatedLoadingRequestScope)
        await fulfillment(of: [disconnectRequested], timeout: 2)

        let disconnected = connectionStateExpectation(
            service,
            description: "Disconnect response applied"
        ) {
            if case .notConnected = $0 {
                return true
            }
            return false
        }
        XCTAssertTrue(
            AuthenticatedLoadingURLProtocol.respond(
                path: "/api/disconnect",
                statusCode: 200,
                data: disconnectSuccessData
            )
        )
        await fulfillment(of: [disconnected], timeout: 2)

        var staleOutcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: oldOwner,
            data: accountsData(id: "late-account"),
            response: httpResponse(path: "/api/accounts", statusCode: 200),
            error: nil,
            reason: .authenticatedSessionAvailable,
            completion: { staleOutcome = $0 }
        )
        service.finishAuthenticatedLoading(for: oldOwner)

        XCTAssertNil(staleOutcome)
        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertTrue(service.transactions.isEmpty)
        XCTAssertFalse(service.isLoadingLinkedAccountsAfterAuthentication)
        XCTAssertTrue(service.canStartManualPlaidRefresh)
    }

    func testDisconnectNetworkFailureAbandonsInitialLoadingAndAllowsRetry() async throws {
        try await assertDisconnectFailureAllowsRetry(.networkFailure)
    }

    func testDisconnectRateLimitAbandonsInitialLoadingAndAllowsRetry() async throws {
        try await assertDisconnectFailureAllowsRetry(.rateLimited)
    }

    func testSignOutAbandonsInitialLoadingAndRejectsStaleResponse() async throws {
        let credentials = Credentials()
        let (service, _) = makeService(credentials: credentials)
        let oldOwner = try await startInitialAuthenticatedLoad(on: service)

        credentials.userID = nil
        credentials.sessionToken = nil
        service.clearLocalFinancialDataForSignOut()

        XCTAssertFalse(service.isLoadingLinkedAccountsAfterAuthentication)
        XCTAssertNil(service.authenticatedLoadingRequestScope)
        XCTAssertFalse(service.acceptsBankSyncRefreshRequests)

        var staleOutcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: oldOwner,
            data: accountsData(id: "signed-out-account"),
            response: httpResponse(path: "/api/accounts", statusCode: 200),
            error: nil,
            reason: .authenticatedSessionAvailable,
            completion: { staleOutcome = $0 }
        )
        service.finishAuthenticatedLoading(for: oldOwner)

        XCTAssertNil(staleOutcome)
        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertFalse(service.isLoadingLinkedAccountsAfterAuthentication)
    }

    func testSessionRotationDuringInitialLoadCreatesNewAuthenticatedOwner() async throws {
        let credentials = Credentials()
        let (service, _) = makeService(credentials: credentials)
        let oldOwner = try await startInitialAuthenticatedLoad(on: service)
        let newCapabilitiesRequested = requestExpectation(path: "/api/capabilities")

        credentials.sessionToken = "session-b"
        service.handleAuthenticationStateChanged(isSignedIn: true)

        let newOwner = try XCTUnwrap(service.authenticatedLoadingRequestScope)
        XCTAssertNotEqual(newOwner, oldOwner)
        XCTAssertEqual(newOwner.bankDataScope.userID, "user-a")
        XCTAssertEqual(newOwner.bankDataScope.sessionToken, "session-b")
        XCTAssertTrue(service.isLoadingLinkedAccountsAfterAuthentication)
        await fulfillment(of: [newCapabilitiesRequested], timeout: 2)

        service.finishAuthenticatedLoading(for: oldOwner)
        XCTAssertTrue(service.isLoadingLinkedAccountsAfterAuthentication)
        XCTAssertEqual(service.authenticatedLoadingRequestScope, newOwner)

        let finished = loadingExpectation(
            service,
            isLoading: false,
            description: "Rotated session loading finished"
        )
        await completeRefresh(
            on: service,
            capabilitiesSelection: .last,
            accountID: "rotated-session-account",
            transactionID: "rotated-session-transaction",
            completionExpectation: finished
        )

        XCTAssertNil(service.authenticatedLoadingRequestScope)
        XCTAssertEqual(service.accounts.map(\.account_id), ["rotated-session-account"])
    }

    func testUserChangeDuringInitialLoadAbandonsOldOwnerAndStartsNewOwner() async throws {
        let credentials = Credentials()
        let (service, _) = makeService(credentials: credentials)
        let oldOwner = try await startInitialAuthenticatedLoad(on: service)
        let newCapabilitiesRequested = requestExpectation(path: "/api/capabilities")

        credentials.userID = "user-b"
        credentials.sessionToken = "session-b"
        service.handleAuthenticationStateChanged(isSignedIn: true)

        let newOwner = try XCTUnwrap(service.authenticatedLoadingRequestScope)
        XCTAssertNotEqual(newOwner, oldOwner)
        XCTAssertEqual(newOwner.bankDataScope.userID, "user-b")
        XCTAssertEqual(newOwner.bankDataScope.sessionToken, "session-b")
        XCTAssertTrue(service.isLoadingLinkedAccountsAfterAuthentication)
        await fulfillment(of: [newCapabilitiesRequested], timeout: 2)

        var staleOutcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: oldOwner,
            data: accountsData(id: "user-a-late-account"),
            response: httpResponse(path: "/api/accounts", statusCode: 200),
            error: nil,
            reason: .authenticatedSessionAvailable,
            completion: { staleOutcome = $0 }
        )
        service.finishAuthenticatedLoading(for: oldOwner)

        XCTAssertNil(staleOutcome)
        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertTrue(service.isLoadingLinkedAccountsAfterAuthentication)
        XCTAssertEqual(service.authenticatedLoadingRequestScope, newOwner)
    }

    func testNewerAuthenticatedRefreshSupersedesOlderOwnerWithoutStaleClear() async throws {
        let (service, _) = makeService()
        let oldOwner = try await startInitialAuthenticatedLoad(on: service)
        let newerCapabilitiesRequested = requestExpectation(path: "/api/capabilities")

        service.refreshPlaidData(reason: .authenticatedSessionAvailable)

        let newOwner = try XCTUnwrap(service.authenticatedLoadingRequestScope)
        XCTAssertNotEqual(newOwner, oldOwner)
        XCTAssertTrue(service.isLoadingLinkedAccountsAfterAuthentication)
        await fulfillment(of: [newerCapabilitiesRequested], timeout: 2)

        service.finishAuthenticatedLoading(for: oldOwner)
        XCTAssertTrue(service.isLoadingLinkedAccountsAfterAuthentication)
        XCTAssertEqual(service.authenticatedLoadingRequestScope, newOwner)

        let finished = loadingExpectation(
            service,
            isLoading: false,
            description: "Newer authenticated refresh finished"
        )
        await completeRefresh(
            on: service,
            capabilitiesSelection: .last,
            accountID: "newer-account",
            transactionID: "newer-transaction",
            completionExpectation: finished
        )

        XCTAssertNil(service.authenticatedLoadingRequestScope)
        XCTAssertEqual(service.accounts.map(\.account_id), ["newer-account"])
    }

    func testManualRefreshOwnershipRemainsIndependentOfSupersededAuthenticatedLoad() async throws {
        let (service, _) = makeService()
        let oldAuthenticatedOwner = try await startInitialAuthenticatedLoad(on: service)
        let manualCapabilitiesRequested = requestExpectation(path: "/api/capabilities")

        service.refreshPlaidDataFromSettings()

        XCTAssertNil(service.authenticatedLoadingRequestScope)
        XCTAssertFalse(service.isLoadingLinkedAccountsAfterAuthentication)
        XCTAssertTrue(service.isRefreshingPlaidData)
        await fulfillment(of: [manualCapabilitiesRequested], timeout: 2)

        service.finishAuthenticatedLoading(for: oldAuthenticatedOwner)
        XCTAssertTrue(service.isRefreshingPlaidData)

        let finished = manualLoadingExpectation(
            service,
            isLoading: false,
            description: "Manual refresh loading finished"
        )
        await completeRefresh(
            on: service,
            capabilitiesSelection: .last,
            accountID: "manual-account",
            transactionID: "manual-transaction",
            completionExpectation: finished
        )

        XCTAssertFalse(service.isRefreshingPlaidData)
        XCTAssertEqual(service.accounts.map(\.account_id), ["manual-account"])
    }

    private func assertDisconnectFailureAllowsRetry(
        _ result: DisconnectResult
    ) async throws {
        let (service, _) = makeService()
        seedCachedAccount(on: service)
        _ = try await startInitialAuthenticatedLoad(on: service)
        let disconnectRequested = requestExpectation(path: "/api/disconnect")

        service.disconnectBank()

        XCTAssertFalse(service.isLoadingLinkedAccountsAfterAuthentication)
        XCTAssertNil(service.authenticatedLoadingRequestScope)
        await fulfillment(of: [disconnectRequested], timeout: 2)

        let messageSet = accountMessageExpectation(
            service,
            description: "Disconnect failure message applied"
        )
        switch result {
        case .networkFailure:
            XCTAssertTrue(
                AuthenticatedLoadingURLProtocol.respond(
                    path: "/api/disconnect",
                    error: URLError(.notConnectedToInternet)
                )
            )
        case .rateLimited:
            XCTAssertTrue(
                AuthenticatedLoadingURLProtocol.respond(
                    path: "/api/disconnect",
                    statusCode: 429,
                    data: rateLimitData
                )
            )
        }
        await fulfillment(of: [messageSet], timeout: 2)

        XCTAssertEqual(service.accounts.map(\.account_id), ["cached-account"])
        XCTAssertTrue(service.acceptsBankSyncRefreshRequests)
        XCTAssertTrue(service.canStartManualPlaidRefresh)

        let retryRequested = requestExpectation(path: "/api/capabilities")
        service.refreshPlaidDataFromSettings()
        await fulfillment(of: [retryRequested], timeout: 2)

        XCTAssertTrue(service.isRefreshingPlaidData)
        XCTAssertFalse(service.isLoadingLinkedAccountsAfterAuthentication)
    }

    private func startInitialAuthenticatedLoad(
        on service: PlaidService
    ) async throws -> BankSyncRefreshRequestScope {
        let capabilitiesRequested = requestExpectation(path: "/api/capabilities")

        service.handleAuthenticationStateChanged(isSignedIn: true)

        XCTAssertTrue(service.isLoadingLinkedAccountsAfterAuthentication)
        let owner = try XCTUnwrap(service.authenticatedLoadingRequestScope)
        await fulfillment(of: [capabilitiesRequested], timeout: 2)
        return owner
    }

    private func completeRefresh(
        on service: PlaidService,
        capabilitiesSelection: AuthenticatedLoadingURLProtocol.Selection,
        accountID: String,
        transactionID: String,
        completionExpectation: XCTestExpectation
    ) async {
        let accountsRequested = requestExpectation(path: "/api/accounts")
        let transactionsRequested = requestExpectation(path: "/api/transactions")

        XCTAssertTrue(
            AuthenticatedLoadingURLProtocol.respond(
                path: "/api/capabilities",
                selection: capabilitiesSelection,
                statusCode: 200,
                data: capabilitiesData
            )
        )
        await fulfillment(
            of: [accountsRequested, transactionsRequested],
            timeout: 2
        )

        XCTAssertTrue(
            AuthenticatedLoadingURLProtocol.respond(
                path: "/api/accounts",
                statusCode: 200,
                data: accountsData(id: accountID)
            )
        )
        XCTAssertTrue(
            AuthenticatedLoadingURLProtocol.respond(
                path: "/api/transactions",
                statusCode: 200,
                data: transactionsData(id: transactionID)
            )
        )
        await fulfillment(of: [completionExpectation], timeout: 2)
    }

    private func seedCachedAccount(
        on service: PlaidService
    ) {
        let scope = service.beginBankSyncRefreshRequest()
        var outcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: scope,
            data: accountsData(id: "cached-account"),
            response: httpResponse(path: "/api/accounts", statusCode: 200),
            error: nil,
            reason: .debugTool,
            completion: { outcome = $0 }
        )
        XCTAssertEqual(outcome, .success)
    }

    private func makeService(
        credentials providedCredentials: Credentials? = nil
    ) -> (PlaidService, Credentials) {
        let credentials = providedCredentials ?? Credentials()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticatedLoadingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        sessions.append(session)
        let service = PlaidService(
            sessionTokenProvider: { credentials.sessionToken },
            authenticatedUserIDProvider: { credentials.userID },
            urlSession: session,
            bankCacheDefaults: cacheDefaults
        )
        return (service, credentials)
    }

    private func requestExpectation(
        path: String
    ) -> XCTestExpectation {
        let requested = expectation(description: "Requested \(path)")
        AuthenticatedLoadingURLProtocol.observeNextRequest(path: path) {
            requested.fulfill()
        }
        return requested
    }

    private func loadingExpectation(
        _ service: PlaidService,
        isLoading: Bool,
        description: String
    ) -> XCTestExpectation {
        let changed = expectation(description: description)
        service.$isLoadingLinkedAccountsAfterAuthentication
            .filter { $0 == isLoading }
            .prefix(1)
            .sink { _ in
                changed.fulfill()
            }
            .store(in: &cancellables)
        return changed
    }

    private func manualLoadingExpectation(
        _ service: PlaidService,
        isLoading: Bool,
        description: String
    ) -> XCTestExpectation {
        let changed = expectation(description: description)
        service.$isRefreshingPlaidData
            .filter { $0 == isLoading }
            .prefix(1)
            .sink { _ in
                changed.fulfill()
            }
            .store(in: &cancellables)
        return changed
    }

    private func connectionStateExpectation(
        _ service: PlaidService,
        description: String,
        predicate: @escaping (PlaidConnectionState) -> Bool
    ) -> XCTestExpectation {
        let changed = expectation(description: description)
        service.$connectionState
            .filter(predicate)
            .prefix(1)
            .sink { _ in
                changed.fulfill()
            }
            .store(in: &cancellables)
        return changed
    }

    private func accountMessageExpectation(
        _ service: PlaidService,
        description: String
    ) -> XCTestExpectation {
        let changed = expectation(description: description)
        service.$accountRefreshMessage
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .prefix(1)
            .sink { _ in
                changed.fulfill()
            }
            .store(in: &cancellables)
        return changed
    }

    private var disconnectSuccessData: Data {
        Data(
            """
            {
              "success": true,
              "linked": false,
              "total_items": 1,
              "removed_items": 1,
              "failed_items": 0
            }
            """.utf8
        )
    }

    private var rateLimitData: Data {
        Data("{\"error\":\"rate_limited\",\"retry_after_seconds\":60}".utf8)
    }

    private var capabilitiesData: Data {
        Data(
            """
            {
              "accounts_enabled": true,
              "transactions_enabled": true,
              "liabilities_enabled": false,
              "liabilities_link_enabled": false
            }
            """.utf8
        )
    }

    private func accountsData(
        id: String
    ) -> Data {
        Data(
            """
            {
              "accounts": [
                {
                  "account_id": "\(id)",
                  "name": "Checking",
                  "official_name": null,
                  "type": "depository",
                  "subtype": "checking",
                  "mask": "1234",
                  "balances": {
                    "available": 1200,
                    "current": 1200
                  }
                }
              ],
              "partial_failure": false
            }
            """.utf8
        )
    }

    private func transactionsData(
        id: String
    ) -> Data {
        Data(
            """
            {
              "transactions_enabled": true,
              "transactions": [
                {
                  "transaction_id": "\(id)",
                  "name": "Purchase",
                  "amount": 10,
                  "date": "2026-09-15",
                  "pending": false,
                  "account_id": "checking"
                }
              ],
              "window_start": "2026-06-17",
              "window_end": "2026-09-15",
              "lookback_days": 90,
              "total_transactions": 1,
              "returned_transactions": 1,
              "complete": true,
              "partial_failure": false
            }
            """.utf8
        )
    }

    private func httpResponse(
        path: String,
        statusCode: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com\(path)")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

private final class AuthenticatedLoadingURLProtocol: URLProtocol, @unchecked Sendable {

    enum Selection {
        case first
        case last
    }

    private static let lock = NSLock()
    private static var pendingProtocols: [AuthenticatedLoadingURLProtocol] = []
    private static var requestObservers: [String: [() -> Void]] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let observer: (() -> Void)?
        let path = request.url?.path ?? ""

        Self.lock.lock()
        Self.pendingProtocols.append(self)
        if var observers = Self.requestObservers[path], !observers.isEmpty {
            observer = observers.removeFirst()
            Self.requestObservers[path] = observers
        } else {
            observer = nil
        }
        Self.lock.unlock()

        observer?()
    }

    override func stopLoading() {
        Self.lock.lock()
        Self.pendingProtocols.removeAll { $0 === self }
        Self.lock.unlock()
    }

    static func observeNextRequest(
        path: String,
        observer: @escaping () -> Void
    ) {
        lock.lock()
        requestObservers[path, default: []].append(observer)
        lock.unlock()
    }

    @discardableResult
    static func respond(
        path: String,
        selection: Selection = .first,
        statusCode: Int = 200,
        data: Data? = nil,
        error: Error? = nil
    ) -> Bool {
        let protocolInstance: AuthenticatedLoadingURLProtocol?

        lock.lock()
        let matchingIndices = pendingProtocols.indices.filter {
            pendingProtocols[$0].request.url?.path == path
        }
        let selectedIndex = selection == .first
            ? matchingIndices.first
            : matchingIndices.last
        if let selectedIndex {
            protocolInstance = pendingProtocols.remove(at: selectedIndex)
        } else {
            protocolInstance = nil
        }
        lock.unlock()

        guard let protocolInstance else {
            return false
        }

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
        requestObservers = [:]
        lock.unlock()
    }
}
