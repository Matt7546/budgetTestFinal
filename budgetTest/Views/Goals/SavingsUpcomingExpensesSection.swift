import SwiftUI

struct SavingsUpcomingExpensesSection: View {

    let hasUpcomingExpenses: Bool
    let visibleRows: [SavingsUpcomingExpenseRow]
    let trailing: AnyView
    let addAction: () -> Void
    let selectAction: (ForecastEvent) -> Void

    private let style = CalderaCategoryStyle.style(for: .upcomingExpense)

    var body: some View {
        SavingsSectionShell(
            title: "Upcoming Expenses",
            style: style
        ) {
            trailing
        } content: {
            VStack(spacing: AppSpacing.small) {
                if !hasUpcomingExpenses {
                    SavingsEmptyPreviewRow(
                        title: "Nothing planned here yet",
                        subtitle: "Add an upcoming expense when you want Caldera to help keep it visible.",
                        style: style
                    )
                } else {
                    ForEach(visibleRows) { row in
                        expenseRow(row)
                    }
                }

                SavingsQuickAddButton(
                    title: "Add Expense",
                    style: style,
                    accessibilityLabel: "Add upcoming expense",
                    action: addAction
                )
            }
        }
    }

    private func expenseRow(
        _ row: SavingsUpcomingExpenseRow
    ) -> some View {
        SavingsCompactRow(
            title: row.forecast.event.name,
            subtitle: "\(AppFormatters.abbreviatedMonthDay(row.forecast.occurrenceDate)) · \(AppFormatters.currency(row.allocatedAmount)) set aside",
            value: row.remainingAmount <= 0
                ? "Covered"
                : "Still needs \(AppFormatters.currency(row.remainingAmount))",
            style: style,
            valueStyle: row.remainingAmount <= 0
                ? CalderaCategoryStyle.style(for: .covered)
                : CalderaCategoryStyle.style(for: .needsMoney),
            progress: row.progress,
            rowAction: {
                selectAction(row.forecast)
            }
        )
    }
}
