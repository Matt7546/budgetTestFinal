import SwiftUI

struct SettingsLegalSection: View {

    let showPrivacyPolicy: () -> Void
    let showTerms: () -> Void

    var body: some View {
        SettingsSection(
            title: "Legal",
            systemImage: "doc.text.fill",
            color: AppColors.secondaryText
        ) {
            Button {
                showPrivacyPolicy()
            } label: {
                SettingsNavigationRow(
                    title: "Privacy Policy",
                    description: "Review how \(AppBrand.fullName) uses financial data.",
                    systemImage: "lock.doc.fill",
                    color: AppColors.protected
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Privacy Policy")

            Divider()

            Button {
                showTerms()
            } label: {
                SettingsNavigationRow(
                    title: "Terms of Use",
                    description: "Review terms for using \(AppBrand.fullName).",
                    systemImage: "doc.plaintext.fill",
                    color: AppColors.secondaryText
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Terms of Use")
        }
    }
}
