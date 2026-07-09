import SwiftUI

struct SavingsHeaderMetricsSection: View {

    let goalsTotal: Double
    let upcomingExpensesTotal: Double
    let debtPayoffTotal: Double

    var body: some View {
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
                style: CalderaCategoryStyle.style(for: .savingsGoal)
            )

            metricCard(
                title: "Upcoming",
                value: upcomingExpensesTotal,
                style: CalderaCategoryStyle.style(for: .upcomingExpense),
                accessibilityLabel: "Upcoming Expenses"
            )

            metricCard(
                title: "Payment Plans",
                value: debtPayoffTotal,
                style: CalderaCategoryStyle.style(for: .debtPayoff)
            )
        }
    }

    private func metricCard(
        title: String,
        value: Double,
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppSpacing.compact)
        .padding(.horizontal, AppSpacing.small)
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .leading)
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
