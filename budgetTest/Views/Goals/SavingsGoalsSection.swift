import SwiftUI

struct SavingsGoalsSection: View {

    let hasSavingsGoals: Bool
    let visibleSavingsGoals: [SavingsGoal]
    let trailing: AnyView
    let createAction: () -> Void
    let editAction: (SavingsGoal) -> Void
    let addMoneyAction: (SavingsGoal) -> Void

    private let style = CalderaCategoryStyle.style(for: .savingsGoal)
    private let presentation = SetAsideSectionPresentation.content(
        for: .savingsGoals
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
                if !hasSavingsGoals {
                    SavingsEmptyPreviewRow(
                        title: presentation.emptyTitle,
                        subtitle: presentation.emptyDetail,
                        style: style
                    )
                } else {
                    ForEach(visibleSavingsGoals) { goal in
                        goalRow(goal)
                    }
                }

                SavingsQuickAddButton(
                    title: presentation.quickAddTitle ?? "Create Savings Goal",
                    style: style,
                    accessibilityLabel: presentation.quickAddTitle ?? "Create Savings Goal",
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
