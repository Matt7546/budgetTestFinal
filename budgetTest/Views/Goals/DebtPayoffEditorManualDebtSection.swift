import SwiftUI

struct DebtPayoffEditorManualDebtSection: View {

    let manualNameTitle: String

    @Binding var manualNameText: String
    @Binding var manualBalanceText: String

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "Debt Details",
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
                    subtitle: "Shown on Debt Payoff cards."
                )

                AmountEntryField(
                    title: "Current Balance",
                    subtitle: "Amount still owed. This only changes after a real payment is reported.",
                    placeholder: "0.00",
                    text: $manualBalanceText,
                    style: CalderaCategoryStyle.style(for: .debtPayoff),
                    accessibilityLabel: "Current balance"
                )
            }
        }
    }
}
