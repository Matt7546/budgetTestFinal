import SwiftUI

struct SavingsHeaderMetricsSection: View {

    let cashCushionTotal: Double
    let goalsTotal: Double
    let upcomingExpensesTotal: Double
    let debtPayoffTotal: Double

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .flexible(),
                    spacing: AppSpacing.small
                ),
                GridItem(
                    .flexible(),
                    spacing: AppSpacing.small
                )
            ],
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            metricCard(
                title: "Cash Cushion",
                value: cashCushionTotal,
                style: CalderaCategoryStyle.style(for: .reserve)
            )

            metricCard(
                title: "Goals",
                value: goalsTotal,
                style: CalderaCategoryStyle.style(for: .savingsGoal)
            )

            metricCard(
                title: "Upcoming Expenses",
                value: upcomingExpensesTotal,
                style: CalderaCategoryStyle.style(for: .upcomingExpense)
            )

            metricCard(
                title: "Debt Payoff",
                value: debtPayoffTotal,
                style: CalderaCategoryStyle.style(for: .debtPayoff)
            )
        }
    }

    private func metricCard(
        title: String,
        value: Double,
        style: CalderaCategoryStyle
    ) -> some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.small
        ) {
            CalderaGradientIcon(
                style: style,
                size: 38,
                iconSize: 15
            )
            .layoutPriority(1)

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppFormatters.currency(value))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(style.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppSpacing.compact)
        .padding(.horizontal, AppSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: 0.88,
            strokeOpacity: 0.72,
            shadowOpacity: 0.036,
            shadowRadius: 14,
            shadowY: 7
        )
        .accessibilityElement(children: .combine)
    }
}
