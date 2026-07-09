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
    @State private var showDisconnectConfirmation = false

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
           message.contains("refresh failed") || message.contains("need refreshing") {
            return true
        }

        return false
    }

    private var refreshStatusMessage: String? {
        if hasRefreshFailureWithSavedBalances {
            return "Some balances may need refreshing. Showing last saved balances."
        }

        guard let message = plaid.accountRefreshMessage,
              !message.isEmpty else {
            return nil
        }

        return message
    }

    private var syncStatusText: String {
        if plaid.isRefreshingPlaidData {
            return "Refreshing linked balances…"
        }

        if hasRefreshFailureWithSavedBalances {
            return "Some balances may need refreshing. Showing last saved balances."
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

    private var plaidRefreshButtonTitle: String {
        if plaid.isRefreshingPlaidData {
            return "Refreshing…"
        }

        if hasRefreshFailureWithSavedBalances {
            return "Try Again"
        }

        return "Refresh Bank Data"
    }

    private var manualRefreshStatusTitle: String {
        if hasRefreshFailureWithSavedBalances {
            return "Balances may need refreshing"
        }

        return plaid.isRefreshingPlaidData ? "Refreshing…" : "Refresh Status"
    }

    private var manualRefreshStatusColor: Color {
        if hasRefreshFailureWithSavedBalances {
            return AppColors.warning
        }

        return plaid.isRefreshingPlaidData
            ? AppColors.accent
            : AppColors.secondaryText
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
            backgroundStyle: .page(.more),
            contentPadding: .vertical
        ) {

                    // MARK: Header

                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        CalderaPageHeader(
                            eyebrow: "Bank Sync",
                            title: "Linked Accounts",
                            titleAccessory: {
                                ContextHelpButton(
                                    title: "Bank Sync",
                                    bodyText: "Linked balances help estimate Available to Spend. Set Aside money stays in your bank account and is managed inside \(AppBrand.shortName).",
                                    footnote: "Balances update when you refresh Bank Sync. \(AppBrand.shortName) does not move money or make payments."
                                )
                            }
                        )

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
                            message: "After Sign in with Apple, you can connect banks and cards. Your Linked Accounts will appear here."
                        )
                        .padding(.horizontal)

                    } else if visibleAccounts.isEmpty {

                        EmptyStateView(
                            systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
                            title: "No accounts connected yet",
                            description: "Connect accounts to show linked balances. You can do this later.",
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

                        bankSyncControlsCard
                            .padding(.horizontal)

                        refreshStatusCard
                            .padding(.horizontal)

                        if let bankSyncChangeSummary = plaid.latestBankSyncChangeSummary {
                            bankSyncChangeCard(
                                bankSyncChangeSummary
                            )
                            .padding(.horizontal)
                        }

                        // MARK: Connect Button

                        SecondaryButton(
                            "Connect Accounts",
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
        .calderaTopScrollFade(mood: .more)
        .confirmationDialog(
            "Disconnect all bank connections?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect All Banks", role: .destructive) {
                plaid.disconnectBank()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes connected bank access and clears saved account and recent activity data on this device. Your Set Aside items, Upcoming Expenses, and Cash Cushion stay in place.")
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
                Text("Recent activity: \(transactionsLastSyncedText)")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.82))
            }
        }
        .padding(.top, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Account data \(syncStatusText)")
    }

    private var bankSyncControlsCard: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                IconBadge(
                    systemImage: "arrow.clockwise.circle.fill",
                    color: CalderaCategoryStyle.style(for: .bankAccount).primary,
                    size: 34,
                    iconSize: 14
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Bank Sync controls")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text("Refresh linked balances when you want Caldera to update your spending picture.")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: AppSpacing.small) {
                SettingsRefreshStatusRow(
                    title: "Linked balances",
                    value: plaid.accountsLastUpdatedText,
                    systemImage: "building.columns.fill",
                    color: CalderaCategoryStyle.style(for: .bankAccount).primary
                )

                if plaid.backendTransactionsEnabled {
                    SettingsRefreshStatusRow(
                        title: "Recent activity",
                        value: plaid.transactionsLastUpdatedText,
                        systemImage: "list.bullet.rectangle",
                        color: AppColors.secondaryText
                    )
                }
            }

            if let message = plaid.manualPlaidRefreshMessage,
               !message.isEmpty {
                SettingsInfoRow(
                    title: manualRefreshStatusTitle,
                    description: message,
                    systemImage: plaid.isRefreshingPlaidData
                        ? "arrow.clockwise"
                        : "info.circle.fill",
                    color: manualRefreshStatusColor
                )
            }

            PrimaryButton(
                plaidRefreshButtonTitle,
                systemImage: "arrow.clockwise",
                trailingSystemImage: nil,
                cornerRadius: AppRadii.button,
                isDisabled: !canShowBankData || plaid.isRefreshingPlaidData,
                fillsWidth: true
            ) {
                plaid.refreshPlaidDataFromSettings()
            }
            .accessibilityLabel(plaidRefreshButtonTitle)

            DestructiveButton(
                "Disconnect All Banks",
                systemImage: "xmark.circle.fill",
                cornerRadius: AppRadii.button
            ) {
                showDisconnectConfirmation = true
            }
            .accessibilityLabel("Disconnect all linked banks")
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
                        Text(hasRefreshFailureWithSavedBalances ? "Balances may need refreshing" : "Bank Sync status")
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
                                ? "\(accountsLastSyncedText). Try refreshing again when you're ready."
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
                    Text("Connect accounts to show linked balances when you're ready.")
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

    private func bankSyncChangeCard(
        _ summary: BankSyncChangeSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                IconBadge(
                    systemImage: "arrow.left.arrow.right.circle.fill",
                    color: CalderaCategoryStyle.style(for: .bankAccount).primary,
                    size: 34,
                    iconSize: 14
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("What changed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text("After your latest Bank Sync refresh.")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if summary.hasMeaningfulChanges {
                VStack(spacing: AppSpacing.small) {
                    ForEach(
                        Array(summary.changedAccounts.prefix(4))
                    ) { change in
                        bankSyncChangeRow(
                            change
                        )
                    }
                }

                if summary.changedAccounts.count > 4 {
                    Text("Showing 4 of \(summary.changedAccounts.count) changed accounts.")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.82))
                }
            } else {
                Text("No major balance changes since the last refresh.")
                    .font(.caption.weight(.medium))
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

    private func bankSyncChangeRow(
        _ change: BankSyncBalanceChange
    ) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.small) {
            VStack(alignment: .leading, spacing: 3) {
                Text(change.accountLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let institutionLabel = change.institutionLabel {
                    Text(institutionLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AppSpacing.small)

            VStack(alignment: .trailing, spacing: 3) {
                Text(bankSyncChangeDeltaText(change))
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .multilineTextAlignment(.trailing)

                Text("\(AppFormatters.currency(change.balanceAfter)) now")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.82))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(AppSpacing.medium)
        .background(
            RoundedRectangle(
                cornerRadius: AppRadii.control,
                style: .continuous
            )
            .fill(AppColors.card.opacity(0.54))
        )
    }

    private func bankSyncChangeDeltaText(
        _ change: BankSyncBalanceChange
    ) -> String {
        let sign = change.delta >= 0 ? "+" : "-"
        let amount = AppFormatters.currency(
            abs(change.delta)
        )

        return "Changed by \(sign)\(amount)"
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

                Text("Set Aside money stays in your bank account and is managed inside \(AppBrand.shortName). Linked balances update when you refresh Bank Sync.")
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
