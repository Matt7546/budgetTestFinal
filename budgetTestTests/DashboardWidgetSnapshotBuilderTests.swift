import XCTest
@testable import Caldera_Money

@MainActor
final class DashboardWidgetSnapshotBuilderTests: XCTestCase {

    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        now = date(2026, 8, 10)
    }

    override func tearDown() {
        now = nil
        calendar = nil
        super.tearDown()
    }

    func testPopulatedStateProducesFixedDefaultWidgetOrder() {
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput()
        )

        XCTAssertEqual(
            result.orderedSnapshots.map(\.kind),
            DashboardWidgetKind.defaultOrder
        )
        XCTAssertEqual(
            result.visibleSnapshots.map(\.kind),
            DashboardWidgetKind.defaultOrder
        )
        XCTAssertEqual(
            result.snapshot(for: .setAside)?.primaryValue,
            AppFormatters.currency(1_000)
        )
        XCTAssertEqual(
            result.snapshot(for: .reviewUpdates)?.contentState,
            .content
        )
    }

    func testSavingsGoalUsesPinnedFirstAndHidesWhenEmpty() {
        let firstGoal = SavingsGoal(
            name: "First",
            targetAmount: 1_000,
            currentAmount: 100
        )
        let pinnedGoal = SavingsGoal(
            name: "Pinned",
            targetAmount: 2_000,
            currentAmount: 500,
            isPinned: true
        )
        let populated = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(goals: [firstGoal, pinnedGoal])
        )
        let empty = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(goals: [])
        )

        guard case .savingsGoal(let goalID) =
            populated.snapshot(for: .savingsGoal)?.destination else {
            return XCTFail("Expected a Savings Goal destination")
        }

        XCTAssertEqual(goalID, pinnedGoal.id)
        XCTAssertEqual(
            populated.snapshot(for: .savingsGoal)?.subtitle,
            "Pinned"
        )
        XCTAssertEqual(
            empty.snapshot(for: .savingsGoal)?.contentState,
            .hidden
        )
        XCTAssertFalse(
            empty.visibleSnapshots.contains { $0.kind == .savingsGoal }
        )
    }

    func testNoUpcomingExpenseHidesUpcomingWidget() {
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(events: [])
        )

        XCTAssertEqual(
            result.snapshot(for: .upcomingExpenses)?.contentState,
            .hidden
        )
        XCTAssertFalse(
            result.visibleSnapshots.contains { $0.kind == .upcomingExpenses }
        )
    }

    func testNoPaymentPlansHidesPaymentPlanWidget() {
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(paymentPlans: [], paymentPlanCycles: [])
        )

        XCTAssertEqual(
            result.snapshot(for: .paymentPlans)?.contentState,
            .hidden
        )
        XCTAssertFalse(
            result.visibleSnapshots.contains { $0.kind == .paymentPlans }
        )
    }

    func testHandledOnlyPaymentPlanCyclesAreExcluded() {
        let paymentPlan = makePaymentPlan()
        let handledCycle = PaymentPlanCycle(
            paymentPlanID: paymentPlan.id,
            dueDate: paymentPlan.dueDate,
            frozenTargetAmount: paymentPlan.paymentTargetAmount,
            status: .handled,
            calendar: calendar
        )
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(
                paymentPlans: [paymentPlan],
                paymentPlanCycles: [handledCycle]
            )
        )

        XCTAssertEqual(
            result.snapshot(for: .paymentPlans)?.contentState,
            .hidden
        )
        XCTAssertTrue(
            result.snapshot(for: .paymentPlans)?.items.isEmpty == true
        )
    }

    func testLegacyPaymentPlanWithoutCyclesRemainsIncluded() {
        let legacyPlan = makePaymentPlan()
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(
                paymentPlans: [legacyPlan],
                paymentPlanCycles: []
            )
        )
        let snapshot = result.snapshot(for: .paymentPlans)

        XCTAssertEqual(snapshot?.contentState, .content)
        XCTAssertEqual(snapshot?.items.count, 1)

        guard case .paymentPlan(let bucketID, let cycleID) =
            snapshot?.items.first?.destination else {
            return XCTFail("Expected a Payment Plan destination")
        }

        XCTAssertEqual(bucketID, legacyPlan.id)
        XCTAssertNil(cycleID)
    }

    func testActivePaymentPlanPreservesBucketAndCycleIdentity() {
        let paymentPlan = makePaymentPlan()
        let activeCycle = PaymentPlanCycle(
            paymentPlanID: paymentPlan.id,
            dueDate: paymentPlan.dueDate,
            frozenTargetAmount: paymentPlan.paymentTargetAmount,
            calendar: calendar
        )
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(
                paymentPlans: [paymentPlan],
                paymentPlanCycles: [activeCycle]
            )
        )

        guard case .paymentPlan(let bucketID, let cycleID) =
            result.snapshot(for: .paymentPlans)?.items.first?.destination else {
            return XCTFail("Expected a Payment Plan destination")
        }

        XCTAssertEqual(bucketID, paymentPlan.id)
        XCTAssertEqual(cycleID, activeCycle.id)
    }

    func testSignedOutAndUnlinkedBankSyncStatesAreSafe() {
        let signedOut = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(
                isSignedIn: false,
                canShowBankData: false
            )
        )
        let unlinked = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(linkedAccounts: [])
        )

        XCTAssertEqual(
            signedOut.snapshot(for: .bankSync)?.contentState,
            .empty
        )
        XCTAssertEqual(
            signedOut.snapshot(for: .bankSync)?.primaryValue,
            "Sign in required"
        )
        XCTAssertEqual(
            unlinked.snapshot(for: .bankSync)?.contentState,
            .empty
        )
        XCTAssertEqual(
            unlinked.snapshot(for: .bankSync)?.primaryValue,
            "No linked accounts"
        )
    }

    func testCurrentAndStaleBankSyncStatesRemainDistinct() {
        let current = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(bankSyncState: currentBankSyncState())
        )
        let stale = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(bankSyncState: staleBankSyncState())
        )

        XCTAssertEqual(
            current.snapshot(for: .bankSync)?.primaryValue,
            "Up to date"
        )
        XCTAssertEqual(
            stale.snapshot(for: .bankSync)?.primaryValue,
            "Showing earlier data"
        )
        XCTAssertEqual(
            stale.snapshot(for: .bankSync)?.status,
            "Showing earlier data"
        )
    }

    func testReviewUpdatesAreHiddenWhenThereAreNoItems() {
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(reviewItems: [])
        )

        XCTAssertEqual(
            result.snapshot(for: .reviewUpdates)?.contentState,
            .hidden
        )
        XCTAssertFalse(
            result.visibleSnapshots.contains { $0.kind == .reviewUpdates }
        )
    }

    func testUpcomingSnapshotPreservesExactForecastOccurrenceIdentity() {
        let event = makeExpense()
        let expectedForecast = ForecastEvent(
            event: event,
            occurrenceDate: event.date
        )
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(events: [event])
        )
        let item = result.snapshot(for: .upcomingExpenses)?.items.first

        XCTAssertEqual(item?.id, expectedForecast.occurrenceID)

        guard case .upcomingExpense(let eventID, let occurrenceID) =
            item?.destination else {
            return XCTFail("Expected an Upcoming Expense destination")
        }

        XCTAssertEqual(eventID, event.id)
        XCTAssertEqual(occurrenceID, expectedForecast.occurrenceID)
    }

    private func populatedInput(
        isSignedIn: Bool = true,
        canShowBankData: Bool = true,
        linkedAccounts: [PlaidAccount]? = nil,
        bankSyncState: BankSyncRefreshState? = nil,
        goals: [SavingsGoal]? = nil,
        events: [PlannerEvent]? = nil,
        paymentPlans: [DebtPayoffBucket]? = nil,
        paymentPlanCycles: [PaymentPlanCycle]? = nil,
        reviewItems: [ReviewUpdateItem]? = nil
    ) -> DashboardWidgetSnapshotBuilder.Input {
        DashboardWidgetSnapshotBuilder.Input(
            financialSummary: FinancialSummary(
                cash: 5_000,
                checking: 3_000,
                savings: 2_000,
                debt: 1_000,
                netWorth: 4_000,
                savingsGoalsSetAside: 400,
                reserve: 250,
                upcomingExpensesSetAside: 150,
                debtPaymentsSetAside: 200
            ),
            isSignedIn: isSignedIn,
            canShowBankData: canShowBankData,
            linkedAccounts: linkedAccounts ?? [makeLinkedAccount()],
            bankSyncState: bankSyncState ?? currentBankSyncState(),
            accountsLastUpdatedText: "Last refreshed just now",
            savingsGoals: goals ?? [
                SavingsGoal(
                    name: "Vacation",
                    targetAmount: 1_000,
                    currentAmount: 400,
                    isPinned: true
                )
            ],
            events: events ?? [makeExpense()],
            allocations: [],
            occurrenceStatuses: [],
            paymentPlans: paymentPlans ?? [makePaymentPlan()],
            paymentPlanCycles: paymentPlanCycles ?? [],
            reviewItems: reviewItems ?? [makeReviewItem()],
            now: now,
            calendar: calendar
        )
    }

    private func makeExpense() -> PlannerEvent {
        PlannerEvent(
            name: "Rent",
            amount: 1_200,
            date: date(2026, 8, 14),
            frequency: .once,
            type: .expense
        )
    }

    private func makePaymentPlan() -> DebtPayoffBucket {
        DebtPayoffBucket(
            plaidAccountID: "card-1",
            accountName: "Amex Gold",
            dueDate: date(2026, 8, 13),
            paymentTargetAmount: 500,
            protectedAmount: 200,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: .currentBalance
        )
    }

    private func makeReviewItem() -> ReviewUpdateItem {
        ReviewUpdateItem(
            id: "review-1",
            kind: .pastDuePaymentPlan,
            title: "Review Amex Gold",
            detail: "This Payment Plan needs review.",
            relevantDate: date(2026, 8, 9),
            destination: .pastDuePaymentPlan
        )
    }

    private func makeLinkedAccount() -> PlaidAccount {
        PlaidAccount(
            account_id: "card-1",
            name: "Amex Gold",
            official_name: nil,
            type: "credit",
            subtype: "credit card",
            mask: "1234",
            balances: PlaidBalance(
                available: 1_000,
                current: 500,
                limit: 1_500
            )
        )
    }

    private func currentBankSyncState() -> BankSyncRefreshState {
        BankSyncRefreshState(
            phase: .fullyUpdated,
            balances: .updated,
            transactions: .updated,
            lastSuccessfulBalanceRefresh: now,
            lastSuccessfulTransactionRefresh: now,
            hasUsableBalances: true,
            hasUsableTransactions: true,
            rateLimitMessage: nil
        )
    }

    private func staleBankSyncState() -> BankSyncRefreshState {
        BankSyncRefreshState(
            phase: .showingEarlierData,
            balances: .showingEarlierData,
            transactions: .showingEarlierData,
            lastSuccessfulBalanceRefresh: date(2026, 8, 9),
            lastSuccessfulTransactionRefresh: date(2026, 8, 9),
            hasUsableBalances: true,
            hasUsableTransactions: true,
            rateLimitMessage: nil
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
                day: day,
                hour: 12
            )
        )!
    }
}
