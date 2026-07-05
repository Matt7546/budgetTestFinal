import SwiftUI

struct ReserveBalanceCard: View {

    let balance: Double
    @Binding var amountText: String
    let canAdjust: Bool
    let onAdd: () -> Void
    let onSubtract: () -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(
                alignment: .center,
                spacing: AppSpacing.medium
            ) {
                ZStack {
                    Circle()
                        .fill(
                            AppColors.protected.opacity(0.14)
                        )
                        .frame(
                            width: 42,
                            height: 42
                        )

                    Image(
                        systemName: "lock.shield.fill"
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(AppColors.protected)
                }

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Cash Cushion")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)

                    Text("Flexible money set aside for breathing room.")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                MetricValue(
                    balance,
                    font: .system(
                        size: 30,
                        weight: .bold,
                        design: .rounded
                    ),
                    minimumScaleFactor: 0.65,
                    lineLimit: 1
                )
            }

            AmountEntryField(
                title: "Cash Cushion Adjustment",
                subtitle: "Add to or use from your cushion.",
                placeholder: "0.00",
                text: $amountText,
                style: CalderaCategoryStyle.style(for: .reserve),
                accessibilityLabel: "Cash Cushion amount"
            )

            HStack(spacing: AppSpacing.medium) {
                SecondaryButton(
                    "Use from Cushion",
                    systemImage: "minus.circle",
                    cornerRadius: AppRadii.button,
                    fillsWidth: true,
                    action: onSubtract
                )
                .disabled(!canAdjust)
                .opacity(canAdjust ? 1.0 : 0.6)
                .accessibilityLabel("Use from Cash Cushion")

                PrimaryButton(
                    "Add to Cushion",
                    systemImage: "plus.circle.fill",
                    trailingSystemImage: nil,
                    cornerRadius: AppRadii.button,
                    isDisabled: !canAdjust,
                    fillsWidth: true,
                    action: onAdd
                )
                .accessibilityLabel("Add to Cash Cushion")
            }
        }
        .padding(AppSpacing.card)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .calderaGlassCard(
            cornerRadius: AppRadii.hero,
            fillOpacity: 0.88,
            strokeOpacity: 0.74,
            shadowOpacity: 0.04,
            shadowRadius: 18,
            shadowY: 8,
            darkGlowColor: AppColors.protected
        )
    }
}
