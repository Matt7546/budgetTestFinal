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
                    systemImage: "wallet.pass.fill",
                    iconColor: AppColors.spendable
                )
            }
            .buttonStyle(.plain)

            Button(action: onAvailable) {
                MetricCard(
                    title: "Safe To Spend",
                    value: totalAvailable,
                    subtitle: "After protection",
                    systemImage: "checkmark.circle.fill",
                    iconColor: totalAvailable >= 0
                        ? AppColors.accent
                        : AppColors.negative,
                    valueColor: totalAvailable >= 0
                        ? AppColors.primaryText
                        : AppColors.negative
                )
            }
            .buttonStyle(.plain)

            Button(action: onSavings) {
                MetricCard(
                    title: "Protected Money",
                    value: totalSavings,
                    subtitle: "Savings and expenses",
                    systemImage: "shield.fill",
                    iconColor: AppColors.protected
                )
            }
            .buttonStyle(.plain)

            Button(action: onReserve) {
                MetricCard(
                    title: "Savings Reserve",
                    value: reserveBalance,
                    subtitle: "Protected balance",
                    systemImage: "lock.shield.fill",
                    iconColor: AppColors.protected
                )
            }
            .buttonStyle(.plain)

            Button(action: onDebt) {
                MetricCard(
                    title: "Debt",
                    value: totalDebt,
                    subtitle: "Amount owed",
                    systemImage: "creditcard.fill",
                    iconColor: AppColors.obligation
                )
            }
            .buttonStyle(.plain)

            Button(action: onNextExpense) {
                MetricCard(
                    title: "Next Expense",
                    valueText: nextExpenseValueText,
                    subtitle: nextExpenseSubtitle,
                    systemImage: "calendar.badge.exclamationmark",
                    iconColor: nextExpenseAccentColor,
                    valueColor: hasNextExpense
                        ? nextExpenseAccentColor
                        : AppColors.primaryText
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}
