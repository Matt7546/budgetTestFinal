import Foundation
import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class CardPaymentDetailsSessionIsolationTests: ContainedNetworkTestCase {

    private var cacheDefaults: UserDefaults!
    private var cacheSuiteName: String!

    override func setUp() {
        super.setUp()
        cacheSuiteName = "CardPaymentDetailsSessionIsolationTests.\(UUID().uuidString)"
        cacheDefaults = UserDefaults(suiteName: cacheSuiteName)!
    }

    override func tearDown() {
        cacheDefaults.removePersistentDomain(forName: cacheSuiteName)
        cacheDefaults = nil
        cacheSuiteName = nil
        super.tearDown()
    }

    func testCardDetailFixtureInterceptsAuthenticatedRefresh() async throws {
        let (service, _) = makeService()
        let intercepted = expectation(description: "Exact card-detail request consumed")
        let completed = expectation(description: "Production card-detail handler completed")
        transport.expect(method: "GET", path: "/api/card-payment-details",
                         authorization: "Bearer session-a",
                         body: successData(accountID: "contained-card"), consumed: intercepted)
        service.fetchCardPaymentDetails(reason: .debugTool) { response in
            XCTAssertEqual(response?.cards.first?.account_id, "contained-card")
            completed.fulfill()
        }
        await fulfillment(of: [intercepted, completed], timeout: 3)
        XCTAssertEqual(transport.observations, [
            .init(method: "GET", path: "/api/card-payment-details", matched: true)
        ])
        transport.assertSatisfied()
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

    func testCurrentScopeSuccessfulResponseUpdatesCardPaymentDetails() throws {
        let (service, _) = makeService()

        applySuccess(
            accountID: "card-current",
            statementBalance: 420,
            to: service
        )

        let card = try XCTUnwrap(service.cardPaymentDetails.first)
        XCTAssertEqual(card.account_id, "card-current")
        XCTAssertEqual(card.last_statement_balance, 420)
        XCTAssertEqual(
            service.latestCardPaymentDetailsResponse?.cards.first?.account_id,
            "card-current"
        )
        XCTAssertEqual(service.cardPaymentDetailsRefreshState, .updated)
        XCTAssertNotNil(service.lastSuccessfulCardPaymentDetailsRefresh)
    }

    func testResponseAfterSignOutDoesNotRepopulateClearedFinancialData() throws {
        let (service, credentials) = makeService()
        let container = try makeContainer()
        let eventID = try seedPlans(in: container)
        service.configurePersistence(modelContext: container.mainContext)
        applySuccess(accountID: "seeded-before-ordinary-sign-out", to: service)
        XCTAssertEqual(service.cardPaymentDetails.count, 1)
        let staleScope = service.beginCardPaymentDetailsRequest()

        // This lifecycle regression supplies a callback directly; it declares
        // no HTTP action. The separate fixture test proves real interception.
        XCTAssertTrue(transport.observations.isEmpty)
        credentials.userID = nil
        credentials.sessionToken = nil
        // Ordinary sign-out uses the production auth-loss observer, not the
        // destructive clear path (Settings clears before dropping credentials).
        service.handleAuthenticationStateChanged(isSignedIn: false)
        service.handlePlanningOwnerScopeChanged(authenticatedUserID: nil)

        service.handleCardPaymentDetailsResponse(
            requestScope: staleScope,
            data: successData(accountID: "old-session-card"),
            response: httpResponse(statusCode: 200),
            error: nil,
            reason: .debugTool
        )

        XCTAssertTrue(service.cardPaymentDetails.isEmpty)
        XCTAssertNil(service.latestCardPaymentDetailsResponse)
        XCTAssertNil(service.lastSuccessfulCardPaymentDetailsRefresh)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<PlannerEvent>())
            .contains { $0.id == eventID })
        XCTAssertTrue(transport.observations.isEmpty)
    }

    func testDestructiveClearRequiresSavedOwnedRowsBeforeCredentialRemoval() throws {
        let credentials = Credentials()
        var savedOwners: [String?] = []
        let service = PlaidService(
            sessionTokenProvider: { credentials.sessionToken },
            authenticatedUserIDProvider: { credentials.userID },
            urlSession: transport.session,
            bankCacheDefaults: cacheDefaults,
            localFinancialDataClearDidSave: { savedOwners.append(credentials.userID) }
        )
        let container = try makeContainer()
        let eventID = try seedPlans(in: container)
        service.configurePersistence(modelContext: container.mainContext)
        applySuccess(accountID: "seeded-before-clear", to: service)
        let staleScope = service.beginCardPaymentDetailsRequest()
        XCTAssertEqual(service.cardPaymentDetails.count, 1)

        XCTAssertEqual(service.clearLocalFinancialDataForSignOut(
            authenticatedUserID: credentials.userID
        ), .cleared)
        XCTAssertEqual(savedOwners, ["user-a"])
        XCTAssertEqual(credentials.userID, "user-a")
        let freshContext = ModelContext(container)
        let events = try freshContext.fetch(FetchDescriptor<PlannerEvent>())
        XCTAssertFalse(events.contains { $0.id == eventID })
        XCTAssertEqual(events.map(\.name), ["Owner B preserved"])
        let reserves = try freshContext.fetch(FetchDescriptor<ReserveSettings>())
        XCTAssertFalse(reserves.contains { $0.ownerScopeID == PlanningOwnerScope.authenticated("user-a") })
        XCTAssertEqual(reserves.first?.balance, 125)
        XCTAssertTrue(service.cardPaymentDetails.isEmpty)
        XCTAssertNil(service.latestCardPaymentDetailsResponse)
        XCTAssertNil(service.lastSuccessfulCardPaymentDetailsRefresh)

        // Match the production order: only successful local clearing permits
        // credential removal. A late previously captured response stays stale.
        credentials.userID = nil
        credentials.sessionToken = nil
        service.handleCardPaymentDetailsResponse(
            requestScope: staleScope, data: successData(accountID: "late-cleared-card"),
            response: httpResponse(statusCode: 200), error: nil, reason: .debugTool
        )
        XCTAssertTrue(service.cardPaymentDetails.isEmpty)
        XCTAssertTrue(transport.observations.isEmpty)
    }

    func testMissingContextClearFailsAndPreservesMeaningfulCardState() throws {
        let (service, credentials) = makeService()
        applySuccess(accountID: "preserve-on-clear-failure", statementBalance: 420, to: service)
        let refresh = service.lastSuccessfulCardPaymentDetailsRefresh
        XCTAssertEqual(service.cardPaymentDetails.count, 1)
        XCTAssertEqual(service.clearLocalFinancialDataForSignOut(), .failed)
        XCTAssertEqual(credentials.userID, "user-a")
        XCTAssertEqual(credentials.sessionToken, "session-a")
        XCTAssertEqual(service.cardPaymentDetails.first?.account_id, "preserve-on-clear-failure")
        XCTAssertEqual(service.cardPaymentDetails.first?.last_statement_balance, 420)
        XCTAssertEqual(service.latestCardPaymentDetailsResponse?.cards.first?.account_id,
                       "preserve-on-clear-failure")
        XCTAssertEqual(service.lastSuccessfulCardPaymentDetailsRefresh, refresh)
        XCTAssertEqual(service.cardPaymentDetailsRefreshState, .updated)
        XCTAssertTrue(transport.observations.isEmpty)
    }

    func testResponseAfterUserAndSessionChangeDoesNotMutateNewSession() throws {
        let (service, credentials) = makeService()
        applySuccess(accountID: "card-a", to: service)
        let staleScope = service.beginCardPaymentDetailsRequest()

        credentials.userID = "user-b"
        credentials.sessionToken = "session-b"
        applySuccess(accountID: "card-b", to: service)

        service.handleCardPaymentDetailsResponse(
            requestScope: staleScope,
            data: successData(accountID: "late-card-a"),
            response: httpResponse(statusCode: 200),
            error: nil,
            reason: .debugTool
        )

        let card = try XCTUnwrap(service.cardPaymentDetails.first)
        XCTAssertEqual(card.account_id, "card-b")
        XCTAssertEqual(service.cardPaymentDetails.count, 1)
    }

    func testResponseAfterSessionTokenRotationIsDiscarded() throws {
        let (service, credentials) = makeService()
        applySuccess(accountID: "card-current", to: service)
        let staleScope = service.beginCardPaymentDetailsRequest()

        credentials.sessionToken = "session-rotated"
        service.handleCardPaymentDetailsResponse(
            requestScope: staleScope,
            data: successData(accountID: "card-from-old-token"),
            response: httpResponse(statusCode: 200),
            error: nil,
            reason: .debugTool
        )

        XCTAssertEqual(
            try XCTUnwrap(service.cardPaymentDetails.first).account_id,
            "card-current"
        )
    }

    func testResponseAfterLinkedAccountIdentityChangesIsDiscarded() throws {
        let (service, _) = makeService()
        applySuccess(accountID: "card-current", to: service)
        service.accounts = [account(id: "checking-a")]
        let staleScope = service.beginCardPaymentDetailsRequest()

        service.accounts = [account(id: "checking-b")]
        service.handleCardPaymentDetailsResponse(
            requestScope: staleScope,
            data: successData(accountID: "card-from-old-link-state"),
            response: httpResponse(statusCode: 200),
            error: nil,
            reason: .debugTool
        )

        XCTAssertEqual(
            try XCTUnwrap(service.cardPaymentDetails.first).account_id,
            "card-current"
        )
    }

    func testRateLimitPreservesExistingCardPaymentDetails() throws {
        let (service, _) = makeService()
        applySuccess(accountID: "existing-card", to: service)
        let successfulRefresh = try XCTUnwrap(
            service.lastSuccessfulCardPaymentDetailsRefresh
        )
        let scope = service.beginCardPaymentDetailsRequest()

        service.handleCardPaymentDetailsResponse(
            requestScope: scope,
            data: errorData(error: "rate_limited"),
            response: httpResponse(
                statusCode: 429,
                headers: ["Retry-After": "30"]
            ),
            error: nil,
            reason: .debugTool
        )

        XCTAssertEqual(
            try XCTUnwrap(service.cardPaymentDetails.first).account_id,
            "existing-card"
        )
        XCTAssertEqual(
            service.latestCardPaymentDetailsResponse?.cards.first?.account_id,
            "existing-card"
        )
        XCTAssertTrue(
            service.cardPaymentDetailsConsentMessage?.contains("briefly paused") == true
        )
        XCTAssertEqual(service.cardPaymentDetailsRefreshState, .rateLimited)
        XCTAssertEqual(
            service.lastSuccessfulCardPaymentDetailsRefresh,
            successfulRefresh
        )
    }

    func testAuthorizationAndUnavailableResponsesPreserveExistingDetails() throws {
        let (authorizationService, _) = makeService()
        applySuccess(accountID: "authorized-cache", to: authorizationService)
        let authorizationScope = authorizationService.beginCardPaymentDetailsRequest()

        authorizationService.handleCardPaymentDetailsResponse(
            requestScope: authorizationScope,
            data: errorData(error: "unauthorized"),
            response: httpResponse(statusCode: 401),
            error: nil,
            reason: .debugTool
        )

        XCTAssertEqual(
            try XCTUnwrap(authorizationService.cardPaymentDetails.first).account_id,
            "authorized-cache"
        )
        XCTAssertEqual(
            authorizationService.latestCardPaymentDetailsResponse?.cards.first?.account_id,
            "authorized-cache"
        )

        let (unavailableService, _) = makeService()
        applySuccess(accountID: "available-cache", to: unavailableService)
        let unavailableScope = unavailableService.beginCardPaymentDetailsRequest()

        unavailableService.handleCardPaymentDetailsResponse(
            requestScope: unavailableScope,
            data: errorData(error: "card_payment_details_unavailable"),
            response: httpResponse(statusCode: 502),
            error: nil,
            reason: .debugTool
        )

        XCTAssertEqual(
            try XCTUnwrap(unavailableService.cardPaymentDetails.first).account_id,
            "available-cache"
        )
        XCTAssertEqual(
            unavailableService.latestCardPaymentDetailsResponse?.cards.first?.account_id,
            "available-cache"
        )
    }

    func testDecodeFailurePreservesExistingDetails() throws {
        let (service, _) = makeService()
        applySuccess(accountID: "existing-card", to: service)
        let scope = service.beginCardPaymentDetailsRequest()

        service.handleCardPaymentDetailsResponse(
            requestScope: scope,
            data: Data("not-json".utf8),
            response: httpResponse(statusCode: 200),
            error: nil,
            reason: .debugTool
        )

        XCTAssertEqual(
            try XCTUnwrap(service.cardPaymentDetails.first).account_id,
            "existing-card"
        )
        XCTAssertEqual(
            service.latestCardPaymentDetailsResponse?.cards.first?.account_id,
            "existing-card"
        )
    }

    func testNetworkFailurePreservesExistingDetails() throws {
        let (service, _) = makeService()
        applySuccess(accountID: "existing-card", to: service)
        let successfulRefresh = try XCTUnwrap(
            service.lastSuccessfulCardPaymentDetailsRefresh
        )
        let scope = service.beginCardPaymentDetailsRequest()

        service.handleCardPaymentDetailsResponse(
            requestScope: scope,
            data: nil,
            response: nil,
            error: URLError(.notConnectedToInternet),
            reason: .debugTool
        )

        XCTAssertEqual(
            try XCTUnwrap(service.cardPaymentDetails.first).account_id,
            "existing-card"
        )
        XCTAssertEqual(
            service.latestCardPaymentDetailsResponse?.cards.first?.account_id,
            "existing-card"
        )
        XCTAssertEqual(
            service.cardPaymentDetailsRefreshState,
            .showingEarlierData
        )
        XCTAssertEqual(
            service.lastSuccessfulCardPaymentDetailsRefresh,
            successfulRefresh
        )
    }

    func testFailedCardPaymentDetailsRefreshDoesNotMutatePlanCycleOrSetAside() throws {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self,
            IncomeSchedule.self,
            TransactionMatchedExpenseResolution.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            ]
        )
        let context = ModelContext(container)
        let plan = DebtPayoffBucket(
            plaidAccountID: "refreshed-card",
            accountName: "Blue Cash",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            paymentTargetAmount: 275,
            protectedAmount: 125,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: .statementBalance
        )
        let cycle = PaymentPlanCycle(
            paymentPlanID: plan.id,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            frozenTargetAmount: 275
        )
        context.insert(plan)
        context.insert(cycle)
        context.insert(ReserveSettings(balance: 125))
        try context.save()

        let (service, _) = makeService()
        service.configurePersistence(modelContext: context)
        let reserveBeforeRefresh = service.reserveBalance

        applySuccess(
            accountID: "refreshed-card",
            statementBalance: 900,
            to: service
        )
        let successfulRefresh = try XCTUnwrap(
            service.lastSuccessfulCardPaymentDetailsRefresh
        )
        let failedScope = service.beginCardPaymentDetailsRequest()
        service.handleCardPaymentDetailsResponse(
            requestScope: failedScope,
            data: nil,
            response: nil,
            error: URLError(.notConnectedToInternet),
            reason: .debugTool
        )

        let storedPlan = try XCTUnwrap(
            context.fetch(FetchDescriptor<DebtPayoffBucket>()).first
        )
        let storedCycle = try XCTUnwrap(
            context.fetch(FetchDescriptor<PaymentPlanCycle>()).first
        )
        let storedReserve = try XCTUnwrap(
            context.fetch(FetchDescriptor<ReserveSettings>()).first
        )
        XCTAssertEqual(storedPlan.paymentTargetAmount, 275)
        XCTAssertEqual(storedPlan.protectedAmount, 125)
        XCTAssertEqual(storedCycle.status, .active)
        XCTAssertEqual(storedCycle.frozenTargetAmount, 275)
        XCTAssertEqual(storedCycle.releasedSetAsideAmount, 0)
        XCTAssertEqual(service.reserveBalance, reserveBeforeRefresh)
        XCTAssertEqual(storedReserve.balance, 125)
        XCTAssertEqual(
            service.cardPaymentDetailsRefreshState,
            .showingEarlierData
        )
        XCTAssertEqual(
            service.lastSuccessfulCardPaymentDetailsRefresh,
            successfulRefresh
        )
    }

    private func makeService() -> (PlaidService, Credentials) {
        let credentials = Credentials()
        let service = PlaidService(
            sessionTokenProvider: { credentials.sessionToken },
            authenticatedUserIDProvider: { credentials.userID },
            urlSession: transport.session,
            bankCacheDefaults: cacheDefaults
        )
        return (service, credentials)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            PlannerEvent.self, EventAllocation.self, ExpenseOccurrenceStatus.self,
            TransactionMatchedExpenseResolution.self, SavingsGoalRecord.self,
            ReserveSettings.self, DebtPayoffBucket.self, PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self, IncomeSchedule.self,
            PlanningOwnershipMigrationState.self
        ])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
    }

    private func seedPlans(in container: ModelContainer) throws -> UUID {
        let ownerA = PlanningOwnerScope.authenticated("user-a")!
        let ownerB = PlanningOwnerScope.authenticated("user-b")!
        let event = PlannerEvent(ownerScopeID: ownerA, name: "Owner A preserved on sign-out",
                                 amount: 300, date: Date(), type: .expense)
        let context = container.mainContext
        context.insert(event)
        context.insert(PlannerEvent(ownerScopeID: ownerB, name: "Owner B preserved",
                                    amount: 90, date: Date(), type: .expense))
        context.insert(ReserveSettings(ownerScopeID: ownerA, balance: 500))
        context.insert(ReserveSettings(ownerScopeID: ownerB, balance: 125))
        try context.save()
        return event.id
    }

    private func applySuccess(
        accountID: String,
        statementBalance: Double = 250,
        to service: PlaidService
    ) {
        let scope = service.beginCardPaymentDetailsRequest()
        service.handleCardPaymentDetailsResponse(
            requestScope: scope,
            data: successData(
                accountID: accountID,
                statementBalance: statementBalance
            ),
            response: httpResponse(statusCode: 200),
            error: nil,
            reason: .debugTool
        )
    }

    private func successData(
        accountID: String,
        statementBalance: Double = 250
    ) -> Data {
        Data(
            """
            {
              "enabled": true,
              "cards": [
                {
                  "account_id": "\(accountID)",
                  "last_statement_balance": \(statementBalance),
                  "next_payment_due_date": "2026-09-15"
                }
              ]
            }
            """.utf8
        )
    }

    private func errorData(error: String) -> Data {
        Data(
            """
            {
              "cards": [],
              "error": "\(error)",
              "retry_after_seconds": 30
            }
            """.utf8
        )
    }

    private func httpResponse(
        statusCode: Int,
        headers: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/api/card-payment-details")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    private func account(id: String) -> PlaidAccount {
        PlaidAccount(
            account_id: id,
            name: "Checking",
            official_name: nil,
            type: "depository",
            subtype: "checking",
            mask: nil,
            balances: PlaidBalance(
                available: 1_000,
                current: 1_000
            )
        )
    }
}
