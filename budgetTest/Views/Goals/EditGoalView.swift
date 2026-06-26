import SwiftUI

struct EditGoalView: View {

    @EnvironmentObject var plaid: PlaidService
    @Environment(\.dismiss) var dismiss

    private let isNew: Bool
    private let originalGoal: SavingsGoal

    @State private var draft: SavingsGoal
    @State private var saveRequestID = 0

    init(goal: SavingsGoal, isNew: Bool = false) {
        self.isNew = isNew
        self.originalGoal = goal
        _draft = State(initialValue: goal)
    }

    private var progress: Double {
        guard draft.targetAmount > 0 else { return 0 }
        return min(draft.currentAmount / draft.targetAmount, 1.0)
    }

    private var remaining: Double {
        max(draft.targetAmount - draft.currentAmount, 0)
    }

    var body: some View {

        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                backgroundStyle: .staticGradient,
                contentPadding: .all,
                contentSpacing: AppSpacing.regular
            ) {
                GoalForm(
                    mode: .edit(
                        draft: $draft,
                        isNew: isNew,
                        progress: progress,
                        remaining: remaining,
                        canSave: canSave,
                        saveRequestID: saveRequestID,
                        onSave: { saveGoal() },
                        onDelete: isNew ? nil : { deleteGoal() }
                    )
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {

                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel savings changes")
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {

                    Button(isNew ? "Add" : "Save") {
                        saveRequestID += 1
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(isNew ? "Add savings goal" : "Save savings changes")
                }
            }
        }
    }

    private func saveGoal() {

        if isNew {
            plaid.addGoal(draft)
        } else {
            plaid.updateGoal(draft)
        }

        dismiss()
    }

    private func deleteGoal() {

        plaid.deleteGoal(
            originalGoal
        )

        dismiss()
    }

    private var canSave: Bool {

        if isNew {

            return !draft.name
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
            &&
            draft.targetAmount > 0
        }

        let nameOK =
            !draft.name
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty

        let targetOK =
            draft.targetAmount > 0

        return nameOK
            && targetOK
            && draft != originalGoal
    }

}
