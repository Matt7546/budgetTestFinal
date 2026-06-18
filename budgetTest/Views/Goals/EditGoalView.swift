import SwiftUI

struct EditGoalView: View {

    @EnvironmentObject var plaid: PlaidService
    @Environment(\.dismiss) var dismiss

    private let isNew: Bool
    private let originalGoal: SavingsGoal

    @State private var draft: SavingsGoal

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

            ZStack {

                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.97, blue: 1.00),
                        Color(red: 0.92, green: 0.95, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {

                    VStack(
                        alignment: .leading,
                        spacing: 24
                    ) {

                        VStack(
                            alignment: .leading,
                            spacing: 6
                        ) {

                            Text(
                                isNew
                                ? "Create New Goal"
                                : "Update Goal"
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                            Text(
                                isNew
                                ? "New Goal"
                                : "Edit Goal"
                            )
                            .font(
                                .system(
                                    size: 38,
                                    weight: .bold
                                )
                            )
                            .foregroundColor(
                                Color(
                                    red: 0.10,
                                    green: 0.14,
                                    blue: 0.22
                                )
                            )
                        }

                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {

                            Text("Goal Name")
                                .font(.headline)

                            TextField(
                                "Emergency Fund",
                                text: $draft.name
                            )
                            .padding()
                            .background(
                                RoundedRectangle(
                                    cornerRadius: 20
                                )
                                .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: 20
                                )
                                .stroke(
                                    Color.white.opacity(0.85),
                                    lineWidth: 1
                                )
                            )
                        }

                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {

                            Text("Target Amount")
                                .font(.headline)

                            TextField(
                                "$0.00",
                                value: $draft.targetAmount,
                                format: .number
                            )
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(
                                RoundedRectangle(
                                    cornerRadius: 20
                                )
                                .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: 20
                                )
                                .stroke(
                                    Color.white.opacity(0.85),
                                    lineWidth: 1
                                )
                            )
                        }

                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {

                            Text("Saved So Far")
                                .font(.headline)

                            TextField(
                                "$0.00",
                                value: $draft.currentAmount,
                                format: .number
                            )
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(
                                RoundedRectangle(
                                    cornerRadius: 20
                                )
                                .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: 20
                                )
                                .stroke(
                                    Color.white.opacity(0.85),
                                    lineWidth: 1
                                )
                            )
                        }

                        VStack(
                            alignment: .leading,
                            spacing: 18
                        ) {

                            Text("Goal Progress")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(
                                draft.currentAmount,
                                format: .currency(code: "USD")
                            )
                            .font(
                                .system(
                                    size: 42,
                                    weight: .bold
                                )
                            )

                            ProgressView(
                                value: progress
                            )
                            .tint(.blue)

                            HStack {

                                VStack(
                                    alignment: .leading
                                ) {

                                    Text("Remaining")
                                        .font(.caption)

                                    Text(
                                        remaining,
                                        format: .currency(code: "USD")
                                    )
                                    .font(.headline)
                                }

                                Spacer()

                                VStack(
                                    alignment: .trailing
                                ) {

                                    Text("Target")
                                        .font(.caption)

                                    Text(
                                        draft.targetAmount,
                                        format: .currency(code: "USD")
                                    )
                                    .font(.headline)
                                }
                            }
                        }
                        .padding(28)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .background(
                            RoundedRectangle(
                                cornerRadius: 30
                            )
                            .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 30
                            )
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        Color.cyan.opacity(0.08),
                                        Color.green.opacity(0.05),
                                        Color.blue.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 30
                            )
                            .stroke(
                                Color.white.opacity(0.85),
                                lineWidth: 1
                            )
                        )
                        .shadow(
                            color: .black.opacity(0.05),
                            radius: 30,
                            y: 15
                        )

                        Button {

                            if isNew {
                                plaid.addGoal(draft)
                            } else {
                                plaid.updateGoal(draft)
                            }

                            dismiss()

                        } label: {

                            HStack {

                                Image(
                                    systemName:
                                        "checkmark.circle.fill"
                                )

                                Text("Save Goal")

                                Spacer()

                                Image(
                                    systemName:
                                        "arrow.right"
                                )
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color.blue,
                                        Color.cyan
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                        }
                        .disabled(!canSave)
                        .opacity(
                            canSave ? 1.0 : 0.6
                        )

                        if !isNew {

                            Button {

                                plaid.deleteGoal(
                                    originalGoal
                                )

                                dismiss()

                            } label: {

                                HStack {

                                    Image(
                                        systemName:
                                            "trash"
                                    )

                                    Text("Delete Goal")

                                    Spacer()
                                }
                                .font(.headline)
                                .foregroundColor(.red)
                                .padding()
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: 20
                                    )
                                    .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: 20
                                    )
                                    .stroke(
                                        Color.red.opacity(0.25),
                                        lineWidth: 1
                                    )
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {

                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
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
