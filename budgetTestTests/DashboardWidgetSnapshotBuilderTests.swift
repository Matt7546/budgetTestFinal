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

    func testUpcomingExpensesDefaultsToNext30Days() {
        let inside = makeExpense(
            name: "Inside",
            dueDate: date(daysFromNow: 29)
        )
        let outside = makeExpense(
            name: "Outside",
            dueDate: date(daysFromNow: 30)
        )
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(events: [inside, outside])
        )
        let snapshot = result.snapshot(for: .upcomingExpenses)

        XCTAssertEqual(snapshot?.timeframe, .next30Days)
        XCTAssertEqual(snapshot?.items.map(\.title), ["Inside"])
    }

    func testEachUpcomingExpensesTimeframeUsesItsCalendarDayBoundary() {
        for timeframe in DashboardWidgetTimeframe.allCases {
            let inside = makeExpense(
                name: "Inside \(timeframe.dayCount)",
                dueDate: date(daysFromNow: timeframe.dayCount - 1)
            )
            let outside = makeExpense(
                name: "Outside \(timeframe.dayCount)",
                dueDate: date(daysFromNow: timeframe.dayCount)
            )
            let result = DashboardWidgetSnapshotBuilder.build(
                from: populatedInput(
                    events: [inside, outside],
                    upcomingExpensesTimeframe: timeframe
                )
            )
            let snapshot = result.snapshot(for: .upcomingExpenses)

            XCTAssertEqual(snapshot?.timeframe, timeframe)
            XCTAssertEqual(
                snapshot?.items.map(\.title),
                ["Inside \(timeframe.dayCount)"]
            )
        }
    }

    func testNarrowUpcomingWindowRemainsAvailableWhenLaterExpensesExist() {
        let laterExpense = makeExpense(
            name: "Later",
            dueDate: date(daysFromNow: 20)
        )
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(
                events: [laterExpense],
                upcomingExpensesTimeframe: .next7Days
            )
        )
        let snapshot = result.snapshot(for: .upcomingExpenses)

        XCTAssertEqual(snapshot?.contentState, .empty)
        XCTAssertEqual(snapshot?.timeframe, .next7Days)
        XCTAssertTrue(snapshot?.items.isEmpty == true)
        XCTAssertTrue(
            result.visibleSnapshots.contains { $0.kind == .upcomingExpenses }
        )
    }

    func testUpcomingTimeframeDoesNotChangeOtherWidgetPresentation() {
        let events = [
            makeExpense(name: "Soon", dueDate: date(daysFromNow: 5)),
            makeExpense(name: "Later", dueDate: date(daysFromNow: 45))
        ]
        let goals = [
            SavingsGoal(
                name: "Vacation",
                targetAmount: 1_000,
                currentAmount: 400,
                isPinned: true
            )
        ]
        let paymentPlans = [makePaymentPlan()]
        let shortWindow = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(
                goals: goals,
                events: events,
                paymentPlans: paymentPlans,
                upcomingExpensesTimeframe: .next7Days
            )
        )
        let longWindow = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(
                goals: goals,
                events: events,
                paymentPlans: paymentPlans,
                upcomingExpensesTimeframe: .next60Days
            )
        )

        for kind in DashboardWidgetKind.allCases where kind != .upcomingExpenses {
            assertPresentationEqual(
                shortWindow.snapshot(for: kind),
                longWindow.snapshot(for: kind),
                kind: kind
            )
        }
    }

    func testUpcomingTimeframeContinuesToExcludePastDueExpenses() {
        let pastDue = makeExpense(
            name: "Past Due",
            dueDate: date(daysFromNow: -1)
        )
        let upcoming = makeExpense(
            name: "Upcoming",
            dueDate: date(daysFromNow: 2)
        )
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(
                events: [pastDue, upcoming],
                upcomingExpensesTimeframe: .next60Days
            )
        )

        XCTAssertEqual(
            result.snapshot(for: .upcomingExpenses)?.items.map(\.title),
            ["Upcoming"]
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

    func testFundingWidgetsPreserveChildTargetAndSetAsideAmounts() {
        let expense = makeExpense()
        let forecast = ForecastEvent(
            event: expense,
            occurrenceDate: expense.date
        )
        let allocation = EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: expense.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: 450
        )
        let paymentPlan = makePaymentPlan()
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(
                events: [expense],
                allocations: [allocation],
                paymentPlans: [paymentPlan],
                paymentPlanCycles: []
            )
        )

        let expenseItem = result.snapshot(for: .upcomingExpenses)?.items.first
        let paymentPlanItem = result.snapshot(for: .paymentPlans)?.items.first

        XCTAssertEqual(expenseItem?.targetAmount ?? -1, 1_200, accuracy: 0.001)
        XCTAssertEqual(expenseItem?.setAsideAmount ?? -1, 450, accuracy: 0.001)
        XCTAssertEqual(paymentPlanItem?.targetAmount ?? -1, 500, accuracy: 0.001)
        XCTAssertEqual(paymentPlanItem?.setAsideAmount ?? -1, 200, accuracy: 0.001)
    }

    func testFundingWidgetsKeepZeroTargetValuesSafe() {
        let expense = PlannerEvent(
            name: "No amount",
            amount: 0,
            date: date(2026, 8, 14),
            frequency: .once,
            type: .expense
        )
        let paymentPlan = DebtPayoffBucket(
            plaidAccountID: "card-1",
            accountName: "No target",
            dueDate: date(2026, 8, 13),
            paymentTargetAmount: 0,
            protectedAmount: 0,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: .currentBalance
        )
        let result = DashboardWidgetSnapshotBuilder.build(
            from: populatedInput(
                events: [expense],
                paymentPlans: [paymentPlan],
                paymentPlanCycles: []
            )
        )

        XCTAssertEqual(
            result.snapshot(for: .upcomingExpenses)?.items.first?.targetAmount ?? -1,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            result.snapshot(for: .paymentPlans)?.items.first?.targetAmount ?? -1,
            0,
            accuracy: 0.001
        )
    }

    private func populatedInput(
        isSignedIn: Bool = true,
        canShowBankData: Bool = true,
        linkedAccounts: [PlaidAccount]? = nil,
        bankSyncState: BankSyncRefreshState? = nil,
        goals: [SavingsGoal]? = nil,
        events: [PlannerEvent]? = nil,
        allocations: [EventAllocation]? = nil,
        paymentPlans: [DebtPayoffBucket]? = nil,
        paymentPlanCycles: [PaymentPlanCycle]? = nil,
        reviewItems: [ReviewUpdateItem]? = nil,
        upcomingExpensesTimeframe: DashboardWidgetTimeframe = .next30Days
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
            allocations: allocations ?? [],
            occurrenceStatuses: [],
            paymentPlans: paymentPlans ?? [makePaymentPlan()],
            paymentPlanCycles: paymentPlanCycles ?? [],
            reviewItems: reviewItems ?? [makeReviewItem()],
            upcomingExpensesTimeframe: upcomingExpensesTimeframe,
            now: now,
            calendar: calendar
        )
    }

    private func makeExpense(
        name: String = "Rent",
        dueDate: Date? = nil
    ) -> PlannerEvent {
        PlannerEvent(
            name: name,
            amount: 1_200,
            date: dueDate ?? date(2026, 8, 14),
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

    private func date(daysFromNow dayOffset: Int) -> Date {
        calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: now
        )!
    }

    private func assertPresentationEqual(
        _ lhs: DashboardWidgetSnapshot?,
        _ rhs: DashboardWidgetSnapshot?,
        kind: DashboardWidgetKind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs?.kind, rhs?.kind, file: file, line: line)
        XCTAssertEqual(lhs?.title, rhs?.title, file: file, line: line)
        XCTAssertEqual(lhs?.subtitle, rhs?.subtitle, file: file, line: line)
        XCTAssertEqual(lhs?.primaryValue, rhs?.primaryValue, file: file, line: line)
        XCTAssertEqual(lhs?.secondaryValue, rhs?.secondaryValue, file: file, line: line)
        XCTAssertEqual(lhs?.status, rhs?.status, file: file, line: line)
        XCTAssertEqual(lhs?.progress, rhs?.progress, file: file, line: line)
        XCTAssertEqual(lhs?.contentState, rhs?.contentState, file: file, line: line)
        XCTAssertEqual(lhs?.destination, rhs?.destination, file: file, line: line)
        XCTAssertEqual(lhs?.items.map(\.id), rhs?.items.map(\.id), file: file, line: line)
        XCTAssertEqual(lhs?.timeframe, rhs?.timeframe, file: file, line: line)
        XCTAssertNotEqual(kind, .upcomingExpenses, file: file, line: line)
    }
}
