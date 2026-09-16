import Foundation
import XCTest
@testable import Caldera_Money

@MainActor
final class BankDataRequestCacheIsolationTests: XCTestCase {

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

    private var cacheDefaults: UserDefaults!
    private var cacheSuiteName: String!

    override func setUp() {
        super.setUp()
        cacheSuiteName = "BankDataRequestCacheIsolationTests.\(UUID().uuidString)"
        cacheDefaults = UserDefaults(suiteName: cacheSuiteName)
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        ControlledBankURLProtocol.reset()
    }

    override func tearDown() {
        ControlledBankURLProtocol.reset()
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        cacheDefaults = nil
        cacheSuiteName = nil
        super.tearDown()
    }

    func testAccountResponseAfterLocalSignOutClearCannotRepopulateMemoryOrCache() {
        let (service, _) = makeService()
        let staleScope = service.beginBankSyncRefreshRequest()

        service.clearLocalFinancialDataForSignOut()
        let outcome = applyAccounts(
            id: "late-account",
            balance: 900,
            scope: staleScope,
            to: service
        )

        XCTAssertNil(outcome)
        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertNil(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )
        XCTAssertFalse(service.acceptsBankSyncRefreshRequests)

        service.refreshPlaidData(reason: .debugTool)
        XCTAssertEqual(ControlledBankURLProtocol.requestCount, 0)
    }

