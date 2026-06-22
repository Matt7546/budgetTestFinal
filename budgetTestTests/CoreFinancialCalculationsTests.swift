import XCTest
@testable import budgetTest

@MainActor
final class CoreFinancialCalculationsTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    func testSafeToSpendDoesNotSubtractDebt() {
        let totals = AccountTotals(
            accounts: [
                account(
                    name: "Checking",
                    type: "depository",
                    balance: 2_000
                ),
                account(
                    name: "Credit Card",
                    type: "credit",
                    balance: -500
                )
            ],
            goals: [
                goal(
                    currentAmount: 300,
                    targetAmount: 1_000
                )
            ],
            reserveBalance: 200
        )
        let activeUpcomingExpenseSetAside = 400.0

        XCTAssertEqual(totals.totalCash, 2_000, accuracy: 0.001)
        XCTAssertEqual(totals.totalDebt, 500, accuracy: 0.001)
        XCTAssertEqual(
            totals.totalAvailable - activeUpcomingExpenseSetAside,
            1_100,
            accuracy: 0.001
        )
        XCTAssertEqual(
            totals.reserveBalance + totals.totalGoalAllocated + activeUpcomingExpenseSetAside,
            900,
            accuracy: 0.001
        )
        XCTAssertNotEqual(
            totals.totalAvailable - activeUpcomingExpenseSetAside,
            600,
            accuracy: 0.001
        )
    }

    func testSafeToSpendMatchesNoDebtComparison() {
        let totals = AccountTotals(
            accounts: [
                account(
                    type: "depository",
                    balance: 2_000
                )
            ],
            goals: [
                goal(
                    currentAmount: 300,
                    targetAmount: 1_000
                )
            ],
            reserveBalance: 200
        )

        XCTAssertEqual(
            totals.totalAvailable - 400,
            1_100,
            accuracy: 0.001
        )
        XCTAssertEqual(
            totals.reserveBalance + totals.totalGoalAllocated + 400,
            900,
            accuracy: 0.001
        )
    }

    func testDebtOnlyDoesNotReduceSafeToSpendButReducesNetWorth() {
        let totals = AccountTotals(
            accounts: [
                account(
                    type: "depository",
                    balance: 2_000
                ),
                account(
                    type: "loan",
                    balance: -1_500
                )
            ],
            goals: [],
            reserveBalance: 0
        )

        XCTAssertEqual(totals.totalAvailable, 2_000, accuracy: 0.001)
        XCTAssertEqual(totals.totalDebt, 1_500, accuracy: 0.001)
        XCTAssertEqual(totals.totalNetWorth, 500, accuracy: 0.001)
    }

    func testProtectedMoneyUsesSavedGoalAmountsNotTargets() {
        let totals = AccountTotals(
            accounts: [],
            goals: [
                goal(
                    currentAmount: 200,
                    targetAmount: 5_000
                )
            ],
            reserveBalance: 100
        )
        let activeUpcomingExpenseSetAside = 300.0

        XCTAssertEqual(totals.totalGoalAllocated, 200, accuracy: 0.001)
        XCTAssertEqual(
            totals.reserveBalance + totals.totalGoalAllocated + activeUpcomingExpenseSetAside,
            600,
            accuracy: 0.001
        )
    }

    func testActiveUpcomingExpenseAllocationAndRemainingAmount() {
        let forecast = singleExpenseForecast(
            amount: 1_000,
            date: date(2026, 7, 21)
        )
        let allocation = allocation(
            for: forecast,
            amount: 400
        )

        let activeTotal = EventAllocationTotals.activeTotal(
            allocations: [allocation],
            forecastEvents: [forecast]
        )

        XCTAssertEqual(activeTotal, 400, accuracy: 0.001)
        XCTAssertEqual(
            max(forecast.event.amount - activeTotal, 0),
            600,
            accuracy: 0.001
        )
    }

    func testOverAllocatedUpcomingExpenseCapsAtAmountDue() {
        let forecast = singleExpenseForecast(
            amount: 1_000,
            date: date(2026, 7, 21)
        )
        let allocation = allocation(
            for: forecast,
            amount: 1_200
        )

        let activeTotal = EventAllocationTotals.activeTotal(
            allocations: [allocation],
            forecastEvents: [forecast]
        )
        let remaining = max(
            forecast.event.amount - activeTotal,
            0
        )
        let progress = min(
            activeTotal / forecast.event.amount,
            1
        )

        XCTAssertEqual(activeTotal, 1_000, accuracy: 0.001)
        XCTAssertEqual(remaining, 0, accuracy: 0.001)
        XCTAssertEqual(progress, 1, accuracy: 0.001)
    }

    func testPaidOccurrenceIsExcludedFromActiveTotalsAndNextExpense() {
        let rent = event(
            name: "Rent",
            amount: 1_000,
            date: date(2026, 7, 21),
            frequency: .once
        )
        let utilities = event(
            name: "Utilities",
            amount: 200,
            date: date(2026, 7, 22),
            frequency: .once
        )
        let baseCalculator = calculator(
            events: [
                rent,
                utilities
            ],
            now: date(2026, 7, 20)
        )
        let rentForecast = try! XCTUnwrap(
            baseCalculator.forecastEvents.first {
                $0.event.id == rent.id
            }
        )
        let paidStatus = status(
            for: rentForecast,
            resolution: .paid
        )
        let inactiveIDs = ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: [paidStatus]
        )
        let filteredCalculator = calculator(
            events: [
                rent,
                utilities
            ],
            now: date(2026, 7, 20),
            inactiveOccurrenceIDs: inactiveIDs
        )
        let activeTotal = EventAllocationTotals.activeTotal(
            allocations: [
                allocation(
                    for: rentForecast,
                    amount: 1_000
                )
            ],
            forecastEvents: filteredCalculator.forecastEvents
        )

        XCTAssertEqual(activeTotal, 0, accuracy: 0.001)
        XCTAssertEqual(filteredCalculator.nextExpense?.event.name, "Utilities")
    }

    func testSkippedOccurrenceIsExcludedFromActiveTotals() {
        let forecast = singleExpenseForecast(
            amount: 1_000,
            date: date(2026, 7, 21)
        )
        let inactiveIDs = ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: [
                status(
                    for: forecast,
                    resolution: .skipped
                )
            ]
        )
        let filteredForecasts = [forecast].filter {
            !inactiveIDs.contains($0.occurrenceID)
        }
        let activeTotal = EventAllocationTotals.activeTotal(
            allocations: [
                allocation(
                    for: forecast,
                    amount: 1_000
                )
            ],
            forecastEvents: filteredForecasts
        )

        XCTAssertTrue(filteredForecasts.isEmpty)
        XCTAssertEqual(activeTotal, 0, accuracy: 0.001)
    }

    func testOverdueUnresolvedOccurrenceStaysActive() {
        let now = date(2026, 7, 21)
        let forecast = singleExpenseForecast(
            amount: 1_000,
            date: date(2026, 7, 20),
            now: now
        )
        let activeTotal = EventAllocationTotals.activeTotal(
            allocations: [
                allocation(
                    for: forecast,
                    amount: 500
                )
            ],
            forecastEvents: [forecast]
        )

        XCTAssertEqual(
            ExpenseOccurrenceLifecycleResolver.lifecycle(
                for: forecast,
                statuses: [],
                now: now,
                calendar: calendar
            ),
            .overdue
        )
        XCTAssertEqual(activeTotal, 500, accuracy: 0.001)
    }

    func testMonthlyOccurrenceAllocationsAndStatusesAreIndependent() {
        let rent = event(
            name: "Rent",
            amount: 1_000,
            date: date(2026, 7, 1),
            frequency: .monthly
        )
        let baseCalculator = calculator(
            events: [rent],
            now: date(2026, 7, 1)
        )
        let forecasts = baseCalculator.forecastEvents
        let july = try! XCTUnwrap(
            forecasts.first {
                dateKey($0.occurrenceDate) == "2026-07-01"
            }
        )
        let august = try! XCTUnwrap(
            forecasts.first {
                dateKey($0.occurrenceDate) == "2026-08-01"
            }
        )
        let julyAllocation = allocation(
            for: july,
            amount: 400
        )

        XCTAssertNotEqual(july.occurrenceID, august.occurrenceID)
        XCTAssertEqual(
            EventAllocationTotals.activeTotal(
                allocations: [julyAllocation],
                forecastEvents: [july]
            ),
            400,
            accuracy: 0.001
        )
        XCTAssertEqual(
            EventAllocationTotals.activeTotal(
                allocations: [julyAllocation],
                forecastEvents: [august]
            ),
            0,
            accuracy: 0.001
        )

        let inactiveIDs = ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: [
                status(
                    for: july,
                    resolution: .paid
                )
            ]
        )
        let filteredCalculator = calculator(
            events: [rent],
            now: date(2026, 7, 1),
            inactiveOccurrenceIDs: inactiveIDs
        )

        XCTAssertFalse(
            filteredCalculator.forecastEvents.contains {
                $0.occurrenceID == july.occurrenceID
            }
        )
        XCTAssertTrue(
            filteredCalculator.forecastEvents.contains {
                $0.occurrenceID == august.occurrenceID
            }
        )
    }

    func testDashboardNextExpenseUsesFullAmountDueAndCoveredStatus() {
        let rent = event(
            name: "Rent",
            amount: 1_000,
            date: date(2026, 7, 21),
            frequency: .once
        )
        let forecast = try! XCTUnwrap(
            calculator(
                events: [rent],
                now: date(2026, 7, 20)
            )
            .nextExpense
        )
        let partialAllocation = allocation(
            for: forecast,
            amount: 400
        )
        let fullAllocation = allocation(
            for: forecast,
            amount: 1_000
        )

        XCTAssertEqual(forecast.event.amount, 1_000, accuracy: 0.001)
        XCTAssertFalse(isCovered(forecast, allocation: partialAllocation))
        XCTAssertTrue(isCovered(forecast, allocation: fullAllocation))
    }

    func testMonthlyJan29PreservesAnchorDayWhenPossible() {
        XCTAssertEqual(
            occurrenceKeys(
                frequency: .monthly,
                start: date(2026, 1, 29),
                now: date(2026, 1, 1),
                count: 4
            ),
            [
                "2026-01-29",
                "2026-02-28",
                "2026-03-29",
                "2026-04-29"
            ]
        )
    }

    func testMonthlyJan30PreservesAnchorDayWhenPossible() {
        XCTAssertEqual(
            occurrenceKeys(
                frequency: .monthly,
                start: date(2026, 1, 30),
                now: date(2026, 1, 1),
                count: 4
            ),
            [
                "2026-01-30",
                "2026-02-28",
                "2026-03-30",
                "2026-04-30"
            ]
        )
    }

    func testMonthlyJan31PreservesAnchorDayWhenPossible() {
        XCTAssertEqual(
            occurrenceKeys(
                frequency: .monthly,
                start: date(2026, 1, 31),
                now: date(2026, 1, 1),
                count: 5
            ),
            [
                "2026-01-31",
                "2026-02-28",
                "2026-03-31",
                "2026-04-30",
                "2026-05-31"
            ]
        )
    }

    func testQuarterlyJan31PreservesAnchorDayWhenPossible() {
        XCTAssertEqual(
            occurrenceKeys(
                frequency: .quarterly,
                start: date(2026, 1, 31),
                now: date(2026, 1, 1),
                count: 5
            ),
            [
                "2026-01-31",
                "2026-04-30",
                "2026-07-31",
                "2026-10-31",
                "2027-01-31"
            ]
        )
    }

    func testBiweeklyYearEndRepeatsEveryFourteenDays() {
        XCTAssertEqual(
            occurrenceKeys(
                frequency: .biweekly,
                start: date(2026, 12, 25),
                now: date(2026, 12, 24),
                count: 4
            ),
            [
                "2026-12-25",
                "2027-01-08",
                "2027-01-22",
                "2027-02-05"
            ]
        )
    }
}

