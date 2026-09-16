import Foundation
import XCTest
@testable import Caldera_Money

@MainActor
final class BankSyncLifecycleIsolationTests: XCTestCase {

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
        case success
        case networkFailure
        case rateLimited
    }

    private enum StaleCapabilitiesResult {
        case rateLimited
        case transactionsDisabled
        case ordinaryFailure
    }

    private var cacheDefaults: UserDefaults!
    private var cacheSuiteName: String!

    override func setUp() {
        super.setUp()
        cacheSuiteName = "BankSyncLifecycleIsolationTests.\(UUID().uuidString)"
        cacheDefaults = UserDefaults(suiteName: cacheSuiteName)
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        LifecycleBankURLProtocol.reset()
    }

    override func tearDown() {
        LifecycleBankURLProtocol.reset()
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        cacheDefaults = nil
        cacheSuiteName = nil
        super.tearDown()
    }

    func testOldExchangeSuccessAfterDisconnectDoesNotInvalidateDisconnectScope() async {
        let (service, _) = makeService()
        seedAccount(id: "connected-account", on: service)
        let oldLinkScope = service.beginPlaidLinkOperation()
        service.startPublicTokenExchange(
            "old-public-token",
            institutionName: "Old Bank",
            institutionID: "old-bank",
            requestScope: oldLinkScope
        )
        await waitForPendingRequest(path: "/api/exchange_public_token")

        service.disconnectBank()
        await waitForPendingRequest(path: "/api/disconnect")

        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/exchange_public_token",
                statusCode: 200,
                data: Data("{\"success\":true}".utf8)
            )
        )
        await settleCallbacks()
        XCTAssertEqual(LifecycleBankURLProtocol.pendingRequestCount(path: "/api/capabilities"), 0)

        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/disconnect",
                statusCode: 200,
                data: disconnectSuccessData
            )
        )
        await waitUntil {
            service.accounts.isEmpty && service.acceptsBankSyncRefreshRequests
        }

        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertTrue(service.transactions.isEmpty)
        XCTAssertFalse(service.isRefreshingPlaidData)
        XCTAssertEqual(LifecycleBankURLProtocol.pendingRequestCount(path: "/api/capabilities"), 0)
    }

    func testOldExchangeSuccessAfterUserAndSessionChangeIsIgnored() async {
        let credentials = Credentials()
        let (service, _) = makeService(credentials: credentials)
        let oldLinkScope = service.beginPlaidLinkOperation()
        service.startPublicTokenExchange(
            "old-public-token",
            institutionName: "Old Bank",
            institutionID: "old-bank",
            requestScope: oldLinkScope
        )
        await waitForPendingRequest(path: "/api/exchange_public_token")

        credentials.userID = "user-b"
        credentials.sessionToken = "session-b"
        seedAccount(id: "user-b-account", on: service)
        service.accountRefreshMessage = "Current session message"

        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/exchange_public_token",
                statusCode: 200,
                data: Data("{\"success\":true}".utf8)
            )
        )
        await settleCallbacks()
        XCTAssertEqual(service.accounts.map(\.account_id), ["user-b-account"])
        XCTAssertEqual(service.accountRefreshMessage, "Current session message")
        XCTAssertEqual(LifecycleBankURLProtocol.totalRequestCount, 1)
    }

    func testOldExchange401CannotDamageNewerSession() async {
        let credentials = Credentials()
        let (service, _) = makeService(credentials: credentials)
        let oldLinkScope = service.beginPlaidLinkOperation()
        service.startPublicTokenExchange(
            "old-public-token",
            institutionName: "Old Bank",
            institutionID: "old-bank",
            requestScope: oldLinkScope
        )
        await waitForPendingRequest(path: "/api/exchange_public_token")

        credentials.userID = "user-b"
        credentials.sessionToken = "session-b"
        seedAccount(id: "user-b-account", on: service)
        service.accountRefreshMessage = "Current session message"

        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/exchange_public_token",
                statusCode: 401,
                data: Data("{\"error\":\"unauthorized\"}".utf8)
            )
        )
        await settleCallbacks()
        XCTAssertEqual(service.accounts.map(\.account_id), ["user-b-account"])
        XCTAssertEqual(service.accountRefreshMessage, "Current session message")
        XCTAssertTrue(service.acceptsBankSyncRefreshRequests)
        if case .connected = service.connectionState {
        } else {
            XCTFail("A stale exchange 401 changed the newer session's connection state.")
        }
    }

    func testOldLinkTokenCallbackAfterLifecycleChangeIsIgnored() {
        let (service, _) = makeService()
        let oldLinkScope = service.beginPlaidLinkOperation()
        service.accountRefreshMessage = "Current message"

        service.disconnectBank()

        XCTAssertNil(
            service.handleCreateLinkTokenResponse(
                requestScope: oldLinkScope,
                data: Data("{\"link_token\":\"old-link-token\"}".utf8),
                response: httpResponse(path: "/api/create_link_token", statusCode: 200),
                error: nil
            )
        )
        XCTAssertEqual(service.accountRefreshMessage, "Current message")
        XCTAssertFalse(service.isLinkOpen)
    }

    func testCurrentLinkAndExchangeResponsesStartNormalPostLinkRefresh() async throws {
        let (service, _) = makeService()
        let linkScope = service.beginPlaidLinkOperation()
        let token = try XCTUnwrap(
            service.handleCreateLinkTokenResponse(
                requestScope: linkScope,
                data: Data("{\"link_token\":\"current-link-token\"}".utf8),
                response: httpResponse(path: "/api/create_link_token", statusCode: 200),
                error: nil
            )
        )
        XCTAssertEqual(token, "current-link-token")

        service.startPublicTokenExchange(
            "current-public-token",
            institutionName: "Current Bank",
            institutionID: "current-bank",
            requestScope: linkScope
        )
        await waitForPendingRequest(path: "/api/exchange_public_token")
        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/exchange_public_token",
                statusCode: 200,
                data: Data("{\"success\":true}".utf8)
            )
        )

        await completeCurrentRefresh(
            service: service,
            accountID: "linked-account",
            transactionID: "linked-transaction"
        )
        XCTAssertEqual(service.accounts.map(\.account_id), ["linked-account"])
        XCTAssertEqual(service.transactions.map(\.transaction_id), ["linked-transaction"])
        XCTAssertEqual(service.bankSyncRefreshState.phase, .fullyUpdated)
    }

    func testStaleStandalone429CannotOverwriteNewerCoordinatedRefresh() async {
        await assertStaleStandaloneCapabilitiesIsIgnored(.rateLimited)
    }

    func testStaleStandaloneDisabledTransactionsCannotClearNewerData() async {
        await assertStaleStandaloneCapabilitiesIsIgnored(.transactionsDisabled)
    }

    func testStaleStandaloneOrdinaryFailureCannotOverwriteNewerRefresh() async {
        await assertStaleStandaloneCapabilitiesIsIgnored(.ordinaryFailure)
    }

    func testCurrentStandaloneCapabilitiesStillApplies() async {
        let (service, _) = makeService()

        service.refreshPlaidCapabilities()
        await waitForPendingRequest(path: "/api/capabilities")
        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/capabilities",
                statusCode: 200,
                data: capabilitiesData(transactionsEnabled: false)
            )
        )
        await waitUntil {
            service.backendTransactionsEnabled == false
        }

        XCTAssertFalse(service.backendTransactionsEnabled)
    }

    func testDisconnectSuccessAbandonsManualLoadingAndRejectsStaleRefresh() async {
        await assertDisconnectAbandonsManualLoading(.success)
    }

    func testDisconnectNetworkFailureAbandonsManualLoadingAndAllowsRetry() async {
        await assertDisconnectAbandonsManualLoading(.networkFailure)
    }

    func testDisconnectRateLimitAbandonsManualLoadingAndAllowsRetry() async {
        await assertDisconnectAbandonsManualLoading(.rateLimited)
    }

    func testNonmanualRefreshSupersedesManualLoadingWithoutLettingStaleWorkClearNewOwner() async {
        let (service, _) = makeService()

        service.refreshPlaidDataFromSettings()
        await waitForPendingRequest(path: "/api/capabilities", count: 1)
        XCTAssertTrue(service.isRefreshingPlaidData)

        service.refreshPlaidData(reason: .linkSuccessInitialLoad)
        await waitForPendingRequest(path: "/api/capabilities", count: 2)
        XCTAssertFalse(service.isRefreshingPlaidData)

        service.refreshPlaidDataFromSettings()
        await waitForPendingRequest(path: "/api/capabilities", count: 3)
        XCTAssertTrue(service.isRefreshingPlaidData)

        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/capabilities",
                selection: .first,
                statusCode: 429,
                data: rateLimitData
            )
        )
        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/capabilities",
                selection: .first,
                statusCode: 500,
                data: ordinaryFailureData
            )
        )
        await settleCallbacks()
        XCTAssertTrue(service.isRefreshingPlaidData)

        await completeCurrentRefresh(
            service: service,
            accountID: "newest-account",
            transactionID: "newest-transaction"
        )
        XCTAssertFalse(service.isRefreshingPlaidData)
        XCTAssertFalse(service.canStartManualPlaidRefresh)
        XCTAssertEqual(service.accounts.map(\.account_id), ["newest-account"])
    }

    private func assertStaleStandaloneCapabilitiesIsIgnored(
        _ staleResult: StaleCapabilitiesResult
    ) async {
        let (service, _) = makeService()

        service.refreshPlaidCapabilities()
        await waitForPendingRequest(path: "/api/capabilities", count: 1)

        service.refreshPlaidDataFromSettings()
        await waitForPendingRequest(path: "/api/capabilities", count: 2)
        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/capabilities",
                selection: .last,
                statusCode: 200,
                data: capabilitiesData(transactionsEnabled: true)
            )
        )
        await completeAccountsAndTransactions(
            service: service,
            accountID: "new-account",
            transactionID: "new-transaction"
        )

        service.accountRefreshMessage = "Newer refresh won"
        let balanceRefresh = service.lastAccountsRefreshDate
        let transactionRefresh = service.lastTransactionsRefreshDate
        let automationEligibility = service.transactionAutomationIsEligible
        let accountSnapshot = PlaidLocalCache.loadAccountSnapshot(
            for: "user-a",
            defaults: cacheDefaults
        )
        let transactionSnapshot = PlaidLocalCache.loadTransactionSnapshot(
            defaults: cacheDefaults
        )

        switch staleResult {
        case .rateLimited:
            XCTAssertTrue(
                LifecycleBankURLProtocol.respond(
                    path: "/api/capabilities",
                    selection: .first,
                    statusCode: 429,
                    data: rateLimitData
                )
            )
        case .transactionsDisabled:
            XCTAssertTrue(
                LifecycleBankURLProtocol.respond(
                    path: "/api/capabilities",
                    selection: .first,
                    statusCode: 200,
                    data: capabilitiesData(transactionsEnabled: false)
                )
            )
        case .ordinaryFailure:
            XCTAssertTrue(
                LifecycleBankURLProtocol.respond(
                    path: "/api/capabilities",
                    selection: .first,
                    statusCode: 500,
                    data: ordinaryFailureData
                )
            )
        }
        await settleCallbacks()

        XCTAssertEqual(service.accounts.map(\.account_id), ["new-account"])
        XCTAssertEqual(service.transactions.map(\.transaction_id), ["new-transaction"])
        XCTAssertEqual(service.lastAccountsRefreshDate, balanceRefresh)
        XCTAssertEqual(service.lastTransactionsRefreshDate, transactionRefresh)
        XCTAssertEqual(service.transactionAutomationIsEligible, automationEligibility)
        XCTAssertTrue(automationEligibility)
        XCTAssertEqual(service.accountRefreshMessage, "Newer refresh won")
        XCTAssertTrue(service.backendTransactionsEnabled)
        XCTAssertEqual(accountSnapshot?.accounts.map(\.account_id), ["new-account"])
        XCTAssertEqual(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )?.lastSuccessfulRefresh,
            accountSnapshot?.lastSuccessfulRefresh
        )
        XCTAssertEqual(transactionSnapshot.transactions.map(\.transaction_id), ["new-transaction"])
        XCTAssertEqual(
            PlaidLocalCache.loadTransactionSnapshot(
                defaults: cacheDefaults
            ).lastSuccessfulRefresh,
            transactionSnapshot.lastSuccessfulRefresh
        )
    }

    private func assertDisconnectAbandonsManualLoading(
        _ result: DisconnectResult
    ) async {
        let (service, _) = makeService()

        service.refreshPlaidDataFromSettings()
        await waitForPendingRequest(path: "/api/capabilities")
        XCTAssertTrue(service.isRefreshingPlaidData)

        service.disconnectBank()
        await waitForPendingRequest(path: "/api/disconnect")
        XCTAssertFalse(service.isRefreshingPlaidData)

        switch result {
        case .success:
            XCTAssertTrue(
                LifecycleBankURLProtocol.respond(
                    path: "/api/disconnect",
                    statusCode: 200,
                    data: disconnectSuccessData
                )
            )
        case .networkFailure:
            XCTAssertTrue(
                LifecycleBankURLProtocol.respond(
                    path: "/api/disconnect",
                    error: URLError(.notConnectedToInternet)
                )
            )
        case .rateLimited:
            XCTAssertTrue(
                LifecycleBankURLProtocol.respond(
                    path: "/api/disconnect",
                    statusCode: 429,
                    data: rateLimitData
                )
            )
        }

        await waitUntil {
            service.acceptsBankSyncRefreshRequests
        }
        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/capabilities",
                statusCode: 429,
                data: rateLimitData
            )
        )
        await settleCallbacks()

        XCTAssertFalse(service.isRefreshingPlaidData)
        XCTAssertTrue(service.canStartManualPlaidRefresh)
    }

    private func completeCurrentRefresh(
        service: PlaidService,
        accountID: String,
        transactionID: String
    ) async {
        await waitForPendingRequest(path: "/api/capabilities")
        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/capabilities",
                selection: .last,
                statusCode: 200,
                data: capabilitiesData(transactionsEnabled: true)
            )
        )
        await completeAccountsAndTransactions(
            service: service,
            accountID: accountID,
            transactionID: transactionID
        )
    }

    private func completeAccountsAndTransactions(
        service: PlaidService,
        accountID: String,
        transactionID: String
    ) async {
        await waitForPendingRequest(path: "/api/accounts")
        await waitForPendingRequest(path: "/api/transactions")
        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/accounts",
                statusCode: 200,
                data: accountsData(id: accountID)
            )
        )
        XCTAssertTrue(
            LifecycleBankURLProtocol.respond(
                path: "/api/transactions",
                statusCode: 200,
                data: transactionsData(id: transactionID)
            )
        )
        await waitUntil {
            service.bankSyncRefreshState.phase == .fullyUpdated &&
                service.accounts.map(\.account_id) == [accountID] &&
                service.transactions.map(\.transaction_id) == [transactionID]
        }
    }

    private func seedAccount(
        id: String,
        on service: PlaidService
    ) {
        let scope = service.beginBankSyncRefreshRequest()
        service.handleAccountsResponse(
            requestScope: scope,
            data: accountsData(id: id),
            response: httpResponse(path: "/api/accounts", statusCode: 200),
            error: nil,
            reason: .debugTool,
            completion: { _ in }
        )
    }

    private func makeService(
        credentials providedCredentials: Credentials? = nil
    ) -> (PlaidService, Credentials) {
        let credentials = providedCredentials ?? Credentials()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LifecycleBankURLProtocol.self]
        let service = PlaidService(
            sessionTokenProvider: { credentials.sessionToken },
            authenticatedUserIDProvider: { credentials.userID },
            urlSession: URLSession(configuration: configuration),
            bankCacheDefaults: cacheDefaults
        )
        return (service, credentials)
    }

    private func waitForPendingRequest(
        path: String,
        count: Int = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await waitUntil(file: file, line: line) {
            LifecycleBankURLProtocol.pendingRequestCount(path: path) >= count
        }
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<400 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for asynchronous Bank Sync state.", file: file, line: line)
    }

    private func settleCallbacks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
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

    private var ordinaryFailureData: Data {
        Data("{\"error\":\"server_error\"}".utf8)
    }

    private func capabilitiesData(
        transactionsEnabled: Bool
    ) -> Data {
        Data(
            """
            {
              "accounts_enabled": true,
              "transactions_enabled": \(transactionsEnabled),
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

private final class LifecycleBankURLProtocol: URLProtocol, @unchecked Sendable {

    enum Selection {
        case first
        case last
    }

    private static let lock = NSLock()
    private static var pendingProtocols: [LifecycleBankURLProtocol] = []
    private static var storedTotalRequestCount = 0

    static var totalRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedTotalRequestCount
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.storedTotalRequestCount += 1
        Self.pendingProtocols.append(self)
        Self.lock.unlock()
    }

    override func stopLoading() {
        Self.lock.lock()
        Self.pendingProtocols.removeAll { $0 === self }
        Self.lock.unlock()
    }

    static func pendingRequestCount(
        path: String
    ) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pendingProtocols.filter { $0.request.url?.path == path }.count
    }

    @discardableResult
    static func respond(
        path: String,
        selection: Selection = .first,
        statusCode: Int = 200,
        data: Data? = nil,
        error: Error? = nil
    ) -> Bool {
        let protocolInstance: LifecycleBankURLProtocol?

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
        storedTotalRequestCount = 0
        lock.unlock()
    }
}
