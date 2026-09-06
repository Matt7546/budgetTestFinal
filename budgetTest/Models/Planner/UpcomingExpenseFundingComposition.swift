import Foundation

/// Wires the authoritative unresolved-expense snapshot into production
/// financial surfaces. This type owns no state and performs no mutations.
struct UpcomingExpenseFundingComposition {

    let snapshot: UpcomingExpenseFundingSnapshot

    init(
        events: [PlannerEvent],
        allocations: [EventAllocation],
        occurrenceStatuses: [ExpenseOccurrenceStatus]
    ) {
        snapshot = UpcomingExpenseFundingSnapshot(
            events: events,
            allocations: allocations,
            occurrenceStatuses: occurrenceStatuses
        )
    }

    var totalSetAside: Double {
        snapshot.totalSetAside
    }

    func dashboardFinancialSummary(
        accounts: [PlaidAccount],
        goals: [SavingsGoal],
        reserveBalance: Double,
        debtPaymentsSetAside: Double
    ) -> FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: accounts,
            goals: goals,
            reserveBalance: reserveBalance,
            upcomingExpensesSetAside: totalSetAside,
            debtPaymentsSetAside: debtPaymentsSetAside
        )
    }

    func forecastCalculator(
        events: [PlannerEvent],
        totalAvailable: Double,
        totalGoalAllocated: Double,
        reserveBalance: Double = 0,
        includeFutureIncome: Bool,
        protectGoals: Bool,
        now: Date = Date(),
        calendar: Calendar = .current,
        allocatedAmountProvider: ((ForecastEvent) -> Double)? = nil,
        inactiveOccurrenceIDs: Set<String> = []
    ) -> PlannerForecastCalculator {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: totalAvailable,
            totalGoalAllocated: totalGoalAllocated,
            reserveBalance: reserveBalance,
            protectedEventAllocations: totalSetAside,
            includeFutureIncome: includeFutureIncome,
            protectGoals: protectGoals,
            now: now,
            calendar: calendar,
            allocatedAmountProvider: allocatedAmountProvider,
            inactiveOccurrenceIDs: inactiveOccurrenceIDs,
            fundingSnapshot: snapshot
        )
    }
}
