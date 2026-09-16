import Foundation
import XCTest
@testable import Caldera_Money

@MainActor
final class BankSyncItemRecoveryTests: XCTestCase {

    private final class Credentials {
        var userID = "user-a"
        var sessionToken = "session-a"
    }

    private var cacheDefaults: UserDefaults!
    private var cacheSuiteName: String!

    override func setUp() {
        super.setUp()
        cacheSuiteName = "BankSyncItemRecoveryTests.\(UUID().uuidString)"
        cacheDefaults = UserDefaults(suiteName: cacheSuiteName)
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        ItemRecoveryURLProtocol.reset()
    }

    override func tearDown() {
        ItemRecoveryURLProtocol.reset()
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        cacheDefaults = nil
        cacheSuiteName = nil
        super.tearDown()
    }

    func testAccountsResponseDecodesExactReconnectItemIdentity() throws {
        let response = try JSONDecoder().decode(
            AccountsResponse.self,
            from: partialAccountsData(
                accounts: [accountJSON(id: "chase-checking", itemID: "item-chase")],
                failedItemID: "item-amex",
                institutionID: "ins-amex",
                institutionName: "Amex",
                category: "reconnectRequired",
                refreshedItemIDs: ["item-chase"],
                evaluatedItemIDs: ["item-chase", "item-amex"]
            )
        )

        XCTAssertEqual(response.accounts.map(\.account_id), ["chase-checking"])
        XCTAssertEqual(response.partial_failure, true)
        XCTAssertEqual(response.itemOutcomes.count, 1)
        XCTAssertEqual(response.itemOutcomes.first?.itemID, "item-amex")
        XCTAssertEqual(response.itemOutcomes.first?.institutionID, "ins-amex")
        XCTAssertEqual(response.itemOutcomes.first?.institutionName, "Amex")
        XCTAssertEqual(
            response.itemOutcomes.first?.recoveryCategory,
            .reconnectRequired
        )
        XCTAssertEqual(response.refreshedItemIDs, ["item-chase"])
        XCTAssertEqual(response.evaluatedItemIDs, ["item-amex", "item-chase"])
    }

    func testUnknownBackendRecoveryCategoryFallsBackCautiously() throws {
        let response = try JSONDecoder().decode(
            AccountsResponse.self,
            from: partialAccountsData(
                accounts: [],
                failedItemID: "item-new",
                institutionID: "ins-new",
                institutionName: "New Bank",
                category: "futureRecoveryCategory"
            )
        )

        XCTAssertEqual(
            response.itemOutcomes.first?.recoveryCategory,
            .unknownFailure
        )
    }

