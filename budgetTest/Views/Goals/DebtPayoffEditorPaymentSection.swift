import SwiftUI

struct DebtPayoffEditorPaymentSection: View {

    @Binding var paymentAmountText: String

    let warningMessage: String?
    var basisMessage: String? = nil

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "Planned payment",
            systemImage: "dollarsign.circle.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            AmountEntryField(
                title: "Planned payment",
                subtitle: "The amount you want Caldera to plan for.",
                placeholder: "0.00",
                text: $paymentAmountText,
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                accessibilityLabel: "Planned payment"
            )

            if let basisMessage {
                Text(basisMessage)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let warningMessage {
                Text(warningMessage)
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DebtPayoffEditorLinkedCardPaymentTargetSection: View {

    let selectedChoice: DebtPayoffLinkedCardPaymentTargetChoice?
    let statementBalance: Double?
    let minimumPayment: Double?
    let currentBalance: Double?
    @Binding var paymentAmountText: String
    let selectChoice: (DebtPayoffLinkedCardPaymentTargetChoice) -> Void

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "What would you like to plan for?",
            systemImage: "dollarsign.circle.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            if selectedChoice == nil {
                Text("Choose what you'd like to plan for.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppSpacing.small) {
                ForEach(DebtPayoffLinkedCardPaymentTargetChoice.allCases) { choice in
                    choiceRow(choice)
                }
            }

            if selectedChoice == .customAmount {
                AmountEntryField(
                    title: "Planned payment",
                    subtitle: "The amount you want Caldera to plan for.",
                    placeholder: "0.00",
                    text: $paymentAmountText,
                    style: CalderaCategoryStyle.style(for: .debtPayoff),
                    accessibilityLabel: "Custom planned payment"
                )
            }
        }
    }

    private func choiceRow(
        _ choice: DebtPayoffLinkedCardPaymentTargetChoice
    ) -> some View {
        let amount = amount(for: choice)
        let isAvailable = choice == .customAmount || amount != nil

        return DebtPayoffEditorChoiceRow(
            title: choice.title,
            isSelected: selectedChoice == choice,
            accessibilityLabel: choice.title,
            accessibilityHint: choiceDescription(choice, amount: amount),
            action: {
                selectChoice(choice)
            }
        ) {
            Text(choiceDescription(choice, amount: amount))
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.56)
    }

    private func amount(
        for choice: DebtPayoffLinkedCardPaymentTargetChoice
    ) -> Double? {
        choice.suggestedAmount(
            statementBalance: statementBalance,
            minimumPayment: minimumPayment,
            currentBalance: currentBalance
        )
    }

    private func choiceDescription(
        _ choice: DebtPayoffLinkedCardPaymentTargetChoice,
        amount: Double?
    ) -> String {
        if choice == .customAmount {
            return "Enter the amount you want in this payment plan."
        }

        guard let amount else {
            return "Not available from this linked card."
        }

        return AppFormatters.currency(amount)
    }
}
