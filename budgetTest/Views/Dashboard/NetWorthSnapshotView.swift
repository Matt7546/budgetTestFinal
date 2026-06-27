import SwiftUI

struct NetWorthSnapshotView: View {

    @EnvironmentObject var plaid: PlaidService
    @Environment(\.dismiss) private var dismiss

    private var financialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: plaid.accounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance
        )
    }

    private var totalAssets: Double {
        financialSummary.cash
    }

    private var totalDebt: Double {
        financialSummary.debt
    }

    private var netWorth: Double {
        financialSummary.netWorth
    }

    var body: some View {

        SnapshotScreen(
            title: "Net Worth"
        ) {
            dismiss()
        } content: {
            SnapshotHeroCard(
                title: "Net Worth",
                value: netWorth,
                subtitle: "Assets minus liabilities"
            )

            SnapshotPanel {
                SectionTitle(
                    "Assets",
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
                    "Total Assets",
                    value: totalAssets,
                    labelWeight: .semibold,
                    valueWeight: .bold
                )
            }

            SnapshotPanel {
                SectionTitle(
                    "Liabilities",
                    font: .title3.bold()
                )

                ForEach(
                    plaid.accounts.debtAccounts
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

            SnapshotPanel(
                alignment: .center
            ) {
                MetricRow(
                    "Assets",
                    value: totalAssets
                )

                MetricRow(
                    "- Debt",
                    value: totalDebt
                )

                Divider()

                MetricRow(
                    "Net Worth",
                    value: netWorth,
                    labelFont: .headline,
                    valueFont: .headline.bold()
                )
            }
        }
    }
}

#Preview {
    NetWorthSnapshotView()
}
