import XCTest
@testable import Caldera_Money

@MainActor
final class ReviewUpdateSourceAssemblerTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    func testPastDueExpenseOnlyPreservesItemKindIDAndDestination() {
        let pastDue = forecast(name: "Rent", date: date(2026, 7, 2))

        let items = assemble(pastDueExpenses: [pastDue])

        XCTAssertEqual(items.map(\.kind), [.pastDueExpense])
        XCTAssertEqual(items.first?.id, "past-due-expense-\(pastDue.occurrenceID)")
        assertUpcomingExpenseDestination(items.first, matches: pastDue)
    }

    func testLikelyPostedPaymentOnlyPreservesItemKindIDAndDestination() {
        let candidate = paymentCandidate(transactionID: "payment-1")

        let items = assemble(likelyPostedCardPayments: [candidate])

        XCTAssertEqual(items.map(\.kind), [.likelyPostedCardPayment])
        XCTAssertEqual(items.first?.id, "likely-card-payment-\(candidate.id)")
        assertPaymentCandidateDestination(items.first, matches: candidate)
    }

    func testCardDetailsUpdateOnlyUsesPrefilteredPaymentPlan() {
        let plan = linkedPlan(accountID: "card-1")

        let items = assemble(
            paymentPlans: [plan],
            cardPaymentDetails: [cardDetails(accountID: "card-1", currentBalance: 120)]
        )

        XCTAssertEqual(items.map(\.kind), [.paymentPlanUpdate])
        XCTAssertEqual(items.first?.id, "payment-plan-update-\(plan.id.uuidString.lowercased())")
        assertPaymentPlanDestination(items.first, matches: plan.id)
    }

    func testRecurringRecommendationOnlyPreservesItemKindIDAndDestination() {
        let recurring = recurringRecommendation()

        let items = assemble(recurringRecommendations: [recurring])

        XCTAssertEqual(items.map(\.kind), [.recurringExpenseRecommendation])
        XCTAssertEqual(items.first?.id, "recurring-expense-\(recurring.historyID)")
        assertRecurringDestination(items.first, matches: recurring.historyID)
    }

    func testAllSourceTypesKeepPriorityAndDashboardDeepLink() {
        let pastDue = forecast(name: "Rent", date: date(2026, 7, 2))
        let candidate = paymentCandidate(transactionID: "payment-2")
        let plan = linkedPlan(accountID: "card-2")
        let recurring = recurringRecommendation()

        let items = assemble(
            pastDueExpenses: [pastDue],
            likelyPostedCardPayments: [candidate],
            paymentPlans: [plan],
            cardPaymentDetails: [cardDetails(accountID: "card-2", currentBalance: 120)],
            recurringRecommendations: [recurring]
        )

        XCTAssertEqual(
            items.map(\.kind),
            [
                .pastDueExpense,
                .likelyPostedCardPayment,
                .paymentPlanUpdate,
                .recurringExpenseRecommendation
            ]
        )

        let highest = try! XCTUnwrap(ReviewUpdateItems.highestPriority(in: items))
        guard case .pastDueExpense(let selected) =
            DashboardNextAction.reviewItemAction(highest) else {
            return XCTFail("Expected the existing past-due Dashboard action")
        }
        XCTAssertEqual(selected.occurrenceID, pastDue.occurrenceID)
    }

    func testDuplicateSourceCandidatesStillProduceOneStableItem() {
        let candidate = paymentCandidate(transactionID: "payment-duplicate")

        let items = assemble(likelyPostedCardPayments: [candidate, candidate])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, "likely-card-payment-\(candidate.id)")
    }

    func testHandledPaymentPlanCycleInputDoesNotCreatePaymentReviewItem() {
        let items = assemble(
            likelyPostedCardPayments: [],
            paymentPlans: [],
            cardPaymentDetails: []
        )

        XCTAssertTrue(items.isEmpty)
    }

    func testResolvedUpcomingExpenseInputDoesNotCreatePastDueReviewItem() {
        let items = assemble(pastDueExpenses: [])

        XCTAssertTrue(items.isEmpty)
    }

    func testLegacyPaymentPlanRemainsVisibleWhenPassedByItsConsumer() {
        let legacyPlan = linkedPlan(accountID: "legacy-card")

        let dashboardItems = assemble(
            paymentPlans: [legacyPlan],
            cardPaymentDetails: [
                cardDetails(accountID: "legacy-card", currentBalance: 120)
            ]
        )
        let planAheadItems = assemble(
            paymentPlans: [],
            cardPaymentDetails: [
                cardDetails(accountID: "legacy-card", currentBalance: 120)
            ]
        )

        XCTAssertEqual(dashboardItems.map(\.kind), [.paymentPlanUpdate])
        XCTAssertTrue(planAheadItems.isEmpty)
    }

    func testMissingOrUntrustedTransactionInputsProduceNoPaymentCandidate() {
        let items = assemble(likelyPostedCardPayments: [])

        XCTAssertTrue(items.isEmpty)
    }

    func testUserScopedRecurringInputsDoNotCarryIntoAnEmptySecondUserInput() {
        let userAItems = assemble(recurringRecommendations: [recurringRecommendation()])
        let userBItems = assemble(recurringRecommendations: [])

        XCTAssertEqual(userAItems.map(\.kind), [.recurringExpenseRecommendation])
        XCTAssertTrue(userBItems.isEmpty)
    }

    func testDashboardAndPlanAheadKeepTheirOwnPrefilteredInputs() {
        let dashboardPastDue = forecast(name: "Dashboard Rent", date: date(2026, 7, 2))
        let planAheadPastDue = forecast(name: "Plan Ahead Utilities", date: date(2026, 7, 3))

        let dashboardItems = assemble(pastDueExpenses: [dashboardPastDue])
        let planAheadItems = assemble(pastDueExpenses: [planAheadPastDue])

        XCTAssertEqual(dashboardItems.first?.title, "Dashboard Rent")
        XCTAssertEqual(planAheadItems.first?.title, "Plan Ahead Utilities")
        XCTAssertNotEqual(dashboardItems.first?.id, planAheadItems.first?.id)
    }

    private func assemble(
        pastDueExpenses: [ForecastEvent] = [],
        likelyPostedCardPayments: [PaymentPlanPaymentCandidate] = [],
        paymentPlans: [DebtPayoffBucket] = [],
        cardPaymentDetails: [LinkedCardPaymentDetails] = [],
        recurringRecommendations: [RecurringExpenseRecommendationItem] = []
    ) -> [ReviewUpdateItem] {
        ReviewUpdateSourceAssembler.make(
            .init(
                pastDueExpenses: pastDueExpenses,
                likelyPostedCardPayments: likelyPostedCardPayments,
                paymentPlans: paymentPlans,
                cardPaymentDetails: cardPaymentDetails,
                recurringRecommendations: recurringRecommendations
            ),
            calendar: calendar
        )
    }

    private func forecast(name: String, date: Date) -> ForecastEvent {
        ForecastEvent(
            event: PlannerEvent(
                name: name,
                amount: 100,
                date: date,
                type: .expense
            ),
            occurrenceDate: date
        )
    }

    private func linkedPlan(accountID: String) -> DebtPayoffBucket {
        DebtPayoffBucket(
            plaidAccountID: accountID,
            accountName: "Blue Cash",
            dueDate: date(2026, 7, 15),
            paymentTargetAmount: 100,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: .currentBalance
        )
    }

    private func cardDetails(
        accountID: String,
        currentBalance: Double
    ) -> LinkedCardPaymentDetails {
        LinkedCardPaymentDetails(
            account_id: accountID,
            account_name: "Blue Cash",
            institution_name: nil,
            mask: nil,
            current_balance: currentBalance,
            available_credit: nil,
            last_statement_balance: nil,
            last_statement_issue_date: nil,
            minimum_payment_amount: nil,
            next_payment_due_date: "2026-07-15",
            last_payment_amount: nil,
            last_payment_date: nil,
            is_overdue: nil,
            last_refreshed_at: nil
        )
    }

    private func paymentCandidate(
        transactionID: String
    ) -> PaymentPlanPaymentCandidate {
        PaymentPlanPaymentCandidate(
            paymentPlanID: UUID(),
            cycleID: UUID(),
            transactionID: transactionID,
            amount: 100,
            postedDate: date(2026, 7, 10),
            isCorroboratedByCardDetails: false
        )
    }

    private func recurringRecommendation() -> RecurringExpenseRecommendationItem {
        let historyID = RecurringExpenseRecommendationIdentity.familyID(
            normalizedName: "example wireless",
            accountID: "card-1"
        )
        let suggestion = RecurringExpenseSuggestion(
            id: RecurringExpenseRecommendationIdentity.suggestionID(
                familyID: historyID,
                amount: 82,
                dayOfMonth: 15
            ),
            historyID: historyID,
            merchantName: "Example Wireless",
            normalizedName: "example wireless",
            amount: 82,
            nextDueDate: date(2026, 7, 15),
            dayOfMonth: 15,
            occurrenceCount: 3,
            isAlreadyInPlan: false
        )

        return RecurringExpenseRecommendationItem(
            suggestion: suggestion,
            history: nil
        )
    }

    private func assertUpcomingExpenseDestination(
        _ item: ReviewUpdateItem?,
        matches forecast: ForecastEvent
    ) {
        guard case .upcomingExpense(let actual) = item?.destination else {
            return XCTFail("Expected the existing upcoming-expense destination")
        }
        XCTAssertEqual(actual.occurrenceID, forecast.occurrenceID)
    }

    private func assertPaymentCandidateDestination(
        _ item: ReviewUpdateItem?,
        matches candidate: PaymentPlanPaymentCandidate
    ) {
        guard case .likelyPostedCardPayment(let actual) = item?.destination else {
            return XCTFail("Expected the existing payment-review destination")
        }
        XCTAssertEqual(actual.id, candidate.id)
    }

    private func assertPaymentPlanDestination(
        _ item: ReviewUpdateItem?,
        matches paymentPlanID: UUID
    ) {
        guard case .paymentPlanUpdate(let actual) = item?.destination else {
            return XCTFail("Expected the existing payment-plan destination")
        }
        XCTAssertEqual(actual, paymentPlanID)
    }

    private func assertRecurringDestination(
        _ item: ReviewUpdateItem?,
        matches historyID: String
    ) {
        guard case .recurringExpenseRecommendation(let actual) = item?.destination else {
            return XCTFail("Expected the existing recurring-review destination")
        }
        XCTAssertEqual(actual, historyID)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
