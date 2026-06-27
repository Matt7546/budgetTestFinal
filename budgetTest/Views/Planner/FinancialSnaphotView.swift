import SwiftUI
import SwiftData

struct FinancialSnapshotView: View {

    @EnvironmentObject var plaid: PlaidService
    @Environment(\.dismiss) private var dismiss

    @Query
    private var events: [PlannerEvent]

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    private var totalCash: Double {
        plaid.accounts.totalCashBalance
    }

    private var totalDebt: Double {
        plaid.accounts.totalDebtBalance
    }

    private var totalGoals: Double {
        plaid.savingsGoals.totalSaved
    }

    private var reserveBalance: Double {
        plaid.reserveBalance
    }

    private var activeProtectedEventAllocations: Double {
        EventAllocationTotals.activeTotal(
            allocations: allocations,
            forecastEvents: PlannerForecastCalculator(
                events: events,
                totalAvailable: totalCash - totalGoals - reserveBalance,
                totalGoalAllocated: totalGoals,
                reserveBalance: reserveBalance,
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
        totalCash - totalGoals - reserveBalance - activeProtectedEventAllocations
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
                    plaid.accounts.cashAccounts
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
                    plaid.accounts.debtAccounts
                ) { account in

                    MetricRow(
                        account.name,
                        value: abs(account.balances.current)
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
