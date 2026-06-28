import Foundation

struct FinancialSummary: Equatable {

    let cash: Double
    let checking: Double
    let savings: Double
    let debt: Double
    let netWorth: Double
    let savingsGoalsSetAside: Double
    let reserve: Double
    let upcomingExpensesSetAside: Double
    let debtPaymentsSetAside: Double

    var protectedMoney: Double {
        reserve + savingsGoalsSetAside + upcomingExpensesSetAside + debtPaymentsSetAside
    }

    var safeToSpendBeforeUpcomingExpenses: Double {
        cash - savingsGoalsSetAside - reserve
    }

    var safeToSpend: Double {
        safeToSpendBeforeUpcomingExpenses - upcomingExpensesSetAside - debtPaymentsSetAside
    }
}

enum FinancialSummaryCalculator {

    static func calculate(
        accounts: [PlaidAccount],
        goals: [SavingsGoal],
        reserveBalance: Double = 0,
        upcomingExpensesSetAside: Double = 0,
        debtPaymentsSetAside: Double = 0
    ) -> FinancialSummary {
        let cash = accounts.reduce(0.0) {
            $0 + PlaidAccountBalancePolicy.cashBalance(for: $1)
        }
        let checking = accounts
            .filter {
                PlaidAccountClassification(account: $0).isChecking
            }
            .reduce(0.0) {
                $0 + PlaidAccountBalancePolicy.cashBalance(for: $1)
            }
        let savings = accounts
            .filter {
                PlaidAccountClassification(account: $0).isSavings
            }
            .reduce(0.0) {
                $0 + PlaidAccountBalancePolicy.cashBalance(for: $1)
            }
        let debt = accounts.reduce(0.0) {
            $0 + PlaidAccountBalancePolicy.debtBalance(for: $1)
        }
        let savingsGoalsSetAside = goals.reduce(0.0) {
            $0 + $1.currentAmount
        }

        return FinancialSummary(
            cash: cash,
            checking: checking,
            savings: savings,
            debt: debt,
            netWorth: cash - debt,
            savingsGoalsSetAside: savingsGoalsSetAside,
            reserve: reserveBalance,
            upcomingExpensesSetAside: upcomingExpensesSetAside,
            debtPaymentsSetAside: debtPaymentsSetAside
        )
    }

    static func activeUpcomingExpensesSetAside(
        allocations: [EventAllocation],
        forecastEvents: [ForecastEvent]
    ) -> Double {
        EventAllocationTotals.activeTotal(
            allocations: allocations,
            forecastEvents: forecastEvents
        )
    }
}
