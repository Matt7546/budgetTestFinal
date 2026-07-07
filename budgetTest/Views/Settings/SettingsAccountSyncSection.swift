import SwiftUI

struct SettingsAccountSyncSection<AuthAction: View, PlaidDataControls: View>: View {

    let authStatusTitle: String
    let authStatusDescription: String
    let isSignedIn: Bool
    let authStatusMessage: String?
    let isAuthFailed: Bool
    let linkedAccountsDescription: String
    let connectionStatus: String
    let hasVisibleBankAccounts: Bool
    let canShowBankData: Bool
    let accountStatusMessage: String?
    let hasBankRefreshWarning: Bool
    let connectAccount: () -> Void
    let disconnectAllBanks: () -> Void
    let authAction: AuthAction
    let plaidDataControls: PlaidDataControls

    init(
        authStatusTitle: String,
        authStatusDescription: String,
        isSignedIn: Bool,
        authStatusMessage: String?,
        isAuthFailed: Bool,
        linkedAccountsDescription: String,
        connectionStatus: String,
        hasVisibleBankAccounts: Bool,
        canShowBankData: Bool,
        accountStatusMessage: String?,
        hasBankRefreshWarning: Bool,
        connectAccount: @escaping () -> Void,
        disconnectAllBanks: @escaping () -> Void,
        @ViewBuilder authAction: () -> AuthAction,
        @ViewBuilder plaidDataControls: () -> PlaidDataControls
    ) {
        self.authStatusTitle = authStatusTitle
        self.authStatusDescription = authStatusDescription
        self.isSignedIn = isSignedIn
        self.authStatusMessage = authStatusMessage
        self.isAuthFailed = isAuthFailed
        self.linkedAccountsDescription = linkedAccountsDescription
        self.connectionStatus = connectionStatus
        self.hasVisibleBankAccounts = hasVisibleBankAccounts
        self.canShowBankData = canShowBankData
        self.accountStatusMessage = accountStatusMessage
        self.hasBankRefreshWarning = hasBankRefreshWarning
        self.connectAccount = connectAccount
        self.disconnectAllBanks = disconnectAllBanks
        self.authAction = authAction()
        self.plaidDataControls = plaidDataControls()
    }

    var body: some View {
        SettingsSection(
            title: "Account & Bank Sync",
            systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
            color: CalderaCategoryStyle.style(for: .bankAccount).primary
        ) {
            SettingsInfoRow(
                title: authStatusTitle,
                description: authStatusDescription,
                systemImage: isSignedIn
                    ? "checkmark.seal.fill"
                    : "person.crop.circle.badge.plus",
                color: isSignedIn
                    ? AppColors.spendable
                    : AppColors.accentSecondary
            )

            if let authStatusMessage,
               !authStatusMessage.isEmpty {
                Divider()

                SettingsInfoRow(
                    title: "Account Status",
                    description: authStatusMessage,
                    systemImage: isAuthFailed
                        ? "exclamationmark.triangle.fill"
                        : "info.circle.fill",
                    color: isAuthFailed
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
                systemImage: hasVisibleBankAccounts
                    ? CalderaCategoryStyle.style(for: .covered).icon
                    : "link.badge.plus",
                color: hasVisibleBankAccounts
                    ? CalderaCategoryStyle.style(for: .covered).primary
                    : CalderaCategoryStyle.style(for: .bankAccount).primary
            )

            if canShowBankData {
                Divider()

                plaidDataControls

                if let accountStatusMessage {
                    Divider()

                    SettingsInfoRow(
                        title: hasBankRefreshWarning ? "Refresh failed" : "Bank Data Status",
                        description: accountStatusMessage,
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
                    title: "Bank Sync requires sign-in",
                    description: "Sign in before connecting banks so bank data stays tied to your \(AppBrand.shortName) account.",
                    systemImage: "person.crop.circle.badge.checkmark",
                    color: AppColors.accentSecondary
                )
            } else if !hasVisibleBankAccounts {
                PrimaryButton(
                    "Connect Account",
                    systemImage: "link",
                    trailingSystemImage: nil,
                    cornerRadius: AppRadii.button,
                    fillsWidth: true
                ) {
                    connectAccount()
                }
            } else {
                DestructiveButton(
                    "Disconnect All Banks",
                    systemImage: "xmark.circle.fill",
                    cornerRadius: AppRadii.button
                ) {
                    disconnectAllBanks()
                }
                .accessibilityLabel("Disconnect all linked banks")
            }
        }
    }
}
