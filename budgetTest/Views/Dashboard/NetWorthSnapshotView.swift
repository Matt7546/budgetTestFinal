import SwiftUI

struct NetWorthSnapshotView: View {

    @EnvironmentObject var plaid: PlaidService
    @Environment(\.dismiss) private var dismiss

    private var totalAssets: Double {
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

    private var netWorth: Double {
        totalAssets - totalDebt
    }

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(spacing: 24) {

                    VStack(spacing: 8) {

                        Text("Net Worth")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text(
                            netWorth,
                            format: .currency(code: "USD")
                        )
                        .font(
                            .system(
                                size: 42,
                                weight: .bold
                            )
                        )

                        Text(
                            "Assets minus liabilities"
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

                    VStack(alignment: .leading, spacing: 12) {

                        Text("Assets")
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

                            Text("Total Assets")
                                .fontWeight(.semibold)

                            Spacer()

                            Text(
                                totalAssets,
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

                    VStack(alignment: .leading, spacing: 12) {

                        Text("Liabilities")
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

                    VStack(spacing: 12) {

                        HStack {

                            Text("Assets")

                            Spacer()

                            Text(
                                totalAssets,
                                format: .currency(code: "USD")
                            )
                        }

                        HStack {

                            Text("- Debt")

                            Spacer()

                            Text(
                                totalDebt,
                                format: .currency(code: "USD")
                            )
                        }

                        Divider()

                        HStack {

                            Text("Net Worth")
                                .font(.headline)

                            Spacer()

                            Text(
                                netWorth,
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
            .navigationTitle("Net Worth")
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
    NetWorthSnapshotView()
}
