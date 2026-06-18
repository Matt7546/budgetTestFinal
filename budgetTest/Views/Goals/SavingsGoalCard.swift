import SwiftUI

struct SavingsGoalCard: View {

    let goal: SavingsGoal
    let onAdd: () -> Void
    let onEdit: () -> Void

    private var progress: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(goal.currentAmount / goal.targetAmount, 1.0)
    }

    private var remainingAmount: Double {
        max(goal.targetAmount - goal.currentAmount, 0)
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 18
        ) {

            // MARK: Header

            HStack(alignment: .top) {

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {

                    Text(goal.name)
                        .font(
                            .system(
                                size: 22,
                                weight: .bold
                            )
                        )

                    Text("Savings Goal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                ZStack {

                    Circle()
                        .fill(
                            Color.blue.opacity(0.12)
                        )
                        .frame(
                            width: 52,
                            height: 52
                        )

                    Image(systemName: "target")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }

            // MARK: Amount

            VStack(
                alignment: .leading,
                spacing: 6
            ) {

                Text("Saved So Far")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(
                    goal.currentAmount,
                    format: .currency(code: "USD")
                )
                .font(
                    .system(
                        size: 36,
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

            // MARK: Progress

            VStack(
                alignment: .leading,
                spacing: 8
            ) {

                ProgressView(value: progress)
                    .tint(.blue)

                HStack {

                    Text(
                        "\(Int(progress * 100))% Complete"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Spacer()

                    Text(
                        goal.targetAmount,
                        format: .currency(code: "USD")
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                }
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.25),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // MARK: Details

            HStack {

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {

                    Text("Remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(
                        remainingAmount,
                        format: .currency(code: "USD")
                    )
                    .font(.headline)
                }

                Spacer()

                VStack(
                    alignment: .trailing,
                    spacing: 4
                ) {

                    Text("Target")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(
                        goal.targetAmount,
                        format: .currency(code: "USD")
                    )
                    .font(.headline)
                }
            }

            // MARK: Actions

            HStack(spacing: 12) {

                Button {

                    print("🔥 EDIT BUTTON INSIDE CARD")
                    onEdit()

                } label: {

                    HStack {

                        Image(systemName: "pencil")

                        Text("Edit")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(
                            cornerRadius: 18
                        )
                        .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 18
                        )
                        .stroke(
                            Color.white.opacity(0.85),
                            lineWidth: 1
                        )
                    )
                }
                .foregroundColor(
                    Color(
                        red: 0.10,
                        green: 0.14,
                        blue: 0.22
                    )
                )

                Button {

                    print("🔥 ADD BUTTON INSIDE CARD")
                    onAdd()

                } label: {

                    HStack {

                        Image(
                            systemName:
                                "plus.circle.fill"
                        )

                        Text("Add Money")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
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
                    .foregroundColor(.white)
                    .cornerRadius(18)
                }
            }
        }
        .padding(24)
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
            .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 30
            )
            .stroke(
                Color.white.opacity(0.85),
                lineWidth: 1
            )
            .allowsHitTesting(false)
        )
        .shadow(
            color: .black.opacity(0.05),
            radius: 30,
            y: 15
        )
    }
}
