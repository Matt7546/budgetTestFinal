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
        canShowBankData
            ? plaid.accounts.deduplicatedForDisplayAndTotals
            : []
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
        PlaidDataFreshnessFormatter.text(
            for: plaid.lastAccountsRefreshDate
        )
    }

    private var transactionsLastSyncedText: String? {
        guard plaid.backendTransactionsEnabled else {
            return nil
        }

        guard let lastTransactionsRefreshDate = plaid.lastTransactionsRefreshDate else {
            return nil
        }

        return PlaidDataFreshnessFormatter.text(
            for: lastTransactionsRefreshDate
        )
    }

    private var hasRefreshFailureWithSavedBalances: Bool {
        guard !visibleAccounts.isEmpty else {
            return false
        }

        if let message = plaid.accountRefreshMessage?.lowercased(),
           message.contains("refresh") {
            return true
        }

        if let message = plaid.manualPlaidRefreshMessage?.lowercased(),
           message.contains("refresh failed") {
            return true
        }

        return false
    }

    private var refreshStatusMessage: String? {
        if hasRefreshFailureWithSavedBalances {
            return "Refresh failed — showing last saved balances."
        }

        guard let message = plaid.accountRefreshMessage,
              !message.isEmpty else {
            return nil
        }

        return message
    }

    private var syncStatusText: String {
        if plaid.isRefreshingPlaidData {
            return "Refreshing Bank Sync…"
        }

        if hasRefreshFailureWithSavedBalances {
            return "Refresh failed — showing last saved balances."
        }

        if !visibleAccounts.isEmpty {
            return "Connected • \(accountsLastSyncedText)"
        }

        return accountsLastSyncedText
    }

    private var syncStatusIcon: String {
        if hasRefreshFailureWithSavedBalances {
            return "wifi.exclamationmark"
        }

        return plaid.isRefreshingPlaidData
            ? "arrow.clockwise.circle.fill"
            : "checkmark.circle.fill"
    }

    private var syncStatusColor: Color {
        if hasRefreshFailureWithSavedBalances {
            return AppColors.warning
        }

        return plaid.isRefreshingPlaidData
            ? AppColors.accent
            : CalderaCategoryStyle.style(for: .covered).primary
    }

    private var canRetryRefreshFromStatusCard: Bool {
        guard let message = refreshStatusMessage?.lowercased() else {
            return false
        }

        return hasRefreshFailureWithSavedBalances || message.contains("refresh")
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

                        HStack(alignment: .center, spacing: AppSpacing.xxSmall) {
                            Text("Linked Accounts")
                                .font(
                                    .system(
                                        size: 38,
                                        weight: .bold
                                    )
                                )
                                .foregroundColor(AppColors.primaryText)

                            ContextHelpButton(
                                title: "Bank Sync",
                                bodyText: "Linked balances help estimate Available to Spend. Set Aside money stays in your bank account and is managed inside \(AppBrand.shortName).",
                                footnote: "Balances update when you refresh Bank Sync. \(AppBrand.shortName) does not move money or make payments."
                            )
                        }

                        if canShowBankData {
                            syncStatusView
                        }
                    }
                    .padding(.horizontal)

                    if canShowBankData {
                        bankSyncTrustNote
                            .padding(.horizontal)
                    }

                    if !canShowBankData {

                        BankDataSignInRequiredCard(
                            title: "Sign in to connect accounts",
                            message: "After Sign in with Apple, you can use Plaid to connect banks and cards. Your Linked Accounts will appear here."
                        )
                        .padding(.horizontal)

                    } else if visibleAccounts.isEmpty {

                        EmptyStateView(
                            systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
                            title: "No linked accounts yet",
                            description: "Link accounts to estimate Available to Spend from your balances.",
                            primaryActionTitle: "Connect Accounts",
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
            plaid.refreshPlaidCapabilities()

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
                Image(systemName: syncStatusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(syncStatusColor)

                Text(syncStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
            }

            if hasRefreshFailureWithSavedBalances {
                Text(accountsLastSyncedText)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.82))
            }

            if let transactionsLastSyncedText {
                Text("Transactions: \(transactionsLastSyncedText)")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.82))
            }
        }
        .padding(.top, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Account data \(syncStatusText)")
    }

    @ViewBuilder
    private var refreshStatusCard: some View {
        if let message = refreshStatusMessage {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                HStack(spacing: AppSpacing.small) {
                    IconBadge(
                        systemImage: hasRefreshFailureWithSavedBalances
                            ? "wifi.exclamationmark"
                            : "info.circle.fill",
                        color: hasRefreshFailureWithSavedBalances
                            ? AppColors.warning
                            : AppColors.accent,
                        size: 34,
                        iconSize: 14
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                        Text(hasRefreshFailureWithSavedBalances ? "Needs attention" : "Bank Sync status")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.primaryText)

                        Text(message)
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if canRetryRefreshFromStatusCard {
                    HStack(
                        alignment: .center,
                        spacing: AppSpacing.small
                    ) {
                        Text(
                            hasRefreshFailureWithSavedBalances
                                ? "\(accountsLastSyncedText). Try again when you're ready."
                                : "Try again when you're ready."
                        )
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: AppSpacing.small)

                        Button {
                            plaid.refreshPlaidDataFromSettings()
                        } label: {
                            HStack(spacing: AppSpacing.xxSmall) {
                                Image(systemName: "arrow.clockwise")

                                Text("Try again")
                            }
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, AppSpacing.medium)
                            .padding(.vertical, AppSpacing.xSmall)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppColors.accent.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(plaid.isRefreshingPlaidData)
                        .opacity(plaid.isRefreshingPlaidData ? 0.6 : 1.0)
                        .accessibilityLabel("Try refreshing bank data again")
                    }
                } else {
                    Text("Use Connect with Plaid when you're ready.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(AppSpacing.card)
            .calderaGlassCard(
                cornerRadius: AppRadii.panel,
                fillOpacity: 0.90,
                strokeOpacity: 0.76,
                shadowOpacity: 0.035,
                shadowRadius: 14,
                shadowY: 6,
                darkGlowColor: AppColors.warning
            )
        }
    }

    private var bankSyncTrustNote: some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            IconBadge(
                systemImage: "info.circle.fill",
                color: CalderaCategoryStyle.style(for: .bankAccount).primary,
                size: 34,
                iconSize: 14
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Linked balances help estimate Available to Spend")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text("Set Aside money stays in your bank account and is managed inside \(AppBrand.shortName). Balances show the latest linked refresh, not a real-time bank lookup.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.88,
            strokeOpacity: 0.72,
            shadowOpacity: 0.026,
            shadowRadius: 12,
            shadowY: 5,
            darkGlowColor: CalderaCategoryStyle.style(for: .bankAccount).primary
        )
    }

}
