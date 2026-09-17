extension PlannerView {

    var plannerFinancialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: canUseBankDataForPlanning
                ? plaid.financialSummaryAccounts
                : [],
            goals: plaid.savingsGoals(
                authenticatedUserID: auth.user?.id
            ),
            reserveBalance: plaid.reserveBalance(
                authenticatedUserID: auth.user?.id
            )
        )
    }

    var canUseBankDataForPlanning: Bool {
        !AppConfig.requiresAuthenticatedBankData || auth.isSignedIn
    }

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
            totalGoalAllocated: plannerFinancialSummary.savingsGoalsSetAside,
            reserveBalance: plannerFinancialSummary.reserve,
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
        plannerFinancialSummary.safeToSpend - totalDebtPayoffSetAside
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
