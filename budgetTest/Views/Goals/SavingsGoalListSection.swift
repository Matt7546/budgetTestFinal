import SwiftUI

struct SavingsGoalListSection: View {

    let goals: [SavingsGoal]
    let onCreate: () -> Void
    let onAdd: (SavingsGoal) -> Void
    let onEdit: (SavingsGoal) -> Void

    var body: some View {
        if goals.isEmpty {

            EmptyStateView(
                systemImage: CalderaCategoryStyle.style(for: .savingsGoal).icon,
                title: "No savings goals yet",
                description: "Save toward something specific while keeping that money out of Available to Spend.",
                primaryActionTitle: "Create Goal",
                primaryAction: onCreate,
                color: CalderaCategoryStyle.style(for: .savingsGoal).primary
            )

        } else {

            VStack(
                spacing: 16
            ) {
                SectionTitle(
                    "Savings Goals",
                    font: .title3.bold()
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

                ForEach(
                    goals
                ) { goal in

                    SavingsGoalCard(
                        goal: goal,
                        onAdd: {
                            onAdd(goal)
                        },
                        onEdit: {
                            onEdit(goal)
                        }
                    )
                }
            }
        }
    }
}
