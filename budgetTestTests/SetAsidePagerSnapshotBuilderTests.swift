import XCTest
@testable import Caldera_Money

@MainActor
final class SetAsidePagerSnapshotBuilderTests: XCTestCase {

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

    func testGoalsSummaryHandlesTotalsRemainingAndOverfunding() {
        let overfunded = SavingsGoal(
            name: "Rainy Day",
            targetAmount: 100,
            currentAmount: 125.50
        )
        let second = SavingsGoal(
            name: "Trip",
            targetAmount: 100,
            currentAmount: 24.50
        )

        let snapshot = build(goals: [overfunded, second]).goals

        XCTAssertEqual(snapshot.totalSaved, 150, accuracy: 0.001)
        XCTAssertEqual(snapshot.totalTarget, 200, accuracy: 0.001)
        XCTAssertEqual(snapshot.remainingAmount, 50, accuracy: 0.001)
        XCTAssertEqual(snapshot.progress, 0.75, accuracy: 0.001)
        XCTAssertEqual(snapshot.activeCount, 2)
        XCTAssertEqual(snapshot.rows[0].remainingAmount, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.rows[0].progress, 1, accuracy: 0.001)
    }

    func testGoalsEmptyStateAndRoutesRemainAvailable() {
        let snapshot = build().goals

        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertTrue(snapshot.rows.isEmpty)
        XCTAssertEqual(snapshot.progress, 0)
        XCTAssertEqual(snapshot.emptyState.title, "No Savings Goals yet")
        XCTAssertEqual(snapshot.createDestination, .createSavingsGoal)
        XCTAssertEqual(snapshot.seeAllDestination, .seeAllSavingsGoals)
    }

    func testGoalsPreviewPreservesPinnedOnlyPolicyAndStableIDs() {
        let first = SavingsGoal(name: "First", targetAmount: 100)
        let pinnedOne = SavingsGoal(
            name: "Pinned one",
            targetAmount: 200,
            isPinned: true
        )
        let unpinned = SavingsGoal(name: "Unpinned", targetAmount: 300)
        let pinnedTwo = SavingsGoal(
            name: "Pinned two",
            targetAmount: 400,
            isPinned: true
        )

        let snapshot = build(
            goals: [first, pinnedOne, unpinned, pinnedTwo]
        ).goals

        XCTAssertEqual(snapshot.rows.map(\.id), [pinnedOne.id, pinnedTwo.id])
        XCTAssertEqual(snapshot.allGoalsCount, 4)
        XCTAssertTrue(snapshot.hasAdditionalItems)
        XCTAssertEqual(
            snapshot.rows[0].contributeDestination,
            .contributeToSavingsGoal(goalID: pinnedOne.id)
        )
    }

    func testPaymentsUseActiveAndLegacyRulesForSummary() {
        let legacy = paymentPlan(
            name: "Legacy card",
            dueDate: date(2026, 8, 12),
            target: 500,
            setAside: 200
        )
        let active = paymentPlan(
            name: "Active card",
            dueDate: date(2026, 8, 20),
            target: 900,
            setAside: 100
        )
        let activeCycle = PaymentPlanCycle(
            paymentPlanID: active.id,
            dueDate: date(2026, 8, 15),
            frozenTargetAmount: 300,
            calendar: calendar
        )
        let handled = paymentPlan(
            name: "Handled card",
            dueDate: date(2026, 8, 11),
            target: 700,
            setAside: 700
        )
        let handledCycle = PaymentPlanCycle(
            paymentPlanID: handled.id,
            dueDate: handled.dueDate,
            frozenTargetAmount: 700,
            status: .handled,
            calendar: calendar
        )

        let snapshot = build(
            paymentPlans: [active, handled, legacy],
            paymentPlanCycles: [activeCycle, handledCycle]
        ).payments

        XCTAssertEqual(snapshot.activeCount, 2)
        XCTAssertEqual(snapshot.totalPlanned, 800, accuracy: 0.001)
        XCTAssertEqual(snapshot.totalSetAside, 300, accuracy: 0.001)
        XCTAssertEqual(snapshot.remainingAmount, 500, accuracy: 0.001)
        XCTAssertEqual(snapshot.rows.map(\.bucketID), [legacy.id, active.id])
        XCTAssertFalse(snapshot.rows.contains { $0.bucketID == handled.id })
    }

    func testHandledOnlyPaymentPlanCyclesAreExcluded() {
        let plan = paymentPlan()
        let cycle = PaymentPlanCycle(
            paymentPlanID: plan.id,
            dueDate: plan.dueDate,
            frozenTargetAmount: plan.paymentTargetAmount,
            status: .handled,
            calendar: calendar
        )

        let snapshot = build(
            paymentPlans: [plan],
            paymentPlanCycles: [cycle]
        ).payments

        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertEqual(snapshot.activeCount, 0)
        XCTAssertTrue(snapshot.rows.isEmpty)
        XCTAssertEqual(snapshot.allPaymentPlanCount, 1)
        XCTAssertTrue(snapshot.hasAdditionalItems)
    }

