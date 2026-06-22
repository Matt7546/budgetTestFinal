import SwiftUI

struct SavingsGoalListSection: View {

    let goals: [SavingsGoal]
    let onCreate: () -> Void
    let onAdd: (SavingsGoal) -> Void
    let onEdit: (SavingsGoal) -> Void

    var body: some View {
        if goals.isEmpty {

            EmptyStateView(
                systemImage: "target",
                title: "Start your Savings Goals",
                description: "Create your first savings goal and keep it separate from everyday spending.",
                primaryActionTitle: "Create Savings Goal",
                primaryAction: onCreate,
                color: AppColors.protected
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