private extension CoreFinancialCalculationsTests {

    func account(
        name: String = "Account",
        type: String,
        subtype: String? = nil,
        balance: Double
    ) -> PlaidAccount {
        PlaidAccount(
            account_id: UUID().uuidString,
            name: name,
            type: type,
            subtype: subtype,
            balances: PlaidBalance(
                available: balance,
                current: balance
            )
        )
    }

    func goal(
        currentAmount: Double,
        targetAmount: Double
    ) -> SavingsGoal {
        SavingsGoal(
            name: "Goal",
            targetAmount: targetAmount,
            currentAmount: currentAmount
        )
    }

    func event(
        id: UUID = UUID(),
        name: String = "Expense",
        amount: Double,
        date: Date,
        frequency: PlannerFrequency,
        type: PlannerEventType = .expense
    ) -> PlannerEvent {
        PlannerEvent(
            id: id,
            name: name,
            amount: amount,
            date: date,
            frequency: frequency,
            type: type
        )
    }

    func allocation(
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

    func status(
        for forecast: ForecastEvent,
        resolution: ExpenseOccurrenceResolution
    ) -> ExpenseOccurrenceStatus {
        ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.occurrenceDate,
            status: resolution
        )
    }

    func singleExpenseForecast(
        amount: Double,
        date: Date,
        now: Date? = nil
    ) -> ForecastEvent {
        let expense = event(
            amount: amount,
            date: date,
            frequency: .once
        )

        return calculator(
            events: [expense],
            now: now ?? date
        )
        .forecastEvents[0]
    }

