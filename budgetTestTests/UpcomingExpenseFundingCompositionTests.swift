import SwiftData
import XCTest

@testable import Caldera_Money

@MainActor
final class UpcomingExpenseFundingCompositionTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDashboardCompositionIncludesUnresolvedHistoricalFunding() {
        let fixture = historicalFixture()
        let composition = compose(fixture)
        let summary = dashboardSummary(composition)

        XCTAssertEqual(composition.totalSetAside, 500, accuracy: 0.001)
        XCTAssertEqual(summary.upcomingExpensesSetAside, 500, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpend, 1_500, accuracy: 0.001)
    }

    func testPlanAheadCompositionUsesTheSameAuthoritativeFundingTotal() {
        let fixture = historicalFixture()
        let composition = compose(fixture)
        let dashboard = dashboardSummary(composition)
        let planAhead = planAheadCalculator(
            composition,
            events: fixture.events,
            totalAvailable: dashboard.safeToSpendBeforeUpcomingExpenses
        )

        XCTAssertEqual(planAhead.protectedEventAllocations, 500, accuracy: 0.001)
        XCTAssertEqual(planAhead.safeToSpend, dashboard.safeToSpend, accuracy: 0.001)
        XCTAssertEqual(
            Set(planAhead.forecastEvents.map(\.occurrenceID))
                .intersection(fixture.allocations.map(\.occurrenceID)),
            Set(fixture.allocations.map(\.occurrenceID))
        )
    }

    func testResolvedOccurrenceIsNoLongerDeductedFromDashboardOrPlanAhead() {
        let fixture = historicalFixture()
        let resolved = ExpenseOccurrenceStatus(
            occurrenceID: fixture.july.occurrenceID,
            sourceEventID: fixture.expense.id,
            occurrenceDate: fixture.july.normalizedOccurrenceDate,
            status: .paid
        )
        let composition = compose(fixture, statuses: [resolved])
        let dashboard = dashboardSummary(composition)
        let planAhead = planAheadCalculator(
            composition,
            events: fixture.events,
            totalAvailable: dashboard.safeToSpendBeforeUpcomingExpenses,
            statuses: [resolved]
        )

        XCTAssertEqual(composition.totalSetAside, 100, accuracy: 0.001)
        XCTAssertEqual(dashboard.safeToSpend, 1_900, accuracy: 0.001)
        XCTAssertEqual(planAhead.safeToSpend, 1_900, accuracy: 0.001)
        XCTAssertFalse(
            planAhead.forecastEvents.contains {
                $0.occurrenceID == fixture.july.occurrenceID
            }
        )
        XCTAssertTrue(
            planAhead.forecastEvents.contains {
                $0.occurrenceID == fixture.august.occurrenceID
            }
        )
    }

    func testRepeatedResolutionCannotReleaseTheSameFundingTwice() throws {
        let fixture = historicalFixture()
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(fixture.expense)
        fixture.allocations.forEach { context.insert($0) }
        try context.save()

        for _ in 0..<2 {
            let statuses = try context.fetch(
                FetchDescriptor<ExpenseOccurrenceStatus>()
            )
            let result = UpcomingExpenseActionPersistenceCoordinator.resolve(
                .paid,
                forecast: fixture.july,
                existingStatus: statuses.first {
                    $0.occurrenceID == fixture.july.occurrenceID
                },
                modelContext: context,
                persistChanges: { try context.save() },
                rollback: { context.rollback() }
            )

            guard case .saved = result else {
                return XCTFail("Expected the resolution to save")
            }

            let savedStatuses = try context.fetch(
                FetchDescriptor<ExpenseOccurrenceStatus>()
            )
            let composition = compose(fixture, statuses: savedStatuses)
            let dashboard = dashboardSummary(composition)
            let planAhead = planAheadCalculator(
                composition,
                events: fixture.events,
                totalAvailable: dashboard.safeToSpendBeforeUpcomingExpenses,
                statuses: savedStatuses
            )

            XCTAssertEqual(savedStatuses.count, 1)
            XCTAssertEqual(composition.totalSetAside, 100, accuracy: 0.001)
            XCTAssertEqual(dashboard.safeToSpend, 1_900, accuracy: 0.001)
            XCTAssertEqual(planAhead.safeToSpend, 1_900, accuracy: 0.001)
        }
    }

    func testExpectedIncomeDoesNotRaiseCurrentAvailableToSpend() {
        let fixture = historicalFixture()
        let expectedIncome = PlannerEvent(
            name: "Expected paycheck",
            amount: 5_000,
            date: date(2029, 1, 15),
            frequency: .monthly,
            type: .income
        )
        let eventsWithIncome = fixture.events + [expectedIncome]
        let composition = UpcomingExpenseFundingComposition(
            events: eventsWithIncome,
            allocations: fixture.allocations,
            occurrenceStatuses: []
        )
        let dashboard = dashboardSummary(composition)
        let planAhead = planAheadCalculator(
            composition,
            events: eventsWithIncome,
            totalAvailable: dashboard.safeToSpendBeforeUpcomingExpenses
        )

        XCTAssertEqual(dashboard.cash, 2_000, accuracy: 0.001)
        XCTAssertEqual(dashboard.safeToSpend, 1_500, accuracy: 0.001)
        XCTAssertEqual(planAhead.safeToSpend, 1_500, accuracy: 0.001)
        XCTAssertTrue(
            planAhead.forecastEvents.contains { $0.event.id == expectedIncome.id }
        )
    }

    func testSetAsideCompositionReportsGlobalAndVisibleTotalsWithoutDoubleDeduction() {
        let fixture = fiveOccurrenceFixture()
        let composition = compose(fixture)
        let dashboardBeforePager = dashboardSummary(composition)
        let pager = SetAsidePagerSnapshotBuilder.build(
            from: .init(
                reserveBalance: 0,
                savingsGoals: [],
                events: fixture.events,
                allocations: fixture.allocations,
                occurrenceStatuses: [],
                paymentPlans: [],
                paymentPlanCycles: [],
                debtAccounts: [],
                now: date(2027, 1, 2),
                calendar: calendar
            )
        )
        let dashboardAfterPager = dashboardSummary(composition)

        XCTAssertEqual(pager.upcomingExpenses.totalActiveSetAside, 500, accuracy: 0.001)
        XCTAssertEqual(pager.upcomingExpenses.totalSetAside, 300, accuracy: 0.001)
        XCTAssertEqual(dashboardBeforePager.safeToSpend, 1_500, accuracy: 0.001)
        XCTAssertEqual(dashboardAfterPager, dashboardBeforePager)
    }

    func testMultipleRecurrencesPreserveExactOccurrenceIdentityAcrossCompositions() {
        let fixture = historicalFixture()
        let composition = compose(fixture)
        let planAhead = planAheadCalculator(
            composition,
            events: fixture.events,
            totalAvailable: 2_000
        )
        let pager = SetAsidePagerSnapshotBuilder.build(
            from: .init(
                reserveBalance: 0,
                savingsGoals: [],
                events: fixture.events,
                allocations: fixture.allocations,
                occurrenceStatuses: [],
                paymentPlans: [],
                paymentPlanCycles: [],
                debtAccounts: [],
                now: date(2027, 1, 2),
                calendar: calendar
            )
        )
        let exactIDs = Set(fixture.allocations.map(\.occurrenceID))

        XCTAssertEqual(exactIDs.count, 2)
        XCTAssertEqual(composition.snapshot.fundedOccurrences.map(\.occurrenceID), exactIDs.sorted())
        XCTAssertEqual(
            planAhead.forecastEvents.filter { exactIDs.contains($0.occurrenceID) }
                .map(\.occurrenceID).sorted(),
            exactIDs.sorted()
        )
        XCTAssertEqual(
            Set(pager.upcomingExpenses.rows.map(\.occurrenceID))
                .intersection(exactIDs),
            exactIDs
        )
    }

    private func dashboardSummary(
        _ composition: UpcomingExpenseFundingComposition
    ) -> FinancialSummary {
        composition.dashboardFinancialSummary(
            accounts: [checkingAccount()],
            goals: [],
            reserveBalance: 0,
            debtPaymentsSetAside: 0
        )
    }

    private func planAheadCalculator(
        _ composition: UpcomingExpenseFundingComposition,
        events: [PlannerEvent],
        totalAvailable: Double,
        statuses: [ExpenseOccurrenceStatus] = []
    ) -> PlannerForecastCalculator {
        composition.forecastCalculator(
            events: events,
            totalAvailable: totalAvailable,
            totalGoalAllocated: 0,
            includeFutureIncome: true,
            protectGoals: true,
            now: date(2027, 1, 2),
            calendar: calendar,
            allocatedAmountProvider: {
                composition.snapshot.allocatedAmount(for: $0)
            },
            inactiveOccurrenceIDs: ExpenseOccurrenceLifecycleResolver
                .resolvedOccurrenceIDs(from: statuses)
        )
    }

    private func compose(
        _ fixture: Fixture,
        statuses: [ExpenseOccurrenceStatus] = []
    ) -> UpcomingExpenseFundingComposition {
        UpcomingExpenseFundingComposition(
            events: fixture.events,
            allocations: fixture.allocations,
            occurrenceStatuses: statuses
        )
    }

    private func historicalFixture() -> Fixture {
        let expense = PlannerEvent(
            name: "Rent",
            amount: 400,
            date: date(2026, 7, 1),
            frequency: .monthly,
            type: .expense
        )
        let july = ForecastEvent(
            event: expense,
            occurrenceDate: date(2026, 7, 1)
        )
        let august = ForecastEvent(
            event: expense,
            occurrenceDate: date(2026, 8, 1)
        )
        return Fixture(
            expense: expense,
            events: [expense],
            july: july,
            august: august,
            allocations: [
                allocation(july, amount: 400),
                allocation(august, amount: 100)
            ]
        )
    }

    private func fiveOccurrenceFixture() -> Fixture {
        let expense = PlannerEvent(
            name: "Rent",
            amount: 100,
            date: date(2026, 1, 1),
            frequency: .monthly,
            type: .expense
        )
        let forecasts = (1...5).map {
            ForecastEvent(
                event: expense,
                occurrenceDate: date(2026, $0, 1)
            )
        }
        return Fixture(
            expense: expense,
            events: [expense],
            july: forecasts[0],
            august: forecasts[1],
            allocations: forecasts.map { allocation($0, amount: 100) }
        )
    }

    private func allocation(
        _ forecast: ForecastEvent,
        amount: Double
    ) -> EventAllocation {
        EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: amount
        )
    }

    private func checkingAccount() -> PlaidAccount {
        PlaidAccount(
            account_id: "checking",
            name: "Checking",
            official_name: nil,
            type: "depository",
            subtype: "checking",
            mask: nil,
            balances: PlaidBalance(available: 2_000, current: 2_000)
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )!
    }

    private struct Fixture {
        let expense: PlannerEvent
        let events: [PlannerEvent]
        let july: ForecastEvent
        let august: ForecastEvent
        let allocations: [EventAllocation]
    }
}
