import SwiftUI

struct SettingsHelpSection: View {

    let supportURL: URL
    let showTutorial: () -> Void
    let sendFeedback: () -> Void

    var body: some View {
        SettingsSection(
            title: "Help",
            systemImage: "questionmark.circle.fill",
            color: AppColors.warning
        ) {
            Button {
                showTutorial()
            } label: {
                SettingsNavigationRow(
                    title: "How \(AppBrand.shortName) Works",
                    description: "Replay the quick walkthrough.",
                    systemImage: "sparkles.rectangle.stack.fill",
                    color: AppColors.accentSecondary
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("How \(AppBrand.shortName) works")

            Divider()

            SettingsExternalLinkRow(
                title: "Contact Support",
                description: "Open support options and contact email.",
                systemImage: "envelope.fill",
                color: AppColors.accent,
                destination: supportURL
            )

            Divider()

            Button {
                sendFeedback()
            } label: {
                SettingsNavigationRow(
                    title: "Send Feedback",
                    description: "Share an idea or report an issue.",
                    systemImage: "exclamationmark.bubble.fill",
                    color: AppColors.warning
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send feedback")
        }
    }
}
