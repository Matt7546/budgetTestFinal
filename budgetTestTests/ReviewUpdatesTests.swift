import XCTest
@testable import Caldera_Money

@MainActor
final class ReviewUpdatesTests: XCTestCase {
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

    func testItemsUsePriorityAndStableDateOrdering() {
        let olderPastDue = forecast(
            name: "Rent",
            date: date(2026, 7, 1)
        )
        let newerPastDue = forecast(
            name: "Utilities",
            date: date(2026, 7, 3)
        )
        let olderCandidate = candidate(
            transactionID: "payment-old",
            postedDate: date(2026, 7, 8)
        )
        let newerCandidate = candidate(
            transactionID: "payment-new",
            postedDate: date(2026, 7, 10)
        )
        let update = PaymentPlanReviewUpdate(
            paymentPlanID: UUID(),
            paymentPlanName: "Blue Cash",
            detail: "Statement details changed.",
            relevantDate: date(2026, 7, 11)
        )

        let items = ReviewUpdateItems.make(
            pastDueExpenses: [newerPastDue, olderPastDue],
            likelyPostedCardPayments: [olderCandidate, newerCandidate],
            paymentPlanUpdates: [update],
            recurringRecommendations: [recurringRecommendation()]
        )

        XCTAssertEqual(
            items.map(\.kind),
            [
                .pastDueExpense,
                .pastDueExpense,
                .likelyPostedCardPayment,
                .likelyPostedCardPayment,
                .paymentPlanUpdate,
                .recurringExpenseRecommendation
            ]
        )
        XCTAssertEqual(
            items[0].id,
            "past-due-expense-\(olderPastDue.occurrenceID)"
        )
        XCTAssertEqual(
            items[2].id,
            "likely-card-payment-\(newerCandidate.id)"
        )
    }

