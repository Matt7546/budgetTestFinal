import SwiftUI

struct EditGoalView: View {

    @EnvironmentObject var plaid: PlaidService
    @Environment(\.dismiss) var dismiss

    private let isNew: Bool
    private let onSaved: ((Bool) -> Void)?
    private let onDeleted: (() -> Void)?

    @State private var draft: SavingsGoal
    @State private var savedGoalSnapshot: SavingsGoal
    @State private var saveRequestID = 0
    @State private var isAdjustingSetAside = false
    @State private var confirmationMessage: String?
    @State private var confirmationID = UUID()

    init(
        goal: SavingsGoal,
        isNew: Bool = false,
        onSaved: ((Bool) -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        self.isNew = isNew
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _draft = State(initialValue: goal)
        _savedGoalSnapshot = State(initialValue: goal)
    }

    private var progress: Double {
        guard draft.targetAmount > 0 else { return 0 }

        let value = draft.currentAmount / draft.targetAmount
        guard value.isFinite else { return 0 }

        return min(
            max(value, 0),
            1
        )
    }

    private var remaining: Double {
        max(draft.targetAmount - draft.currentAmount, 0)
    }

    var body: some View {

        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                backgroundStyle: .editorModal(.savingsGoal),
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
                        onDelete: isNew ? nil : { deleteGoal() },
                        onAdjustSetAside: isNew ? nil : {
                            isAdjustingSetAside = true
                        }
                    )
                )
            }
            .navigationTitle(isNew ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .calderaConfirmationOverlay(message: confirmationMessage)
            .sheet(isPresented: $isAdjustingSetAside) {
                AdjustGoalSetAsideView(
                    goal: savedGoalSnapshot,
                    onSaved: adjustSetAside
                )
            }
            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {

                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel")
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {

                    Button("Save") {
                        saveRequestID += 1
                    }
                    .disabled(!canSave)
                    .accessibilityLabel("Save")
                }
            }
        }
    }

    private func saveGoal() {

        if isNew {
            plaid.addGoal(draft)
        } else {
            plaid.updateGoal(draft)
            savedGoalSnapshot = draft
        }

        onSaved?(isNew)

        dismiss()
    }

    private func deleteGoal() {

        plaid.deleteGoal(
            savedGoalSnapshot
        )

        onDeleted?()

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
            && draft != savedGoalSnapshot
    }

    private func adjustSetAside(
        to newAmount: Double
    ) {
        var updatedGoal = savedGoalSnapshot
        updatedGoal.currentAmount = newAmount

        plaid.updateGoal(updatedGoal)

        savedGoalSnapshot = updatedGoal
        draft.currentAmount = newAmount
        showConfirmation("Goal Set Aside updated.")
    }

    private func showConfirmation(
        _ message: String
    ) {
        let id = UUID()
        confirmationID = id
        confirmationMessage = message

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)

            if confirmationID == id {
                confirmationMessage = nil
            }
        }
    }

}