    func testLegacyPaymentPlanKeepsBucketIdentityAndFallbackMarker() {
        let legacyDebt = paymentPlan(
            name: "Student Loan",
            dueDate: date(2026, 8, 14),
            target: 300,
            setAside: 50,
            debtKind: .studentLoan
        )

        let row = build(paymentPlans: [legacyDebt]).payments.rows[0]

        XCTAssertEqual(row.bucketID, legacyDebt.id)
        XCTAssertNil(row.cycleID)
        XCTAssertEqual(row.editor, .legacyDebt)
        XCTAssertEqual(
            row.updateDestination,
            .updatePaymentPlan(
                bucketID: legacyDebt.id,
                cycleID: nil,
                editor: .legacyDebt
            )
        )
    }

    func testPaymentPlanChildPreservesActiveCycleIdentity() {
        let plan = paymentPlan()
        let cycle = PaymentPlanCycle(
            paymentPlanID: plan.id,
            dueDate: date(2026, 8, 18),
            frozenTargetAmount: 425,
            calendar: calendar
        )

        let snapshot = build(
            paymentPlans: [plan],
            paymentPlanCycles: [cycle]
        ).payments
        let row = snapshot.rows[0]

        XCTAssertEqual(row.bucketID, plan.id)
        XCTAssertEqual(row.cycleID, cycle.id)
        XCTAssertEqual(row.dueDate, cycle.dueDate)
        XCTAssertEqual(row.plannedAmount, 425, accuracy: 0.001)
        XCTAssertEqual(snapshot.segments[0].cycleID, cycle.id)
        XCTAssertEqual(row.editor, .modernCard)
    }

    func testUpcomingSummaryUsesOnlyNextThreeActiveOccurrences() {
        let events = [
            expense("First", amount: 100, day: 11),
            expense("Second", amount: 200, day: 12),
            expense("Third", amount: 300, day: 13),
            expense("Fourth", amount: 400, day: 14)
        ]

        let snapshot = build(events: events).upcomingExpenses

        XCTAssertEqual(snapshot.activeDisplayedCount, 3)
        XCTAssertEqual(snapshot.allUpcomingOccurrenceCount, 4)
        XCTAssertEqual(snapshot.totalNeeded, 600, accuracy: 0.001)
        XCTAssertEqual(snapshot.rows.map(\.title), ["First", "Second", "Third"])
        XCTAssertEqual(snapshot.summaryLabel, "Next 3 upcoming expenses")
        XCTAssertTrue(snapshot.hasAdditionalItems)
    }

    func testUpcomingAllocationIsCappedAndExactOccurrenceIsPreserved() {
        let event = expense("Rent", amount: 1_200, day: 14)
        let forecast = ForecastEvent(
            event: event,
            occurrenceDate: event.date
        )
        let allocation = EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: 1_500
        )

        let row = build(
            events: [event],
            allocations: [allocation]
        ).upcomingExpenses.rows[0]

