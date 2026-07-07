import SwiftUI

struct SettingsLegalSection: View {

    let privacyPolicyURL: URL
    let showTerms: () -> Void

    var body: some View {
        SettingsSection(
            title: "Legal",
            systemImage: "doc.text.fill",
            color: AppColors.secondaryText
        ) {
            SettingsExternalLinkRow(
                title: "Privacy Policy",
                description: "Review how \(AppBrand.shortName) uses financial data.",
                systemImage: "lock.doc.fill",
                color: AppColors.protected,
                destination: privacyPolicyURL
            )

            Divider()

            Button {
                showTerms()
            } label: {
                SettingsNavigationRow(
                    title: "Terms of Use",
                    description: "Review the beta terms for using \(AppBrand.fullName).",
                    systemImage: "doc.plaintext.fill",
                    color: AppColors.secondaryText
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Terms of Use")
        }
    }
}
