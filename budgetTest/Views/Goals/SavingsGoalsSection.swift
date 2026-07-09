import SwiftUI

struct SavingsGoalsSection: View {

    let cashCushionAmount: Double
    let hasSavingsGoals: Bool
    let visibleSavingsGoals: [SavingsGoal]
    let trailing: AnyView
    let cashCushionAction: () -> Void
    let createAction: () -> Void
    let editAction: (SavingsGoal) -> Void
    let addMoneyAction: (SavingsGoal) -> Void

    private let style = CalderaCategoryStyle.style(for: .savingsGoal)
    private let cashCushionStyle = CalderaCategoryStyle.style(for: .reserve)

    var body: some View {
        SavingsSectionShell(
            title: "Savings Goals",
            style: style
        ) {
            trailing
        } content: {
            VStack(spacing: AppSpacing.small) {
                cashCushionRow

                if !hasSavingsGoals {
                    SavingsEmptyPreviewRow(
                        title: "Nothing planned here yet",
                        subtitle: "Create a goal for something you want to set money aside for.",
                        style: style
                    )
                } else {
                    ForEach(visibleSavingsGoals) { goal in
                        goalRow(goal)
                    }
                }

                SavingsQuickAddButton(
                    title: "Create Goal",
                    style: style,
                    accessibilityLabel: "Add savings goal",
                    action: createAction
                )
            }
        }
    }

    private var cashCushionRow: some View {
        SavingsCompactRow(
            title: "Cash Cushion",
            subtitle: "Flexible savings buffer",
            value: "\(AppFormatters.currency(cashCushionAmount))",
            style: cashCushionStyle,
            progress: 0,
            showsProgress: false,
            rowAction: cashCushionAction
        )
    }

    private func goalRow(
        _ goal: SavingsGoal
    ) -> some View {
        SavingsCompactRow(
            title: goal.name.isEmpty ? "Untitled Savings Goal" : goal.name,
            subtitle: "\(AppFormatters.currency(goal.currentAmount)) saved of \(AppFormatters.currency(goal.targetAmount))",
            value: "\(Int(goal.progress * 100))%",
            style: style,
            progress: goal.progress,
            rowAction: {
                editAction(goal)
            },
            accessorySystemImage: "plus.circle.fill",
            accessoryAccessibilityLabel: "Add money to \(goal.name)",
            accessoryAction: {
                addMoneyAction(goal)
            }
        )
    }
}
