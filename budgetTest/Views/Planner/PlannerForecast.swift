extension PlannerView {

    var expenseFundingComposition: UpcomingExpenseFundingComposition {
        UpcomingExpenseFundingComposition(
            events: events,
            allocations: allocations,
            occurrenceStatuses: occurrenceStatuses
        )
    }

    var forecastCalculator: PlannerForecastCalculator {
        expenseFundingComposition.forecastCalculator(
            events: events,
            totalAvailable: safeToSpendBeforeUpcomingAfterDebtPayoff,
            totalGoalAllocated: summary.totalGoalAllocated,
            reserveBalance: summary.reserveBalance,
            includeFutureIncome: true,
            protectGoals: true,
            allocatedAmountProvider: { forecast in
                allocatedAmount(for: forecast)
            },
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
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
