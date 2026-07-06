import SwiftUI

struct SettingsPreferencesSection: View {

    @Binding var selectedAppearance: AppearanceMode

    let personalizationDescription: String
    let editPersonalization: () -> Void

    var body: some View {
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
                    selection: $selectedAppearance
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
                editPersonalization()
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
}