        XCTAssertEqual(row.setAsideAmount, 1_200, accuracy: 0.001)
        XCTAssertEqual(row.remainingAmount, 0, accuracy: 0.001)
        XCTAssertEqual(row.progress, 1, accuracy: 0.001)
        XCTAssertEqual(row.eventID, event.id)
        XCTAssertEqual(row.occurrenceID, forecast.occurrenceID)
        XCTAssertEqual(
            row.updateDestination,
            .updateUpcomingExpense(
                eventID: event.id,
                occurrenceID: forecast.occurrenceID
            )
        )
    }

    func testResolvedUpcomingOccurrenceIsExcluded() {
        let event = expense("Phone", amount: 100, day: 14)
        let forecast = ForecastEvent(event: event, occurrenceDate: event.date)
        let status = ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            status: .paid
        )

        let snapshot = build(
            events: [event],
            occurrenceStatuses: [status]
        ).upcomingExpenses

        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertTrue(snapshot.rows.isEmpty)
        XCTAssertEqual(snapshot.summaryLabel, "No upcoming expenses yet")
    }

    func testCashCushionAlwaysExistsAndUsesProductionNormalization() {
        let empty = build(reserveBalance: -50).cashCushion
        let populated = build(reserveBalance: 250.25).cashCushion

        XCTAssertEqual(empty.currentAmount, 0)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.addDestination, .addCashCushion)
        XCTAssertNil(empty.useDestination)
        XCTAssertEqual(populated.currentAmount, 250.25, accuracy: 0.001)
        XCTAssertEqual(populated.useDestination, .useCashCushion)
        XCTAssertNil(populated.targetAmount)
        XCTAssertNil(populated.progress)
    }

    func testZeroTargetsRemainFiniteAndSafe() {
        let goal = SavingsGoal(
            name: "No goal target",
            targetAmount: 0,
            currentAmount: 25
        )
        let plan = paymentPlan(target: 0, setAside: 25)
        let event = expense("No expense target", amount: 0, day: 14)

        let snapshot = build(
            goals: [goal],
            events: [event],
            paymentPlans: [plan]
        )

        XCTAssertEqual(snapshot.goals.progress, 0)
        XCTAssertEqual(snapshot.goals.rows[0].progress, 0)
        XCTAssertEqual(snapshot.payments.progress, 0)
        XCTAssertEqual(snapshot.payments.rows[0].progress, 0)
        XCTAssertTrue(snapshot.payments.segments.isEmpty)
        XCTAssertEqual(snapshot.upcomingExpenses.progress, 0)
        XCTAssertEqual(snapshot.upcomingExpenses.rows[0].progress, 0)
    }

    func testSeeAllSupportReflectsAdditionalRecordsForEveryPagerSection() {
        let goals = (1...4).map {
            SavingsGoal(name: "G\($0)", targetAmount: 100)
        }
        let plans = (1...4).map {
            paymentPlan(
                name: "P\($0)",
                dueDate: date(2026, 8, 10 + $0)
            )
        }
        let events = (1...4).map {
            expense("E\($0)", amount: 100, day: 10 + $0)
        }

        let snapshot = build(
            goals: goals,
            events: events,
            paymentPlans: plans
        )

        XCTAssertTrue(snapshot.goals.hasAdditionalItems)
        XCTAssertTrue(snapshot.payments.hasAdditionalItems)
        XCTAssertTrue(snapshot.upcomingExpenses.hasAdditionalItems)
        XCTAssertEqual(snapshot.goals.seeAllDestination, .seeAllSavingsGoals)
        XCTAssertEqual(snapshot.payments.seeAllDestination, .seeAllPaymentPlans)
        XCTAssertEqual(
            snapshot.upcomingExpenses.seeAllDestination,
            .seeAllUpcomingExpenses
        )
    }

    func testEmptyProductionInputDoesNotInjectLabSampleValues() {
        let snapshot = build()
        let labels = [
            snapshot.cashCushion.accessibilityLabel,
            snapshot.goals.accessibilityLabel,
            snapshot.payments.accessibilityLabel,
            snapshot.upcomingExpenses.accessibilityLabel
        ]
        .joined(separator: " ")

        XCTAssertTrue(snapshot.goals.rows.isEmpty)
        XCTAssertTrue(snapshot.payments.rows.isEmpty)
        XCTAssertTrue(snapshot.upcomingExpenses.rows.isEmpty)
        XCTAssertFalse(labels.contains("Amex Gold"))
        XCTAssertFalse(labels.contains("Platinum"))
        XCTAssertFalse(labels.contains("Rent"))
    }

    private func build(
        reserveBalance: Double = 0,
        goals: [SavingsGoal] = [],
        events: [PlannerEvent] = [],
        allocations: [EventAllocation] = [],
        occurrenceStatuses: [ExpenseOccurrenceStatus] = [],
        paymentPlans: [DebtPayoffBucket] = [],
        paymentPlanCycles: [PaymentPlanCycle] = [],
        debtAccounts: [PlaidAccount] = []
    ) -> SetAsidePagerSnapshot {
        SetAsidePagerSnapshotBuilder.build(
            from: SetAsidePagerSnapshotBuilder.Input(
                reserveBalance: reserveBalance,
                savingsGoals: goals,
                events: events,
                allocations: allocations,
                occurrenceStatuses: occurrenceStatuses,
                paymentPlans: paymentPlans,
                paymentPlanCycles: paymentPlanCycles,
                debtAccounts: debtAccounts,
                now: now,
                calendar: calendar
            )
        )
    }

    private func paymentPlan(
        name: String = "Card",
        dueDate: Date? = nil,
        target: Double = 500,
        setAside: Double = 200,
        debtKind: DebtPayoffKind = .linkedCreditCard
    ) -> DebtPayoffBucket {
        DebtPayoffBucket(
            plaidAccountID: debtKind == .linkedCreditCard ? "card-1" : "",
            accountName: name,
            dueDate: dueDate ?? date(2026, 8, 13),
            paymentTargetAmount: target,
            protectedAmount: setAside,
            debtKind: debtKind,
            paymentTargetChoice: debtKind == .linkedCreditCard
                ? .currentBalance
                : nil,
            monthlyPayment: debtKind == .linkedCreditCard ? nil : target
        )
    }

    private func expense(
        _ name: String,
        amount: Double,
        day: Int
    ) -> PlannerEvent {
        PlannerEvent(
            name: name,
            amount: amount,
            date: date(2026, 8, day),
            frequency: .once,
            type: .expense
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
