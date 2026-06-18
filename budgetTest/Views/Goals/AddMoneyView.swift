import SwiftUI

struct AddMoneyView: View {

    @EnvironmentObject var plaid: PlaidService
    @Environment(\.dismiss) var dismiss

    let goal: SavingsGoal

    @State private var centsText = ""

    @FocusState private var isAmountFocused: Bool

    private var amount: Double? {
        guard let cents = Double(centsText) else {
            return nil
        }
        return cents / 100
    }

    private var formattedAmount: String {
        let cents = Double(centsText) ?? 0
        let dollars = cents / 100
        return String(format: "$%.2f", dollars)
    }

    private var projectedAmount: Double {
        goal.currentAmount + (amount ?? 0)
    }

    private var projectedProgress: Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(projectedAmount / goal.targetAmount, 1.0)
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

                VStack {

                    VStack(spacing: 8) {

                        Text("Add Money")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text(goal.name)
                            .font(
                                .system(
                                    size: 34,
                                    weight: .bold
                                )
                            )

                    }
                    .padding(.top, 24)

                    Spacer()

                    // MARK: Amount Display

                    VStack(spacing: 12) {

                        Text("Amount")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ZStack {

                            Text(formattedAmount)
                                .font(
                                    .system(
                                        size: 64,
                                        weight: .bold
                                    )
                                )
                                .monospacedDigit()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isAmountFocused = true
                                }

                            TextField(
                                "",
                                text: $centsText
                            )
                            .keyboardType(.numberPad)
                            .foregroundColor(.clear)
                            .accentColor(.clear)
                            .focused($isAmountFocused)
                        }
                    }

                    Spacer()

                    // MARK: Goal Preview Card

                    VStack(
                        alignment: .leading,
                        spacing: 18
                    ) {

                        Text("Goal Progress")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(
                            projectedAmount,
                            format: .currency(code: "USD")
                        )
                        .font(
                            .system(
                                size: 36,
                                weight: .bold
                            )
                        )

                        ProgressView(
                            value: projectedProgress
                        )
                        .tint(.blue)

                        HStack {

                            Text(
                                "\(Int(projectedProgress * 100))% Complete"
                            )
                            .font(.caption)

                            Spacer()

                            Text(
                                goal.targetAmount,
                                format: .currency(code: "USD")
                            )
                            .font(.caption)
                        }
                        .foregroundColor(.secondary)
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
                    .padding(.horizontal)

                    // MARK: Quick Add

                    HStack(spacing: 12) {

                        quickAddButton(25)
                        quickAddButton(50)
                        quickAddButton(100)
                    }
                    .padding(.horizontal)

                    Spacer()

                    // MARK: Add Money Button

                    Button {

                        if let amount {
                            plaid.addMoney(
                                to: goal.id,
                                amount: amount
                            )
                            dismiss()
                        }

                    } label: {

                        HStack {

                            Image(
                                systemName:
                                    "plus.circle.fill"
                            )

                            Text("Add Money")

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
                    .disabled(amount == nil)
                    .opacity(
                        amount == nil ? 0.6 : 1.0
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {

                    Button {

                        dismiss()

                    } label: {

                        Image(
                            systemName: "xmark"
                        )
                        .font(.headline)
                    }
                }
            }
            .onAppear {

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.15
                ) {
                    isAmountFocused = true
                }
            }
        }
    }

    private func quickAddButton(
        _ value: Int
    ) -> some View {

        Button {

            centsText = String(
                value * 100
            )

            isAmountFocused = true

        } label: {

            Text("+$\(value)")
                .font(
                    .subheadline.weight(.semibold)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
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
    }
}
