import SwiftUI

struct SavingsOverviewCard: View {

    let totalSaved: Double
    let totalTarget: Double
    let overallProgress: Double
    let goalCount: Int

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {

            HStack(
                alignment: .top
            ) {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xSmall
                ) {
                    Text("Savings Overview")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)

                    MetricValue(
                        totalSaved,
                        font: .system(
                            size: 34,
                            weight: .bold,
                            design: .rounded
                        ),
                        minimumScaleFactor: 0.7,
                        lineLimit: 1
                    )

                    Text("Total saved")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                MetricLabelValue(
                    label: "Target",
                    value: totalTarget,
                    alignment: .trailing,
                    spacing: AppSpacing.xSmall,
                    labelColor: AppColors.secondaryText
                )
            }

            ProgressView(
                value: overallProgress
            )
            .tint(AppColors.protected)

            HStack(spacing: AppSpacing.xSmall) {
                Text("\(goalCount)")
                    .font(.headline)

                Text(goalCount == 1 ? "savings goal" : "savings goals")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding(AppSpacing.card)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.glassOverlayProtected,
                    AppColors.protected.opacity(0.04)
                ]
            ),
            accent: AppColors.protected,
            shadow: AppShadows.softPanel
        )
    }
}
