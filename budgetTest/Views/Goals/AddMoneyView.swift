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
                        AppColors.screenGradientTop,
                        AppColors.screenGradientBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack {

                    ModalHeaderView(
                        eyebrow: "Add Money",
                        title: goal.name,
                        subtitle: "Add money toward this savings goal.",
                        systemImage: "plus.circle.fill",
                        color: AppColors.protected
                    )
                    .padding(.top, 24)
                    .padding(.horizontal)

                    Spacer()

                    // MARK: Amount Display

                    VStack(spacing: 12) {

                        Text("Amount")
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)

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
                            .accessibilityLabel("Money to Add")
                            .accessibilityValue(formattedAmount)
                        }
                        .accessibilityElement(children: .contain)
                    }

                    Spacer()

                    // MARK: Goal Preview Card

                    VStack(
                        alignment: .leading,
                        spacing: 18
                    ) {

                        Text("Savings Progress")
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)

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
                        .tint(AppColors.protected)

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
                        .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(24)
                    .glassCard(
                        cornerRadius: AppRadii.panel,
                        overlay: .gradient(
                            colors: [
                                AppColors.glassOverlayWhite,
                                AppColors.glassOverlayProtected,
                                AppColors.protected.opacity(0.04)
                            ]
                        ),
                        shadow: nil
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

                    PrimaryButton(
                        "Add Money",
                        systemImage: "plus.circle.fill",
                        trailingSystemImage: nil,
                        isDisabled: amount == nil,
                        fillsWidth: true
                    ) {
                        if let amount {
                            plaid.addMoney(
                                to: goal.id,
                                amount: amount
                            )
                            dismiss()
                        }
                    }
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
                    .accessibilityLabel("Cancel add money")
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
                .glassCard(
                    cornerRadius: AppRadii.button,
                    shadow: nil
                )
        }
        .foregroundColor(
            AppColors.primaryText
        )
        .accessibilityLabel("Add \(value) dollars")
    }
}
