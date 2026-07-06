import SwiftUI

struct SettingsAboutSection: View {

    let appVersion: String
    let buildNumber: String

    var body: some View {
        SettingsSection(
            title: "About",
            systemImage: "info.circle.fill",
            color: AppColors.accent
        ) {
            Text("A calm way to see Available to Spend, Set Aside money, and what’s coming.")
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
}
