import SwiftUI

struct FinancialSnapshotView: View {

@EnvironmentObject var plaid: PlaidService
@Environment(\.dismiss) private var dismiss

private var totalCash: Double {
    plaid.accounts
        .filter {
            $0.type.lowercased() == "depository"
        }
        .reduce(0.0) { total, account in
            total + account.balances.current
        }
}

private var totalDebt: Double {
    plaid.accounts
        .filter {
            $0.type.lowercased() == "credit" ||
            $0.type.lowercased() == "loan"
        }
        .reduce(0.0) { total, account in
            total + abs(account.balances.current)
        }
}

private var totalGoals: Double {
    plaid.savingsGoals.reduce(0.0) {
        $0 + $1.currentAmount
    }
}

private var availableToSpend: Double {
    totalCash - totalDebt - totalGoals
}

var body: some View {

    NavigationStack {

        ScrollView {

            VStack(spacing: 24) {

                // MARK: Hero Card

                VStack(spacing: 8) {

                    Text("Available To Spend")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(
                        availableToSpend,
                        format: .currency(code: "USD")
                    )
                    .font(
                        .system(
                            size: 42,
                            weight: .bold
                        )
                    )

                    Text(
                        "Cash minus debt and goal allocations"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(.ultraThinMaterial)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 24
                    )
                )

                // MARK: Cash

                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {

                    Text("Cash Accounts")
                        .font(.title3.bold())

                    ForEach(
                        plaid.accounts.filter {
                            $0.type.lowercased() == "depository"
                        }
                    ) { account in

                        HStack {

                            Text(account.name)

                            Spacer()

                            Text(
                                account.balances.current,
                                format: .currency(code: "USD")
                            )
                        }
                    }

                    Divider()

                    HStack {

                        Text("Total Cash")
                            .fontWeight(.semibold)

                        Spacer()

                        Text(
                            totalCash,
                            format: .currency(code: "USD")
                        )
                        .fontWeight(.bold)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20
                    )
                )

                // MARK: Debt

                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {

                    Text("Debt")
                        .font(.title3.bold())

                    ForEach(
                        plaid.accounts.filter {
                            $0.type.lowercased() == "credit" ||
                            $0.type.lowercased() == "loan"
                        }
                    ) { account in

                        HStack {

                            Text(account.name)

                            Spacer()

                            Text(
                                abs(account.balances.current),
                                format: .currency(code: "USD")
                            )
                        }
                    }

                    Divider()

                    HStack {

                        Text("Total Debt")
                            .fontWeight(.semibold)

                        Spacer()

                        Text(
                            totalDebt,
                            format: .currency(code: "USD")
                        )
                        .fontWeight(.bold)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20
                    )
                )

                // MARK: Goals

                if !plaid.savingsGoals.isEmpty {

                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {

                        Text("Reserved For Goals")
                            .font(.title3.bold())

                        ForEach(plaid.savingsGoals) { goal in

                            HStack {

                                Text(goal.name)

                                Spacer()

                                Text(
                                    goal.currentAmount,
                                    format: .currency(code: "USD")
                                )
                            }
                        }

                        Divider()

                        HStack {

                            Text("Goal Allocations")
                                .fontWeight(.semibold)

                            Spacer()

                            Text(
                                totalGoals,
                                format: .currency(code: "USD")
                            )
                            .fontWeight(.bold)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 20
                        )
                    )
                }

                // MARK: Final Calculation

                VStack(spacing: 12) {

                    HStack {
                        Text("Cash")
                        Spacer()
                        Text(totalCash, format: .currency(code: "USD"))
                    }

                    HStack {
                        Text("- Debt")
                        Spacer()
                        Text(totalDebt, format: .currency(code: "USD"))
                    }

                    HStack {
                        Text("- Goals")
                        Spacer()
                        Text(totalGoals, format: .currency(code: "USD"))
                    }

                    Divider()

                    HStack {

                        Text("Available To Spend")
                            .font(.headline)

                        Spacer()

                        Text(
                            availableToSpend,
                            format: .currency(code: "USD")
                        )
                        .font(.headline.bold())
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20
                    )
                )
            }
            .padding()
        }
        .navigationTitle("Available")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {

            ToolbarItem(
                placement: .topBarTrailing
            ) {

                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}


}

#Preview {
FinancialSnapshotView()
}
