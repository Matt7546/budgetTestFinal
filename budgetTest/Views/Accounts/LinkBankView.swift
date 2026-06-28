import SwiftUI

struct LinkBankView: View {

    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var plaid: PlaidService
    @EnvironmentObject var navigation: AppNavigation

    let presentsLinkSheet: Bool

    init(
        presentsLinkSheet: Bool = true
    ) {
        self.presentsLinkSheet = presentsLinkSheet
    }

    @State private var showChecking = false
    @State private var showSavings = false
    @State private var showCredit = false
    @State private var showLoans = false

    private var canShowBankData: Bool {
        !AppConfig.requiresAuthenticatedBankData || auth.isSignedIn
    }

    private var visibleAccounts: [PlaidAccount] {
        canShowBankData ? plaid.accounts : []
    }

    private var checkingAccounts: [PlaidAccount] {
        visibleAccounts.checkingAccounts
    }

    private var savingsAccounts: [PlaidAccount] {
        visibleAccounts.savingsAccounts
    }

    private var creditAccounts: [PlaidAccount] {
        visibleAccounts.creditAccounts
    }

    private var loanAccounts: [PlaidAccount] {
        visibleAccounts.loanAccounts
    }

    private var accountsLastSyncedText: String {
        LinkedAccountsSyncFormatter.text(
            for: plaid.lastAccountsRefreshDate
        )
    }

    private var transactionsLastSyncedText: String? {
        guard let lastTransactionsRefreshDate = plaid.lastTransactionsRefreshDate else {
            return nil
        }

        return LinkedAccountsSyncFormatter.text(
            for: lastTransactionsRefreshDate
        )
    }

    @ViewBuilder
    var body: some View {
        if presentsLinkSheet {
            accountContent
                .sheet(isPresented: $plaid.isLinkOpen) {
                    if let handler = plaid.linkHandler {
                        PlaidLinkView(handler: handler)
                    }
                }
        } else {
            accountContent
        }
    }

    private var accountContent: some View {

        AppScreen(
            usesNavigationStack: false,
            contentPadding: .vertical
        ) {

                    // MARK: Header

                    VStack(alignment: .leading, spacing: 6) {

                        Text("Financial Accounts")
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)

                        Text("Linked Accounts")
                            .font(
                                .system(
                                    size: 38,
                                    weight: .bold
                                )
                            )
                            .foregroundColor(AppColors.primaryText)

                        if canShowBankData {
                            syncStatusView
                        }
                    }
                    .padding(.horizontal)

                    if !canShowBankData {

                        BankDataSignInRequiredCard(
                            message: "Sign in before connecting banks so Plaid data stays scoped to your Caldera account."
                        )
                        .padding(.horizontal)

                    } else if visibleAccounts.isEmpty {

                        EmptyStateView(
                            systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
                            title: "Connect your accounts",
                            description: "View balances, debt, savings, and cash in one organized place.",
                            primaryActionTitle: "Connect Account",
                            primaryAction: {
                                plaid.createLinkToken()
                            },
                            color: CalderaCategoryStyle.style(for: .bankAccount).primary
                        )
                        .padding(.horizontal)

                        refreshStatusCard
                            .padding(.horizontal)

                    } else {

                        refreshStatusCard
                            .padding(.horizontal)

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
                            lastSyncedText: accountsLastSyncedText,
                            style: CalderaCategoryStyle.style(for: .bankAccount),
                            isExpanded: $showChecking
                        )

                        // MARK: Savings

                        AccountGroupSection(
                            title: "Savings Accounts",
                            accounts: savingsAccounts,
                            balance: savingsAccounts.totalSavingsBalance,
                            lastSyncedText: accountsLastSyncedText,
                            style: CalderaCategoryStyle.style(for: .bankAccount),
                            isExpanded: $showSavings
                        )

                        // MARK: Credit

                        AccountGroupSection(
                            title: "Credit Cards",
                            accounts: creditAccounts,
                            balance: creditAccounts.totalDebtBalance,
                            lastSyncedText: accountsLastSyncedText,
                            style: CalderaCategoryStyle.style(for: .debtPayoff),
                            isExpanded: $showCredit
                        )

                        // MARK: Loans

                        AccountGroupSection(
                            title: "Loans",
                            accounts: loanAccounts,
                            balance: loanAccounts.totalDebtBalance,
                            lastSyncedText: accountsLastSyncedText,
                            style: CalderaCategoryStyle.style(for: .debtPayoff),
                            isExpanded: $showLoans
                        )
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

    private var syncStatusView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.accent)

                Text(accountsLastSyncedText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
            }

            if let transactionsLastSyncedText {
                Text("Transactions: \(transactionsLastSyncedText)")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.82))
            }
        }
        .padding(.top, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Account data \(accountsLastSyncedText)")
    }

    @ViewBuilder
    private var refreshStatusCard: some View {
        if let message = plaid.accountRefreshMessage {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                HStack(spacing: AppSpacing.small) {
                    IconBadge(
                        systemImage: "wifi.exclamationmark",
                        color: AppColors.warning,
                        size: 34,
                        iconSize: 14
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                        Text("Refresh paused")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.primaryText)

                        Text(message)
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SecondaryButton(
                    "Try Again",
                    systemImage: "arrow.clockwise",
                    cornerRadius: AppRadii.button,
                    fillsWidth: true
                ) {
                    plaid.refreshPlaidData()
                }
                .accessibilityLabel("Try refreshing accounts again")
            }
            .padding(AppSpacing.card)
            .glassCard(
                cornerRadius: AppRadii.panel,
                overlay: .gradient(
                    colors: [
                        AppColors.glassOverlayWhite,
                        AppColors.warning.opacity(0.06),
                        AppColors.glassOverlaySurface
                    ]
                ),
                shadow: AppShadows.softPanelCompact
            )
        }
    }

}

private enum LinkedAccountsSyncFormatter {

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let monthDayYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    static func text(
        for date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else {
            return "Not synced yet"
        }

        let secondsAgo = max(
            now.timeIntervalSince(date),
            0
        )

        if secondsAgo < 60 {
            return "Updated just now"
        }

        if secondsAgo < 3600 {
            let minutes = max(
                Int(secondsAgo / 60),
                1
            )

            return "Updated \(minutes) minute\(minutes == 1 ? "" : "s") ago"
        }

        if calendar.isDateInToday(date) {
            return "Updated today at \(timeFormatter.string(from: date))"
        }

        if calendar.isDateInYesterday(date) {
            return "Last updated yesterday"
        }

        let dateIsThisYear = calendar.component(
            .year,
            from: date
        ) == calendar.component(
            .year,
            from: now
        )

        if dateIsThisYear {
            return "Updated \(monthDayFormatter.string(from: date))"
        }

        return "Updated \(monthDayYearFormatter.string(from: date))"
    }
}
