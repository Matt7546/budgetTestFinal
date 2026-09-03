import SwiftUI

struct SettingsPrivacySection: View {
    @AppStorage(PrivacyShieldPreference.storageKey)
    private var isPrivacyShieldEnabled = false

    @Environment(\.isSensitiveDataCaptureActive)
    private var isSensitiveDataCaptureActive

    var body: some View {
        SettingsSection(
            title: "Data & Privacy",
            systemImage: "hand.raised.fill",
            color: AppColors.protected
        ) {
            Toggle(isOn: $isPrivacyShieldEnabled) {
                SettingsPrivacyShieldToggleLabel()
            }
            .tint(AppColors.accent)
            .accessibilityHint(
                "Hides balances and financial amounts throughout Caldera."
            )

            if isSensitiveDataCaptureActive {
                Divider()

                SettingsInfoRow(
                    title: "Screen sharing protection is on",
                    description: "Sensitive values are hidden while your screen is being shared.",
                    systemImage: "eye.slash.fill",
                    color: AppColors.protected
                )
            }

            Divider()

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
                description: "Upcoming Expenses, Savings Goals, Cash Cushion, and Payment Plan values are stored locally on this device.",
                systemImage: "lock.iphone",
                color: AppColors.accent
            )
        }
    }
}

private struct SettingsPrivacyShieldToggleLabel: View {
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: "eye.slash.fill")
                .font(.headline.weight(.semibold))
                .foregroundColor(AppColors.accent)
                .frame(width: 28, height: 28)
                .background(AppColors.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Hide Sensitive Data")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text("Hide balances and amounts when sharing your screen or taking screenshots.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
    }
}
