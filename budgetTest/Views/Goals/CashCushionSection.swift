import SwiftUI

struct CashCushionSection: View {

    let reserveBalance: Double
    @Binding var amountText: String
    let canAdjust: Bool
    let addAction: () -> Void
    let useAction: () -> Void

    var body: some View {
        let reserveStyle = CalderaCategoryStyle.style(for: .reserve)

        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: reserveStyle,
                    size: 34,
                    iconSize: 14
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Cash Cushion")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text("Flexible buffer kept out of Available to Spend.")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppSpacing.small)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppFormatters.currency(reserveBalance))
                        .font(.headline.weight(.bold))
                        .foregroundColor(reserveStyle.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("set aside")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.secondaryText.opacity(0.82))
                        .lineLimit(1)
                }
            }

            VStack(spacing: AppSpacing.xSmall) {
                amountInput(style: reserveStyle)

                HStack(spacing: AppSpacing.small) {
                    actionButton(
                        title: "Use Money",
                        systemImage: "minus.circle",
                        style: reserveStyle,
                        isPrimary: false,
                        isDisabled: !canAdjust,
                        action: useAction,
                        accessibilityLabel: "Use Money from Cash Cushion"
                    )

                    actionButton(
                        title: "Add Money",
                        systemImage: "plus.circle.fill",
                        style: reserveStyle,
                        isPrimary: true,
                        isDisabled: !canAdjust,
                        action: addAction,
                        accessibilityLabel: "Add Money to Cash Cushion"
                    )
                }
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.82,
            strokeOpacity: 0.62,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: reserveStyle.primary
        )
        .accessibilityElement(children: .contain)
    }

    private func amountInput(style: CalderaCategoryStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
            Text("$")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.secondaryText)

            TextField(
                "0.00",
                text: $amountText
            )
            .keyboardType(.decimalPad)
            .keyboardDismissToolbar()
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(AppColors.primaryText)
        }
        .padding(.horizontal, AppSpacing.medium)
        .frame(minHeight: 42)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.78,
            strokeOpacity: 0.56,
            shadowOpacity: 0.0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: style.primary
        )
        .accessibilityLabel("Cash Cushion dollar amount")
    }

    private func actionButton(
        title: String,
        systemImage: String,
        style: CalderaCategoryStyle,
        isPrimary: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundColor(isPrimary ? style.primary : AppColors.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 38)
            .padding(.horizontal, AppSpacing.small)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isPrimary
                            ? style.primary.opacity(0.11)
                            : Color.white.opacity(0.54)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isPrimary
                            ? style.primary.opacity(0.18)
                            : Color.white.opacity(0.58),
                        lineWidth: 1
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.58 : 1.0)
        .accessibilityLabel(accessibilityLabel)
    }
}
