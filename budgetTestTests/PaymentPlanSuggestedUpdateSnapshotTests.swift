import XCTest
@testable import Caldera_Money

@MainActor
final class PaymentPlanSuggestedUpdateSnapshotTests: XCTestCase {

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

    func testDueDateOnlyChangeKeepsEditorAndReviewFactsAligned() {
        assertEditorAndReviewFacts(
            plan: plan(
                choice: .statementBalance,
                target: 100,
                statementIssueDate: date(2026, 7, 1)
            ),
            card: card(
                statementBalance: 100,
                statementIssueDate: "2026-07-01",
                minimumPayment: 30,
                currentBalance: 140,
                dueDate: "2026-07-20"
            ),
            expectedFacts: [.dueDate(date(2026, 7, 20))],
            expectedReviewDetail: "The card due date changed."
        )
    }

    func testStatementTargetIgnoresCurrentBalanceDrift() {
        assertEditorAndReviewFacts(
            plan: plan(
                choice: .statementBalance,
                target: 100,
                statementIssueDate: date(2026, 7, 1)
            ),
            card: card(
                statementBalance: 100,
                statementIssueDate: "2026-07-01",
                minimumPayment: 30,
                currentBalance: 140,
                dueDate: "2026-07-15"
            ),
            expectedFacts: [],
            expectedReviewDetail: nil
        )
    }

    func testNewerStatementProducesStatementFact() {
        assertEditorAndReviewFacts(
            plan: plan(
                choice: .statementBalance,
                target: 100,
                statementIssueDate: date(2026, 7, 1)
            ),
            card: card(
                statementBalance: 120,
                statementIssueDate: "2026-07-02",
                minimumPayment: 30,
                currentBalance: 140,
                dueDate: "2026-07-15"
            ),
            expectedFacts: [
                .statementBalance(
                    amount: 120,
                    reason: .newerStatement,
                    issueDate: date(2026, 7, 2)
                )
            ],
            expectedReviewDetail: "Statement details changed."
        )
    }

    func testSameStatementCorrectionProducesFactualStatementFact() {
        let issueDate = date(2026, 7, 1)

        assertEditorAndReviewFacts(
            plan: plan(
                choice: .statementBalance,
                target: 100,
                statementIssueDate: issueDate
            ),
            card: card(
                statementBalance: 120,
                statementIssueDate: "2026-07-01",
                minimumPayment: 30,
                currentBalance: 140,
                dueDate: "2026-07-15"
            ),
            expectedFacts: [
                .statementBalance(
                    amount: 120,
                    reason: .statementAmountChanged,
                    issueDate: issueDate
                )
            ],
            expectedReviewDetail: "Statement details changed."
        )
    }

    func testMinimumPaymentTargetProducesOnlyMinimumPaymentFact() {
        assertEditorAndReviewFacts(
            plan: plan(choice: .minimumPayment, target: 30),
            card: card(
                statementBalance: 120,
                statementIssueDate: "2026-07-01",
                minimumPayment: 35,
                currentBalance: 140,
                dueDate: "2026-07-15"
            ),
            expectedFacts: [.minimumPayment(amount: 35)],
            expectedReviewDetail: "Minimum payment details changed."
        )
    }

    func testCurrentBalanceTargetProducesOnlyCurrentBalanceFact() {
        assertEditorAndReviewFacts(
            plan: plan(choice: .currentBalance, target: 100),
            card: card(
                statementBalance: 120,
                statementIssueDate: "2026-07-01",
                minimumPayment: 35,
                currentBalance: 140,
                dueDate: "2026-07-15"
            ),
            expectedFacts: [.currentBalance(amount: 140)],
            expectedReviewDetail: "Current balance details changed."
        )
    }

    func testCustomTargetIgnoresLiveAmountChanges() {
        assertEditorAndReviewFacts(
            plan: plan(choice: .customAmount, target: 100),
            card: card(
                statementBalance: 120,
                statementIssueDate: "2026-07-01",
                minimumPayment: 35,
                currentBalance: 140,
                dueDate: "2026-07-15"
            ),
            expectedFacts: [],
            expectedReviewDetail: nil
        )
    }

    func testEqualLiveAndSavedAmountsProduceNoFacts() {
        assertEditorAndReviewFacts(
            plan: plan(
                choice: .statementBalance,
                target: 100,
                statementIssueDate: date(2026, 7, 1)
            ),
            card: card(
                statementBalance: 100,
                statementIssueDate: "2026-07-01",
                minimumPayment: 30,
                currentBalance: 140,
                dueDate: "2026-07-15"
            ),
            expectedFacts: [],
            expectedReviewDetail: nil
        )
    }

    func testCombinedStatementAndDueDateChangesPreserveIndependentFacts() {
        assertEditorAndReviewFacts(
            plan: plan(
                choice: .statementBalance,
                target: 100,
                statementIssueDate: date(2026, 7, 1)
            ),
            card: card(
                statementBalance: 120,
                statementIssueDate: "2026-07-02",
                minimumPayment: 30,
                currentBalance: 140,
                dueDate: "2026-07-20"
            ),
            expectedFacts: [
                .statementBalance(
                    amount: 120,
                    reason: .newerStatement,
                    issueDate: date(2026, 7, 2)
                ),
                .dueDate(date(2026, 7, 20))
            ],
            expectedReviewDetail: "Statement details and the card due date changed."
        )
    }

