import SwiftUI

struct SavingsUpcomingExpensesSection: View {

    let hasUpcomingExpenses: Bool
    let visibleRows: [SavingsUpcomingExpenseRow]
    let trailing: AnyView
    let addAction: () -> Void
    let selectAction: (ForecastEvent) -> Void

    private let style = CalderaCategoryStyle.style(for: .upcomingExpense)
    private let presentation = SetAsideSectionPresentation.content(
        for: .upcomingExpenses
    )

    var body: some View {
        SavingsSectionShell(
            title: presentation.title,
            description: presentation.purpose,
            style: style
        ) {
            trailing
        } content: {
            VStack(spacing: AppSpacing.small) {
                if !hasUpcomingExpenses {
                    SavingsEmptyPreviewRow(
                        title: presentation.emptyTitle,
                        subtitle: presentation.emptyDetail,
                        style: style
                    )
                } else {
                    ForEach(visibleRows) { row in
                        expenseRow(row)
                    }
                }

                SavingsQuickAddButton(
                    title: presentation.quickAddTitle ?? "Add Upcoming Expense",
                    style: style,
                    accessibilityLabel: presentation.quickAddTitle ?? "Add Upcoming Expense",
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
