import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var plaid: PlaidService

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

    private var connectionStatus: String {
        if plaid.accounts.isEmpty {
            return "No bank accounts connected"
        }

        return "\(plaid.accounts.count) connected account\(plaid.accounts.count == 1 ? "" : "s")"
    }

    var body: some View {
        AppScreen {
            header

            appearanceSection

            #if DEBUG
            debugEnvironmentSection
            #endif

            accountsSection

            privacySection

            aboutSection

            supportSection

            #if DEBUG
            DeveloperQASection()
            #endif

            legalSection
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
            spacing: 6
        ) {
            Text("Preferences & Trust")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            Text("Settings")
                .font(
                    .system(
                        size: 38,
                        weight: .bold
                    )
                )
                .foregroundColor(AppColors.primaryText)
        }
    }

    private var appearanceSection: some View {
        SettingsSection(
            title: "Appearance",
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
            SettingsInfoRow(
                title: "Bank Connection",
                description: connectionStatus,
                systemImage: plaid.accounts.isEmpty
                    ? "link.badge.plus"
                    : "checkmark.circle.fill",
                color: plaid.accounts.isEmpty
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

            if let message = plaid.accountRefreshMessage {
                Divider()

                SettingsInfoRow(
                    title: "Refresh Status",
                    description: message,
                    systemImage: "wifi.exclamationmark",
                    color: AppColors.warning
                )
            }

            Divider()

            if plaid.accounts.isEmpty {
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
            SettingsPlaceholderRow(
                title: "Contact Support",
                description: "Support contact options are coming soon.",
                systemImage: "envelope.fill",
                color: AppColors.accent
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
            SettingsPlaceholderRow(
                title: "Privacy Policy",
                description: "A full privacy policy will be added before release.",
                systemImage: "lock.doc.fill",
                color: AppColors.protected
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
                IconBadge(
                    systemImage: systemImage,
                    color: color,
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
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    color.opacity(0.05),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: AppShadows.softPanelCompact
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

private struct SettingsToggleRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color
    @Binding var isOn: Bool

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

            Toggle(
                "",
                isOn: $isOn
            )
            .labelsHidden()
            .tint(color)
        }
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
            IconBadge(
                systemImage: systemImage,
                color: color
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
