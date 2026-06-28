import SwiftUI
import UIKit

struct AmountEntryField: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String?
    let placeholder: String
    @Binding var text: String
    let systemImage: String
    let colors: [Color]
    let keyboardType: UIKeyboardType
    let focus: FocusState<Bool>.Binding?
    let accessibilityLabel: String

    init(
        title: String,
        subtitle: String? = nil,
        placeholder: String = "0.00",
        text: Binding<String>,
        systemImage: String = "dollarsign",
        colors: [Color] = CalderaCategoryStyle.style(for: .safeToSpend).gradient,
        keyboardType: UIKeyboardType = .decimalPad,
        focus: FocusState<Bool>.Binding? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.placeholder = placeholder
        _text = text
        self.systemImage = systemImage
        self.colors = colors
        self.keyboardType = keyboardType
        self.focus = focus
        self.accessibilityLabel = accessibilityLabel ?? title
    }

    init(
        title: String,
        subtitle: String? = nil,
        placeholder: String = "0.00",
        text: Binding<String>,
        style: CalderaCategoryStyle,
        keyboardType: UIKeyboardType = .decimalPad,
        focus: FocusState<Bool>.Binding? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            placeholder: placeholder,
            text: text,
            systemImage: style.icon,
            colors: style.gradient,
            keyboardType: keyboardType,
            focus: focus,
            accessibilityLabel: accessibilityLabel
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    systemImage: systemImage,
                    colors: colors,
                    size: 38,
                    iconSize: 16
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                Text("$")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

                focusedTextField
            }
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.medium)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.86,
                strokeOpacity: 0.70,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: colors.first ?? AppColors.accent
            )
        }
    }

    @ViewBuilder
    private var focusedTextField: some View {
        if let focus {
            baseTextField
                .focused(focus)
        } else {
            baseTextField
        }
    }

    private var baseTextField: some View {
        TextField(
            placeholder,
            text: $text
        )
        .keyboardType(keyboardType)
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
        .accessibilityLabel(accessibilityLabel)
    }
}
