extension PlannerView {

    var forecastCalculator: PlannerForecastCalculator {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: safeToSpendBeforeUpcomingAfterDebtPayoff,
            totalGoalAllocated: summary.totalGoalAllocated,
            reserveBalance: summary.reserveBalance,
            protectedEventAllocations: activeProtectedEventAllocations,
            includeFutureIncome: true,
            protectGoals: true,
            allocatedAmountProvider: { forecast in
                allocatedAmount(for: forecast)
            },
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
    }

    var activeProtectedEventAllocations: Double {
        FinancialSummaryCalculator.activeUpcomingExpensesSetAside(
            allocations: allocations,
            forecastEvents: PlannerForecastCalculator(
                events: events,
                totalAvailable: safeToSpendBeforeUpcomingAfterDebtPayoff,
                totalGoalAllocated: summary.totalGoalAllocated,
                reserveBalance: summary.reserveBalance,
                includeFutureIncome: true,
                protectGoals: true,
                inactiveOccurrenceIDs: inactiveOccurrenceIDs
            )
            .forecastEvents
        )
    }

    var totalDebtPayoffSetAside: Double {
        debtPayoffBuckets.totalProtectedAmount
    }

    var safeToSpendBeforeUpcomingAfterDebtPayoff: Double {
        summary.totalAvailable - totalDebtPayoffSetAside
    }

    var inactiveOccurrenceIDs: Set<String> {
        ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: occurrenceStatuses
        )
    }

    var forecastEvents: [ForecastEvent] {
        forecastCalculator.forecastEvents
    }

    var nextExpense: ForecastEvent? {
        forecastCalculator.nextExpense
    }

}