    func testUserCannotRestoreAnotherUsersAccountSnapshotOrTimestamp() {
        let refreshedAt = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: [account(id: "user-a-account", balance: 700)],
                lastSuccessfulRefresh: refreshedAt,
                ownerUserID: "user-a",
                defaults: cacheDefaults
            )
        )

        let (userBService, _) = makeService(
            credentials: Credentials(
                userID: "user-b",
                sessionToken: "session-b"
            )
        )
        XCTAssertTrue(userBService.accounts.isEmpty)
        XCTAssertNil(userBService.lastAccountsRefreshDate)

        let (userAService, _) = makeService()
        XCTAssertEqual(userAService.accounts.map(\.account_id), ["user-a-account"])
        XCTAssertEqual(userAService.lastAccountsRefreshDate, refreshedAt)
    }

    func testLegacyOwnerlessAccountCacheIsRejectedWithoutClearingUnrelatedPersistence() throws {
        let legacyAccounts = try JSONEncoder().encode([
            account(id: "legacy-account", balance: 500)
        ])
        let legacyRefresh = Date(timeIntervalSince1970: 1_700_000_000)
        cacheDefaults.set(legacyAccounts, forKey: "plaid_cached_accounts")
        cacheDefaults.set(legacyRefresh, forKey: "plaid_last_accounts_refresh_date")
        cacheDefaults.set("planning-data", forKey: "unrelated_planning_marker")

        let (service, _) = makeService()

        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertNil(service.lastAccountsRefreshDate)
        XCTAssertNil(cacheDefaults.object(forKey: "plaid_cached_accounts"))
        XCTAssertNil(cacheDefaults.object(forKey: "plaid_last_accounts_refresh_date"))
        XCTAssertEqual(
            cacheDefaults.string(forKey: "unrelated_planning_marker"),
            "planning-data"
        )
    }

    func testMalformedOrUnknownAccountSnapshotOwnershipIsRejected() throws {
        let malformed = CachedPlaidAccountSnapshot(
            accounts: [account(id: "malformed", balance: 400)],
            lastSuccessfulRefresh: Date(timeIntervalSince1970: 1_700_000_000),
            ownerUserID: " "
        )
        cacheDefaults.set(
            try JSONEncoder().encode(malformed),
            forKey: "plaid_cached_account_snapshot"
        )

        XCTAssertNil(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )
        XCTAssertNil(
            PlaidLocalCache.loadAccountSnapshot(
                for: nil,
                defaults: cacheDefaults
            )
        )
    }

    func testSameUserAccountSnapshotRestoresAcrossServiceInstancesWithOriginalTimestamp() {
        let refreshedAt = Date(timeIntervalSince1970: 1_810_000_000)
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: [account(id: "restored-account", balance: 1_200)],
                lastSuccessfulRefresh: refreshedAt,
                ownerUserID: "user-a",
                defaults: cacheDefaults
            )
        )

        let (firstService, _) = makeService()
        let (secondService, _) = makeService()

        XCTAssertEqual(firstService.accounts.map(\.account_id), ["restored-account"])
        XCTAssertEqual(secondService.accounts.map(\.account_id), ["restored-account"])
        XCTAssertEqual(firstService.lastAccountsRefreshDate, refreshedAt)
        XCTAssertEqual(secondService.lastAccountsRefreshDate, refreshedAt)
    }

    func testOlderAccountResponseCompletingLastCannotOverwriteNewerResult() throws {
        let (service, _) = makeService()
        let olderScope = service.beginBankSyncRefreshRequest()
        let newerScope = service.beginBankSyncRefreshRequest()

        XCTAssertEqual(
            applyAccounts(
                id: "new-account",
                balance: 2_000,
                scope: newerScope,
                to: service
            ),
            .success
        )
        let acceptedSnapshot = try XCTUnwrap(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )

        XCTAssertNil(
            applyAccounts(
                id: "old-account",
                balance: 100,
                scope: olderScope,
                to: service
            )
        )

        XCTAssertEqual(service.accounts.map(\.account_id), ["new-account"])
        let persistedSnapshot = try XCTUnwrap(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )
        XCTAssertEqual(persistedSnapshot.accounts.map(\.account_id), ["new-account"])
        XCTAssertEqual(
            persistedSnapshot.lastSuccessfulRefresh,
            acceptedSnapshot.lastSuccessfulRefresh
        )
    }

    func testOlderTransactionResponseCompletingLastCannotOverwriteNewerResult() {
        let (service, _) = makeService()
        let olderScope = service.beginBankSyncRefreshRequest()
        let newerScope = service.beginBankSyncRefreshRequest()

        XCTAssertEqual(
            applyTransactions(
                id: "new-transaction",
                scope: newerScope,
                to: service
            ),
            .success
        )
        XCTAssertNil(
            applyTransactions(
                id: "old-transaction",
                scope: olderScope,
                to: service
            )
        )

        XCTAssertEqual(service.transactions.map(\.transaction_id), ["new-transaction"])
        XCTAssertEqual(
            PlaidLocalCache.loadTransactionSnapshot(
                defaults: cacheDefaults
            ).transactions.map(\.transaction_id),
            ["new-transaction"]
        )
    }

    func testOlderFailureAndAuthorizationErrorCannotDamageNewerStateOrSession() {
        let (service, credentials) = makeService()
        let olderScope = service.beginBankSyncRefreshRequest()
        let newerScope = service.beginBankSyncRefreshRequest()

        _ = applyAccounts(
            id: "current-account",
            balance: 1_500,
            scope: newerScope,
            to: service
        )
        _ = applyTransactions(
            id: "current-transaction",
            scope: newerScope,
            to: service
        )
        let acceptedCallCount = service.plaidCallsThisSession

        var staleAccountOutcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: olderScope,
            data: Data("{\"error\":\"unauthorized\"}".utf8),
            response: httpResponse(path: "/api/accounts", statusCode: 401),
            error: nil,
            reason: .debugTool,
            completion: { staleAccountOutcome = $0 }
        )
        var staleTransactionOutcome: BankSyncFetchOutcome?
        service.handleTransactionsResponse(
            requestScope: olderScope,
            data: nil,
            response: nil,
            error: URLError(.notConnectedToInternet),
            reason: .debugTool,
            completion: { staleTransactionOutcome = $0 }
        )

        XCTAssertNil(staleAccountOutcome)
        XCTAssertNil(staleTransactionOutcome)
        XCTAssertEqual(service.accounts.map(\.account_id), ["current-account"])
        XCTAssertEqual(service.transactions.map(\.transaction_id), ["current-transaction"])
        XCTAssertEqual(service.plaidCallsThisSession, acceptedCallCount)
        if case .connected = service.connectionState {
        } else {
            XCTFail("A stale authorization error changed the current connection state.")
        }

        credentials.userID = "user-b"
        credentials.sessionToken = "session-b"
        var priorSessionOutcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: newerScope,
            data: Data("{\"error\":\"unauthorized\"}".utf8),
            response: httpResponse(path: "/api/accounts", statusCode: 401),
            error: nil,
            reason: .debugTool,
            completion: { priorSessionOutcome = $0 }
        )
        XCTAssertNil(priorSessionOutcome)
        XCTAssertEqual(credentials.userID, "user-b")
        XCTAssertEqual(credentials.sessionToken, "session-b")
        XCTAssertEqual(service.accounts.map(\.account_id), ["current-account"])
    }

    func testDisconnectDuringRefreshRejectsLateSuccessAndFailureCallbacks() {
        let (service, _) = makeService()
        let staleScope = service.beginBankSyncRefreshRequest()
        service.accountRefreshMessage = "Disconnecting"

        service.disconnectBank()
        XCTAssertFalse(service.acceptsBankSyncRefreshRequests)

        let successOutcome = applyAccounts(
            id: "late-after-disconnect",
            balance: 800,
            scope: staleScope,
            to: service
        )
        var failureOutcome: BankSyncFetchOutcome?
        service.handleTransactionsResponse(
            requestScope: staleScope,
            data: nil,
            response: nil,
            error: URLError(.timedOut),
            reason: .debugTool,
            completion: { failureOutcome = $0 }
        )

        XCTAssertNil(successOutcome)
        XCTAssertNil(failureOutcome)
        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertTrue(service.transactions.isEmpty)
        XCTAssertEqual(service.accountRefreshMessage, "Disconnecting")
        XCTAssertNil(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )
    }

    func testRelinkUserChangeAndSessionRotationInvalidatePreviousRequests() {
        let (relinkService, _) = makeService()
        let relinkScope = relinkService.beginBankSyncRefreshRequest()
        relinkService.invalidatePrimaryRequestsForLinkedBankChange()
        XCTAssertNil(
            applyAccounts(
                id: "old-link-account",
                balance: 100,
                scope: relinkScope,
                to: relinkService
            )
        )

        let userCredentials = Credentials()
        let (userService, _) = makeService(credentials: userCredentials)
        let userScope = userService.beginBankSyncRefreshRequest()
        userCredentials.userID = "user-b"
        userCredentials.sessionToken = "session-b"
        XCTAssertNil(
            applyAccounts(
                id: "user-a-account",
                balance: 100,
                scope: userScope,
                to: userService
            )
        )

        let sessionCredentials = Credentials()
        let (sessionService, _) = makeService(credentials: sessionCredentials)
        let sessionScope = sessionService.beginBankSyncRefreshRequest()
        sessionCredentials.sessionToken = "session-rotated"
        XCTAssertNil(
            applyTransactions(
                id: "old-session-transaction",
                scope: sessionScope,
                to: sessionService
            )
        )
    }

    func testAccountsAndTransactionsFromSameRefreshScopeBothApply() {
        let (service, _) = makeService()
        let sharedScope = service.beginBankSyncRefreshRequest()

        XCTAssertEqual(
            applyAccounts(
                id: "shared-account",
                balance: 1_100,
                scope: sharedScope,
                to: service
            ),
            .success
        )
        XCTAssertEqual(
            applyTransactions(
                id: "shared-transaction",
                scope: sharedScope,
                to: service
            ),
            .success
        )

        XCTAssertEqual(service.accounts.map(\.account_id), ["shared-account"])
        XCTAssertEqual(service.transactions.map(\.transaction_id), ["shared-transaction"])
    }

    func testPartialAccountRefreshPreservesSameOwnerCacheAndFullSuccessTimestamp() throws {
        let (service, _) = makeService()
        let fullScope = service.beginBankSyncRefreshRequest()
        XCTAssertEqual(
            applyAccounts(
                id: "cached-account",
                balance: 900,
                scope: fullScope,
                to: service
            ),
            .success
        )
        let fullSnapshot = try XCTUnwrap(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )
        let fullRefreshDate = try XCTUnwrap(fullSnapshot.lastSuccessfulRefresh)

        let partialScope = service.beginBankSyncRefreshRequest()
        XCTAssertEqual(
            applyAccounts(
                id: "partial-account",
                balance: 600,
                partialFailure: true,
                scope: partialScope,
                to: service
            ),
            .partialSuccess
        )

        XCTAssertEqual(
            Set(service.accounts.map(\.account_id)),
            Set(["cached-account", "partial-account"])
        )
        let partialSnapshot = try XCTUnwrap(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )
        XCTAssertEqual(
            Set(partialSnapshot.accounts.map(\.account_id)),
            Set(["cached-account", "partial-account"])
        )
        XCTAssertEqual(partialSnapshot.lastSuccessfulRefresh, fullRefreshDate)
    }

    func testRejectedResultsLeaveDataPersistenceMessagesLoadingAndAutomationUnchanged() throws {
        let (service, _) = makeService()
        let acceptedScope = service.beginBankSyncRefreshRequest()
        _ = applyAccounts(
            id: "accepted-account",
            balance: 1_300,
            scope: acceptedScope,
            to: service
        )
        _ = applyTransactions(
            id: "accepted-transaction",
            scope: acceptedScope,
            to: service
        )
        service.accountRefreshMessage = "Current message"
        let rejectedScope = service.beginBankSyncRefreshRequest()
        _ = service.beginBankSyncRefreshRequest()

        let accountSnapshotBefore = try XCTUnwrap(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )
        let transactionSnapshotBefore = PlaidLocalCache.loadTransactionSnapshot(
            defaults: cacheDefaults
        )
        let refreshStateBefore = service.bankSyncRefreshState
        let loadingBefore = service.isRefreshingPlaidData
        let automationBefore = service.transactionAutomationIsEligible
        let callCountBefore = service.plaidCallsThisSession

        _ = applyAccounts(
            id: "rejected-account",
            balance: 50,
            scope: rejectedScope,
            to: service
        )
        _ = applyTransactions(
            id: "rejected-transaction",
            scope: rejectedScope,
            to: service
        )
        var failureOutcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: rejectedScope,
            data: nil,
            response: nil,
            error: URLError(.timedOut),
            reason: .debugTool,
            completion: { failureOutcome = $0 }
        )

        XCTAssertNil(failureOutcome)
        XCTAssertEqual(service.accounts.map(\.account_id), ["accepted-account"])
        XCTAssertEqual(service.transactions.map(\.transaction_id), ["accepted-transaction"])
        XCTAssertEqual(service.accountRefreshMessage, "Current message")
        XCTAssertEqual(service.bankSyncRefreshState, refreshStateBefore)
        XCTAssertEqual(service.isRefreshingPlaidData, loadingBefore)
        XCTAssertEqual(service.transactionAutomationIsEligible, automationBefore)
        XCTAssertEqual(service.plaidCallsThisSession, callCountBefore)

        let accountSnapshotAfter = try XCTUnwrap(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )
        let transactionSnapshotAfter = PlaidLocalCache.loadTransactionSnapshot(
            defaults: cacheDefaults
        )
        XCTAssertEqual(
            accountSnapshotAfter.accounts.map(\.account_id),
            accountSnapshotBefore.accounts.map(\.account_id)
        )
        XCTAssertEqual(
            accountSnapshotAfter.lastSuccessfulRefresh,
            accountSnapshotBefore.lastSuccessfulRefresh
        )
        XCTAssertEqual(
            transactionSnapshotAfter.transactions.map(\.transaction_id),
            transactionSnapshotBefore.transactions.map(\.transaction_id)
        )
        XCTAssertEqual(
            transactionSnapshotAfter.lastSuccessfulRefresh,
            transactionSnapshotBefore.lastSuccessfulRefresh
        )
    }

    private func makeService(
        credentials providedCredentials: Credentials? = nil
    ) -> (PlaidService, Credentials) {
        let credentials = providedCredentials ?? Credentials()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledBankURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = PlaidService(
            sessionTokenProvider: { credentials.sessionToken },
            authenticatedUserIDProvider: { credentials.userID },
            urlSession: session,
            bankCacheDefaults: cacheDefaults
        )
        return (service, credentials)
    }

    @discardableResult
    private func applyAccounts(
        id: String,
        balance: Double,
        partialFailure: Bool = false,
        scope: BankSyncRefreshRequestScope,
        to service: PlaidService
    ) -> BankSyncFetchOutcome? {
        var outcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: scope,
            data: accountsData(
                id: id,
                balance: balance,
                partialFailure: partialFailure
            ),
            response: httpResponse(path: "/api/accounts", statusCode: 200),
            error: nil,
            reason: .debugTool,
            completion: { outcome = $0 }
        )
        return outcome
    }

    @discardableResult
    private func applyTransactions(
        id: String,
        scope: BankSyncRefreshRequestScope,
        to service: PlaidService
    ) -> BankSyncFetchOutcome? {
        var outcome: BankSyncFetchOutcome?
        service.handleTransactionsResponse(
            requestScope: scope,
            data: transactionsData(id: id),
            response: httpResponse(path: "/api/transactions", statusCode: 200),
            error: nil,
            reason: .debugTool,
            completion: { outcome = $0 }
        )
        return outcome
    }

    private func accountsData(
        id: String,
        balance: Double,
        partialFailure: Bool
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
                  "item_id": "item-\(id)",
                  "balances": {
                    "available": \(balance),
                    "current": \(balance)
                  }
                }
              ],
              "partial_failure": \(partialFailure),
              "refreshed_item_ids": ["item-\(id)"],
              "evaluated_item_ids": ["item-\(id)"]
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

    private func account(
        id: String,
        balance: Double
    ) -> PlaidAccount {
        PlaidAccount(
            account_id: id,
            name: "Checking",
            official_name: nil,
            type: "depository",
            subtype: "checking",
            mask: "1234",
            balances: PlaidBalance(
                available: balance,
                current: balance
            )
        )
    }
}

private final class ControlledBankURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    private static var storedRequestCount = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCount
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.storedRequestCount += 1
        Self.lock.unlock()
    }

    override func stopLoading() {}

    static func reset() {
        lock.lock()
        storedRequestCount = 0
        lock.unlock()
    }
}