    func testMissingAndNullCardPaymentDetailsProduceNoFacts() {
        let paymentPlan = plan(choice: .statementBalance, target: 100)

        let missing = PaymentPlanSuggestedUpdateSnapshot(
            paymentPlan: paymentPlan,
            cardPaymentDetails: nil,
            calendar: calendar
        )
        let nullDetails = PaymentPlanSuggestedUpdateSnapshot(
            paymentPlan: paymentPlan,
            cardPaymentDetails: card(
                statementBalance: nil,
                statementIssueDate: nil,
                minimumPayment: nil,
                currentBalance: nil,
                dueDate: nil
            ),
            calendar: calendar
        )

        XCTAssertTrue(missing.facts.isEmpty)
        XCTAssertTrue(nullDetails.facts.isEmpty)
        XCTAssertTrue(
            PaymentPlanReviewUpdates.updates(
                paymentPlans: [paymentPlan],
                cardPaymentDetails: []
            ).isEmpty
        )
    }

    func testOlderStatementProducesNoFact() {
        assertEditorAndReviewFacts(
            plan: plan(
                choice: .statementBalance,
                target: 100,
                statementIssueDate: date(2026, 7, 2)
            ),
            card: card(
                statementBalance: 120,
                statementIssueDate: "2026-07-01",
                minimumPayment: 30,
                currentBalance: 140,
                dueDate: "2026-07-15"
            ),
            expectedFacts: [],
            expectedReviewDetail: nil
        )
    }

    func testLegacyPlanWithoutProvenancePreservesAllDistinctFacts() {
        assertEditorAndReviewFacts(
            plan: plan(choice: nil, target: 100),
            card: card(
                statementBalance: 120,
                statementIssueDate: "2026-07-01",
                minimumPayment: 35,
                currentBalance: 140,
                dueDate: "2026-07-15"
            ),
            expectedFacts: [
                .statementBalance(
                    amount: 120,
                    reason: .legacyReview,
                    issueDate: date(2026, 7, 1)
                ),
                .minimumPayment(amount: 35),
                .currentBalance(amount: 140)
            ],
            expectedReviewDetail: "Statement details changed."
        )
    }

    func testEqualAmountsAreDeduplicatedInEditorAndReviewFacts() {
        assertEditorAndReviewFacts(
            plan: plan(choice: nil, target: 100),
            card: card(
                statementBalance: 120,
                statementIssueDate: "2026-07-01",
                minimumPayment: 120,
                currentBalance: 120,
                dueDate: "2026-07-15"
            ),
            expectedFacts: [
                .statementBalance(
                    amount: 120,
                    reason: .legacyReview,
                    issueDate: date(2026, 7, 1)
                )
            ],
            expectedReviewDetail: "Statement details changed."
        )
    }

    func testSharedDateParserUsesUTCAndRejectsInvalidCalendarDates() {
        let parsed = PaymentPlanStatementIssueDate.parse("2026-03-01")
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: try! XCTUnwrap(parsed)
        )

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 1)
        XCTAssertNil(PaymentPlanStatementIssueDate.parse("2026-02-30"))
        XCTAssertNil(PaymentPlanStatementIssueDate.parse("2026-03-01T12:00:00Z"))
    }

    private func assertEditorAndReviewFacts(
        plan: DebtPayoffBucket,
        card: LinkedCardPaymentDetails,
        expectedFacts: [PaymentPlanSuggestedUpdateSnapshot.Fact],
        expectedReviewDetail: String?
    ) {
        let editorSnapshot = PaymentPlanSuggestedUpdateSnapshot(
            currentPaymentTarget: plan.paymentTargetAmount,
            storedTargetChoice: plan.paymentTargetChoice,
            storedStatementIssueDate: plan.targetStatementIssueDate,
            dueDate: plan.dueDate,
            shouldDisplayDueDate: plan.shouldDisplayDueDate,
            cardPaymentDetails: card,
            calendar: calendar
        )
        let reviewSnapshot = PaymentPlanSuggestedUpdateSnapshot(
            paymentPlan: plan,
            cardPaymentDetails: card,
            calendar: calendar
        )
        let updates = PaymentPlanReviewUpdates.updates(
            paymentPlans: [plan],
            cardPaymentDetails: [card],
            calendar: calendar
        )

        XCTAssertEqual(editorSnapshot, reviewSnapshot)
        XCTAssertEqual(editorSnapshot.facts, expectedFacts)

        if let expectedReviewDetail {
            XCTAssertEqual(updates.count, 1)
            XCTAssertEqual(updates.first?.detail, expectedReviewDetail)
        } else {
            XCTAssertTrue(updates.isEmpty)
        }
    }

    private func plan(
        choice: DebtPayoffLinkedCardPaymentTargetChoice?,
        target: Double,
        statementIssueDate: Date? = nil,
        dueDate: Date? = nil
    ) -> DebtPayoffBucket {
        DebtPayoffBucket(
            plaidAccountID: "card-1",
            accountName: "Blue Cash",
            dueDate: dueDate ?? date(2026, 7, 15),
            paymentTargetAmount: target,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: choice,
            targetStatementIssueDate: statementIssueDate
        )
    }

    private func card(
        statementBalance: Double?,
        statementIssueDate: String?,
        minimumPayment: Double?,
        currentBalance: Double?,
        dueDate: String?
    ) -> LinkedCardPaymentDetails {
        LinkedCardPaymentDetails(
            account_id: "card-1",
            account_name: "Blue Cash",
            institution_name: nil,
            mask: nil,
            current_balance: currentBalance,
            available_credit: nil,
            last_statement_balance: statementBalance,
            last_statement_issue_date: statementIssueDate,
            minimum_payment_amount: minimumPayment,
            next_payment_due_date: dueDate,
            last_payment_amount: nil,
            last_payment_date: nil,
            is_overdue: nil,
            last_refreshed_at: nil
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
