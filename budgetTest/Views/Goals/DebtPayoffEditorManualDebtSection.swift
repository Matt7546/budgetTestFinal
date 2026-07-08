import SwiftUI

struct DebtPayoffEditorManualDebtSection: View {

    let manualNameTitle: String

    @Binding var manualNameText: String
    @Binding var manualBalanceText: String

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "What are you planning?",
            systemImage: "building.columns.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.medium
            ) {
                DebtPayoffEditorTextField(
                    title: manualNameTitle,
                    placeholder: "Other Debt",
                    text: $manualNameText,
                    subtitle: "Shown in your plan."
                )

                AmountEntryField(
                    title: "Current Balance",
                    subtitle: "Current amount for planning. You control actual payments outside Caldera.",
                    placeholder: "0.00",
                    text: $manualBalanceText,
                    style: CalderaCategoryStyle.style(for: .debtPayoff),
                    accessibilityLabel: "Current balance"
                )
            }
        }
    }
}
