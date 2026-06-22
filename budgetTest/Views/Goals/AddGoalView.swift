import SwiftUI

struct AddGoalView: View {

    @EnvironmentObject var plaid: PlaidService
    @EnvironmentObject var summary: SummaryViewModel
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var targetAmount = ""

    private var targetValue: Double {
        Double(targetAmount) ?? 0
    }

    private var previewAvailable: Double {
        summary.totalAvailable - targetValue
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && targetValue > 0
    }

    var body: some View {

        AppScreen {
            GoalForm(
                mode: .add(
                    name: $name,
                    targetAmount: $targetAmount,
                    previewAvailable: previewAvailable,
                    canSave: canSave,
                    onSave: { saveGoal() }
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
                .accessibilityLabel("Cancel savings creation")
            }
        }
    }

    private func saveGoal() {

        guard let target = Double(targetAmount)
        else { return }

        plaid.addGoal(
            SavingsGoal(
                name: name,
                targetAmount: target,
                currentAmount: 0
            )
        )

        dismiss()
    }
}
