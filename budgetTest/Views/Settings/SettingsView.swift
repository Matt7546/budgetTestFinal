import AuthenticationServices
import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var plaid: PlaidService
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.colorScheme) private var colorScheme

    @State private var showDisconnectConfirmation = false
    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var showPersonalizationEditor = false
    @State private var showAppTutorial = false
    @State private var showTermsOfUse = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountStatusMessage: String?

    @AppStorage("appearanceMode")
    private var appearanceMode = AppearanceMode.system.rawValue

    @AppStorage(AppPersonalizationKeys.paySchedulePreset)
    private var payScheduleRawValue = ""

    @AppStorage(AppPersonalizationKeys.focus)
    private var focusRawValue = ""

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://matt7546.github.io/budgetTestFinal/privacy.html")!
    }

    private var supportURL: URL {
        URL(string: "https://matt7546.github.io/budgetTestFinal/support.html")!
    }

    private var canShowBankData: Bool {
        !AppConfig.requiresAuthenticatedBankData || auth.isSignedIn
    }

    private var visibleBankAccounts: [PlaidAccount] {
        canShowBankData
            ? plaid.accounts.deduplicatedForDisplayAndTotals
            : []
    }

    private var connectionStatus: String {
        if !canShowBankData {
            return "Sign in with Apple to sync bank data"
        }

        if visibleBankAccounts.isEmpty {
            return "No bank accounts connected"
        }

        return "\(visibleBankAccounts.count) connected account\(visibleBankAccounts.count == 1 ? "" : "s")"
    }

    private var hasBankRefreshWarning: Bool {
        guard !visibleBankAccounts.isEmpty else {
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

    private var accountStatusMessage: String? {
        if hasBankRefreshWarning {
            return "Refresh failed — showing last saved balances. \(plaid.accountsLastUpdatedText)."
        }

        guard let message = plaid.accountRefreshMessage,
              !message.isEmpty else {
            return nil
        }

        return message
    }

    private var plaidRefreshButtonTitle: String {
        if plaid.isRefreshingPlaidData {
            return "Refreshing…"
        }

        if let message = plaid.manualPlaidRefreshMessage?.lowercased(),
           message.contains("refresh failed") {
            return "Try Again"
        }

        return "Refresh Bank Data"
    }

    private var manualRefreshStatusTitle: String {
        guard let message = plaid.manualPlaidRefreshMessage?.lowercased(),
              message.contains("refresh failed") else {
            return plaid.isRefreshingPlaidData ? "Refreshing…" : "Refresh Status"
        }

        return "Refresh failed"
    }

    private var manualRefreshStatusColor: Color {
        guard let message = plaid.manualPlaidRefreshMessage?.lowercased(),
              message.contains("refresh failed") else {
            return plaid.isRefreshingPlaidData
                ? AppColors.accent
                : AppColors.secondaryText
        }

        return AppColors.warning
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .more)

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.screen
                    ) {
                        header

                        SettingsAccountSyncSection(
                            authStatusTitle: authStatusTitle,
                            authStatusDescription: authStatusDescription,
                            isSignedIn: auth.isSignedIn,
                            authStatusMessage: auth.statusMessage,
                            isAuthFailed: auth.state == .failed,
                            linkedAccountsDescription: linkedAccountsDescription,
                            connectionStatus: connectionStatus,
                            hasVisibleBankAccounts: !visibleBankAccounts.isEmpty,
                            canShowBankData: canShowBankData,
                            accountStatusMessage: accountStatusMessage,
                            hasBankRefreshWarning: hasBankRefreshWarning,
                            connectAccount: {
                                plaid.createLinkToken()
                            },
                            disconnectAllBanks: {
                                showDisconnectConfirmation = true
                            },
                            authAction: {
                                authAction
                            },
                            plaidDataControls: {
                                plaidDataControls
                            }
                        )

                        SettingsPreferencesSection(
                            selectedAppearance: selectedAppearance,
                            personalizationDescription: personalizationDescription,
                            editPersonalization: {
                                showPersonalizationEditor = true
                            }
                        )

                        SettingsHelpSection(
                            supportURL: supportURL,
                            showTutorial: {
                                showAppTutorial = true
                            }
                        )

                        SettingsPrivacySection()

                        SettingsLegalSection(
                            privacyPolicyURL: privacyPolicyURL,
                            showTerms: {
                                showTermsOfUse = true
                            }
                        )

                        SettingsAboutSection(
                            appVersion: appVersion,
                            buildNumber: buildNumber
                        )

                        #if DEBUG
                        debugEnvironmentSection

                        debugLabSection

                        DeveloperQASection()
                        #endif

                        SettingsDangerZoneSection(
                            isSignedIn: auth.isSignedIn,
                            deleteAccount: {
                                deleteAccountStatusMessage = nil
                                showDeleteAccountConfirmation = true
                            }
                        )
                    }
                    .padding(.all)
                    .padding(.bottom, AppSpacing.emptyState)
                    .dismissKeyboardOnBackgroundTap()
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollContentBackground(.hidden)
                .dismissKeyboardOnBackgroundTap()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            plaid.refreshPlaidCapabilities()
        }
        .sheet(isPresented: $plaid.isLinkOpen) {
            if let handler = plaid.linkHandler {
                PlaidLinkView(handler: handler)
            }
        }
        .sheet(isPresented: $showDeleteAccountConfirmation) {
            DeleteAccountConfirmationSheet(
                isDeleting: isDeletingAccount,
                statusMessage: deleteAccountStatusMessage,
                onDelete: deleteAccount
            )
        }
        .sheet(isPresented: $showPersonalizationEditor) {
            PersonalizationEditorSheet()
        }
        .sheet(isPresented: $showTermsOfUse) {
            TermsOfUseView()
        }
        .fullScreenCover(isPresented: $showAppTutorial) {
            CalderaTutorialView()
        }
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
            Text("This removes connected bank access and clears saved account and transaction data on this device. Your Savings, Timeline events, and Cash Cushion stay in place.")
        }
        .confirmationDialog(
            "Sign Out?",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "Sign Out and Clear Local Data",
                role: .destructive
            ) {
                plaid.clearLocalFinancialDataForSignOut()
                auth.signOut()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing out removes local financial data from this device, including goals, Cash Cushion, timeline events, Debt Payoff plans, saved bank accounts, and transactions. Bank data can refresh again after signing back in.")
        }
    }

    private var selectedAppearance: Binding<AppearanceMode> {
        Binding(
            get: {
                AppearanceMode(rawValue: appearanceMode) ?? .system
            },
            set: {
                appearanceMode = $0.rawValue
            }
        )
    }

    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text("Control Center")
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppColors.secondaryText)

            Text("More")
                .font(
                    .system(
                        size: 38,
                        weight: .bold
                    )
                )
                .foregroundColor(AppColors.primaryText)
        }
    }

    @ViewBuilder
    private var authAction: some View {
        switch auth.state {
        case .signedIn:
            SecondaryButton(
                "Sign Out",
                systemImage: "rectangle.portrait.and.arrow.right",
                cornerRadius: AppRadii.button,
                fillsWidth: true
            ) {
                showSignOutConfirmation = true
            }
            .accessibilityLabel("Sign out of \(AppBrand.shortName) account")

        case .signingIn:
            HStack(spacing: AppSpacing.small) {
                ProgressView()
                    .tint(AppColors.accent)

                Text("Working on your account…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.xSmall)

        case .signedOut,
                .failed:
            SignInWithAppleButton(
                .signIn,
                onRequest: auth.configureAppleRequest,
                onCompletion: auth.handleAppleCompletion
            )
            .signInWithAppleButtonStyle(
                colorScheme == .dark ? .white : .black
            )
            .frame(height: 48)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AppRadii.button,
                    style: .continuous
                )
            )
            .accessibilityLabel("Sign in with Apple")
        }
    }

    private var authStatusTitle: String {
        switch auth.state {
        case .signedIn:
            return "Signed In"

        case .signingIn:
            return "Checking your account"

        case .failed:
            return "Sign in for bank sync"

        case .signedOut:
            return "Sign in for bank sync"
        }
    }

    private var authStatusDescription: String {
        if let user = auth.user,
           auth.isSignedIn {
            return user.displayName
        }

        return "You can plan locally, but bank sync requires Sign in with Apple."
    }

    private var personalizationDescription: String {
        let paySchedule = AppPersonalization.payScheduleTitle(
            from: payScheduleRawValue
        )
        let focus = AppPersonalization.focusTitle(
            from: focusRawValue
        )

        return "Pay schedule: \(paySchedule) · Focus: \(focus)"
    }

    #if DEBUG
    private var debugEnvironmentSection: some View {
        SettingsSection(
            title: "Environment",
            systemImage: "server.rack",
            color: AppColors.accent
        ) {
            SettingsValueRow(
                title: "Mode",
                value: AppConfig.environmentDisplayName,
                systemImage: "switch.2",
                color: AppColors.accent
            )

            Divider()

            SettingsValueRow(
                title: "Backend",
                value: AppConfig.backendBaseURL.host ?? "Unknown",
                systemImage: "network",
                color: AppColors.secondaryText
            )

            Divider()

            SettingsValueRow(
                title: "Plaid",
                value: AppConfig.expectedPlaidEnvironment.capitalized,
                systemImage: "building.columns.fill",
                color: AppColors.protected
            )

            if !AppConfig.debugConfigurationWarnings.isEmpty {
                Divider()

                ForEach(
                    AppConfig.debugConfigurationWarnings,
                    id: \.self
                ) { warning in
                    SettingsInfoRow(
                        title: "Configuration Warning",
                        description: warning,
                        systemImage: "exclamationmark.triangle.fill",
                        color: AppColors.warning
                    )
                }
            }
        }
    }

    private var debugLabSection: some View {
        SettingsSection(
            title: "Lab",
            systemImage: "testtube.2",
            color: CalderaCategoryStyle.style(for: .safeToSpend).primary
        ) {
            NavigationLink {
                ModularDashboardLabView()
            } label: {
                SettingsNavigationRow(
                    title: "Modular Dashboard Lab",
                    description: "Prototype editable dashboard tiles without changing production.",
                    systemImage: "square.grid.2x2.fill",
                    color: CalderaCategoryStyle.style(for: .safeToSpend).primary
                )
            }
            .buttonStyle(.plain)
        }
    }

    #endif

    private var plaidDataControls: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            SettingsInfoRow(
                title: "Bank Data Refresh",
                description: "During TestFlight, linked account data updates only when you refresh manually.",
                systemImage: "arrow.clockwise.circle.fill",
                color: AppColors.accent
            )

            VStack(spacing: AppSpacing.small) {
                SettingsRefreshStatusRow(
                    title: "Accounts",
                    value: plaid.accountsLastUpdatedText,
                    systemImage: "building.columns.fill",
                    color: CalderaCategoryStyle.style(for: .bankAccount).primary
                )

                if plaid.backendTransactionsEnabled {
                    SettingsRefreshStatusRow(
                        title: "Transactions",
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

            #if DEBUG
            SettingsValueRow(
                title: "Plaid calls this session",
                value: "\(plaid.plaidCallsThisSession)",
                systemImage: "number.circle.fill",
                color: AppColors.secondaryText
            )

            if let lastPlaidCallSummary = plaid.lastPlaidCallSummary {
                SettingsInfoRow(
                    title: "Last Plaid call",
                    description: lastPlaidCallSummary,
                    systemImage: "clock.fill",
                    color: AppColors.secondaryText
                )
            }
            #endif

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
        }
    }

    private var linkedAccountsDescription: String {
        if !canShowBankData {
            return "Sign in to manage banks, cards, and balances"
        }

        if visibleBankAccounts.isEmpty {
            return "Manage banks, cards, and balances"
        }

        return "\(visibleBankAccounts.count) connected account\(visibleBankAccounts.count == 1 ? "" : "s") • \(plaid.accountsLastUpdatedText)"
    }

    private func deleteAccount() {
        guard auth.isSignedIn else {
            deleteAccountStatusMessage = "Sign in with Apple before deleting your account."
            return
        }

        isDeletingAccount = true
        deleteAccountStatusMessage = nil

        Task { @MainActor in
            do {
                try await auth.deleteAccount()
                plaid.clearLocalFinancialDataForSignOut()
                isDeletingAccount = false
                showDeleteAccountConfirmation = false
            } catch {
                isDeletingAccount = false
                deleteAccountStatusMessage = auth.statusMessage ?? "Couldn’t delete your account. Try again."
            }
        }
    }

}

private struct DeleteAccountConfirmationSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""

    let isDeleting: Bool
    let statusMessage: String?
    let onDelete: () -> Void

    private var canDelete: Bool {
        confirmationText
            .trimmingCharacters(in: .whitespacesAndNewlines) == "DELETE" &&
            !isDeleting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .more)

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.large
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: AppSpacing.medium
                        ) {
                            CalderaGradientIcon(
                                systemImage: "trash.fill",
                                colors: CalderaVisualStyle.iconGradient(
                                    for: AppColors.negative
                                ),
                                size: 46,
                                iconSize: 20
                            )

                            VStack(
                                alignment: .leading,
                                spacing: AppSpacing.xSmall
                            ) {
                                Text("Delete your \(AppBrand.shortName) account?")
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(AppColors.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text("This deletes your \(AppBrand.shortName) account, disconnects bank connections, revokes active sessions, and clears local financial data from this device. This cannot be undone.")
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(AppSpacing.card)
                        .calderaGlassCard(
                            cornerRadius: AppRadii.card,
                            fillOpacity: 0.90,
                            strokeOpacity: 0.76,
                            shadowOpacity: 0.035,
                            shadowRadius: 14,
                            shadowY: 6,
                            darkGlowColor: AppColors.negative
                        )

                        VStack(
                            alignment: .leading,
                            spacing: AppSpacing.small
                        ) {
                            Text("Type DELETE to confirm.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppColors.primaryText)

                            TextField(
                                "DELETE",
                                text: $confirmationText
                            )
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .disabled(isDeleting)
                            .onSubmit {
                                if canDelete {
                                    onDelete()
                                }
                            }
                            .font(.headline)
                            .foregroundColor(AppColors.primaryText)
                            .padding()
                            .background(
                                RoundedRectangle(
                                    cornerRadius: AppRadii.field,
                                    style: .continuous
                                )
                                .fill(AppColors.glassOverlaySurface)
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: AppRadii.field,
                                    style: .continuous
                                )
                                .stroke(
                                    AppColors.negative.opacity(0.25),
                                    lineWidth: 1
                                )
                            }

                            if let statusMessage,
                               !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundColor(AppColors.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(AppSpacing.card)
                        .calderaGlassCard(
                            cornerRadius: AppRadii.card,
                            fillOpacity: 0.90,
                            strokeOpacity: 0.76,
                            shadowOpacity: 0.035,
                            shadowRadius: 14,
                            shadowY: 6,
                            darkGlowColor: AppColors.negative
                        )
                    }
                    .padding(.horizontal, AppSpacing.regular)
                    .padding(.top, AppSpacing.large)
                    .padding(.bottom, AppSpacing.emptyState + AppSpacing.screen)
                    .dismissKeyboardOnBackgroundTap()
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollContentBackground(.hidden)
                .dismissKeyboardOnBackgroundTap()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isDeleting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.small) {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        HStack(spacing: AppSpacing.small) {
                            if isDeleting {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(isDeleting ? "Deleting…" : "Delete Account")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            RoundedRectangle(
                                cornerRadius: AppRadii.button,
                                style: .continuous
                            )
                            .fill(AppColors.negative)
                        )
                    }
                    .disabled(!canDelete)
                    .opacity(canDelete ? 1 : 0.55)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .keyboardDismissToolbar()
        }
    }
}
