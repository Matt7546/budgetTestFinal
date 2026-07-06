import SwiftUI

extension PlannerView {


    var availableCard: some View {
        let isPositive = plannerAvailable >= 0
        let semanticStyle = CalderaCategoryStyle.style(
            for: isPositive ? .safeToSpend : .shortfall
        )
        let accentColor = isPositive
            ? semanticStyle.primary
            : semanticStyle.primary
        let accentGradient = semanticStyle.gradient
        let snapshotCaption = isPositive
            ? "After set-asides and upcoming expenses."
            : "Upcoming Expenses and Set Aside money are greater than available cash."

        return ZStack(alignment: .topTrailing) {
            timelineHeroAccent(
                colors: accentGradient
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.card
            ) {
                HStack(
                    alignment: .top,
                    spacing: AppSpacing.medium
                ) {
                    CalderaGradientIcon(
                        style: semanticStyle,
                        size: 48,
                        iconSize: 20
                    )

                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.xxSmall
                    ) {
                        Text("Available to Spend")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.secondaryText)

                        Text("Timeline snapshot")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(
                                AppColors.secondaryText.opacity(0.86)
                            )
                    }

                    Spacer()
                }

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.small
                ) {
                    MetricValue(
                        plannerAvailable,
                        font: .system(
                            size: 48,
                            weight: .bold,
                            design: .rounded
                        ),
                        color: accentColor,
                        minimumScaleFactor: 0.70,
                        lineLimit: 1
                    )

                    Text(snapshotCaption)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(AppSpacing.card)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 178,
            alignment: .topLeading
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 34,
                style: .continuous
            )
        )
        .calderaGlassCard(
            cornerRadius: 34,
            fillOpacity: 0.90,
            strokeOpacity: 0.78,
            shadowOpacity: 0.04,
            shadowRadius: 18,
            shadowY: 9,
            darkGlowColor: accentColor
        )
    }

    private func timelineHeroAccent(
        colors: [Color]
    ) -> some View {
        RoundedRectangle(
            cornerRadius: 30,
            style: .continuous
        )
        .fill(
            LinearGradient(
                colors: [
                    colors.first?.opacity(0.22) ?? AppColors.accent.opacity(0.22),
                    colors.last?.opacity(0.12) ?? AppColors.accentSecondary.opacity(0.12),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .frame(
            width: 164,
            height: 118
        )
        .rotationEffect(.degrees(-10))
        .offset(
            x: 34,
            y: -28
        )
        .allowsHitTesting(false)
    }
}
