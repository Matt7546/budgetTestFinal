import SwiftUI

struct SettingsDangerZoneSection: View {

    let isSignedIn: Bool
    let deleteAccount: () -> Void

    var body: some View {
        SettingsSection(
            title: "Danger Zone",
            systemImage: "exclamationmark.triangle.fill",
            color: AppColors.negative
        ) {
            if isSignedIn {
                DestructiveButton(
                    "Delete Account",
                    systemImage: "trash.fill",
                    cornerRadius: AppRadii.button
                ) {
                    deleteAccount()
                }
                .accessibilityLabel("Delete \(AppBrand.shortName) account")
            } else {
                SettingsInfoRow(
                    title: "Delete Account",
                    description: "Sign in with Apple to delete your \(AppBrand.shortName) account.",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    color: AppColors.warning
                )
            }
        }
    }
}
