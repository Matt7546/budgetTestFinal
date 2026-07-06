import SwiftUI

struct SettingsLegalSection: View {

    let privacyPolicyURL: URL

    var body: some View {
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
}
