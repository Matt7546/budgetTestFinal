import SwiftUI

struct SavingsHeaderMetricsSection: View {

    let goalsTotal: Double
    let upcomingExpensesTotal: Double
    let debtPayoffTotal: Double

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.xSmall),
                    GridItem(.flexible(), spacing: AppSpacing.xSmall),
                    GridItem(.flexible(), spacing: AppSpacing.xSmall)
                ],
                alignment: .leading,
                spacing: AppSpacing.xSmall
            ) {
                metricCard(
                    title: "Goals",
                    value: goalsTotal,
                    caption: "Set aside so far",
                    style: CalderaCategoryStyle.style(for: .savingsGoal)
                )

                metricCard(
                    title: "Upcoming",
                    value: upcomingExpensesTotal,
                    caption: "For expenses",
                    style: CalderaCategoryStyle.style(for: .upcomingExpense),
                    accessibilityLabel: "Upcoming Expenses"
                )

                metricCard(
                    title: "Payment Plans",
                    value: debtPayoffTotal,
                    caption: "For payment plans",
                    style: CalderaCategoryStyle.style(for: .debtPayoff)
                )
            }

            Label(
                "Cash Cushion remains available below as a flexible balance and is included in total Set Aside.",
                systemImage: "info.circle.fill"
            )
            .font(.caption.weight(.medium))
            .foregroundColor(AppColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricCard(
        title: String,
        value: Double,
        caption: String,
        style: CalderaCategoryStyle,
        accessibilityLabel: String? = nil
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xSmall
        ) {
            CalderaGradientIcon(
                style: style,
                size: 34,
                iconSize: 14
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(AppFormatters.currency(value))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(style.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .monospacedDigit()

                Text(caption)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppSpacing.compact)
        .padding(.horizontal, AppSpacing.small)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: 0.88,
            strokeOpacity: 0.72,
            shadowOpacity: 0.036,
            shadowRadius: 14,
            shadowY: 7
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}
