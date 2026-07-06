import SwiftUI

enum DebtPayoffCreditCardSource: String, CaseIterable, Identifiable {
    case linked
    case manual

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .linked:
            return "Linked Account"

        case .manual:
            return "Manual Entry"
        }
    }

    var helper: String {
        switch self {
        case .linked:
            return "Use a credit card from Linked Accounts."

        case .manual:
            return "Enter the card details yourself."
        }
    }
}

struct DebtPayoffEditorFormCard<Content: View>: View {

    let title: String
    let systemImage: String
    let color: Color
    let content: Content

    init(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.content = content()
    }

    var body: some View {
        CalderaEditorFormCard(
            title: title,
            systemImage: systemImage,
            color: color
        ) {
            content
        }
    }
}

struct DebtPayoffEditorChoiceRow<SupportingText: View>: View {

    let title: String
    let isSelected: Bool
    let accessibilityLabel: String
    let accessibilityHint: String?
    let action: () -> Void
    let supportingText: SupportingText

    init(
        title: String,
        isSelected: Bool,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder supportingText: () -> SupportingText
    ) {
        self.title = title
        self.isSelected = isSelected
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
        self.supportingText = supportingText()
    }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    supportingText
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.medium)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: isSelected ? 0.90 : 0.76,
                strokeOpacity: isSelected ? 0.78 : 0.46,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

struct DebtPayoffEditorTextField: View {

    let title: String
    let placeholder: String
    @Binding var text: String
    let subtitle: String?

    var body: some View {
        CalderaTextEntryField(
            title: title,
            subtitle: subtitle,
            placeholder: placeholder,
            text: $text,
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary,
            accessibilityLabel: title
        )
    }
}

struct DebtPayoffEditorPercentageField: View {

    let title: String
    let placeholder: String
    @Binding var text: String
    let subtitle: String

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)

            TextField(
                placeholder,
                text: $text
            )
            .keyboardType(.decimalPad)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.86,
                strokeOpacity: 0.68,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
            )
            .accessibilityLabel(title)
        }
    }
}

struct DebtPayoffEditorSetAsideAmountField: View {

    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        AmountEntryField(
            title: title,
            subtitle: "Money Caldera keeps out of Available to Spend for this payment. This does not make a payment or change your bank balance.",
            placeholder: placeholder,
            text: $text,
            style: CalderaCategoryStyle.style(for: .debtPayoff),
            accessibilityLabel: title
        )
    }
}

struct DebtPayoffEditorValidationFooter: View {

    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.medium))
            .foregroundColor(AppColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
