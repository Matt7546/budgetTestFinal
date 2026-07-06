import SwiftUI

struct SettingsPrivacySection: View {

    var body: some View {
        SettingsSection(
            title: "Data & Privacy",
            systemImage: "hand.raised.fill",
            color: AppColors.protected
        ) {
            SettingsInfoRow(
                title: "Bank connections are powered by Plaid",
                description: "Plaid handles the secure connection between your bank and the app.",
                systemImage: "shield.fill",
                color: AppColors.protected
            )

            Divider()

            SettingsInfoRow(
                title: "Bank credentials stay out of \(AppBrand.shortName)",
                description: "Your banking credentials are never stored in this app.",
                systemImage: "key.slash.fill",
                color: AppColors.warning
            )

            Divider()

            SettingsInfoRow(
                title: "Planning data stays on this device",
                description: "Upcoming Expenses, Goals, Cash Cushion, and Debt Payoff values are stored locally on this device.",
                systemImage: "lock.iphone",
                color: AppColors.accent
            )
        }
    }
}
