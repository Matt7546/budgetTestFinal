import XCTest
@testable import Caldera_Money

final class PlanAheadProductionPresentationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCardsAndListConsumeSameEventIdentitySetAndRoutes() throws {
        let fixture = makeFixture()
        let composition = fixture.composition

        XCTAssertEqual(composition.cardsEventIDs, composition.listEventIDs)
        XCTAssertEqual(composition.cardsEventIDs.count, 6)

        let expense = try XCTUnwrap(
            composition.upcomingObligations.first {
                $0.kind == .upcomingExpense
            }
        )
        XCTAssertEqual(
            expense.route,
            .upcomingExpense(
                eventID: fixture.upcomingExpense.event.id,
                occurrenceID: fixture.upcomingExpense.occurrenceID
            )
        )

        let paymentPlan = try XCTUnwrap(
            composition.upcomingObligations.first {
                $0.kind == .paymentPlan
            }
        )
        XCTAssertEqual(
            paymentPlan.route,
            .paymentPlan(
                paymentPlanID: fixture.paymentPlan.id,
                cycleID: fixture.paymentPlanCycle.id
            )
        )

        let income = try XCTUnwrap(composition.incoming.first)
        XCTAssertEqual(
            income.route,
            .expectedIncome(scheduleID: fixture.incomeSchedule.id)
        )
    }

    func testCardsDeduplicateAndOrderObligationsAcrossMonthBoundary() {
        let fixture = makeFixture(duplicatesUpcomingExpense: true)
        let composition = fixture.composition

        XCTAssertEqual(
            Set(composition.upcomingObligations.map(\.id)).count,
            composition.upcomingObligations.count
        )
        XCTAssertEqual(
            composition.upcomingObligations.map(\.date),
            composition.upcomingObligations.map(\.date).sorted()
        )

        let months = composition.upcomingMonths(calendar: calendar)
        XCTAssertEqual(months.count, 2)
        XCTAssertEqual(months.map { $0.items.count }, [3, 1])
        XCTAssertEqual(
            months.flatMap(\.items).map(\.id),
            composition.upcomingObligations.map(\.id)
        )
    }

    func testPastDueItemsStaySeparateAndChronological() {
        let composition = makeFixture().composition

        XCTAssertEqual(composition.pastDueObligations.count, 1)
        XCTAssertTrue(composition.pastDueObligations.allSatisfy(\.isPastDue))
        XCTAssertLessThan(
            composition.pastDueObligations[0].date,
            composition.upcomingObligations[0].date
        )
        XCTAssertEqual(composition.groupedPastDue(calendar: calendar).count, 1)
    }

    func testUpcomingExpenseFundingStatesUseProvidedAllocationValues() {
        let covered = PlanAheadFundingPresentation.upcomingExpense(
            amount: 120,
            allocatedAmount: 120
        )
        let partial = PlanAheadFundingPresentation.upcomingExpense(
            amount: 120,
            allocatedAmount: 45
        )
        let notStarted = PlanAheadFundingPresentation.upcomingExpense(
            amount: 120,
            allocatedAmount: 0
        )

        XCTAssertEqual(covered.state, .covered)
        XCTAssertEqual(covered.progress, 1, accuracy: 0.001)
        XCTAssertEqual(covered.statusLine, "Covered")

        XCTAssertEqual(partial.state, .partial)
        XCTAssertEqual(partial.setAsideAmount, 45, accuracy: 0.001)
        XCTAssertEqual(partial.remainingAmount, 75, accuracy: 0.001)

        XCTAssertEqual(notStarted.state, .notStarted)
        XCTAssertEqual(notStarted.setAsideAmount, 0, accuracy: 0.001)
        XCTAssertEqual(notStarted.remainingAmount, 120, accuracy: 0.001)
    }

    func testPaymentPlanFundingUsesDebtPayoffDisplayModelValues() throws {
        let fixture = makeFixture()
        let item = try XCTUnwrap(
            fixture.composition.upcomingObligations.first {
                $0.kind == .paymentPlan
            }
        )
        let funding = try XCTUnwrap(item.funding)
        let authoritative = DebtPayoffDisplayModel(
            bucket: fixture.paymentPlan,
            linkedAccount: nil,
            cycle: fixture.paymentPlanCycle,
            today: fixture.today,
            calendar: calendar
        )

        XCTAssertEqual(
            funding.dueAmount ?? -1,
            authoritative.plannedPaymentAmount,
            accuracy: 0.001
        )
        XCTAssertEqual(
            funding.setAsideAmount,
            authoritative.coveredPaymentAmount,
            accuracy: 0.001
        )
        XCTAssertEqual(
            funding.remainingAmount,
            authoritative.remainingPaymentAmount,
            accuracy: 0.001
        )
    }

    func testExpectedIncomeIsExcludedFromObligationsAndRemainsPlanningOnly() throws {
        let composition = makeFixture().composition

        XCTAssertFalse(
            composition.pastDueObligations.contains {
                $0.kind == .expectedIncome
            }
        )
        XCTAssertFalse(
            composition.upcomingObligations.contains {
                $0.kind == .expectedIncome
            }
        )

        let income = try XCTUnwrap(composition.incoming.first)
        XCTAssertEqual(income.kind, .expectedIncome)
        XCTAssertNil(income.funding)
        XCTAssertEqual(income.statusValue, "Planning estimate")
    }

    func testPlanningOutlookHorizonsUseSamePresentedFundingValues() {
        let fixture = makeFixture()
        let composition = fixture.composition

        let sevenDays = composition.summary(
            for: .days7,
            today: fixture.today,
            calendar: calendar
        )
        let thirtyDays = composition.summary(
            for: .days30,
            today: fixture.today,
            calendar: calendar
        )
        let ninetyDays = composition.summary(
            for: .days90,
            today: fixture.today,
            calendar: calendar
        )

        XCTAssertEqual(sevenDays.dueSoonAmount, 320, accuracy: 0.001)
        XCTAssertEqual(sevenDays.coveredAmount, 120, accuracy: 0.001)
        XCTAssertEqual(sevenDays.periodTitle, "Next 7 days")
        XCTAssertTrue(sevenDays.accessibilitySummary.contains("Next 7 days"))
        XCTAssertEqual(thirtyDays.dueSoonAmount, 470, accuracy: 0.001)
        XCTAssertEqual(thirtyDays.coveredAmount, 170, accuracy: 0.001)
        XCTAssertEqual(ninetyDays.dueSoonAmount, 560, accuracy: 0.001)
        XCTAssertEqual(ninetyDays.coveredAmount, 170, accuracy: 0.001)
    }

    func testPlanningOutlookIncludesTodayAndExactEndpointForEveryHorizon() {
        let today = date(2026, 12, 20)
        let composition = expenseComposition(
            today: today,
            offsets: [0, 7, 8, 30, 31, 90, 91]
        )

        XCTAssertEqual(
            composition.summary(
                for: .days7,
                today: today,
                calendar: calendar
            ).dueSoonAmount,
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            composition.summary(
                for: .days30,
                today: today,
                calendar: calendar
            ).dueSoonAmount,
            4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            composition.summary(
                for: .days90,
                today: today,
                calendar: calendar
            ).dueSoonAmount,
            6,
            accuracy: 0.001
        )
    }

    func testPlanningOutlookInclusiveEndpointCrossesYearBoundary() {
        let today = date(2026, 12, 20)
        let composition = expenseComposition(
            today: today,
            offsets: [30, 31]
        )

        XCTAssertEqual(
            composition.summary(
                for: .days30,
                today: today,
                calendar: calendar
            ).dueSoonAmount,
            1,
            accuracy: 0.001
        )
    }

    func testExpiredMonthlyIncomeRemainsActionableWithoutInventingDate() throws {
        try assertExpiredIncomeRemainsActionable(frequency: .monthly)
    }

    func testExpiredTwiceMonthlyIncomeRemainsActionableWithoutInventingDate() throws {
        try assertExpiredIncomeRemainsActionable(frequency: .twiceMonthly)
    }

    func testPastDueFocusFromCardsSwitchesToListAndCreatesRequest() {
        var navigation = PlanAheadPresentationNavigationState(
            selectedMode: .cards
        )

        navigation.requestPastDueFocus()

        XCTAssertEqual(navigation.selectedMode, .list)
        XCTAssertEqual(navigation.pastDueFocusRequestID, 1)
    }

    func testPastDueFocusCanRepeatWhileListIsAlreadySelected() {
        var navigation = PlanAheadPresentationNavigationState()

        navigation.requestPastDueFocus()
        navigation.requestPastDueFocus()

        XCTAssertEqual(navigation.selectedMode, .list)
        XCTAssertEqual(navigation.pastDueFocusRequestID, 2)
    }

    func testLargeSameDayGroupRetainsEveryIdentityInDeterministicOrder() throws {
        let today = date(2026, 9, 16)
        let dueDate = date(2026, 9, 21)
        let forecasts = (0..<250).reversed().map { index in
            forecast(
                name: String(format: "Expense %03d", index),
                amount: 1,
                date: dueDate
            )
        }
        let composition = PlanAheadProductionCompositionBuilder.make(
            pastDueItems: [],
            upcomingItems: forecasts.map(PlanAheadTimelineItem.upcomingExpense),
            allocationAmounts: EventAllocationAmountLookup(allocations: []),
            accountByID: [:],
            cycles: [],
            expectedIncomeSchedule: nil,
            today: today,
            calendar: calendar
        )

        let group = try XCTUnwrap(
            composition.groupedUpcomingIncludingIncome(calendar: calendar).first
        )
        let titles = group.items.map(\.title)

        XCTAssertEqual(group.items.count, 250)
        XCTAssertEqual(Set(group.items.map(\.id)).count, 250)
        XCTAssertEqual(titles, titles.sorted())
    }

    func testReadingEitherPresentationDoesNotMutateFundingModels() {
        let fixture = makeFixture()
        let allocationBefore = fixture.upcomingAllocation.allocatedAmount
        let paymentSetAsideBefore = fixture.paymentPlan.protectedAmount

        _ = fixture.composition.cardsEventIDs
        _ = fixture.composition.listEventIDs
        _ = fixture.composition.upcomingMonths(calendar: calendar)
        _ = fixture.composition.groupedUpcomingIncludingIncome(calendar: calendar)

        XCTAssertEqual(
            fixture.upcomingAllocation.allocatedAmount,
            allocationBefore,
            accuracy: 0.001
        )
        XCTAssertEqual(
            fixture.paymentPlan.protectedAmount,
            paymentSetAsideBefore,
            accuracy: 0.001
        )
    }

    func testDynamicTypeCardLayoutDecision() {
        XCTAssertEqual(
            PlanAheadCardLayout.columnCount(isAccessibilitySize: false),
            2
        )
        XCTAssertEqual(
            PlanAheadCardLayout.columnCount(isAccessibilitySize: true),
            1
        )
    }

    func testSameDayItemsRemainGroupedInList() throws {
        let composition = makeFixture().composition
        let groups = composition.groupedUpcomingIncludingIncome(
            calendar: calendar
        )
        let sameDay = try XCTUnwrap(
            groups.first {
                calendar.isDate(
                    $0.date,
                    inSameDayAs: date(2026, 9, 21)
                )
            }
        )

        XCTAssertEqual(sameDay.items.count, 2)
        XCTAssertEqual(
            sameDay.items.map(\.kind),
            [.upcomingExpense, .paymentPlan]
        )
    }

    private func makeFixture(
        duplicatesUpcomingExpense: Bool = false
    ) -> Fixture {
        let today = date(2026, 9, 16)
        let upcomingExpense = forecast(
            name: "Home insurance",
            amount: 120,
            date: date(2026, 9, 21)
        )
        let laterExpense = forecast(
            name: "Phone bill",
            amount: 90,
            date: date(2026, 11, 10)
        )
        let pastDueExpense = forecast(
            name: "Water bill",
            amount: 75,
            date: date(2026, 9, 12)
        )
        let midWindowExpense = forecast(
            name: "Utilities",
            amount: 150,
            date: date(2026, 9, 30)
        )

        let upcomingAllocation = allocation(
            for: upcomingExpense,
            amount: 40
        )
        let laterAllocation = allocation(for: laterExpense, amount: 0)
        let pastDueAllocation = allocation(for: pastDueExpense, amount: 75)
        let midWindowAllocation = allocation(
            for: midWindowExpense,
            amount: 50
        )
        let allocationLookup = EventAllocationAmountLookup(
            allocations: [
                upcomingAllocation,
                laterAllocation,
                pastDueAllocation,
                midWindowAllocation
            ]
        )

        let paymentPlan = DebtPayoffBucket(
            plaidAccountID: "",
            accountName: "Visa",
            dueDate: date(2026, 9, 21),
            paymentTargetAmount: 200,
            protectedAmount: 80,
            debtKind: .other,
            manualCurrentBalance: 1_000,
            monthlyPayment: 200,
            hasPaymentDueDate: true
        )
        let paymentPlanCycle = PaymentPlanCycle(
            paymentPlanID: paymentPlan.id,
            dueDate: paymentPlan.dueDate,
            frozenTargetAmount: 200,
            calendar: calendar
        )
        let planAheadPayment = PlanAheadPaymentPlan(
            bucket: paymentPlan,
            dueDate: paymentPlanCycle.dueDate
        )

        let incomeSchedule = IncomeSchedule(
            ownerScopeID: "test-owner",
            sourceLabel: "Paycheck",
            takeHomeAmountCents: 250_000,
            frequency: .monthly,
            lastPaydayDateKey: "2026-08-30",
            nextExpectedPaydayDateKey: "2026-09-25",
            dateBasis: .explicit
        )

        var upcomingItems: [PlanAheadTimelineItem] = [
            .upcomingExpense(laterExpense),
            .paymentPlan(planAheadPayment),
            .upcomingExpense(upcomingExpense),
            .upcomingExpense(midWindowExpense)
        ]
        if duplicatesUpcomingExpense {
            upcomingItems.append(.upcomingExpense(upcomingExpense))
        }

        let composition = PlanAheadProductionCompositionBuilder.make(
            pastDueItems: [.upcomingExpense(pastDueExpense)],
            upcomingItems: upcomingItems,
            allocationAmounts: allocationLookup,
            accountByID: [:],
            cycles: [paymentPlanCycle],
            expectedIncomeSchedule: incomeSchedule,
            today: today,
            calendar: calendar
        )

        return Fixture(
            today: today,
            composition: composition,
            upcomingExpense: upcomingExpense,
            upcomingAllocation: upcomingAllocation,
            paymentPlan: paymentPlan,
            paymentPlanCycle: paymentPlanCycle,
            incomeSchedule: incomeSchedule
        )
    }

    private func expenseComposition(
        today: Date,
        offsets: [Int]
    ) -> PlanAheadProductionComposition {
        let forecasts = offsets.map { offset in
            let dueDate = calendar.date(
                byAdding: .day,
                value: offset,
                to: today
            )!
            return forecast(
                name: "Expense day \(offset)",
                amount: 1,
                date: dueDate
            )
        }

        return PlanAheadProductionCompositionBuilder.make(
            pastDueItems: [],
            upcomingItems: forecasts.map(PlanAheadTimelineItem.upcomingExpense),
            allocationAmounts: EventAllocationAmountLookup(allocations: []),
            accountByID: [:],
            cycles: [],
            expectedIncomeSchedule: nil,
            today: today,
            calendar: calendar
        )
    }

    private func assertExpiredIncomeRemainsActionable(
        frequency: IncomeScheduleFrequency
    ) throws {
        let today = date(2026, 9, 16)
        let schedule = IncomeSchedule(
            ownerScopeID: "test-owner",
            sourceLabel: "Paycheck",
            takeHomeAmountCents: 250_000,
            frequency: frequency,
            lastPaydayDateKey: "2026-08-31",
            nextExpectedPaydayDateKey: "2026-09-15",
            dateBasis: .explicit
        )
        let composition = PlanAheadProductionCompositionBuilder.make(
            pastDueItems: [],
            upcomingItems: [],
            allocationAmounts: EventAllocationAmountLookup(allocations: []),
            accountByID: [:],
            cycles: [],
            expectedIncomeSchedule: schedule,
            today: today,
            calendar: calendar
        )

        XCTAssertTrue(composition.incoming.isEmpty)
        let update = try XCTUnwrap(composition.expectedIncomeUpdate)
        XCTAssertEqual(update.statusValue, "Update your next payday")
        XCTAssertEqual(
            update.route,
            .expectedIncome(scheduleID: schedule.id)
        )
        XCTAssertTrue(update.schedule === schedule)
        XCTAssertEqual(composition.cardsEventIDs, composition.listEventIDs)
        XCTAssertEqual(composition.cardsEventIDs, [update.id])
    }

    private func forecast(
        name: String,
        amount: Double,
        date: Date
    ) -> ForecastEvent {
        let event = PlannerEvent(
            name: name,
            amount: amount,
            date: date,
            frequency: .once,
            type: .expense
        )
        return ForecastEvent(event: event, occurrenceDate: date)
    }

    private func allocation(
        for forecast: ForecastEvent,
        amount: Double
    ) -> EventAllocation {
        EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.occurrenceDate,
            allocatedAmount: amount
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )
        )!
    }
}

private struct Fixture {
    let today: Date
    let composition: PlanAheadProductionComposition
    let upcomingExpense: ForecastEvent
    let upcomingAllocation: EventAllocation
    let paymentPlan: DebtPayoffBucket
    let paymentPlanCycle: PaymentPlanCycle
    let incomeSchedule: IncomeSchedule
}
