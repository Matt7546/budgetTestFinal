import SwiftUI
import UIKit

struct GoalForm: View {

    enum Mode {
        case add(
            name: Binding<String>,
            targetAmount: Binding<String>,
            previewAvailable: Double,
            canSave: Bool,
            onSave: () -> Void
        )

        case edit(
            draft: Binding<SavingsGoal>,
            isNew: Bool,
            progress: Double,
            remaining: Double,
            canSave: Bool,
            saveRequestID: Int,
            onSave: () -> Void,
            onDelete: (() -> Void)?
        )
    }

    private let mode: Mode
    @State private var targetAmountDraft = ""
    @State private var showsDeleteConfirmation = false
    @FocusState private var isTargetAmountFocused: Bool

    init(mode: Mode) {
        self.mode = mode
    }

    var body: some View {
        switch mode {
        case .add(
            let name,
            let targetAmount,
            let previewAvailable,
            let canSave,
            let onSave
        ):
            addForm(
                name: name,
                targetAmount: targetAmount,
                previewAvailable: previewAvailable,
                canSave: canSave,
                onSave: onSave
            )

        case .edit(
            let draft,
            let isNew,
            let progress,
            let remaining,
            let canSave,
            let saveRequestID,
            let onSave,
            let onDelete
        ):
            editForm(
                draft: draft,
                isNew: isNew,
                progress: progress,
                remaining: remaining,
                canSave: canSave,
                saveRequestID: saveRequestID,
                onSave: onSave,
                onDelete: onDelete
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        commitTargetAmountEdit(
                            draft: draft
                        )
                        UIApplication.shared.dismissKeyboard()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func addForm(
        name: Binding<String>,
        targetAmount: Binding<String>,
        previewAvailable: Double,
        canSave: Bool,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.screen
        ) {
            header(
                eyebrow: "Goals",
                title: "New Goal",
                subtitle: "Set money aside for something that matters."
            )

            textFieldSection(
                title: "Goal name",
                placeholder: "Emergency Fund",
                text: name,
                subtitle: "Name what you want to set money aside for."
            )

            textFieldSection(
                title: "Target amount",
                placeholder: "0.00",
                text: targetAmount,
                keyboardType: .decimalPad,
                subtitle: "How much you want to set aside for this goal."
            )

            impactCard(previewAvailable: previewAvailable)

            PrimaryButton(
                "Create Goal",
                systemImage: CalderaCategoryStyle.style(for: .savingsGoal).icon,
                trailingSystemImage: nil,
                isDisabled: !canSave,
                fillsWidth: true,
                action: onSave
            )
            .accessibilityLabel("Create goal")
        }
    }

    private func editForm(
        draft: Binding<SavingsGoal>,
        isNew: Bool,
        progress: Double,
        remaining: Double,
        canSave: Bool,
        saveRequestID: Int,
        onSave: @escaping () -> Void,
        onDelete: (() -> Void)?
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.screen
        ) {
            header(
                eyebrow: "Goals",
                title: isNew ? "New Goal" : "Edit Goal",
                subtitle: isNew
                    ? "Set money aside for something that matters."
                    : "Update the goal, date, and amount you want to set aside."
            )

            goalDetailsCard(
                draft: draft
            )

            saveByDateCard(
                saveByDate: draft.saveByDate
            )

            targetAmountCard(
                draft: draft
            )

            setAsideProgressCard(
                draft: draft,
                progress: progress,
                remaining: remaining
            )

            pinCard(
                isPinned: draft.isPinned
            )

            if !canSave {
                Text(saveDisabledMessage(
                    draft: draft.wrappedValue,
                    isNew: isNew
                ))
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if !isNew, let onDelete {
                DestructiveButton(
                    "Delete Goal",
                    systemImage: "trash.fill"
                ) {
                    showsDeleteConfirmation = true
                }
                .accessibilityLabel("Delete goal")
                .confirmationDialog(
                    "Delete goal?",
                    isPresented: $showsDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete Goal", role: .destructive) {
                        onDelete()
                    }

                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes the goal from your plan. Money set aside for it will no longer be kept out of Available to Spend.")
                }
            }
        }
        .onChange(of: saveRequestID) { _, _ in
            guard canSave else {
                return
            }

            commitTargetAmountEdit(
                draft: draft
            )
            onSave()
        }
        .onAppear {
            prepareEditFields(
                draft: draft.wrappedValue
            )
        }
    }

    private func header(
        eyebrow: String,
        title: String,
        subtitle: String
    ) -> some View {
        ModalHeaderView(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            systemImage: CalderaCategoryStyle.style(for: .savingsGoal).icon,
            color: CalderaCategoryStyle.style(for: .savingsGoal).primary
        )
    }

    @ViewBuilder
    private func textFieldSection(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        subtitle: String? = nil
    ) -> some View {
        if keyboardType == .decimalPad || keyboardType == .numberPad {
            AmountEntryField(
                title: title,
                subtitle: subtitle ?? "Enter dollars and cents, like 25.50.",
                placeholder: placeholder,
                text: text,
                style: CalderaCategoryStyle.style(for: .savingsGoal),
                keyboardType: .decimalPad,
                accessibilityLabel: title
            )
        } else {
            CalderaTextEntryField(
                title: title,
                subtitle: subtitle ?? "Use a short name you’ll recognize.",
                placeholder: placeholder,
                text: text,
                keyboardType: keyboardType,
                color: CalderaCategoryStyle.style(for: .savingsGoal).primary,
                accessibilityLabel: title
            )
        }
    }

    private func saveDisabledMessage(
        draft: SavingsGoal,
        isNew: Bool
    ) -> String {
        let hasName = !draft.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let hasTarget = draft.targetAmount > 0

        if !hasName || !hasTarget {
            return "Add a name and target amount to save."
        }

        return isNew ? "Add a name and target amount to save." : "Make a change to save."
    }

    private func impactCard(
        previewAvailable: Double
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            Text("Available to Spend preview")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            MetricValue(
                previewAvailable,
                font: .system(
                    size: 42,
                    weight: .bold
                ),
                color: previewAvailable >= 0
                ? CalderaCategoryStyle.style(for: .safeToSpend).primary
                : CalderaCategoryStyle.style(for: .shortfall).primary
            )

            HStack {
                Text("Available after goal")

                Spacer()

                Image(
                    systemName:
                        previewAvailable >= 0
                        ? CalderaCategoryStyle.style(for: .covered).icon
                        : CalderaCategoryStyle.style(for: .shortfall).icon
                )
                .foregroundColor(
                    previewAvailable >= 0
                    ? CalderaCategoryStyle.style(for: .covered).primary
                    : CalderaCategoryStyle.style(for: .shortfall).primary
                )
            }
            .font(.caption)
        }
        .standardGoalPanel()
        .accessibilityElement(children: .contain)
    }

