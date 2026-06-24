import SwiftUI

struct DashboardHeroCard: View {

    let netWorth: Double
    let targetHeight: CGFloat?

    init(
        netWorth: Double,
        targetHeight: CGFloat? = nil
    ) {
        self.netWorth = netWorth
        self.targetHeight = targetHeight
    }

    var body: some View {
        let accentColor =
            netWorth >= 0
            ? AppColors.accent
            : AppColors.negative

        VStack(
            alignment: .leading,
            spacing: 10
        ) {

            Text("Net Worth")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            Text(
                AppFormatters.currency(
                    netWorth
                )
            )
            .font(
                .system(
                    size: 42,
                    weight: .bold
                )
            )
            .foregroundColor(
                netWorth >= 0
                ? AppColors.primaryText
                : AppColors.negative
            )
            .lineLimit(1)
            .minimumScaleFactor(0.62)

            HStack {

                Label(
                    "Safe To Spend",
                    systemImage: "arrow.up.right"
                )
                .foregroundColor(AppColors.spendable)

                Spacer()

                Text("Tap for Details")
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(
            maxWidth: .infinity,
            minHeight: targetHeight,
            alignment: .leading
        )
        .dashboardGlassCard(
            cornerRadius: AppRadii.panel,
            accent: accentColor,
            bloomOpacity: 0.08,
            borderOpacity: 0.82,
            shadow: AppShadows.softPanel
        )
    }
}