    func calculator(
        events: [PlannerEvent],
        now: Date,
        totalAvailable: Double = 2_000,
        totalGoalAllocated: Double = 0,
        reserveBalance: Double = 0,
        protectedEventAllocations: Double = 0,
        inactiveOccurrenceIDs: Set<String> = []
    ) -> PlannerForecastCalculator {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: totalAvailable,
            totalGoalAllocated: totalGoalAllocated,
            reserveBalance: reserveBalance,
            protectedEventAllocations: protectedEventAllocations,
            includeFutureIncome: true,
            protectGoals: true,
            now: now,
            calendar: calendar,
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
    }

    func occurrenceKeys(
        frequency: PlannerFrequency,
        start: Date,
        now: Date,
        count: Int
    ) -> [String] {
        let recurringEvent = event(
            amount: 100,
            date: start,
            frequency: frequency
        )

        return Array(
            calculator(
                events: [recurringEvent],
                now: now
            )
            .forecastEvents
            .prefix(count)
            .map {
                dateKey($0.occurrenceDate)
            }
        )
    }

    func isCovered(
        _ forecast: ForecastEvent,
        allocation: EventAllocation
    ) -> Bool {
        allocation.allocatedAmount + 0.005 >= forecast.event.amount
    }

    func date(
        _ year: Int,
        _ month: Int,
        _ day: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        )!
    }

    func dateKey(
        _ date: Date
    ) -> String {
        let components = calendar.dateComponents(
            [
                .year,
                .month,
                .day
            ],
            from: date
        )

        return String(
            format: "%04d-%02d-%02d",
            components.year!,
            components.month!,
            components.day!
        )
    }
}
