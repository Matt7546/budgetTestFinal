import SwiftUI

struct LinkBankView: View {

    @EnvironmentObject var plaid: PlaidService
    @EnvironmentObject var navigation: AppNavigation

    @State private var showChecking = false
    @State private var showSavings = false
    @State private var showCredit = false
    @State private var showLoans = false

    private var checkingAccounts: [PlaidAccount] {
        plaid.accounts.filter {
            $0.type == "depository" &&
            ($0.subtype?.lowercased() != "savings")
        }
    }

    private var savingsAccounts: [PlaidAccount] {
        plaid.accounts.filter {
            $0.subtype?.lowercased() == "savings"
        }
    }

    private var creditAccounts: [PlaidAccount] {
        plaid.accounts.filter {
            $0.type == "credit"
        }
    }

    private var loanAccounts: [PlaidAccount] {
        plaid.accounts.filter {
            $0.type == "loan"
        }
    }

    var body: some View {

        ZStack {

            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 1.00),
                    Color(red: 0.92, green: 0.95, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {

                VStack(alignment: .leading, spacing: 24) {

                    // MARK: Header

                    VStack(alignment: .leading, spacing: 6) {

                        Text("Financial Accounts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Banking")
                            .font(
                                .system(
                                    size: 38,
                                    weight: .bold
                                )
                            )
                            .foregroundColor(
                                Color(
                                    red: 0.10,
                                    green: 0.14,
                                    blue: 0.22
                                )
                            )
                    }
                    .padding(.horizontal)

                    // MARK: Connect Button

                    Button {
                        plaid.createLinkToken()
                    } label: {

                        HStack {

                            Image(systemName: "link")

                            Text("Connect with Plaid")

                            Spacer()

                            Image(systemName: "plus.circle.fill")
                        }
                        .font(.headline)
                        .foregroundColor(
                            Color(
                                red: 0.10,
                                green: 0.14,
                                blue: 0.22
                            )
                        )
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(
                                    Color.white.opacity(0.85),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: .black.opacity(0.04),
                            radius: 20,
                            y: 10
                        )
                    }
                    .padding(.horizontal)

                    // MARK: Checking

                    AccountGroupHeader(
                        title: "Checking Accounts",
                        count: checkingAccounts.count,
                        balance: checkingAccounts.reduce(0.0) {
                            $0 + $1.balances.current
                        },
                        isExpanded: $showChecking
                    )
                    .padding(.horizontal)

                    if showChecking {

                        VStack(spacing: 12) {

                            ForEach(checkingAccounts) { account in
                                DetailedAccountCard(
                                    account: account
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    // MARK: Savings

                    AccountGroupHeader(
                        title: "Savings Accounts",
                        count: savingsAccounts.count,
                        balance: savingsAccounts.reduce(0.0) {
                            $0 + $1.balances.current
                        },
                        isExpanded: $showSavings
                    )
                    .padding(.horizontal)

                    if showSavings {

                        VStack(spacing: 12) {

                            ForEach(savingsAccounts) { account in
                                DetailedAccountCard(
                                    account: account
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    // MARK: Credit

                    AccountGroupHeader(
                        title: "Credit Cards",
                        count: creditAccounts.count,
                        balance: creditAccounts.reduce(0.0) {
                            $0 + abs($1.balances.current)
                        },
                        isExpanded: $showCredit
                    )
                    .padding(.horizontal)

                    if showCredit {

                        VStack(spacing: 12) {

                            ForEach(creditAccounts) { account in
                                DetailedAccountCard(
                                    account: account
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    // MARK: Loans

                    AccountGroupHeader(
                        title: "Loans",
                        count: loanAccounts.count,
                        balance: loanAccounts.reduce(0.0) {
                            $0 + abs($1.balances.current)
                        },
                        isExpanded: $showLoans
                    )
                    .padding(.horizontal)

                    if showLoans {

                        VStack(spacing: 12) {

                            ForEach(loanAccounts) { account in
                                DetailedAccountCard(
                                    account: account
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .sheet(isPresented: $plaid.isLinkOpen) {
            if let handler = plaid.linkHandler {
                PlaidLinkView(handler: handler)
            }
        }
        .onAppear {

            if navigation.expandChecking {
                showChecking = true
                navigation.expandChecking = false
            }

            if navigation.expandSavings {
                showSavings = true
                navigation.expandSavings = false
            }

            if navigation.expandCredit {
                showCredit = true
                navigation.expandCredit = false
            }

            if navigation.expandLoans {
                showLoans = true
                navigation.expandLoans = false
            }
        }
    }
}

struct AccountGroupHeader: View {

    let title: String
    let count: Int
    let balance: Double

    @Binding var isExpanded: Bool

    var body: some View {

        Button {

            withAnimation(
                .spring(
                    response: 0.35,
                    dampingFraction: 0.8
                )
            ) {
                isExpanded.toggle()
            }

        } label: {

            VStack(
                alignment: .leading,
                spacing: 6
            ) {

                HStack {

                    Text(title)
                        .font(
                            .system(
                                size: 24,
                                weight: .bold
                            )
                        )

                    Spacer()

                    Text("\(count)")
                        .font(
                            .system(
                                size: 24,
                                weight: .black
                            )
                        )

                    Image(
                        systemName:
                            isExpanded
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(.caption.bold())
                }

                Text(
                    "\(count) Account\(count == 1 ? "" : "s") • \(balance.formatted(.currency(code: "USD")))"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(
                    cornerRadius: 24
                )
                .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 24
                )
                .stroke(
                    Color.white.opacity(0.85),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(
            Color(
                red: 0.10,
                green: 0.14,
                blue: 0.22
            )
        )
    }
}
