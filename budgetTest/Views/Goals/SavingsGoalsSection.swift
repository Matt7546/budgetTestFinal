import SwiftUI

struct SavingsGoalsSection: View {

    let hasSavingsGoals: Bool
    let visibleSavingsGoals: [SavingsGoal]
    let trailing: AnyView
    let createAction: () -> Void
    let editAction: (SavingsGoal) -> Void
    let addMoneyAction: (SavingsGoal) -> Void

    private let style = CalderaCategoryStyle.style(for: .savingsGoal)

    var body: some View {
        SavingsSectionShell(
            title: "Savings Goals",
            style: style
        ) {
            trailing
        } content: {
            VStack(spacing: AppSpacing.small) {
                if !hasSavingsGoals {
                    SavingsEmptyPreviewRow(
                        title: "No savings goals yet",
                        subtitle: "Save toward something specific while keeping that money out of Available to Spend.",
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
