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

        let value = projectedAmount / goal.targetAmount
        guard value.isFinite else { return 0 }

        return min(
            max(value, 0),
            1
        )
    }

    var body: some View {

        NavigationStack {

            ZStack {

                CalderaPageBackground(mood: .savings)

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

                    amountEntryCard

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
                            AppFormatters.currency(
                                projectedAmount
                            )
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
                                AppFormatters.currency(
                                    goal.targetAmount
                                )
                            )
                            .font(.caption)
                        }
                        .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(24)
                    .calderaGlassCard(
                        cornerRadius: AppRadii.panel,
                        fillOpacity: 0.88,
                        strokeOpacity: 0.72,
                        shadowOpacity: 0.04,
                        shadowRadius: 18,
                        shadowY: 8,
                        darkGlowColor: CalderaCategoryStyle.style(for: .savingsGoal).primary
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

                    if amount == nil {
                        Text("Enter an amount to save.")
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                    }
                }
            }
            .keyboardDismissToolbar()
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

                ToolbarItem(
                    placement: .confirmationAction
                ) {

                    Button("Save") {
                        saveMoney()
                    }
                    .disabled(amount == nil)
                    .accessibilityLabel("Save money to goal")
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

    private func saveMoney() {
        guard let amount else {
            return
        }

        plaid.addMoney(
            to: goal.id,
            amount: amount
        )
        dismiss()
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
                .calderaGlassCard(
                    cornerRadius: AppRadii.button,
                    fillOpacity: 0.86,
                    strokeOpacity: 0.68,
                    shadowOpacity: 0.0,
                    shadowRadius: 0,
                    shadowY: 0,
                    darkGlowColor: CalderaCategoryStyle.style(for: .savingsGoal).primary
                )
        }
        .foregroundColor(
            AppColors.primaryText
        )
        .accessibilityLabel("Add \(value) dollars")
    }

    private var amountEntryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: CalderaCategoryStyle.style(for: .savingsGoal),
                    size: 42,
                    iconSize: 18
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Amount to Add")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text("Money set aside for this goal")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer(minLength: 0)
            }

            ZStack {
                Text(formattedAmount)
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.large)
            .padding(.horizontal, AppSpacing.regular)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.86,
                strokeOpacity: 0.70,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: CalderaCategoryStyle.style(for: .savingsGoal).primary
            )
            .accessibilityElement(children: .contain)
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.88,
            strokeOpacity: 0.74,
            shadowOpacity: 0.04,
            shadowRadius: 18,
            shadowY: 8,
            darkGlowColor: CalderaCategoryStyle.style(for: .savingsGoal).primary
        )
        .padding(.horizontal)
    }
}
