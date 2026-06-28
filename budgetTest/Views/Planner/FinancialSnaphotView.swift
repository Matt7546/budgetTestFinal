import SwiftUI
import SwiftData

struct FinancialSnapshotView: View {

    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var plaid: PlaidService
    @Environment(\.dismiss) private var dismiss

    @Query
    private var events: [PlannerEvent]

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @Query
    private var debtPayoffBuckets: [DebtPayoffBucket]

    private var baseFinancialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: visibleBankAccounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance
        )
    }

    private var financialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: visibleBankAccounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance,
            upcomingExpensesSetAside: activeProtectedEventAllocations,
            debtPaymentsSetAside: totalDebtPayoffSetAside
        )
    }

    private var totalCash: Double {
        financialSummary.cash
    }

    private var totalDebt: Double {
        financialSummary.debt
    }

    private var totalGoals: Double {
        financialSummary.savingsGoalsSetAside
    }

    private var reserveBalance: Double {
        financialSummary.reserve
    }

    private var totalDebtPayoffSetAside: Double {
        debtPayoffBuckets.totalProtectedAmount
    }

    private var canShowBankData: Bool {
        !AppConfig.requiresAuthenticatedBankData || auth.isSignedIn
    }

    private var visibleBankAccounts: [PlaidAccount] {
        canShowBankData ? plaid.accounts : []
    }

    private var activeProtectedEventAllocations: Double {
        FinancialSummaryCalculator.activeUpcomingExpensesSetAside(
            allocations: allocations,
            forecastEvents: PlannerForecastCalculator(
                events: events,
                totalAvailable: baseFinancialSummary.safeToSpendBeforeUpcomingExpenses - totalDebtPayoffSetAside,
                totalGoalAllocated: baseFinancialSummary.savingsGoalsSetAside,
                reserveBalance: baseFinancialSummary.reserve,
                includeFutureIncome: true,
                protectGoals: true,
                inactiveOccurrenceIDs: inactiveOccurrenceIDs
            )
            .forecastEvents
        )
    }

    private var inactiveOccurrenceIDs: Set<String> {
        ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: occurrenceStatuses
        )
    }

    private var availableToSpend: Double {
        financialSummary.safeToSpend
    }

    var body: some View {

        SnapshotScreen(
            title: "Safe To Spend"
        ) {
            dismiss()
        } content: {
            SnapshotHeroCard(
                title: "Safe To Spend",
                value: availableToSpend,
                subtitle: "Cash minus protected money"
            )

            // MARK: Cash

            SnapshotPanel {
                SectionTitle(
                    "Cash Accounts",
                    font: .title3.bold()
                )

                ForEach(
                    visibleBankAccounts.cashAccounts
                ) { account in

                    MetricRow(
                        account.name,
                        value: account.cashBalanceValue
                    )
                }

                Divider()

                MetricRow(
                    "Total Cash",
                    value: totalCash,
                    labelWeight: .semibold,
                    valueWeight: .bold
                )
            }

            // MARK: Debt

            SnapshotPanel {
                SectionTitle(
                    "Debt",
                    font: .title3.bold()
                )

                ForEach(
                    visibleBankAccounts.debtAccounts
                ) { account in

                    MetricRow(
                        account.name,
                        value: account.debtBalanceValue
                    )
                }

                Divider()

                MetricRow(
                    "Total Debt",
                    value: totalDebt,
                    labelWeight: .semibold,
                    valueWeight: .bold
                )
            }

            // MARK: Savings Goals

            if !plaid.savingsGoals.isEmpty {

                SnapshotPanel {
                    SectionTitle(
                        "Savings Goals",
                        font: .title3.bold()
                    )

                    ForEach(plaid.savingsGoals) { goal in

                        MetricRow(
                            goal.name,
                            value: goal.currentAmount
                        )
                    }

                    Divider()

                    MetricRow(
                        "Savings Goals",
                        value: totalGoals,
                        labelWeight: .semibold,
                        valueWeight: .bold
                    )
                }
            }

            // MARK: Final Calculation

            SnapshotPanel(
                alignment: .center
            ) {
                MetricRow("Cash", value: totalCash)

                MetricRow("- Savings Goals", value: totalGoals)

                MetricRow("- Savings Reserve", value: reserveBalance)

                if activeProtectedEventAllocations > 0 {
                    MetricRow(
                        "- Upcoming Expenses",
                        value: activeProtectedEventAllocations
                    )
                }

                if totalDebtPayoffSetAside > 0 {
                    MetricRow(
                        "- Debt Payoff",
                        value: totalDebtPayoffSetAside
                    )
                }

                Divider()

                MetricRow(
                    "Safe To Spend",
                    value: availableToSpend,
                    labelFont: .headline,
                    valueFont: .headline.bold()
                )
            }
        }
    }


}

#Preview {
    FinancialSnapshotView()
}
