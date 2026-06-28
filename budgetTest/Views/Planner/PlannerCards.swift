import SwiftUI

extension PlannerView {
    
    
    var availableCard: some View {
        let accentColor =
            plannerAvailable >= 0
            ? AppColors.spendable
            : AppColors.negative
        let snapshotCaption =
            plannerAvailable >= 0
            ? "After protected money and upcoming expenses"
            : "Upcoming expenses exceed available cash"
        
        return ZStack(alignment: .topTrailing) {
            VStack {
                HStack {
                    Spacer()

                    ZStack {
                        RoundedRectangle(
                            cornerRadius: 22
                        )
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.glassSubtleHighlight,
                                    accentColor.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(
                            width: 110,
                            height: 90
                        )

                        RoundedRectangle(
                            cornerRadius: 22
                        )
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.glassOverlayWhite,
                                    accentColor.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(
                            width: 110,
                            height: 90
                        )
                        .offset(
                            x: 12,
                            y: 10
                        )
                    }
                    .rotationEffect(
                        .degrees(-12)
                    )
                    .opacity(0.55)
                }

                Spacer()
            }
            .padding(.top, 18)
            .padding(.trailing, 22)

            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                HStack {
                    CalderaGradientIcon(
                        systemImage: "wallet.pass.fill",
                        colors: plannerAvailable >= 0
                            ? CalderaVisualStyle.safeGradient
                            : CalderaVisualStyle.expenseGradient,
                        size: 36,
                        iconSize: 15
                    )

                    Text("Safe to Spend")
                        .font(.headline)
                        .foregroundStyle(AppColors.secondaryText)

                    Spacer()
                }

                MetricValue(
                    plannerAvailable,
                    font: .system(
                        size: 50,
                        weight: .bold,
                        design: .rounded
                    ),
                    color: accentColor,
                    minimumScaleFactor: 0.7,
                    lineLimit: 1
                )

                Text(snapshotCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)

                Spacer()
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
        }
        .frame(height: 180)
        .calderaGlassCard(
            cornerRadius: 34,
            fillOpacity: 0.88,
            strokeOpacity: 0.76,
            shadowOpacity: 0.045,
            shadowRadius: 20,
            shadowY: 10
        )
    }
}
