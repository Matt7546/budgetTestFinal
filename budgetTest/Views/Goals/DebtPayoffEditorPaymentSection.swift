import SwiftUI

struct DebtPayoffEditorPaymentSection: View {

    @Binding var paymentAmountText: String

    let warningMessage: String?

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "How much is needed?",
            systemImage: "dollarsign.circle.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            AmountEntryField(
                title: "Payment Target",
                subtitle: "The amount you want visible in this payment plan.",
                placeholder: "0.00",
                text: $paymentAmountText,
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                accessibilityLabel: "Payment target"
            )

            if let warningMessage {
                Text(warningMessage)
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
