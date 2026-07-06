import SwiftUI

struct DebtPayoffEditorSetAsideSection: View {

    @Binding var protectedAmountText: String

    let setAsideTarget: Double
    let protectedAmount: Double
    let setAsideLimitMessage: String

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "Amount to Set Aside",
            systemImage: CalderaCategoryStyle.style(for: .debtPayoff).icon,
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            DebtPayoffEditorSetAsideAmountField(
                title: "Amount to Set Aside",
                text: $protectedAmountText,
                placeholder: "0.00"
            )

            Text("Payment target: \(AppFormatters.currency(setAsideTarget)).")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if protectedAmount > setAsideTarget,
               setAsideTarget > 0 {
                Text(setAsideLimitMessage)
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