    func testDuplicateSourcesProduceOneReviewRowPerStableID() {
        let paymentCandidate = candidate(
            transactionID: "payment-duplicate",
            postedDate: date(2026, 7, 10)
        )
        let update = PaymentPlanReviewUpdate(
            paymentPlanID: UUID(),
            paymentPlanName: "Blue Cash",
            detail: "Card due date changed.",
            relevantDate: date(2026, 7, 15)
        )
        let recurring = recurringRecommendation()

        let items = ReviewUpdateItems.make(
            pastDueExpenses: [],
            likelyPostedCardPayments: [paymentCandidate, paymentCandidate],
            paymentPlanUpdates: [update, update],
            recurringRecommendations: [recurring, recurring]
        )

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.id)).count, 3)
    }

    func testDashboardUsesTheHighestPriorityReviewItemAfterBankConfidence() {
        let pastDue = forecast(
            name: "Rent",
            date: date(2026, 7, 2)
        )
        let candidate = candidate(
            transactionID: "payment",
            postedDate: date(2026, 7, 10)
        )
        let items = ReviewUpdateItems.make(
            pastDueExpenses: [pastDue],
            likelyPostedCardPayments: [candidate],
            paymentPlanUpdates: [],
            recurringRecommendations: []
        )
        let highest = try! XCTUnwrap(
            ReviewUpdateItems.highestPriority(in: items)
        )

        let action = DashboardNextActionPriority.resolve(
            hasBankRefreshWarning: false,
            needsAccountScope: false,
            reviewItem: highest,
            upcomingExpenseNeedingMoney: nil,
            hasPaymentPlanNeedingMoney: false
        )
        let bankAction = DashboardNextActionPriority.resolve(
            hasBankRefreshWarning: true,
            needsAccountScope: false,
            reviewItem: highest,
            upcomingExpenseNeedingMoney: nil,
            hasPaymentPlanNeedingMoney: false
        )

        guard case .pastDueExpense(let selectedForecast) = action else {
            return XCTFail("Expected the highest review item to be past due")
        }
        XCTAssertEqual(selectedForecast.occurrenceID, pastDue.occurrenceID)

        guard case .bankSync = bankAction else {
            return XCTFail("Expected Bank Sync to outrank review items")
        }
    }

    func testReviewDestinationsMapToExistingActions() {
        let pastDue = forecast(
            name: "Rent",
            date: date(2026, 7, 2)
        )
        let candidate = candidate(
            transactionID: "payment",
            postedDate: date(2026, 7, 10)
        )
        let paymentPlanID = UUID()
        let paymentPlanUpdate = PaymentPlanReviewUpdate(
            paymentPlanID: paymentPlanID,
            paymentPlanName: "Blue Cash",
            detail: "Card due date changed.",
            relevantDate: date(2026, 7, 15)
        )
        let recurring = recurringRecommendation()

        let items = ReviewUpdateItems.make(
            pastDueExpenses: [pastDue],
            likelyPostedCardPayments: [candidate],
            paymentPlanUpdates: [paymentPlanUpdate],
            recurringRecommendations: [recurring]
        )

        XCTAssertEqual(items.count, 4)

        for item in items {
            let action = DashboardNextAction.reviewItemAction(item)

            switch (item.destination, action) {
            case (.upcomingExpense(let expected), .pastDueExpense(let actual)):
                XCTAssertEqual(actual.occurrenceID, expected.occurrenceID)
            case (.likelyPostedCardPayment(let expected), .possibleCardPayment(let actual)):
                XCTAssertEqual(actual.id, expected.id)
            case (.paymentPlanUpdate(let expected), .paymentPlanSuggestedUpdate(let actual)):
                XCTAssertEqual(actual, expected)
            case (.recurringExpenseRecommendation(let expected), .recurringExpenseRecommendation(let actual)):
                XCTAssertEqual(actual, expected)
            default:
                XCTFail("Review destination did not map to its existing action")
            }
        }
    }

    func testPaymentPlanUpdateUsesExistingRulesWithoutMutatingPlan() {
        let originalDueDate = date(2026, 7, 15)
        let originalTarget = 100.0
        let bucket = DebtPayoffBucket(
            plaidAccountID: "card-1",
            accountName: "Blue Cash",
            dueDate: originalDueDate,
            paymentTargetAmount: originalTarget,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: .statementBalance,
            targetStatementIssueDate: date(2026, 7, 1)
        )
        let card = LinkedCardPaymentDetails(
            account_id: "card-1",
            account_name: "Blue Cash",
            institution_name: nil,
            mask: nil,
            current_balance: 140,
            available_credit: nil,
            last_statement_balance: 120,
            last_statement_issue_date: "2026-07-02",
            minimum_payment_amount: 30,
            next_payment_due_date: "2026-07-15",
            last_payment_amount: nil,
            last_payment_date: nil,
            is_overdue: nil,
            last_refreshed_at: nil
        )

        let updates = PaymentPlanReviewUpdates.updates(
            paymentPlans: [bucket],
            cardPaymentDetails: [card],
            calendar: calendar
        )

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.paymentPlanID, bucket.id)
        XCTAssertEqual(bucket.paymentTargetAmount, originalTarget)
        XCTAssertEqual(bucket.dueDate, originalDueDate)
        XCTAssertEqual(
            bucket.targetStatementIssueDate,
            date(2026, 7, 1)
        )
    }

    func testUserScopedHistoryDoesNotCarryAnotherUsersDismissal() {
        let suiteName = "ReviewUpdatesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let suggestion = recurringSuggestion()
        let store = RecurringExpenseRecommendationHistoryStore(
            defaults: defaults
        )
        store.record(
            suggestion,
            status: .dismissed,
            plannerEventID: nil,
            for: "user-a"
        )

        let userBGroups = RecurringExpenseRecommendationGroups(
            suggestions: [suggestion],
            history: store.records(for: "user-b"),
            existingExpenseIDs: []
        )

        XCTAssertTrue(userBGroups.dismissed.isEmpty)
        XCTAssertEqual(userBGroups.needsReview.count, 1)
    }

    private func forecast(
        name: String,
        date: Date
    ) -> ForecastEvent {
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

    private func candidate(
        transactionID: String,
        postedDate: Date
    ) -> PaymentPlanPaymentCandidate {
        PaymentPlanPaymentCandidate(
            paymentPlanID: UUID(),
            cycleID: UUID(),
            transactionID: transactionID,
            amount: 100,
            postedDate: postedDate,
            isCorroboratedByCardDetails: false
        )
    }

    private func recurringRecommendation()
        -> RecurringExpenseRecommendationItem {
        RecurringExpenseRecommendationItem(
            suggestion: recurringSuggestion(),
            history: nil
        )
    }

    private func recurringSuggestion() -> RecurringExpenseSuggestion {
        let historyID = RecurringExpenseRecommendationIdentity.familyID(
            normalizedName: "example wireless",
            accountID: "card-1"
        )

        return RecurringExpenseSuggestion(
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
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day
            )
        )!
    }
}
