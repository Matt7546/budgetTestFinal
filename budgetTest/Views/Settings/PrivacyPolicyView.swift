import SwiftUI

struct PrivacyPolicyView: View {

    @Environment(\.dismiss) private var dismiss

    private let updatedDate = "June 22, 2026"

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaModalBackground(mood: .general)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.screen) {
                        ModalHeaderView(
                            eyebrow: "Legal",
                            title: "Privacy Policy",
                            subtitle: "How \(AppBrand.fullName) handles your data.",
                            systemImage: "lock.doc.fill",
                            color: AppColors.protected
                        )

                        PrivacyPolicyCard(color: AppColors.protected) {
                            Text("Last updated: \(updatedDate)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.secondaryText)

                            PrivacyPolicyParagraph(
                                "\(AppBrand.fullName) is a spending clarity app that helps you understand Available to Spend after money has been Set Aside for future needs."
                            )
                        }

                        PrivacyPolicySection(
                            title: "Financial Data",
                            paragraphs: [
                                "When you use Bank Sync, \(AppBrand.fullName) uses linked account data to estimate balances and Available to Spend. This may include account balances, names, types, and transaction data when available from your linked institution.",
                                "Bank data can be delayed, incomplete, or unavailable. Available to Spend and other planning calculations are estimates based on available data, so verify important information with your financial institution."
                            ]
                        )

                        PrivacyPolicySection(
                            title: "Bank Connections",
                            paragraphs: [
                                "\(AppBrand.fullName) does not store your bank login credentials. Bank Sync is handled by Plaid, a financial account connection provider.",
                                "Plaid connects linked accounts with your consent and may process information according to its own policies and consent flow."
                            ]
                        )

                        PrivacyPolicySection(
                            title: "Local App Data",
                            paragraphs: [
                                "User-created app data, such as Cash Cushion values, Savings Goals, Upcoming Expenses, Plan Ahead entries, and Payment Plans, may be stored locally on your device to provide planning features."
                            ]
                        )

                        PrivacyPolicySection(
                            title: "Set Aside Planning",
                            paragraphs: [
                                "Set Aside is virtual planning inside \(AppBrand.fullName). Your money stays in your bank account. \(AppBrand.fullName) does not move money, make payments, or change real account or debt balances."
                            ]
                        )

                        PrivacyPolicySection(
                            title: "Account Controls and Support",
                            paragraphs: [
                                "Where supported, you can disconnect linked banks and delete your account in the app.",
                                "For privacy questions, account deletion help, or support, contact Caldera Support at mthomas7546@icloud.com."
                            ]
                        )
                    }
                    .padding(AppSpacing.screen)
                    .padding(.bottom, AppSpacing.emptyState)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .calderaTransparentNavigationSurface()
        }
    }
}

private struct PrivacyPolicySection: View {

    let title: String
    let paragraphs: [String]

    var body: some View {
        PrivacyPolicyCard(color: AppColors.accent) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.primaryText)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                ForEach(paragraphs, id: \.self) { paragraph in
                    PrivacyPolicyParagraph(paragraph)
                }
            }
        }
    }
}

private struct PrivacyPolicyCard<Content: View>: View {

    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        GlassFormCard(color: color) {
            content
        }
    }
}

private struct PrivacyPolicyParagraph: View {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(AppColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
