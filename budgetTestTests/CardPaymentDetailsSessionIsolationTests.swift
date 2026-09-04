import Foundation
import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class CardPaymentDetailsSessionIsolationTests: XCTestCase {

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
    }

    func testResponseAfterSignOutDoesNotRepopulateClearedFinancialData() {
        let (service, credentials) = makeService()
        let staleScope = service.beginCardPaymentDetailsRequest()

        credentials.userID = nil
        credentials.sessionToken = nil
        service.clearLocalFinancialDataForSignOut()

        service.handleCardPaymentDetailsResponse(
            requestScope: staleScope,
            data: successData(accountID: "old-session-card"),
            response: httpResponse(statusCode: 200),
            error: nil,
            reason: .debugTool
        )

        XCTAssertTrue(service.cardPaymentDetails.isEmpty)
        XCTAssertNil(service.latestCardPaymentDetailsResponse)
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
    }

    func testCardPaymentDetailsRefreshDoesNotMutateCycleOrSetAsideState() throws {
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
        let cycle = PaymentPlanCycle(
            paymentPlanID: UUID(),
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            frozenTargetAmount: 275
        )
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

        let storedCycle = try XCTUnwrap(
            context.fetch(FetchDescriptor<PaymentPlanCycle>()).first
        )
        let storedReserve = try XCTUnwrap(
            context.fetch(FetchDescriptor<ReserveSettings>()).first
        )
        XCTAssertEqual(storedCycle.status, .active)
        XCTAssertEqual(storedCycle.frozenTargetAmount, 275)
        XCTAssertEqual(storedCycle.releasedSetAsideAmount, 0)
        XCTAssertEqual(service.reserveBalance, reserveBeforeRefresh)
        XCTAssertEqual(storedReserve.balance, 125)
    }

    private func makeService() -> (PlaidService, Credentials) {
        let credentials = Credentials()
        let service = PlaidService(
            sessionTokenProvider: { credentials.sessionToken },
            authenticatedUserIDProvider: { credentials.userID }
        )
        return (service, credentials)
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
