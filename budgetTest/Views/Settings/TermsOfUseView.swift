import SwiftUI

struct TermsOfUseView: View {

    @Environment(\.dismiss) private var dismiss

    private let updatedDate = "July 6, 2026"

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaModalBackground(mood: .general)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.screen) {
                        ModalHeaderView(
                            eyebrow: "Legal",
                            title: "Terms of Use",
                            subtitle: "A practical beta draft for using \(AppBrand.fullName).",
                            systemImage: "doc.plaintext.fill",
                            color: AppColors.secondaryText
                        )

                        GlassFormCard(color: AppColors.secondaryText) {
                            Text("Last updated: \(updatedDate)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.secondaryText)

                            TermsParagraph(
                                "These Terms are a plain-language beta draft and are not final attorney-reviewed legal advice. By using \(AppBrand.fullName), you agree to use it as a planning tool and to verify important financial information with your financial institution."
                            )
                        }

                        TermsSection(
                            title: "What \(AppBrand.fullName) Does",
                            paragraphs: [
                                "\(AppBrand.fullName) helps you understand Available to Spend after money has been Set Aside for future needs.",
                                "Bank Sync uses linked account data to estimate balances. Set Aside money is virtual planning inside the app."
                            ]
                        )

                        TermsSection(
                            title: "What \(AppBrand.fullName) Does Not Do",
                            paragraphs: [
                                "\(AppBrand.fullName) is not a bank. It does not move money, make payments, or change real account or debt balances.",
                                "Debt Payoff helps plan money for a card or debt payment. It does not make that payment for you."
                            ]
                        )

                        TermsSection(
                            title: "Your Responsibility",
                            paragraphs: [
                                "You are responsible for verifying real balances, due dates, transfers, and payments with your bank, card issuer, lender, or other financial institution.",
                                "\(AppBrand.fullName) is not financial, investment, tax, legal, credit, or debt advice."
                            ]
                        )

                        TermsSection(
                            title: "Beta Software",
                            paragraphs: [
                                "During TestFlight or beta use, the app may contain bugs, incomplete features, delayed account data, or inaccurate information.",
                                "Do not rely on \(AppBrand.fullName) as the only source for payment timing, account balances, or spending decisions."
                            ]
                        )

                        TermsSection(
                            title: "Bank Sync and Account Controls",
                            paragraphs: [
                                "If you use Bank Sync, linked account data is provided through Plaid with your consent.",
                                "Where supported, you can disconnect banks and delete your account from inside the app."
                            ]
                        )

                        TermsSection(
                            title: "Support",
                            paragraphs: [
                                "For support, questions, bugs, confusing numbers, or account deletion help, contact \(AppBrand.supportName)."
                            ]
                        )
                    }
                    .padding(AppSpacing.screen)
                    .padding(.bottom, AppSpacing.emptyState)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Terms of Use")
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

private struct TermsSection: View {

    let title: String
    let paragraphs: [String]

    var body: some View {
        GlassFormCard(color: AppColors.accent) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.primaryText)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                ForEach(paragraphs, id: \.self) { paragraph in
                    TermsParagraph(paragraph)
                }
            }
        }
    }
}

private struct TermsParagraph: View {

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
