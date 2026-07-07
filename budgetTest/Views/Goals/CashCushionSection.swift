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
            spacing: AppSpacing.compact
        ) {
            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: reserveStyle,
                    size: 42,
                    iconSize: 18
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Cash Cushion")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)

                    Text(cushionDescription)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(AppFormatters.currency(reserveBalance))
                    .font(.title2.bold())
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                Text("$")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.secondaryText)

                TextField(
                    "0.00",
                    text: $amountText
                )
                .keyboardType(.decimalPad)
                .keyboardDismissToolbar()
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(AppColors.primaryText)
            }
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.compact)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.88,
                strokeOpacity: 0.70,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0
            )
            .accessibilityLabel("Cash Cushion dollar amount")

            HStack(spacing: AppSpacing.medium) {
                actionButton(
                    title: "Use Money",
                    systemImage: "minus.circle",
                    isPrimary: false,
                    isDisabled: !canAdjust,
                    action: useAction,
                    accessibilityLabel: "Use Money from Cash Cushion"
                )

                actionButton(
                    title: "Add Money",
                    systemImage: "plus.circle.fill",
                    isPrimary: true,
                    isDisabled: !canAdjust,
                    action: addAction,
                    accessibilityLabel: "Add Money to Cash Cushion"
                )
            }
        }
        .padding(AppSpacing.regular)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.90,
            strokeOpacity: 0.76,
            shadowOpacity: 0.038,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: reserveStyle.primary
        )
        .background {
            RoundedRectangle(cornerRadius: AppRadii.panel, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            reserveStyle.primary.opacity(0.16),
                            AppColors.accentSecondary.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 4)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadii.panel, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            reserveStyle.primary.opacity(0.72),
                            AppColors.accentSecondary.opacity(0.46),
                            reserveStyle.primary.opacity(0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.1
                )
                .shadow(
                    color: reserveStyle.primary.opacity(0.18),
                    radius: 3,
                    x: 0,
                    y: 0
                )
                .shadow(
                    color: AppColors.accentSecondary.opacity(0.12),
                    radius: 4,
                    x: 0,
                    y: 0
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: reserveStyle.primary.opacity(0.08),
            radius: 6,
            x: 0,
            y: 3
        )
        .shadow(
            color: AppColors.accentSecondary.opacity(0.05),
            radius: 8,
            x: 0,
            y: 4
        )
    }

    private var cushionDescription: String {
        if reserveBalance <= 0.005 {
            return "Start with a small Cash Cushion to keep it out of Available to Spend."
        }

        return "A simple set-aside buffer kept out of Available to Spend."
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, AppSpacing.small)
            .foregroundColor(isPrimary ? .white : AppColors.secondaryText)
            .background {
                if isPrimary {
                    LinearGradient(
                        colors: [
                            AppColors.primaryButtonStart,
                            AppColors.primaryButtonEnd
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
                        .fill(Color.white.opacity(0.74))
                }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
                    .stroke(
                        isPrimary
                            ? Color.white.opacity(0.24)
                            : Color.white.opacity(0.72),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: isPrimary
                    ? AppColors.primaryButtonEnd.opacity(0.20)
                    : Color.black.opacity(0.035),
                radius: isPrimary ? 12 : 10,
                x: 0,
                y: isPrimary ? 7 : 5
            )
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.62 : 1.0)
        .accessibilityLabel(accessibilityLabel)
    }
}
