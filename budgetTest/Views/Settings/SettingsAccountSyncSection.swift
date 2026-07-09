import SwiftUI

struct SettingsAccountSyncSection<AuthAction: View>: View {

    let authStatusTitle: String
    let authStatusDescription: String
    let isSignedIn: Bool
    let authStatusMessage: String?
    let isAuthFailed: Bool
    let linkedAccountsDescription: String
    let canShowBankData: Bool
    let authAction: AuthAction

    init(
        authStatusTitle: String,
        authStatusDescription: String,
        isSignedIn: Bool,
        authStatusMessage: String?,
        isAuthFailed: Bool,
        linkedAccountsDescription: String,
        canShowBankData: Bool,
        @ViewBuilder authAction: () -> AuthAction
    ) {
        self.authStatusTitle = authStatusTitle
        self.authStatusDescription = authStatusDescription
        self.isSignedIn = isSignedIn
        self.authStatusMessage = authStatusMessage
        self.isAuthFailed = isAuthFailed
        self.linkedAccountsDescription = linkedAccountsDescription
        self.canShowBankData = canShowBankData
        self.authAction = authAction()
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

            if !canShowBankData {
                Divider()

                SettingsInfoRow(
                    title: "Bank Sync requires sign-in",
                    description: "Sign in before connecting banks so bank data stays tied to your \(AppBrand.shortName) account.",
                    systemImage: "person.crop.circle.badge.checkmark",
                    color: AppColors.accentSecondary
                )
            }
        }
    }
}
