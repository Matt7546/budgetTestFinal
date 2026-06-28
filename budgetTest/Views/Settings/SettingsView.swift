import AuthenticationServices
import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var plaid: PlaidService
    @Environment(\.colorScheme) private var colorScheme

    @State private var showDisconnectConfirmation = false

    @AppStorage("appearanceMode")
    private var appearanceMode = AppearanceMode.system.rawValue

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
        canShowBankData ? plaid.accounts : []
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

                        appStatusCard

                        authSection

                        accountsSection

                        appearanceSection

                        privacySection

                        supportSection

                        aboutSection

                        #if DEBUG
                        debugEnvironmentSection

                        DeveloperQASection()
                        #endif

                        legalSection
                    }
                    .padding(.all)
                    .padding(.bottom, AppSpacing.emptyState)
                }
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
        .confirmationDialog(
            "Disconnect Bank?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect Bank", role: .destructive) {
                plaid.disconnectBank()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the linked bank connection from Caldera and clears cached account and transaction data on this device. Your Savings, Timeline events, and Savings Reserve stay in place.")
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

    private var appStatusCard: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    systemImage: "command.circle.fill",
                    colors: CalderaVisualStyle.dashboardProgressGradient,
                    size: 46,
                    iconSize: 20
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Caldera")
                        .font(.title3.bold())
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                    Text("Your financial command center")
                        .font(.caption.weight(.medium))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: AppSpacing.small) {
                statusBadge(
                    title: canShowBankData
                        ? (visibleBankAccounts.isEmpty ? "Not connected" : "Connected")
                        : "Sign in needed",
                    systemImage: canShowBankData
                        ? (visibleBankAccounts.isEmpty ? "link.badge.plus" : "checkmark.circle.fill")
                        : "person.crop.circle.badge.checkmark",
                    color: canShowBankData
                        ? (visibleBankAccounts.isEmpty ? AppColors.warning : AppColors.spendable)
                        : AppColors.accentSecondary
                )

                #if DEBUG
                statusBadge(
                    title: AppConfig.environmentDisplayName,
                    systemImage: "server.rack",
                    color: AppColors.accent
                )
                #endif
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.88,
            strokeOpacity: 0.76,
            shadowOpacity: 0.045,
            shadowRadius: 18,
            shadowY: 8,
            darkGlowColor: AppColors.accentSecondary
        )
    }

    private func statusBadge(
        title: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(
            title,
            systemImage: systemImage
        )
        .font(.caption.weight(.bold))
        .foregroundColor(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.56), lineWidth: 1)
        }
    }


    private var authSection: some View {
        SettingsSection(
            title: "Caldera Account",
            systemImage: "person.crop.circle.fill",
            color: AppColors.accentSecondary
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
                auth.signOut()
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
            return "Checking Account"

        case .failed:
            return "Sign In Available"

        case .signedOut:
            return "Sign In Optional"
        }
    }

    private var authStatusDescription: String {
        if let user = auth.user,
           auth.isSignedIn {
            return user.displayName
        }

        return "Sign in with Apple is ready for multi-user testing. You can keep using Caldera without signing in for now."
    }

    private var appearanceSection: some View {
        SettingsSection(
            title: "App Preferences",
            systemImage: "moon.stars.fill",
            color: AppColors.accent
        ) {
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

            Text("Choose a polished light theme, deep dark theme, or follow your device setting.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    #endif

    private var accountsSection: some View {
        SettingsSection(
            title: "Accounts & Connections",
            systemImage: "building.columns.fill",
            color: AppColors.accent
        ) {
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
                    systemImage: "building.columns.fill",
                    color: AppColors.accent
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open linked accounts")

            Divider()

            SettingsInfoRow(
                title: "Bank Connection",
                description: connectionStatus,
                systemImage: visibleBankAccounts.isEmpty
                    ? "link.badge.plus"
                    : "checkmark.circle.fill",
                color: visibleBankAccounts.isEmpty
                    ? AppColors.accent
                    : AppColors.spendable
            )

            Divider()

            SettingsInfoRow(
                title: "Powered by Plaid",
                description: "Secure bank connection infrastructure for account linking.",
                systemImage: "shield.lefthalf.filled",
                color: AppColors.protected
            )

            if canShowBankData,
               let message = plaid.accountRefreshMessage {
                Divider()

                SettingsInfoRow(
                    title: "Refresh Status",
                    description: message,
                    systemImage: "wifi.exclamationmark",
                    color: AppColors.warning
                )
            }

            Divider()

            if !canShowBankData {
                SettingsInfoRow(
                    title: "Sign in required",
                    description: "Sign in before connecting banks so bank data stays scoped to your Caldera account.",
                    systemImage: "person.crop.circle.badge.checkmark",
                    color: AppColors.accentSecondary
                )

                Divider()

                authAction
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
                    "Disconnect Bank",
                    systemImage: "xmark.circle.fill",
                    cornerRadius: AppRadii.button
                ) {
                    showDisconnectConfirmation = true
                }
                .accessibilityLabel("Disconnect linked bank")
            }
        }
    }

    private var linkedAccountsDescription: String {
        if !canShowBankData {
            return "Sign in to manage banks, cards, and balances"
        }

        if visibleBankAccounts.isEmpty {
            return "Manage banks, cards, and balances"
        }

        return "\(visibleBankAccounts.count) connected account\(visibleBankAccounts.count == 1 ? "" : "s")"
    }

    private var privacySection: some View {
        SettingsSection(
            title: "Privacy",
            systemImage: "hand.raised.fill",
            color: AppColors.protected
        ) {
            SettingsInfoRow(
                title: "Bank connections are powered by Plaid.",
                description: "Plaid handles the secure connection between your bank and the app.",
                systemImage: "shield.fill",
                color: AppColors.protected
            )

            Divider()

            SettingsInfoRow(
                title: "Credentials stay out of the app.",
                description: "Your banking credentials are never stored in this app.",
                systemImage: "key.slash.fill",
                color: AppColors.warning
            )

            Divider()

            SettingsInfoRow(
                title: "Timeline and protection data stays local.",
                description: "User-created Upcoming Events, Savings Goals, and Savings Reserve values are stored locally on device.",
                systemImage: "lock.iphone",
                color: AppColors.accent
            )
        }
    }

    private var aboutSection: some View {
        SettingsSection(
            title: "About",
            systemImage: "info.circle.fill",
            color: AppColors.accent
        ) {
            Text("A personal finance planner for seeing today’s Safe To Spend, your timeline, and Protected Money.")
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
            title: "Support",
            systemImage: "questionmark.circle.fill",
            color: AppColors.warning
        ) {
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
                title: "Terms",
                description: "Terms of use will be added before release.",
                systemImage: "doc.plaintext.fill",
                color: AppColors.secondaryText
            )
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
