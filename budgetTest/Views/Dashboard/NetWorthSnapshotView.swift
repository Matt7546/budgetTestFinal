import SwiftUI

struct NetWorthSnapshotView: View {

    @EnvironmentObject var plaid: PlaidService
    @Environment(\.dismiss) private var dismiss

    private var totalAssets: Double {
        plaid.accounts.totalCashBalance
    }

    private var totalDebt: Double {
        plaid.accounts.totalDebtBalance
    }

    private var netWorth: Double {
        totalAssets - totalDebt
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
