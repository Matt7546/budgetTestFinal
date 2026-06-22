import SwiftUI

struct LinkBankView: View {

    @EnvironmentObject var plaid: PlaidService
    @EnvironmentObject var navigation: AppNavigation

    @State private var showChecking = false
    @State private var showSavings = false
    @State private var showCredit = false
    @State private var showLoans = false

    private var checkingAccounts: [PlaidAccount] {
        plaid.accounts.checkingAccounts
    }

    private var savingsAccounts: [PlaidAccount] {
        plaid.accounts.savingsAccounts
    }

    private var creditAccounts: [PlaidAccount] {
        plaid.accounts.creditAccounts
    }

    private var loanAccounts: [PlaidAccount] {
        plaid.accounts.loanAccounts
    }

    var body: some View {

        AppScreen(
            usesNavigationStack: false,
            contentPadding: .vertical
        ) {

                    // MARK: Header

                    VStack(alignment: .leading, spacing: 6) {

                        Text("Financial Accounts")
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)

                        Text("Banking")
                            .font(
                                .system(
                                    size: 38,
                                    weight: .bold
                                )
                            )
                            .foregroundColor(AppColors.primaryText)
                    }
                    .padding(.horizontal)

                    if plaid.accounts.isEmpty {

                        EmptyStateView(
                            systemImage: "building.columns.fill",
                            title: "Connect your accounts",
                            description: "View balances, debt, savings, and cash in one organized place.",
                            primaryActionTitle: "Connect Account",
                            primaryAction: {
                                plaid.createLinkToken()
                            },
                            color: AppColors.accent
                        )
                        .padding(.horizontal)

                    } else {

                        // MARK: Connect Button

                        SecondaryButton(
                            "Connect with Plaid",
                            systemImage: "link",
                            trailingSystemImage: "plus.circle.fill",
                            shadow: AppShadows.softCard
                        ) {
                            plaid.createLinkToken()
                        }
                        .padding(.horizontal)

                        // MARK: Checking

                        AccountGroupSection(
                            title: "Checking Accounts",
                            accounts: checkingAccounts,
                            balance: checkingAccounts.totalCashBalance,
                            isExpanded: $showChecking
                        )

                        // MARK: Savings

                        AccountGroupSection(
                            title: "Savings Accounts",
                            accounts: savingsAccounts,
                            balance: savingsAccounts.totalSavingsBalance,
                            isExpanded: $showSavings
                        )

                        // MARK: Credit

                        AccountGroupSection(
                            title: "Credit Cards",
                            accounts: creditAccounts,
                            balance: creditAccounts.totalDebtBalance,
                            isExpanded: $showCredit
                        )

                        // MARK: Loans

                        AccountGroupSection(
                            title: "Loans",
                            accounts: loanAccounts,
                            balance: loanAccounts.totalDebtBalance,
                            isExpanded: $showLoans
                        )
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
