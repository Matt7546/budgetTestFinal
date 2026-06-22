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
                    Text("Savings Reserve")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)

                    Text("Money intentionally protected")
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

            TextField(
                "Amount",
                text: $amountText
            )
            .keyboardType(.decimalPad)
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.medium)
            .glassCard(
                cornerRadius: AppRadii.field,
                shadow: nil
            )
            .accessibilityLabel("Savings reserve amount")

            HStack(spacing: AppSpacing.medium) {
                SecondaryButton(
                    "Subtract",
                    systemImage: "minus.circle",
                    cornerRadius: AppRadii.button,
                    fillsWidth: true,
                    action: onSubtract
                )
                .disabled(!canAdjust)
                .opacity(canAdjust ? 1.0 : 0.6)
                .accessibilityLabel("Subtract from Savings Reserve")

                PrimaryButton(
                    "Add",
                    systemImage: "plus.circle.fill",
                    trailingSystemImage: nil,
                    cornerRadius: AppRadii.button,
                    isDisabled: !canAdjust,
                    fillsWidth: true,
                    action: onAdd
                )
                .accessibilityLabel("Add to Savings Reserve")
            }
        }
        .padding(AppSpacing.card)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background {
            RoundedRectangle(
                cornerRadius: AppRadii.hero
            )
            .fill(.ultraThinMaterial)

            RoundedRectangle(
                cornerRadius: AppRadii.hero
            )
            .fill(
                LinearGradient(
                    colors: [
                        AppColors.glassOverlayWhite,
                        AppColors.glassOverlaySurface
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: AppRadii.hero
            )
            .fill(
                RadialGradient(
                    colors: [
                        AppColors.protected.opacity(0.24),
                        AppColors.protected.opacity(0.10),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 230
                )
            )
            .blendMode(.plusLighter)
            .opacity(0.72)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AppRadii.hero
                )
            )
            .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(
                cornerRadius: AppRadii.hero
            )
            .stroke(
                AppColors.glassStroke.opacity(0.55),
                lineWidth: 1
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: AppRadii.hero
            )
            .stroke(
                LinearGradient(
                    colors: [
                        AppColors.protected.opacity(0.42),
                        AppColors.protected.opacity(0.18),
                        AppColors.glassStroke.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: AppRadii.hero
            )
        )
        .shadow(
            color: AppColors.shadowSoft,
            radius: 12,
            y: 8
        )
    }
}
