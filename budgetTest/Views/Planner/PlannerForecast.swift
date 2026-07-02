import SwiftUI

extension PlannerForecastStatus {

    var color: Color {
        switch self {
        case .shortfallBefore:
            return AppColors.negative

        case .lowBufferUntilPayday:
            return AppColors.warning

        case .protectedByReserve:
            return AppColors.protected

        case .nextExpenseCovered,
                .enoughForNextExpense:
            return AppColors.spendable

        case .safeThrough,
                .noUpcomingExpenses:
            return AppColors.spendable
        }
    }
}

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

    var plannerAvailable: Double {
        forecastCalculator.plannerAvailable
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

    var upcomingBills: Double {
        forecastCalculator.upcomingBills
    }

    var safeToSpend: Double {
        forecastCalculator.safeToSpend
    }

    var nextExpenseRemainingAmount: Double {
        guard let nextExpense else {
            return 0
        }

        return max(
            nextExpense.event.amount - allocatedAmount(
                for: nextExpense
            ),
            0
        )
    }

    var expensesCovered: Int {
        forecastCalculator.expensesCovered
    }

    var plannerStatusText: String {
        guard let nextExpense else {
            return "No Upcoming Expenses"
        }

        if nextExpenseRemainingAmount <= 0.005 {
            return "Next expense covered"
        }

        if safeToSpend >= nextExpenseRemainingAmount {
            return "Enough available for next expense"
        }

        if safeToSpend < 0 {
            return "Needs money before \(nextExpense.event.name)"
        }

        return "Low buffer before payday"
    }

    var plannerStatusColor: Color {
        guard nextExpense != nil else {
            return AppColors.spendable
        }

        if nextExpenseRemainingAmount <= 0.005 ||
            safeToSpend >= nextExpenseRemainingAmount {
            return AppColors.spendable
        }

        if safeToSpend < 0 {
            return AppColors.negative
        }

        return AppColors.warning
    }

    func projectedAvailable(
        after forecast: ForecastEvent
    ) -> Double {
        forecastCalculator.projectedAvailable(
            after: forecast
        )
    }
}
