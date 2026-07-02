import SwiftUI

struct DashboardMetricGrid: View {

    let totalCash: Double
    let totalDebt: Double
    let totalSavings: Double
    let reserveBalance: Double
    let totalAvailable: Double
    let nextExpenseValueText: String
    let nextExpenseSubtitle: String
    let hasNextExpense: Bool
    let nextExpenseAccentColor: Color
    let onCash: () -> Void
    let onDebt: () -> Void
    let onSavings: () -> Void
    let onReserve: () -> Void
    let onAvailable: () -> Void
    let onNextExpense: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(
            columns: columns,
            spacing: 12
        ) {

            Button(action: onCash) {
                MetricCard(
                    title: "Cash",
                    value: totalCash,
                    subtitle: "Spendable cash",
                    systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
                    iconColor: CalderaCategoryStyle.style(for: .bankAccount).primary
                )
            }
            .buttonStyle(.plain)

            Button(action: onAvailable) {
                MetricCard(
                    title: "Available to Spend",
                    value: totalAvailable,
                    subtitle: "After set-asides",
                    systemImage: totalAvailable >= 0
                        ? CalderaCategoryStyle.style(for: .safeToSpend).icon
                        : CalderaCategoryStyle.style(for: .shortfall).icon,
                    iconColor: totalAvailable >= 0
                        ? CalderaCategoryStyle.style(for: .safeToSpend).primary
                        : CalderaCategoryStyle.style(for: .shortfall).primary,
                    valueColor: totalAvailable >= 0
                        ? AppColors.primaryText
                        : CalderaCategoryStyle.style(for: .shortfall).primary
                )
            }
            .buttonStyle(.plain)

            Button(action: onSavings) {
                MetricCard(
                    title: "Set Aside",
                    value: totalSavings,
                    subtitle: "Goals, bills, cushion",
                    systemImage: CalderaCategoryStyle.style(for: .reserve).icon,
                    iconColor: CalderaCategoryStyle.style(for: .reserve).primary
                )
            }
            .buttonStyle(.plain)

            Button(action: onReserve) {
                MetricCard(
                    title: "Cash Cushion",
                    value: reserveBalance,
                    subtitle: "Flexible set-aside",
                    systemImage: CalderaCategoryStyle.style(for: .reserve).icon,
                    iconColor: CalderaCategoryStyle.style(for: .reserve).primary
                )
            }
            .buttonStyle(.plain)

            Button(action: onDebt) {
                MetricCard(
                    title: "Debt",
                    value: totalDebt,
                    subtitle: "Amount owed",
                    systemImage: CalderaCategoryStyle.style(for: .debtPayoff).icon,
                    iconColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
                )
            }
            .buttonStyle(.plain)

            Button(action: onNextExpense) {
                MetricCard(
                    title: "Next Expense",
                    valueText: nextExpenseValueText,
                    subtitle: nextExpenseSubtitle,
                    systemImage: CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                    iconColor: CalderaCategoryStyle.style(for: .upcomingExpense).primary,
                    valueColor: hasNextExpense
                        ? CalderaCategoryStyle.style(for: .upcomingExpense).primary
                        : AppColors.primaryText
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}
