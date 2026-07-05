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
                CalderaPageBackground(
                    mood: .more,
                    isActive: navigation.selectedTab == 3
                )

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.screen
                    ) {
                        header

                        accountBankSyncSection

                        appPreferencesSection

                        supportSection

                        privacySection

                        legalSection

                        aboutSection

                        #if DEBUG
                        debugEnvironmentSection

                        debugLabSection

                        DeveloperQASection()
                        #endif

                        dangerZoneSection
                    }
                    .padding(.all)
                    .padding(.bottom, AppSpacing.emptyState)
                    .dismissKeyboardOnBackgroundTap()
                }
                .scrollDismissesKeyboard(.interactively)
                .dismissKeyboardOnBackgroundTap()
            }
            .optionalTopScrollFade(isEnabled: true)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
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
            Text("This removes connected bank access and clears cached account and transaction data on this device. Your Savings, Timeline events, and Cash Cushion stay in place.")
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
            Text("Signing out removes local financial data from this device, including goals, Cash Cushion, timeline events, debt payoff plans, cached accounts, and transactions. Bank data can sync again after signing back in.")
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
            .accessibilityLabel("Sign out of Caldera account")

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

    private var accountBankSyncSection: some View {
        SettingsSection(
            title: "Account & Bank Sync",
            systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
            color: CalderaCategoryStyle.style(for: .bankAccount).primary
        ) {
            SettingsInfoRow(
                title: authStatusTitle,
                description: authStatusDescription,
                systemImage: auth.isSignedIn
                    ? "checkmark.seal.fill"
                    : "person.crop.circle.badge.plus",
                color: auth.isSignedIn
                    ? AppColors.spendable
                    : AppColors.accentSecondary
            )

            if let statusMessage = auth.statusMessage,
               !statusMessage.isEmpty {
                Divider()

                SettingsInfoRow(
                    title: "Account Status",
                    description: statusMessage,
                    systemImage: auth.state == .failed
                        ? "exclamationmark.triangle.fill"
                        : "info.circle.fill",
                    color: auth.state == .failed
                        ? AppColors.warning
                        : AppColors.secondaryText
                )
            }

            Divider()

            authAction

            Divider()

            NavigationLink {
                LinkBankView(
                    presentsLinkSheet: false
                )
                .navigationTitle("Linked Accounts")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsNavigationRow(
                    title: "Linked Accounts",
                    description: linkedAccountsDescription,
                    systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
                    color: CalderaCategoryStyle.style(for: .bankAccount).primary
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open linked accounts")

            Divider()

            SettingsInfoRow(
                title: "Bank Sync",
                description: connectionStatus,
                systemImage: visibleBankAccounts.isEmpty
                    ? "link.badge.plus"
                    : CalderaCategoryStyle.style(for: .covered).icon,
                color: visibleBankAccounts.isEmpty
                    ? CalderaCategoryStyle.style(for: .bankAccount).primary
                    : CalderaCategoryStyle.style(for: .covered).primary
            )

            if canShowBankData {
                Divider()

                plaidDataControls

                if let message = accountStatusMessage {
                    Divider()

                    SettingsInfoRow(
                        title: hasBankRefreshWarning ? "Refresh failed" : "Bank Data Status",
                        description: message,
                        systemImage: hasBankRefreshWarning
                            ? "wifi.exclamationmark"
                            : "info.circle.fill",
                        color: hasBankRefreshWarning
                            ? AppColors.warning
                            : AppColors.accent
                    )
                }
            }

            Divider()

            if !canShowBankData {
                SettingsInfoRow(
                    title: "Bank sync requires sign-in",
                    description: "Sign in before connecting banks so bank data stays tied to your Caldera account.",
                    systemImage: "person.crop.circle.badge.checkmark",
                    color: AppColors.accentSecondary
                )
            } else if visibleBankAccounts.isEmpty {
                PrimaryButton(
                    "Connect Account",
                    systemImage: "link",
                    trailingSystemImage: nil,
                    cornerRadius: AppRadii.button,
                    fillsWidth: true
                ) {
                    plaid.createLinkToken()
                }
            } else {
                DestructiveButton(
                    "Disconnect All Banks",
                    systemImage: "xmark.circle.fill",
                    cornerRadius: AppRadii.button
                ) {
                    showDisconnectConfirmation = true
                }
                .accessibilityLabel("Disconnect all linked banks")
            }
        }
    }

    private var appPreferencesSection: some View {
        SettingsSection(
            title: "App Preferences",
            systemImage: "moon.stars.fill",
            color: AppColors.accent
        ) {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                Text("Appearance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Picker(
                    "Appearance",
                    selection: selectedAppearance
                ) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Appearance")

                Text("Choose Light, Dark, or follow your device setting.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button {
                showPersonalizationEditor = true
            } label: {
                SettingsNavigationRow(
                    title: "Account Information",
                    description: personalizationDescription,
                    systemImage: "sparkles",
                    color: CalderaCategoryStyle.style(for: .safeToSpend).primary
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit account information")
        }
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

                SettingsRefreshStatusRow(
                    title: "Transactions",
                    value: plaid.transactionsLastUpdatedText,
                    systemImage: "list.bullet.rectangle",
                    color: AppColors.secondaryText
                )
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

    private var privacySection: some View {
        SettingsSection(
            title: "Data & Privacy",
            systemImage: "hand.raised.fill",
            color: AppColors.protected
        ) {
            SettingsInfoRow(
                title: "Bank connections are powered by Plaid",
                description: "Plaid handles the secure connection between your bank and the app.",
                systemImage: "shield.fill",
                color: AppColors.protected
            )

            Divider()

            SettingsInfoRow(
                title: "Bank credentials stay out of Caldera",
                description: "Your banking credentials are never stored in this app.",
                systemImage: "key.slash.fill",
                color: AppColors.warning
            )

            Divider()

            SettingsInfoRow(
                title: "Planning data stays on this device",
                description: "Upcoming Expenses, Goals, Cash Cushion, and Debt Payoff values are stored locally on this device.",
                systemImage: "lock.iphone",
                color: AppColors.accent
            )

        }
    }

    @ViewBuilder
    private var deleteAccountRow: some View {
        if auth.isSignedIn {
            DestructiveButton(
                "Delete Account",
                systemImage: "trash.fill",
                cornerRadius: AppRadii.button
            ) {
                deleteAccountStatusMessage = nil
                showDeleteAccountConfirmation = true
            }
            .accessibilityLabel("Delete Caldera account")
        } else {
            SettingsInfoRow(
                title: "Delete Account",
                description: "Sign in with Apple to delete your Caldera account.",
                systemImage: "person.crop.circle.badge.exclamationmark",
                color: AppColors.warning
            )
        }
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

    private var aboutSection: some View {
        SettingsSection(
            title: "About",
            systemImage: "info.circle.fill",
            color: AppColors.accent
        ) {
            Text("A personal finance planner for seeing today’s Available to Spend, what’s coming up, and money set aside.")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
                .lineSpacing(3)

            Divider()

            SettingsValueRow(
                title: "Version",
                value: appVersion,
                systemImage: "app.badge.fill",
                color: AppColors.accent
            )

            Divider()

            SettingsValueRow(
                title: "Build",
                value: buildNumber,
                systemImage: "hammer.fill",
                color: AppColors.secondaryText
            )
        }
    }

    private var supportSection: some View {
        SettingsSection(
            title: "Help",
            systemImage: "questionmark.circle.fill",
            color: AppColors.warning
        ) {
            Button {
                showAppTutorial = true
            } label: {
                SettingsNavigationRow(
                    title: "How Caldera Works",
                    description: "Replay the quick walkthrough.",
                    systemImage: "sparkles.rectangle.stack.fill",
                    color: AppColors.accentSecondary
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("How Caldera works")

            Divider()

            SettingsExternalLinkRow(
                title: "Contact Support",
                description: "Open support options and contact email.",
                systemImage: "envelope.fill",
                color: AppColors.accent,
                destination: supportURL
            )

            Divider()

            SettingsPlaceholderRow(
                title: "Report a Problem",
                description: "Issue reporting will be available in a future update.",
                systemImage: "exclamationmark.bubble.fill",
                color: AppColors.warning
            )
        }
    }

    private var legalSection: some View {
        SettingsSection(
            title: "Legal",
            systemImage: "doc.text.fill",
            color: AppColors.secondaryText
        ) {
            SettingsExternalLinkRow(
                title: "Privacy Policy",
                description: "Review how Caldera uses financial data.",
                systemImage: "lock.doc.fill",
                color: AppColors.protected,
                destination: privacyPolicyURL
            )

            Divider()

            SettingsPlaceholderRow(
                title: "Terms of Use",
                description: "Terms of use will be added before release.",
                systemImage: "doc.plaintext.fill",
                color: AppColors.secondaryText
            )
        }
    }

    private var dangerZoneSection: some View {
        SettingsSection(
            title: "Danger Zone",
            systemImage: "exclamationmark.triangle.fill",
            color: AppColors.negative
        ) {
            deleteAccountRow
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
                            Text("Delete your Caldera account?")
                                .font(.title3.weight(.bold))
                                .foregroundColor(AppColors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("This deletes your Caldera account, disconnects bank connections, revokes active sessions, and clears local financial data from this device. This cannot be undone.")
                                .font(.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(AppSpacing.card)
                    .glassCard(
                        cornerRadius: AppRadii.card
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
                    .glassCard(
                        cornerRadius: AppRadii.card
                    )
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.top, AppSpacing.large)
                .padding(.bottom, AppSpacing.emptyState + AppSpacing.screen)
                .dismissKeyboardOnBackgroundTap()
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnBackgroundTap()
            .background {
                CalderaPageBackground(mood: .more)
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
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

struct SettingsSection<Content: View>: View {

    let title: String
    let systemImage: String
    let color: Color
    let content: Content

    init(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    systemImage: systemImage,
                    colors: CalderaVisualStyle.iconGradient(for: color),
                    size: 34,
                    iconSize: 14
                )

                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
            }

            VStack(
                alignment: .leading,
                spacing: AppSpacing.medium
            ) {
                content
            }
        }
        .padding(AppSpacing.card)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.72,
            shadowOpacity: 0.036,
            shadowRadius: 16,
            shadowY: 8,
            darkGlowColor: color
        )
    }
}

struct SettingsInfoRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color

    var body: some View {
        SettingsRowShell(
            title: title,
            description: description,
            systemImage: systemImage,
            color: color
        )
    }
}

private struct SettingsNavigationRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: CalderaVisualStyle.iconGradient(for: color),
                size: 34,
                iconSize: 14
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.small)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.secondaryText.opacity(0.65))
        }
        .contentShape(Rectangle())
    }
}

private struct SettingsExternalLinkRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(
                alignment: .center,
                spacing: AppSpacing.medium
            ) {
                SettingsRowShell(
                    title: title,
                    description: description,
                    systemImage: systemImage,
                    color: color
                )

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.65))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsValueRow: View {

    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            SettingsRowShell(
                title: title,
                description: nil,
                systemImage: systemImage,
                color: color
            )

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
        }
    }
}

private struct SettingsRefreshStatusRow: View {

    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: CalderaVisualStyle.iconGradient(for: color),
                size: 34,
                iconSize: 14
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: 0.76,
            strokeOpacity: 0.62,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: color
        )
    }
}

private struct SettingsPlaceholderRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            SettingsRowShell(
                title: title,
                description: description,
                systemImage: systemImage,
                color: color
            )

            Text("Coming Soon")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AppColors.secondaryText.opacity(0.10))
                )
        }
        .opacity(0.82)
    }
}

private struct SettingsRowShell: View {

    let title: String
    let description: String?
    let systemImage: String
    let color: Color

    init(
        title: String,
        description: String?,
        systemImage: String,
        color: Color
    ) {
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: CalderaVisualStyle.iconGradient(for: color),
                size: 34,
                iconSize: 14
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}