    private func goalDetailsCard(
        draft: Binding<SavingsGoal>
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            FormSectionHeader(
                title: "Goal Details",
                systemImage: CalderaCategoryStyle.style(for: .savingsGoal).icon,
                color: CalderaCategoryStyle.style(for: .savingsGoal).primary
            )

            CalderaTextEntryField(
                title: "Goal name",
                subtitle: "Name what you want to set money aside for.",
                placeholder: "Emergency Fund",
                text: Binding(
                    get: {
                        draft.wrappedValue.name
                    },
                    set: {
                        draft.wrappedValue.name = $0
                    }
                ),
                color: CalderaCategoryStyle.style(for: .savingsGoal).primary,
                accessibilityLabel: "Goal name"
            )
        }
        .standardGoalPanel()
        .accessibilityElement(children: .contain)
    }

    private func targetAmountCard(
        draft: Binding<SavingsGoal>
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            FormSectionHeader(
                title: "How much is needed?",
                systemImage: "dollarsign.circle.fill",
                color: CalderaCategoryStyle.style(for: .savingsGoal).primary
            )

            AmountEntryField(
                title: "Target amount",
                subtitle: "How much you want to set aside for this goal.",
                placeholder: "0.00",
                text: $targetAmountDraft,
                style: CalderaCategoryStyle.style(for: .savingsGoal),
                focus: $isTargetAmountFocused,
                accessibilityLabel: "Target amount"
            )
            .onChange(of: targetAmountDraft) { _, _ in
                commitTargetAmountEdit(
                    draft: draft,
                    clearsDraft: false
                )
            }
        }
        .standardGoalPanel()
        .accessibilityElement(children: .contain)
    }

    private func setAsideProgressCard(
        draft: Binding<SavingsGoal>,
        progress: Double,
        remaining: Double
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            FormSectionHeader(
                title: "How much is set aside?",
                systemImage: "chart.line.uptrend.xyaxis",
                color: CalderaCategoryStyle.style(for: .savingsGoal).primary
            )

            savedAmountDisplay(
                draft: draft
            )

            CalderaProgressBar(
                progress: safeProgress(progress),
                colors: CalderaCategoryStyle.style(for: .savingsGoal).gradient
            )

            HStack(
                alignment: .top,
                spacing: AppSpacing.medium
            ) {
                MetricLabelValue(
                    label: "Remaining",
                    value: remaining,
                    spacing: nil
                )

                Spacer()

                MetricLabelValue(
                    label: "Target amount",
                    value: draft.wrappedValue.targetAmount,
                    alignment: .trailing,
                    spacing: nil
                )
            }

            Text("Use Add Money when you want to change the amount set aside.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .standardGoalPanel()
        .accessibilityElement(children: .contain)
    }

    private func savedAmountDisplay(
        draft: Binding<SavingsGoal>
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text("Amount set aside")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            Text(AppFormatters.currency(draft.wrappedValue.currentAmount))
                .font(
                    .system(
                        size: 34,
                        weight: .bold
                    )
                )
                .foregroundColor(CalderaCategoryStyle.style(for: .savingsGoal).primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Amount set aside")
        }
    }

    private func pinCard(
        isPinned: Binding<Bool>
    ) -> some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            IconBadge(
                systemImage: "pin.fill",
                color: CalderaCategoryStyle.style(for: .savingsGoal).primary,
                size: 34,
                iconSize: 14
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("Pin to Set Aside")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text("Pinned goals stay visible on the Set Aside screen.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle(
                "Pin to Set Aside",
                isOn: isPinned
            )
            .labelsHidden()
            .tint(CalderaCategoryStyle.style(for: .savingsGoal).primary)
        }
        .standardGoalPanel()
        .accessibilityElement(children: .combine)
    }

    private func saveByDateCard(
        saveByDate: Binding<Date?>
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(
                alignment: .center,
                spacing: AppSpacing.medium
            ) {
                IconBadge(
                    systemImage: "calendar",
                    color: CalderaCategoryStyle.style(for: .savingsGoal).primary,
                    size: 34,
                    iconSize: 14
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("When is it needed?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text("Optional target date")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()
            }

            if saveByDate.wrappedValue == nil {
                Button {
                    saveByDate.wrappedValue = Date()
                } label: {
                    Label(
                        "Add date",
                        systemImage: "plus.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add target date")
            } else {
                DatePicker(
                    "Target date",
                    selection: Binding(
                        get: {
                            saveByDate.wrappedValue ?? Date()
                        },
                        set: {
                            saveByDate.wrappedValue = $0
                        }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(CalderaCategoryStyle.style(for: .savingsGoal).primary)

                Button {
                    saveByDate.wrappedValue = nil
                } label: {
                    Label(
                        "Remove date",
                        systemImage: "xmark.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove target date")
            }
        }
        .standardGoalPanel()
        .accessibilityElement(children: .contain)
    }

    private func commitTargetAmountEdit(
        draft: Binding<SavingsGoal>,
        clearsDraft: Bool = true
    ) {
        if let value = parsedDollarAmount(
            from: targetAmountDraft
        ),
           value > 0 {
            draft.wrappedValue.targetAmount = value
        }

        if clearsDraft {
            targetAmountDraft = targetAmountText(
                draft.wrappedValue.targetAmount
            )
            isTargetAmountFocused = false
        }
    }

    private func parsedDollarAmount(
        from input: String
    ) -> Double? {
        guard let value = MoneyAmountParser.parse(input),
              value > 0 else {
            return nil
        }

        return value
    }

    private func targetAmountText(
        _ value: Double
    ) -> String {
        guard value > 0 else {
            return ""
        }

        return String(
            format: "%.2f",
            value
        )
    }

    private func safeProgress(
        _ value: Double
    ) -> Double {
        guard value.isFinite else {
            return 0
        }

        return min(
            max(value, 0),
            1
        )
    }

    private func prepareEditFields(
        draft: SavingsGoal
    ) {
        targetAmountDraft = targetAmountText(
            draft.targetAmount
        )
    }

}

private extension View {
    func standardGoalPanel() -> some View {
        calderaEditorPanel(
            color: CalderaCategoryStyle.style(for: .savingsGoal).primary
        )
    }
}
