import Foundation
import XCTest
@testable import Caldera_Money

@MainActor
final class BankSyncLifecycleIsolationTests: XCTestCase {

    private enum AccountTransactionResponseOrder {
        case accountsFirst
        case transactionsFirst
    }

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

    func testAccountCollisionBeforeTransactionsCannotEnableRecurringSuggestions() async throws {
        try await assertAccountCollisionBlocksSuggestions(order: .accountsFirst)
    }

    func testTransactionsBeforeAccountCollisionCannotEnableRecurringSuggestions() async throws {
        try await assertAccountCollisionBlocksSuggestions(order: .transactionsFirst)
    }

    func testMissingCachedItemProvenanceCannotEnableRecurringSuggestions() async throws {
        try await assertAccountCollisionBlocksSuggestions(
            order: .transactionsFirst,
            cachedItemID: nil
        )
    }

    func testSameItemCompleteHistoryStillProducesRecurringSuggestion() async throws {
        let (service, _) = makeService()
        await startManualTransactionsRefresh(on: service)
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/accounts",
            data: provenanceAccountsData(id: "X", itemID: "item-b", balance: 900)
        ))
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/transactions",
            data: monthlyHistoryData(accountID: "X", itemID: "item-b")
        ))
        await waitUntil {
            service.bankSyncRefreshState.phase == .fullyUpdated &&
                !service.isRefreshingPlaidData
        }

        XCTAssertEqual(service.accounts.first?.item_id, "item-b")
        XCTAssertTrue(service.transactionAutomationIsEligible)
        XCTAssertEqual(recurringSuggestions(on: service).count, 1)
    }

    func testMixedProviderReadinessBlocksServiceSuggestionsUntilFreshRefresh() async throws {
        let (service, _) = makeService()
        await startManualTransactionsRefresh(on: service)
        var incomplete = try XCTUnwrap(JSONSerialization.jsonObject(
            with: monthlyHistoryData(accountID: "X", itemID: "item-b")
        ) as? [String: Any])
        var itemEvidence = try XCTUnwrap(incomplete["item_evidence"] as? [[String: Any]])
        var loadingItem = itemEvidence[0]
        loadingItem["item_id"] = "item-c"
        loadingItem["historical_ready"] = false
        loadingItem["historical_ready_at"] = NSNull()
        itemEvidence.append(loadingItem)
        incomplete["item_evidence"] = itemEvidence
        incomplete["evaluated_item_ids"] = ["item-b", "item-c"]
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/accounts",
            data: provenanceAccountsData(id: "X", itemID: "item-b", balance: 900)
        ))
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/transactions",
            data: try JSONSerialization.data(withJSONObject: incomplete)
        ))
        await waitUntil {
            service.bankSyncRefreshState.phase == .fullyUpdated &&
                !service.isRefreshingPlaidData
        }
        XCTAssertEqual(service.transactions.count, 3)
        XCTAssertFalse(service.transactionAutomationIsEligible)
        XCTAssertTrue(recurringSuggestions(on: service).isEmpty)

        let (recoveredService, _) = makeService()
        await startManualTransactionsRefresh(on: recoveredService)
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/accounts",
            data: provenanceAccountsData(id: "X", itemID: "item-b", balance: 900)
        ))
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/transactions",
            data: monthlyHistoryData(accountID: "X", itemID: "item-b")
        ))
        await waitUntil {
            recoveredService.bankSyncRefreshState.phase == .fullyUpdated &&
                !recoveredService.isRefreshingPlaidData &&
                recoveredService.transactionAutomationIsEligible
        }
        XCTAssertEqual(recurringSuggestions(on: recoveredService).count, 1)
    }

    func testUnrelatedPartialAccountUpdateKeepsRecurringSuggestionEligible() async throws {
        let previousRefresh = Date(timeIntervalSince1970: 1_830_000_000)
        XCTAssertTrue(PlaidLocalCache.saveAccountSnapshot(
            accounts: [provenanceAccount(id: "X", itemID: "item-b", balance: 900)],
            lastSuccessfulRefresh: previousRefresh,
            ownerUserID: "user-a",
            defaults: cacheDefaults
        ))
        let (service, _) = makeService()
        await startManualTransactionsRefresh(on: service)
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/accounts",
            data: provenanceAccountsData(
                id: "Y", itemID: "item-a", balance: 100,
                failedItemID: "item-b"
            )
        ))
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/transactions",
            data: monthlyHistoryData(accountID: "Y", itemID: "item-a")
        ))
        await waitUntil {
            service.bankSyncRefreshState.phase == .partiallyUpdated &&
                !service.isRefreshingPlaidData
        }

        XCTAssertEqual(service.accounts.map(\.account_id), ["X", "Y"])
        XCTAssertEqual(service.accounts.first?.balances.current, 900)
        XCTAssertEqual(service.lastAccountsRefreshDate, previousRefresh)
        XCTAssertTrue(service.transactionAutomationIsEligible)
        XCTAssertEqual(recurringSuggestions(on: service).count, 1)
        let persisted = try XCTUnwrap(PlaidLocalCache.loadAccountSnapshot(
            for: "user-a", defaults: cacheDefaults
        ))
        XCTAssertEqual(persisted.accounts.map(\.item_id), ["item-b", "item-a"])
        XCTAssertEqual(persisted.lastSuccessfulRefresh, previousRefresh)
    }

    func testAuthoritativeAccountRecoveryRestoresRecurringEligibility() async throws {
        let previousRefresh = Date(timeIntervalSince1970: 1_830_000_000)
        XCTAssertTrue(PlaidLocalCache.saveAccountSnapshot(
            accounts: [provenanceAccount(id: "X", itemID: "item-b", balance: 900)],
            lastSuccessfulRefresh: previousRefresh,
            ownerUserID: "user-a",
            defaults: cacheDefaults
        ))
        let (service, _) = makeService()
        await startManualTransactionsRefresh(on: service)
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/accounts",
            data: provenanceAccountsData(
                id: "X", itemID: "item-a", balance: 100,
                failedItemID: "item-b"
            )
        ))
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/transactions",
            data: monthlyHistoryData(accountID: "X", itemID: "item-a")
        ))
        await waitUntil {
            service.bankSyncRefreshState.phase == .showingEarlierData &&
                !service.isRefreshingPlaidData
        }
        XCTAssertFalse(service.transactionAutomationIsEligible)
        XCTAssertTrue(recurringSuggestions(on: service).isEmpty)

        let recoveryScope = service.beginBankSyncRefreshRequest()
        var recoveryOutcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: recoveryScope,
            data: provenanceAccountsData(id: "X", itemID: "item-a", balance: 100),
            response: httpResponse(path: "/api/accounts", statusCode: 200),
            error: nil,
            reason: .debugTool,
            completion: { recoveryOutcome = $0 }
        )
        XCTAssertEqual(recoveryOutcome, .success)
        XCTAssertEqual(service.accounts.first?.item_id, "item-a")
        XCTAssertEqual(service.accounts.first?.balances.current, 100)
        XCTAssertTrue(service.transactionAutomationIsEligible)
        XCTAssertEqual(recurringSuggestions(on: service).count, 1)
    }

    private func assertAccountCollisionBlocksSuggestions(
        order: AccountTransactionResponseOrder,
        cachedItemID: String? = "item-b"
    ) async throws {
        let lastFullRefresh = Date(timeIntervalSince1970: 1_830_000_000)
        let cached = provenanceAccount(id: "X", itemID: cachedItemID, balance: 900)
        XCTAssertTrue(PlaidLocalCache.saveAccountSnapshot(
            accounts: [cached],
            lastSuccessfulRefresh: lastFullRefresh,
            ownerUserID: "user-a",
            defaults: cacheDefaults
        ))
        let (service, credentials) = makeService()
        XCTAssertEqual(service.accounts.first?.item_id, cachedItemID)
        await startManualTransactionsRefresh(on: service)

        let collidingAccounts = provenanceAccountsData(
            id: "X", itemID: "item-a", balance: 100,
            failedItemID: "item-b"
        )
        let completeHistory = monthlyHistoryData(accountID: "X", itemID: "item-a")
        switch order {
        case .accountsFirst:
            XCTAssertTrue(LifecycleBankURLProtocol.respond(
                path: "/api/accounts", data: collidingAccounts
            ))
            await waitUntil {
                service.accountRefreshMessage == "Couldn’t refresh accounts. Try again."
            }
            XCTAssertFalse(service.transactionAutomationIsEligible)
            XCTAssertTrue(recurringSuggestions(on: service).isEmpty)
            XCTAssertTrue(LifecycleBankURLProtocol.respond(
                path: "/api/transactions", data: completeHistory
            ))
        case .transactionsFirst:
            XCTAssertTrue(LifecycleBankURLProtocol.respond(
                path: "/api/transactions", data: completeHistory
            ))
            await waitUntil { service.transactions.count == 3 }
            XCTAssertFalse(service.transactionAutomationIsEligible)
            XCTAssertTrue(recurringSuggestions(on: service).isEmpty)
            XCTAssertTrue(LifecycleBankURLProtocol.respond(
                path: "/api/accounts", data: collidingAccounts
            ))
        }
        await waitUntil {
            service.bankSyncRefreshState.phase == .showingEarlierData &&
                service.bankSyncRefreshState.transactions == .updated &&
                !service.isRefreshingPlaidData
        }

        XCTAssertEqual(service.accounts.count, 1)
        XCTAssertEqual(service.accounts.first?.account_id, "X")
        XCTAssertEqual(service.accounts.first?.item_id, cachedItemID)
        XCTAssertEqual(service.accounts.first?.balances.current, 900)
        XCTAssertEqual(service.accounts.totalCashBalance, 900)
        XCTAssertEqual(service.lastAccountsRefreshDate, lastFullRefresh)
        XCTAssertEqual(service.bankSyncRefreshState.balances, .showingEarlierData)
        XCTAssertEqual(service.bankSyncRefreshState.statusMessage,
                       "Showing your earlier balances.")
        XCTAssertTrue(service.transactionSnapshotMetadata.isExplicitlyComplete(
            transactionCount: service.transactions.count
        ))
        XCTAssertEqual(service.transactions.count, 3)
        XCTAssertFalse(service.transactionAutomationIsEligible)
        XCTAssertTrue(recurringSuggestions(on: service).isEmpty)
        let persisted = try XCTUnwrap(PlaidLocalCache.loadAccountSnapshot(
            for: "user-a", defaults: cacheDefaults
        ))
        XCTAssertEqual(persisted.accounts.first?.item_id, cachedItemID)
        XCTAssertEqual(persisted.accounts.first?.balances.current, 900)
        XCTAssertEqual(persisted.lastSuccessfulRefresh, lastFullRefresh)

        let staleScope = service.beginBankSyncRefreshRequest()
        let otherOwnerScope = service.beginBankSyncRefreshRequest()
        var staleOutcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: staleScope,
            data: provenanceAccountsData(id: "X", itemID: "item-a", balance: 100),
            response: httpResponse(path: "/api/accounts", statusCode: 200),
            error: nil,
            reason: .debugTool,
            completion: { staleOutcome = $0 }
        )
        XCTAssertNil(staleOutcome)
        XCTAssertEqual(service.accounts.first?.item_id, cachedItemID)
        XCTAssertFalse(service.transactionAutomationIsEligible)

        credentials.userID = "user-b"
        credentials.sessionToken = "session-b"
        var otherOwnerOutcome: BankSyncFetchOutcome?
        service.handleAccountsResponse(
            requestScope: otherOwnerScope,
            data: provenanceAccountsData(id: "X", itemID: "item-a", balance: 100),
            response: httpResponse(path: "/api/accounts", statusCode: 200),
            error: nil,
            reason: .debugTool,
            completion: { otherOwnerOutcome = $0 }
        )
        XCTAssertNil(otherOwnerOutcome)
        XCTAssertFalse(service.transactionAutomationIsEligible)
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
                data: transactionsData(id: transactionID, accountID: accountID)
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

    private func provenanceAccount(
        id: String,
        itemID: String?,
        balance: Double
    ) -> PlaidAccount {
        PlaidAccount(
            account_id: id,
            name: "Checking",
            official_name: nil,
            type: "depository",
            subtype: "checking",
            mask: "1234",
            balances: PlaidBalance(available: balance, current: balance),
            item_id: itemID
        )
    }

    private func provenanceAccountsData(
        id: String,
        itemID: String,
        balance: Double,
        failedItemID: String? = nil
    ) -> Data {
        let failedItem = failedItemID.map { failedID in
            """
            [{"error":"accounts_fetch_failed","item_id":"\(failedID)",
              "recovery_category":"retryable"}]
            """
        } ?? "[]"
        let evaluatedItems = failedItemID.map { "\"\(itemID)\",\"\($0)\"" }
            ?? "\"\(itemID)\""
        return Data(
            """
            {
              "accounts":[{"account_id":"\(id)","name":"Checking",
                "type":"depository","subtype":"checking","mask":"1234",
                "balances":{"available":\(balance),"current":\(balance)},
                "item_id":"\(itemID)"}],
              "item_errors":\(failedItem),
              "partial_failure":\(failedItemID != nil),
              "refreshed_item_ids":["\(itemID)"],
              "evaluated_item_ids":[\(evaluatedItems)]
            }
            """.utf8
        )
    }

    private func monthlyHistoryData(accountID: String, itemID: String) -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let currentMonth = calendar.date(from: calendar.dateComponents(
            [.year, .month], from: now
        ))!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = (-2...0).map { offset in
            formatter.string(from: calendar.date(
                byAdding: .month, value: offset, to: currentMonth
            )!)
        }
        let transactions = dates.enumerated().map { index, date in
            """
            {"transaction_id":"posted-\(index)","account_id":"\(accountID)",
             "item_id":"\(itemID)","name":"Rent","amount":100,
             "date":"\(date)","pending":false}
            """
        }.joined(separator: ",")
        let windowStart = formatter.string(from: calendar.date(
            byAdding: .day, value: -120, to: now
        )!)
        let windowEnd = formatter.string(from: now)
        return Data(
            """
            {"transactions_enabled":true,"transactions":[\(transactions)],
             "window_start":"\(windowStart)","window_end":"\(windowEnd)",
             "lookback_days":120,"total_transactions":3,
             "returned_transactions":3,"complete":true,"partial_failure":false,
             "evaluated_item_ids":["\(itemID)"],
             "item_evidence":[\(verifiedItemEvidenceJSON(itemID: itemID))]}
            """.utf8
        )
    }

    private func recurringSuggestions(on service: PlaidService) -> [RecurringExpenseSuggestion] {
        RecurringExpenseSuggestionEngine.suggestions(
            transactions: service.transactions,
            existingEvents: [],
            snapshotMetadata: service.transactionSnapshotMetadata,
            automationIsEligible: service.transactionAutomationIsEligible
        )
    }

    private func startManualTransactionsRefresh(on service: PlaidService) async {
        service.refreshPlaidDataFromSettings()
        await waitForPendingRequest(path: "/api/capabilities")
        XCTAssertTrue(LifecycleBankURLProtocol.respond(
            path: "/api/capabilities",
            data: capabilitiesData(transactionsEnabled: true)
        ))
        await waitForPendingRequest(path: "/api/accounts")
        await waitForPendingRequest(path: "/api/transactions")
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
                  "item_id": "item-\(id)",
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
        id: String,
        accountID: String
    ) -> Data {
        let itemID = "item-\(accountID)"
        return Data(
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
                  "account_id": "\(accountID)",
                  "item_id": "\(itemID)"
                }
              ],
              "window_start": "2026-06-17",
              "window_end": "2026-09-15",
              "lookback_days": 90,
              "total_transactions": 1,
              "returned_transactions": 1,
              "complete": true,
              "partial_failure": false,
              "evaluated_item_ids": ["\(itemID)"],
              "item_evidence": [\(verifiedItemEvidenceJSON(itemID: itemID))]
            }
            """.utf8
        )
    }

    private func verifiedItemEvidenceJSON(itemID: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        return """
        {"item_id":"\(itemID)","historical_ready":true,
         "historical_ready_at":"\(formatter.string(from: now.addingTimeInterval(-7200)))",
         "provider_last_successful_update":"\(formatter.string(from: now.addingTimeInterval(-3600)))",
         "provider_observed_at":"\(formatter.string(from: now.addingTimeInterval(-60)))",
         "snapshot_fetched_at":"\(formatter.string(from: now.addingTimeInterval(-30)))"}
        """
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