    func testPartialItemFailureRetainsSameOwnerCacheAndSuccessfulTimestamp() async throws {
        let previousRefresh = Date(timeIntervalSince1970: 1_830_000_000)
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: [
                    account(
                        id: "chase-checking",
                        itemID: "item-chase",
                        institutionName: "Chase",
                        current: 500
                    ),
                    account(
                        id: "amex-savings",
                        itemID: "item-amex",
                        institutionName: "Amex",
                        current: 900
                    )
                ],
                lastSuccessfulRefresh: previousRefresh,
                ownerUserID: "user-a",
                defaults: cacheDefaults
            )
        )
        ItemRecoveryURLProtocol.accountsData = partialAccountsData(
            accounts: [
                accountJSON(
                    id: "chase-checking",
                    itemID: "item-chase",
                    institutionName: "Chase",
                    current: 650
                )
            ],
            failedItemID: "item-amex",
            institutionID: "ins-amex",
            institutionName: "Amex",
            category: "reconnectRequired",
            refreshedItemIDs: ["item-chase"],
            evaluatedItemIDs: ["item-chase", "item-amex"]
        )
        let (service, _) = makeService()
        service.accounts = [
            account(
                id: "chase-checking",
                itemID: "item-chase",
                institutionName: "Chase",
                current: 500
            ),
            account(
                id: "amex-savings",
                itemID: "item-amex",
                institutionName: "Amex",
                current: 900
            )
        ]

        let result = await accountResult(
            service: service,
            data: ItemRecoveryURLProtocol.accountsData,
            response: httpResponse(
                path: "/api/accounts",
                statusCode: 200
            )
        )
        let state = resolvedState(
            from: result,
            previousState: refreshState(
                hasUsableBalances: true,
                lastSuccessfulBalanceRefresh: previousRefresh
            ),
            hasUsableBalances: true
        )

        XCTAssertEqual(result.outcome, .partialSuccess)
        XCTAssertEqual(state.lastSuccessfulBalanceRefresh, previousRefresh)
        XCTAssertEqual(state.balances, .partiallyUpdated)
        XCTAssertEqual(state.itemOutcomes.first?.itemID, "item-amex")
        XCTAssertEqual(
            state.itemOutcomes.first?.recoveryCategory,
            .reconnectRequired
        )
        XCTAssertEqual(
            service.accounts.first { $0.account_id == "chase-checking" }?
                .balances.current,
            650
        )
        XCTAssertEqual(
            service.accounts.first { $0.account_id == "amex-savings" }?
                .balances.current,
            900
        )

        let persisted = try XCTUnwrap(
            PlaidLocalCache.loadAccountSnapshot(
                for: "user-a",
                defaults: cacheDefaults
            )
        )
        XCTAssertEqual(persisted.lastSuccessfulRefresh, previousRefresh)
        XCTAssertEqual(
            persisted.accounts.first { $0.account_id == "amex-savings" }?
                .balances.current,
            900
        )
    }

    func testFailedItemWithoutCacheSurfacesIdentityWithoutInventingBalance() async {
        ItemRecoveryURLProtocol.accountsData = partialAccountsData(
            accounts: [],
            failedItemID: "item-amex",
            institutionID: "ins-amex",
            institutionName: "Amex",
            category: "reconnectRequired"
        )
        let (service, _) = makeService()

        let result = await accountResult(
            service: service,
            data: ItemRecoveryURLProtocol.accountsData,
            response: httpResponse(
                path: "/api/accounts",
                statusCode: 200
            )
        )
        let state = resolvedState(
            from: result,
            previousState: refreshState(hasUsableBalances: false),
            hasUsableBalances: false
        )

        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertTrue(service.financialSummaryAccounts.isEmpty)
        XCTAssertEqual(result.outcome, .failure)
        XCTAssertEqual(state.phase, .unavailable)
        XCTAssertNil(state.lastSuccessfulBalanceRefresh)
        XCTAssertEqual(state.itemOutcomes.first?.itemID, "item-amex")
        XCTAssertEqual(state.hasUsableBalances, false)
    }

    func testAllFailedItemsWithCacheShowEarlierBalancesInServiceFlow() async {
        let previousRefresh = Date(timeIntervalSince1970: 1_830_000_000)
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: [
                    account(
                        id: "amex-savings",
                        itemID: "item-amex",
                        institutionName: "Amex",
                        current: 900
                    )
                ],
                lastSuccessfulRefresh: previousRefresh,
                ownerUserID: "user-a",
                defaults: cacheDefaults
            )
        )
        ItemRecoveryURLProtocol.accountsData = partialAccountsData(
            accounts: [],
            failedItemID: "item-amex",
            institutionID: "ins-amex",
            institutionName: "Amex",
            category: "reconnectRequired",
            evaluatedItemIDs: ["item-amex"]
        )
        let (service, _) = makeService()
        service.accounts = [
            account(
                id: "amex-savings",
                itemID: "item-amex",
                institutionName: "Amex",
                current: 900
            )
        ]

        let result = await accountResult(
            service: service,
            data: ItemRecoveryURLProtocol.accountsData,
            response: httpResponse(
                path: "/api/accounts",
                statusCode: 200
            )
        )
        let state = resolvedState(
            from: result,
            previousState: refreshState(
                hasUsableBalances: true,
                lastSuccessfulBalanceRefresh: previousRefresh
            ),
            hasUsableBalances: true
        )

        XCTAssertEqual(service.accounts.map(\.account_id), ["amex-savings"])
        XCTAssertEqual(result.outcome, .failure)
        XCTAssertEqual(state.lastSuccessfulBalanceRefresh, previousRefresh)
        XCTAssertEqual(state.statusTitle, "Couldn’t update your banks")
        XCTAssertEqual(state.statusMessage, "Showing your earlier balances.")
    }

    func testReconnectAttentionSurvivesSubsequentTimedOutServiceRefresh() async {
        ItemRecoveryURLProtocol.accountsData = partialAccountsData(
            accounts: [],
            failedItemID: "item-amex",
            institutionID: "ins-amex",
            institutionName: "Amex",
            category: "reconnectRequired",
            evaluatedItemIDs: ["item-amex"]
        )
        let (service, _) = makeService()

        let firstResult = await accountResult(
            service: service,
            data: ItemRecoveryURLProtocol.accountsData,
            response: httpResponse(
                path: "/api/accounts",
                statusCode: 200
            )
        )
        let firstState = resolvedState(
            from: firstResult,
            previousState: refreshState(hasUsableBalances: false),
            hasUsableBalances: false
        )
        let secondResult = await accountResult(
            service: service,
            error: URLError(.timedOut)
        )
        let secondState = resolvedState(
            from: secondResult,
            previousState: firstState,
            hasUsableBalances: false
        )

        XCTAssertEqual(
            secondState.itemOutcomes.map(\.itemID),
            ["item-amex"]
        )
        XCTAssertEqual(
            secondState.itemOutcomes.first?.recoveryCategory,
            .reconnectRequired
        )
        XCTAssertTrue(secondState.refreshedItemIDs.isEmpty)
    }

    func testRecoveryRequestBodyTargetsOnlyExactItem() async throws {
        let (service, _) = makeService()

        service.createItemRecoveryLinkToken(itemID: "item-amex")
        await waitUntil {
            ItemRecoveryURLProtocol.requestBodies(path: "/api/items/update-link-token").count == 1
        }

        let body = try XCTUnwrap(
            ItemRecoveryURLProtocol.requestBodies(
                path: "/api/items/update-link-token"
            ).first
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        XCTAssertEqual(object, ["item_id": "item-amex"])
    }

    func testRecoveryTokenRejectsDifferentItemIdentity() {
        let (service, _) = makeService()
        let scope = service.beginPlaidLinkOperation()
        let data = Data(
            """
            {
              "link_token": "token-for-chase",
              "mode": "item_recovery",
              "item_id": "item-chase"
            }
            """.utf8
        )

        let token = service.handleItemRecoveryLinkTokenResponse(
            requestScope: scope,
            expectedItemID: "item-amex",
            data: data,
            response: httpResponse(
                path: "/api/items/update-link-token",
                statusCode: 200
            ),
            error: nil
        )

        XCTAssertNil(token)
        XCTAssertFalse(service.isLinkOpen)
    }

    func testSuccessfulRecoveryUsesExistingRefreshFlow() async {
        ItemRecoveryURLProtocol.accountsData = completeAccountsData(
            accounts: [
                accountJSON(
                    id: "amex-savings",
                    itemID: "item-amex",
                    institutionName: "Amex",
                    current: 1_100
                )
            ]
        )
        let (service, _) = makeService()
        let scope = service.beginPlaidLinkOperation()

        service.finishItemRecovery(itemID: "item-amex", requestScope: scope)
        let result = await accountResult(
            service: service,
            data: ItemRecoveryURLProtocol.accountsData,
            response: httpResponse(
                path: "/api/accounts",
                statusCode: 200
            )
        )
        service.updateItemRecoveryFeedback(for: result)
        let state = resolvedState(
            from: result,
            previousState: refreshState(
                hasUsableBalances: true,
                itemOutcomes: [reconnectOutcome(itemID: "item-amex")]
            ),
            hasUsableBalances: true
        )

        XCTAssertEqual(service.accounts.map(\.account_id), ["amex-savings"])
        XCTAssertEqual(state.itemOutcomes, [])
        XCTAssertNotNil(state.lastSuccessfulBalanceRefresh)
    }

    func testStaleRecoveryCallbackAfterSessionChangeIsRejected() async {
        let credentials = Credentials()
        let (service, _) = makeService(credentials: credentials)
        let staleScope = service.beginPlaidLinkOperation()
        credentials.userID = "user-b"
        credentials.sessionToken = "session-b"

        service.finishItemRecovery(
            itemID: "item-amex",
            requestScope: staleScope
        )
        await settleCallbacks()

        XCTAssertTrue(ItemRecoveryURLProtocol.allRequests().isEmpty)
        XCTAssertTrue(service.accounts.isEmpty)
    }

    func testReconnectAttentionPersistsAfterTimeoutWithoutAuthoritativeItemEvidence() async {
        let (service, _) = makeService()
        let result = await accountResult(
            service: service,
            error: URLError(.timedOut)
        )

        XCTAssertNil(result.itemOutcomes)
        XCTAssertEqual(
            resolvedState(from: result).itemOutcomes,
            [reconnectOutcome(itemID: "item-amex")]
        )
        XCTAssertTrue(resolvedState(from: result).refreshedItemIDs.isEmpty)
    }

    func testReconnectAttentionPersistsAfterAccountRateLimit() async {
        let (service, _) = makeService()
        let result = await accountResult(
            service: service,
            data: Data(
                """
                { "error": "rate_limited", "message": "Try again shortly." }
                """.utf8
            ),
            response: httpResponse(
                path: "/api/accounts",
                statusCode: 429
            )
        )

        XCTAssertNil(result.itemOutcomes)
        XCTAssertEqual(
            result.outcome.rateLimitMessage,
            "Bank Sync is briefly paused. Please try again in a moment."
        )
        XCTAssertEqual(
            resolvedState(from: result).itemOutcomes,
            [reconnectOutcome(itemID: "item-amex")]
        )
    }

    func testReconnectAttentionPersistsAfterDecodeFailure() async {
        let (service, _) = makeService()
        let result = await accountResult(
            service: service,
            data: Data("not-json".utf8),
            response: httpResponse(
                path: "/api/accounts",
                statusCode: 200
            )
        )

        XCTAssertEqual(result.outcome, .failure)
        XCTAssertNil(result.itemOutcomes)
        XCTAssertEqual(
            resolvedState(from: result).itemOutcomes,
            [reconnectOutcome(itemID: "item-amex")]
        )
    }

    func testReconnectAttentionPersistsAfterGenericAccountHTTPFailure() async {
        let (service, _) = makeService()
        let result = await accountResult(
            service: service,
            data: Data(
                """
                { "error": "accounts_unavailable" }
                """.utf8
            ),
            response: httpResponse(
                path: "/api/accounts",
                statusCode: 502
            )
        )

        XCTAssertEqual(result.outcome, .failure)
        XCTAssertNil(result.itemOutcomes)
        XCTAssertEqual(
            resolvedState(from: result).itemOutcomes,
            [reconnectOutcome(itemID: "item-amex")]
        )
    }

    func testExactSuccessfulItemClearsOnlyItsAttention() {
        let previous = refreshState(
            hasUsableBalances: true,
            itemOutcomes: [
                reconnectOutcome(itemID: "item-amex"),
                reconnectOutcome(itemID: "item-capital-one")
            ]
        )
        let next = BankSyncRefreshReducer.resolve(
            accountOutcome: .partialSuccess,
            transactionOutcome: .disabled,
            previousState: previous,
            hasUsableBalances: true,
            hasUsableTransactions: false,
            completedAt: Date(timeIntervalSince1970: 1_900_000_000),
            itemOutcomes: [reconnectOutcome(itemID: "item-capital-one")],
            refreshedItemIDs: ["item-amex"],
            evaluatedItemIDs: ["item-amex", "item-capital-one"]
        )

        XCTAssertEqual(
            next.itemOutcomes,
            [reconnectOutcome(itemID: "item-capital-one")]
        )
        XCTAssertEqual(next.refreshedItemIDs, ["item-amex"])
    }

    func testDisconnectAndAuthenticationLifecycleClearAttention() {
        let previous = refreshState(
            hasUsableBalances: true,
            itemOutcomes: [reconnectOutcome(itemID: "item-amex")]
        )
        let disconnected = BankSyncRefreshReducer.resolve(
            accountOutcome: .notLinked,
            transactionOutcome: .disabled,
            previousState: previous,
            hasUsableBalances: false,
            hasUsableTransactions: false,
            completedAt: Date()
        )
        let changedSession = BankSyncRefreshReducer.resolve(
            accountOutcome: .authenticationRequired,
            transactionOutcome: .disabled,
            previousState: previous,
            hasUsableBalances: false,
            hasUsableTransactions: false,
            completedAt: Date()
        )

        XCTAssertEqual(disconnected.phase, .notConnected)
        XCTAssertTrue(disconnected.itemOutcomes.isEmpty)
        XCTAssertEqual(changedSession.phase, .authenticationRequired)
        XCTAssertTrue(changedSession.itemOutcomes.isEmpty)
    }

    func testSignOutClearsAttentionAndRecoveryFeedback() async {
        let (service, _) = makeService()
        service.createItemRecoveryLinkToken(itemID: "item-amex")

        service.clearLocalFinancialDataForSignOut()

        XCTAssertTrue(service.bankSyncRefreshState.itemOutcomes.isEmpty)
        XCTAssertNil(service.itemRecoveryFeedback)
        XCTAssertTrue(service.accounts.isEmpty)
    }

    func testAllItemsFailWithCacheShowsEarlierDataWithoutAdvancingTimestamp() {
        let previousDate = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = refreshState(
            hasUsableBalances: true,
            lastSuccessfulBalanceRefresh: previousDate
        )
        let next = BankSyncRefreshReducer.resolve(
            accountOutcome: .failure,
            transactionOutcome: .disabled,
            previousState: previous,
            hasUsableBalances: true,
            hasUsableTransactions: false,
            completedAt: Date(timeIntervalSince1970: 1_900_000_000),
            itemOutcomes: [reconnectOutcome(itemID: "item-amex")],
            refreshedItemIDs: [],
            evaluatedItemIDs: ["item-amex"]
        )

        XCTAssertEqual(next.phase, .showingEarlierData)
        XCTAssertEqual(next.balances, .showingEarlierData)
        XCTAssertEqual(next.statusTitle, "Couldn’t update your banks")
        XCTAssertEqual(next.statusMessage, "Showing your earlier balances.")
        XCTAssertEqual(next.lastSuccessfulBalanceRefresh, previousDate)
    }

    func testAllItemsFailWithoutCacheIsUnavailable() {
        let next = BankSyncRefreshReducer.resolve(
            accountOutcome: .failure,
            transactionOutcome: .disabled,
            previousState: refreshState(hasUsableBalances: false),
            hasUsableBalances: false,
            hasUsableTransactions: false,
            completedAt: Date(),
            itemOutcomes: [reconnectOutcome(itemID: "item-amex")],
            refreshedItemIDs: [],
            evaluatedItemIDs: ["item-amex"]
        )

        XCTAssertEqual(next.phase, .unavailable)
        XCTAssertEqual(next.balances, .unavailable)
        XCTAssertNil(next.lastSuccessfulBalanceRefresh)
    }

    func testSomeItemsSucceedAndSomeFailIsPartialWithoutAdvancingGlobalTimestamp() {
        let previousDate = Date(timeIntervalSince1970: 1_800_000_000)
        let next = BankSyncRefreshReducer.resolve(
            accountOutcome: .partialSuccess,
            transactionOutcome: .disabled,
            previousState: refreshState(
                hasUsableBalances: true,
                lastSuccessfulBalanceRefresh: previousDate
            ),
            hasUsableBalances: true,
            hasUsableTransactions: false,
            completedAt: Date(timeIntervalSince1970: 1_900_000_000),
            itemOutcomes: [reconnectOutcome(itemID: "item-amex")],
            refreshedItemIDs: ["item-chase"],
            evaluatedItemIDs: ["item-chase", "item-amex"]
        )

        XCTAssertEqual(next.phase, .partiallyUpdated)
        XCTAssertEqual(next.refreshedItemIDs, ["item-chase"])
        XCTAssertEqual(next.lastSuccessfulBalanceRefresh, previousDate)
    }

    func testAllItemsSucceedClearsAttentionAndAdvancesTimestamp() {
        let completedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let next = BankSyncRefreshReducer.resolve(
            accountOutcome: .success,
            transactionOutcome: .disabled,
            previousState: refreshState(
                hasUsableBalances: true,
                itemOutcomes: [reconnectOutcome(itemID: "item-amex")]
            ),
            hasUsableBalances: true,
            hasUsableTransactions: false,
            completedAt: completedAt,
            itemOutcomes: [],
            refreshedItemIDs: ["item-amex"],
            evaluatedItemIDs: ["item-amex"]
        )

        XCTAssertEqual(next.phase, .fullyUpdated)
        XCTAssertTrue(next.itemOutcomes.isEmpty)
        XCTAssertEqual(next.lastSuccessfulBalanceRefresh, completedAt)
    }

    func testCurrentRecoveryToken401InvalidatesAuthentication() {
        let (service, _) = makeService()
        let scope = service.beginPlaidLinkOperation()

        let token = service.handleItemRecoveryLinkTokenResponse(
            requestScope: scope,
            expectedItemID: "item-amex",
            data: Data("{ \"error\": \"unauthorized\" }".utf8),
            response: httpResponse(
                path: "/api/items/update-link-token",
                statusCode: 401
            ),
            error: nil
        )

        XCTAssertNil(token)
        XCTAssertEqual(service.bankSyncRefreshState.phase, .authenticationRequired)
        guard case .authRequired = service.connectionState else {
            return XCTFail("Expected the current 401 to require authentication.")
        }
        XCTAssertNil(service.itemRecoveryFeedback)
    }

    func testStaleRecoveryToken401CannotInvalidateNewerSession() {
        let credentials = Credentials()
        let (service, _) = makeService(credentials: credentials)
        let staleScope = service.beginPlaidLinkOperation()
        credentials.userID = "user-b"
        credentials.sessionToken = "session-b"
        _ = service.beginPlaidLinkOperation()

        let token = service.handleItemRecoveryLinkTokenResponse(
            requestScope: staleScope,
            expectedItemID: "item-amex",
            data: Data("{ \"error\": \"unauthorized\" }".utf8),
            response: httpResponse(
                path: "/api/items/update-link-token",
                statusCode: 401
            ),
            error: nil
        )

        XCTAssertNil(token)
        XCTAssertNotEqual(service.bankSyncRefreshState.phase, .authenticationRequired)
        if case .authRequired = service.connectionState {
            XCTFail("A stale 401 invalidated the newer session.")
        }
    }

    func testRecoveryOperationFeedbackCoversOpeningFailureRateLimitAndCancellation() {
        let (service, _) = makeService()
        service.createItemRecoveryLinkToken(itemID: "item-amex")
        XCTAssertEqual(
            service.itemRecoveryFeedback?.message,
            "Opening this bank connection…"
        )

        var scope = service.beginPlaidLinkOperation()
        _ = service.handleItemRecoveryLinkTokenResponse(
            requestScope: scope,
            expectedItemID: "item-amex",
            data: nil,
            response: nil,
            error: URLError(.cannotConnectToHost)
        )
        XCTAssertEqual(
            service.itemRecoveryFeedback?.message,
            "This bank connection couldn’t be opened. Try again."
        )

        scope = service.beginPlaidLinkOperation()
        _ = service.handleItemRecoveryLinkTokenResponse(
            requestScope: scope,
            expectedItemID: "item-amex",
            data: Data(
                """
                { "error": "rate_limited", "message": "Try again shortly." }
                """.utf8
            ),
            response: httpResponse(
                path: "/api/items/update-link-token",
                statusCode: 429
            ),
            error: nil
        )
        XCTAssertEqual(
            service.itemRecoveryFeedback?.message,
            "Bank Sync is briefly paused. Please try again in a moment."
        )

        scope = service.beginPlaidLinkOperation()
        service.handleItemRecoveryExit(
            itemID: "item-amex",
            requestScope: scope,
            didEncounterError: false
        )
        XCTAssertEqual(
            service.itemRecoveryFeedback?.message,
            "Reconnect was cancelled. Your saved balances are unchanged."
        )
    }

    func testCapabilitiesRateLimitAfterRecoveryTerminatesFeedbackWithoutMutatingCachedState() async throws {
        let previousRefresh = Date(timeIntervalSince1970: 1_830_000_000)
        let cachedAccounts = [
            account(
                id: "amex-savings",
                itemID: "item-amex",
                institutionName: "Amex",
                current: 900
            )
        ]
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: cachedAccounts,
                lastSuccessfulRefresh: previousRefresh,
                ownerUserID: "user-a",
                defaults: cacheDefaults
            )
        )
        ItemRecoveryURLProtocol.accountsData = partialAccountsData(
            accounts: [],
            failedItemID: "item-amex",
            institutionID: "ins-amex",
            institutionName: "Amex",
            category: "reconnectRequired",
            evaluatedItemIDs: ["item-amex"]
        )
        let (service, credentials) = makeService()

        service.refreshPlaidData(reason: .debugTool)
        await waitUntil {
            service.bankSyncRefreshState.itemOutcomes.map(\.itemID) == ["item-amex"]
        }
        let accountRequestCountBeforeRecovery = ItemRecoveryURLProtocol.requestCount(
            path: "/api/accounts"
        )

        ItemRecoveryURLProtocol.capabilitiesStatusCode = 429
        ItemRecoveryURLProtocol.capabilitiesData = Data(
            """
            { "error": "rate_limited", "message": "Try again shortly." }
            """.utf8
        )
        let scope = service.beginPlaidLinkOperation()
        service.finishItemRecovery(
            itemID: "item-amex",
            requestScope: scope
        )
        await waitUntil {
            service.bankSyncRefreshState.phase == .rateLimited &&
                service.itemRecoveryFeedback?.message !=
                    "Bank connection updated. Refreshing balances…"
        }

        XCTAssertEqual(
            service.itemRecoveryFeedback?.message,
            "Bank connection updated. Balances couldn’t refresh yet."
        )
        XCTAssertEqual(service.bankSyncRefreshState.phase, .rateLimited)
        XCTAssertEqual(
            service.bankSyncRefreshState.statusMessage,
            "Bank Sync is briefly paused. Please try again in a moment. Showing your most recent balances."
        )
        XCTAssertEqual(
            service.accounts.map(\.account_id),
            cachedAccounts.map(\.account_id)
        )
        XCTAssertEqual(
            service.accounts.map(\.balances.current),
            cachedAccounts.map(\.balances.current)
        )
        XCTAssertEqual(
            service.bankSyncRefreshState.lastSuccessfulBalanceRefresh,
            previousRefresh
        )
        XCTAssertEqual(
            service.bankSyncRefreshState.itemOutcomes.map(\.itemID),
            ["item-amex"]
        )
        XCTAssertEqual(
            ItemRecoveryURLProtocol.requestCount(path: "/api/accounts"),
            accountRequestCountBeforeRecovery
        )
        let persisted = try XCTUnwrap(
            PlaidLocalCache.loadAccountSnapshot(
                for: credentials.userID,
                defaults: cacheDefaults
            )
        )
        XCTAssertEqual(
            persisted.accounts.map(\.account_id),
            cachedAccounts.map(\.account_id)
        )
        XCTAssertEqual(
            persisted.accounts.map(\.balances.current),
            cachedAccounts.map(\.balances.current)
        )
        XCTAssertEqual(persisted.lastSuccessfulRefresh, previousRefresh)
        XCTAssertEqual(persisted.ownerUserID, credentials.userID)
        XCTAssertTrue(
            ItemRecoveryURLProtocol.allRequests().allSatisfy {
                $0.value(forHTTPHeaderField: "Authorization") ==
                    "Bearer \(credentials.sessionToken)"
            }
        )
    }

    func testRecoveryLinkExitWithoutErrorShowsCancellationAndPreservesBankState() async {
        let (service, cachedAccounts, previousRefresh) = await serviceWithReconnectAttention()
        let scope = service.beginPlaidLinkOperation()

        service.handleItemRecoveryExit(
            itemID: "item-amex",
            requestScope: scope,
            didEncounterError: false
        )

        XCTAssertEqual(
            service.itemRecoveryFeedback?.message,
            "Reconnect was cancelled. Your saved balances are unchanged."
        )
        XCTAssertEqual(
            service.accounts.map(\.account_id),
            cachedAccounts.map(\.account_id)
        )
        XCTAssertEqual(
            service.accounts.map(\.balances.current),
            cachedAccounts.map(\.balances.current)
        )
        XCTAssertEqual(
            service.bankSyncRefreshState.lastSuccessfulBalanceRefresh,
            previousRefresh
        )
        XCTAssertEqual(
            service.bankSyncRefreshState.itemOutcomes.map(\.itemID),
            ["item-amex"]
        )
    }

    func testRecoveryLinkExitWithErrorShowsSanitizedFailureAndPreservesBankState() async {
        let (service, cachedAccounts, previousRefresh) = await serviceWithReconnectAttention()
        let scope = service.beginPlaidLinkOperation()

        service.handleItemRecoveryExit(
            itemID: "item-amex",
            requestScope: scope,
            didEncounterError: true
        )

        let message = service.itemRecoveryFeedback?.message
        XCTAssertEqual(
            message,
            "Reconnect couldn’t be completed. Try again. Your saved balances are unchanged."
        )
        XCTAssertNotEqual(
            message,
            "Reconnect was cancelled. Your saved balances are unchanged."
        )
        XCTAssertFalse(message?.contains("ITEM_LOGIN_REQUIRED") == true)
        XCTAssertFalse(message?.contains("request-id") == true)
        XCTAssertEqual(
            service.accounts.map(\.account_id),
            cachedAccounts.map(\.account_id)
        )
        XCTAssertEqual(
            service.accounts.map(\.balances.current),
            cachedAccounts.map(\.balances.current)
        )
        XCTAssertEqual(
            service.bankSyncRefreshState.lastSuccessfulBalanceRefresh,
            previousRefresh
        )
        XCTAssertEqual(
            service.bankSyncRefreshState.itemOutcomes.map(\.itemID),
            ["item-amex"]
        )
    }

    func testStaleErrorExitAfterSessionRotationCannotMutateNewerSession() {
        let credentials = Credentials()
        let (service, _) = makeService(credentials: credentials)
        let staleScope = service.beginPlaidLinkOperation()
        credentials.userID = "user-b"
        credentials.sessionToken = "session-b"
        let currentScope = service.beginPlaidLinkOperation()
        service.handleItemRecoveryExit(
            itemID: "item-chase",
            requestScope: currentScope,
            didEncounterError: false
        )

        service.handleItemRecoveryExit(
            itemID: "item-amex",
            requestScope: staleScope,
            didEncounterError: true
        )

        XCTAssertEqual(service.itemRecoveryFeedback?.itemID, "item-chase")
        XCTAssertEqual(
            service.itemRecoveryFeedback?.message,
            "Reconnect was cancelled. Your saved balances are unchanged."
        )
        XCTAssertEqual(
            service.accountRefreshMessage,
            "Reconnect was cancelled. Your saved balances are unchanged."
        )
    }

    func testStaleCancellationAfterNewerLinkOperationCannotMutateNewerFeedback() {
        let (service, _) = makeService()
        let staleScope = service.beginPlaidLinkOperation()
        let currentScope = service.beginPlaidLinkOperation()
        service.handleItemRecoveryExit(
            itemID: "item-chase",
            requestScope: currentScope,
            didEncounterError: true
        )

        service.handleItemRecoveryExit(
            itemID: "item-amex",
            requestScope: staleScope,
            didEncounterError: false
        )

        XCTAssertEqual(service.itemRecoveryFeedback?.itemID, "item-chase")
        XCTAssertEqual(
            service.itemRecoveryFeedback?.message,
            "Reconnect couldn’t be completed. Try again. Your saved balances are unchanged."
        )
        XCTAssertEqual(
            service.accountRefreshMessage,
            "Reconnect couldn’t be completed. Try again. Your saved balances are unchanged."
        )
    }

    func testSuccessfulRecoveryFeedbackTransitionsAfterExactItemRefresh() async {
        ItemRecoveryURLProtocol.accountsData = completeAccountsData(
            accounts: [
                accountJSON(
                    id: "amex-savings",
                    itemID: "item-amex",
                    institutionName: "Amex",
                    current: 1_100
                )
            ],
            refreshedItemIDs: ["item-amex"],
            evaluatedItemIDs: ["item-amex"]
        )
        let (service, _) = makeService()
        let scope = service.beginPlaidLinkOperation()

        service.finishItemRecovery(itemID: "item-amex", requestScope: scope)
        let result = await accountResult(
            service: service,
            data: ItemRecoveryURLProtocol.accountsData,
            response: httpResponse(
                path: "/api/accounts",
                statusCode: 200
            )
        )
        service.updateItemRecoveryFeedback(for: result)

        XCTAssertEqual(
            service.itemRecoveryFeedback?.message,
            "Bank connection updated."
        )
    }

    func testSuccessfulLinkWithPartialPeerRefreshDoesNotStayIndefinitelyLoading() {
        let (service, _) = makeService()
        let scope = service.beginPlaidLinkOperation()

        service.finishItemRecovery(itemID: "item-amex", requestScope: scope)
        service.updateItemRecoveryFeedback(
            for: BankSyncAccountFetchResult(
                outcome: .partialSuccess,
                itemOutcomes: [
                    reconnectOutcome(itemID: "item-amex")
                ],
                refreshedItemIDs: ["item-chase"],
                evaluatedItemIDs: ["item-amex", "item-chase"]
            )
        )

        XCTAssertEqual(
            service.itemRecoveryFeedback?.message,
            "Bank connection updated. Balances couldn’t refresh yet."
        )
    }

    func testPeerSuccessCopyIsBoundedForOneHealthyAndTwoFailedItems() {
        let copy = BankSyncItemRecoveryPresentation.peerStatus(
            itemID: "item-amex",
            refreshedItemIDs: ["item-chase"]
        )

        XCTAssertEqual(copy, "Some other institutions updated successfully.")
        XCTAssertNotEqual(copy, "Other connected institutions updated successfully.")
    }

    func testAdditionalConsentDoesNotOfferUnsupportedPermissionRepair() {
        XCTAssertNil(
            BankSyncItemRecoveryPresentation.action(
                for: .additionalConsentRequired
            )
        )
        XCTAssertEqual(
            BankSyncItemRecoveryPresentation.action(
                for: .reconnectRequired
            ),
            .reconnect
        )
    }

    private func makeService(
        credentials providedCredentials: Credentials? = nil
    ) -> (PlaidService, Credentials) {
        let credentials = providedCredentials ?? Credentials()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ItemRecoveryURLProtocol.self]
        let service = PlaidService(
            sessionTokenProvider: { credentials.sessionToken },
            authenticatedUserIDProvider: { credentials.userID },
            urlSession: URLSession(configuration: configuration),
            bankCacheDefaults: cacheDefaults
        )
        return (service, credentials)
    }

    private func accountResult(
        service: PlaidService,
        data: Data? = nil,
        response: URLResponse? = nil,
        error: Error? = nil
    ) async -> BankSyncAccountFetchResult {
        let scope = service.beginBankSyncRefreshRequest()

        return await withCheckedContinuation { continuation in
            service.handleAccountsResponseResult(
                requestScope: scope,
                data: data,
                response: response,
                error: error,
                reason: .debugTool
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func resolvedState(
        from result: BankSyncAccountFetchResult,
        previousState: BankSyncRefreshState? = nil,
        hasUsableBalances: Bool = true
    ) -> BankSyncRefreshState {
        BankSyncRefreshReducer.resolve(
            accountOutcome: result.outcome,
            transactionOutcome: .disabled,
            previousState: previousState ?? refreshState(
                hasUsableBalances: true,
                itemOutcomes: [reconnectOutcome(itemID: "item-amex")]
            ),
            hasUsableBalances: hasUsableBalances,
            hasUsableTransactions: false,
            completedAt: Date(timeIntervalSince1970: 1_900_000_000),
            itemOutcomes: result.itemOutcomes,
            refreshedItemIDs: result.refreshedItemIDs,
            evaluatedItemIDs: result.evaluatedItemIDs
        )
    }

    private func serviceWithReconnectAttention() async -> (
        service: PlaidService,
        cachedAccounts: [PlaidAccount],
        previousRefresh: Date
    ) {
        let previousRefresh = Date(timeIntervalSince1970: 1_830_000_000)
        let cachedAccounts = [
            account(
                id: "amex-savings",
                itemID: "item-amex",
                institutionName: "Amex",
                current: 900
            )
        ]
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: cachedAccounts,
                lastSuccessfulRefresh: previousRefresh,
                ownerUserID: "user-a",
                defaults: cacheDefaults
            )
        )
        ItemRecoveryURLProtocol.accountsData = partialAccountsData(
            accounts: [],
            failedItemID: "item-amex",
            institutionID: "ins-amex",
            institutionName: "Amex",
            category: "reconnectRequired",
            evaluatedItemIDs: ["item-amex"]
        )
        let (service, _) = makeService()

        service.refreshPlaidData(reason: .debugTool)
        await waitUntil {
            service.bankSyncRefreshState.itemOutcomes.map(\.itemID) == ["item-amex"]
        }

        return (service, cachedAccounts, previousRefresh)
    }

    private func refreshState(
        hasUsableBalances: Bool,
        lastSuccessfulBalanceRefresh: Date? = nil,
        itemOutcomes: [BankSyncItemOutcome] = []
    ) -> BankSyncRefreshState {
        BankSyncRefreshState(
            phase: hasUsableBalances ? .showingEarlierData : .idle,
            balances: hasUsableBalances ? .showingEarlierData : .notRequested,
            transactions: .disabled,
            lastSuccessfulBalanceRefresh: lastSuccessfulBalanceRefresh,
            lastSuccessfulTransactionRefresh: nil,
            hasUsableBalances: hasUsableBalances,
            hasUsableTransactions: false,
            rateLimitMessage: nil,
            itemOutcomes: itemOutcomes
        )
    }

    private func reconnectOutcome(
        itemID: String
    ) -> BankSyncItemOutcome {
        BankSyncItemOutcome(
            error: "accounts_fetch_failed",
            itemID: itemID,
            institutionID: "ins-\(itemID)",
            institutionName: "Institution \(itemID)",
            recoveryCategory: .reconnectRequired
        )
    }

    private func account(
        id: String,
        itemID: String,
        institutionName: String,
        current: Double
    ) -> PlaidAccount {
        PlaidAccount(
            account_id: id,
            name: "Checking",
            official_name: nil,
            type: "depository",
            subtype: "checking",
            mask: "1234",
            balances: PlaidBalance(
                available: current,
                current: current
            ),
            item_id: itemID,
            institution_name: institutionName,
            institution_id: "ins-\(itemID)"
        )
    }

    private func accountJSON(
        id: String,
        itemID: String,
        institutionName: String = "Institution",
        current: Double = 100
    ) -> String {
        """
        {
          "account_id": "\(id)",
          "name": "Checking",
          "official_name": null,
          "type": "depository",
          "subtype": "checking",
          "mask": "1234",
          "balances": { "available": \(current), "current": \(current) },
          "item_id": "\(itemID)",
          "institution_name": "\(institutionName)",
          "institution_id": "ins-\(itemID)"
        }
        """
    }

    private func partialAccountsData(
        accounts: [String],
        failedItemID: String,
        institutionID: String,
        institutionName: String,
        category: String,
        refreshedItemIDs: [String] = [],
        evaluatedItemIDs: [String]? = nil
    ) -> Data {
        let evaluatedItemIDs = evaluatedItemIDs ??
            (refreshedItemIDs + [failedItemID])

        return Data(
            """
            {
              "accounts": [\(accounts.joined(separator: ","))],
              "item_errors": [
                {
                  "error": "accounts_fetch_failed",
                  "item_id": "\(failedItemID)",
                  "institution_id": "\(institutionID)",
                  "institution_name": "\(institutionName)",
                  "recovery_category": "\(category)"
                }
              ],
              "partial_failure": true,
              "refreshed_item_ids": [\(jsonStringArray(refreshedItemIDs))],
              "evaluated_item_ids": [\(jsonStringArray(evaluatedItemIDs))]
            }
            """.utf8
        )
    }

    private func completeAccountsData(
        accounts: [String],
        refreshedItemIDs: [String] = [],
        evaluatedItemIDs: [String] = []
    ) -> Data {
        Data(
            """
            {
              "accounts": [\(accounts.joined(separator: ","))],
              "item_errors": [],
              "partial_failure": false,
              "refreshed_item_ids": [\(jsonStringArray(refreshedItemIDs))],
              "evaluated_item_ids": [\(jsonStringArray(evaluatedItemIDs))]
            }
            """.utf8
        )
    }

    private func jsonStringArray(
        _ values: [String]
    ) -> String {
        values.map { "\"\($0)\"" }.joined(separator: ",")
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
        XCTFail(
            "Timed out waiting for Bank Sync Item recovery state.",
            file: file,
            line: line
        )
    }

    private func settleCallbacks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

private final class ItemRecoveryURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    private static let defaultCapabilitiesData = Data(
        """
        {
          "accounts_enabled": true,
          "transactions_enabled": false,
          "liabilities_enabled": false,
          "liabilities_link_enabled": false
        }
        """.utf8
    )
    private static var storedCapabilitiesStatusCode = 200
    private static var storedCapabilitiesData = defaultCapabilitiesData
    private static var storedAccountsData = Data()
    private static var storedAccountsErrorCode: URLError.Code?
    private static var storedRequests: [URLRequest] = []

    static var capabilitiesStatusCode: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedCapabilitiesStatusCode
        }
        set {
            lock.lock()
            storedCapabilitiesStatusCode = newValue
            lock.unlock()
        }
    }

    static var capabilitiesData: Data {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedCapabilitiesData
        }
        set {
            lock.lock()
            storedCapabilitiesData = newValue
            lock.unlock()
        }
    }

    static var accountsData: Data {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedAccountsData
        }
        set {
            lock.lock()
            storedAccountsData = newValue
            lock.unlock()
        }
    }

    static var accountsErrorCode: URLError.Code? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedAccountsErrorCode
        }
        set {
            lock.lock()
            storedAccountsErrorCode = newValue
            lock.unlock()
        }
    }

    static func reset() {
        lock.lock()
        storedCapabilitiesStatusCode = 200
        storedCapabilitiesData = defaultCapabilitiesData
        storedAccountsData = Data()
        storedAccountsErrorCode = nil
        storedRequests = []
        lock.unlock()
    }

    static func allRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    static func requestBodies(
        path: String
    ) -> [Data] {
        allRequests().compactMap { request in
            guard request.url?.path == path else {
                return nil
            }

            return request.httpBody ?? request.httpBodyStream.flatMap { stream in
                stream.open()
                defer { stream.close() }
                var data = Data()
                let bufferSize = 1_024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(
                    capacity: bufferSize
                )
                defer { buffer.deallocate() }

                while stream.hasBytesAvailable {
                    let count = stream.read(
                        buffer,
                        maxLength: bufferSize
                    )
                    guard count > 0 else {
                        break
                    }
                    data.append(buffer, count: count)
                }

                return data
            }
        }
    }

    static func requestCount(
        path: String
    ) -> Int {
        allRequests().filter { $0.url?.path == path }.count
    }

    override class func canInit(
        with request: URLRequest
    ) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.storedRequests.append(request)
        Self.lock.unlock()

        let path = request.url?.path
        let statusCode: Int
        let data: Data

        switch path {
        case "/api/capabilities":
            statusCode = Self.capabilitiesStatusCode
            data = Self.capabilitiesData

        case "/api/accounts":
            if let errorCode = Self.accountsErrorCode {
                client?.urlProtocol(
                    self,
                    didFailWithError: URLError(errorCode)
                )
                return
            }
            statusCode = 200
            data = Self.accountsData

        case "/api/items/update-link-token":
            statusCode = 502
            data = Data(
                """
                {
                  "error": "item_recovery_unavailable",
                  "message": "This bank connection could not be opened for recovery.",
                  "mode": "item_recovery"
                }
                """.utf8
            )

        default:
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.unsupportedURL)
            )
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
