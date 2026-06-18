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

                        // MARK: Header

                        VStack(
                            alignment: .leading,
                            spacing: 6
                        ) {

                            Text("Create New Goal")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("Savings Goal")
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

                        // MARK: Goal Name

                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {

                            Text("Goal Name")
                                .font(.headline)

                            TextField(
                                "Emergency Fund",
                                text: $name
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

                        // MARK: Target Amount

                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {

                            Text("Target Amount")
                                .font(.headline)

                            TextField(
                                "10000",
                                text: $targetAmount
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

                        // MARK: Impact Card

                        VStack(
                            alignment: .leading,
                            spacing: 18
                        ) {

                            Text("Financial Impact")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(
                                previewAvailable,
                                format: .currency(code: "USD")
                            )
                            .font(
                                .system(
                                    size: 42,
                                    weight: .bold
                                )
                            )
                            .foregroundColor(
                                previewAvailable >= 0
                                ? .green
                                : .red
                            )

                            HStack {

                                Text("Available After Goal")

                                Spacer()

                                Image(
                                    systemName:
                                        previewAvailable >= 0
                                        ? "checkmark.circle.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                .foregroundColor(
                                    previewAvailable >= 0
                                    ? .green
                                    : .orange
                                )
                            }
                            .font(.caption)
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

                        // MARK: Save Button

                        Button {

                            saveGoal()

                        } label: {

                            HStack {

                                Image(
                                    systemName:
                                        "target"
                                )

                                Text("Create Goal")

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
