import SwiftUI

struct AddMoneyView: View {

    @EnvironmentObject var plaid: PlaidService
    @Environment(\.dismiss) var dismiss

    let goal: SavingsGoal
    private let onSaved: ((Double) -> Void)?

    @State private var amountText = ""

    @FocusState private var isAmountFocused: Bool

    private var amount: Double? {
        let sanitized = amountText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value = Double(sanitized),
              value > 0 else {
            return nil
        }

        return value
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

    init(
        goal: SavingsGoal,
        onSaved: ((Double) -> Void)? = nil
    ) {
        self.goal = goal
        self.onSaved = onSaved
    }

    var body: some View {

        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                backgroundStyle: .editorModal(.savingsGoal),
                contentPadding: .all,
                contentSpacing: AppSpacing.regular
            ) {
                ModalHeaderView(
                    eyebrow: "Add Money",
                    title: goal.name,
                    subtitle: "Set aside more money for this goal.",
                    systemImage: "plus.circle.fill",
                    color: CalderaCategoryStyle.style(for: .savingsGoal).primary
                )

                amountEntryCard

                progressPreviewCard

                quickAddCard

                if amount == nil {
                    Text("Enter an amount to save.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .keyboardDismissToolbar()
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {

                    Button("Cancel") {
                        dismiss()
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

        onSaved?(amount)

        dismiss()
    }

    private func quickAddButton(
        _ value: Int
    ) -> some View {

        Button {

            amountText = String(format: "%.2f", Double(value))

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

    private var progressPreviewCard: some View {
        CalderaEditorFormCard(
            title: "Savings Progress",
            systemImage: "chart.line.uptrend.xyaxis",
            color: CalderaCategoryStyle.style(for: .savingsGoal).primary
        ) {
            Text(
                AppFormatters.currency(
                    projectedAmount
                )
            )
            .font(
                .system(
                    size: 36,
                    weight: .bold,
                    design: .rounded
                )
            )
            .foregroundColor(CalderaCategoryStyle.style(for: .savingsGoal).primary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            CalderaProgressBar(
                progress: projectedProgress,
                colors: CalderaCategoryStyle.style(for: .savingsGoal).gradient
            )

            HStack {
                Text("\(Int(projectedProgress * 100))% complete")

                Spacer()

                Text(AppFormatters.currency(goal.targetAmount))
            }
            .font(.caption.weight(.medium))
            .foregroundColor(AppColors.secondaryText)
        }
    }

    private var quickAddCard: some View {
        CalderaEditorFormCard(
            title: "Quick Add",
            systemImage: "plus.circle.fill",
            color: CalderaCategoryStyle.style(for: .savingsGoal).primary
        ) {
            HStack(spacing: AppSpacing.small) {
                quickAddButton(25)
                quickAddButton(50)
                quickAddButton(100)
            }
        }
    }

    private var amountEntryCard: some View {
        CalderaEditorFormCard(
            title: "Amount to Add",
            systemImage: CalderaCategoryStyle.style(for: .savingsGoal).icon,
            color: CalderaCategoryStyle.style(for: .savingsGoal).primary
        ) {
            AmountEntryField(
                title: "Dollar Amount",
                subtitle: "Money set aside for this goal.",
                placeholder: "0.00",
                text: $amountText,
                style: CalderaCategoryStyle.style(for: .savingsGoal),
                focus: $isAmountFocused,
                accessibilityLabel: "Money to Add"
            )
        }
    }
}
