import SwiftUI
import UIKit

struct GoalForm: View {

    private enum EditingField {
        case title
        case targetAmount
    }

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
    @State private var editingField: EditingField?
    @State private var titleDraft = ""
    @State private var targetAmountDraft = ""
    @FocusState private var isTitleFocused: Bool
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
                        commitActiveEdit(
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
                text: name
            )

            textFieldSection(
                title: "Target amount",
                placeholder: "0.00",
                text: targetAmount,
                keyboardType: .decimalPad
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
                    : "Update your target, date, and set-aside amount."
            )

            progressCard(
                draft: draft,
                progress: progress,
                remaining: remaining
            )

            saveByDateCard(
                saveByDate: draft.saveByDate
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
                    systemImage: "trash.fill",
                    action: onDelete
                )
                .accessibilityLabel("Delete goal")
            }
        }
        .onChange(of: saveRequestID) { _, _ in
            guard canSave else {
                return
            }

            commitActiveEdit(
                draft: draft
            )
            onSave()
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
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        if keyboardType == .decimalPad || keyboardType == .numberPad {
            AmountEntryField(
                title: title,
                subtitle: "Enter dollars and cents, like 25.50.",
                placeholder: placeholder,
                text: text,
                style: CalderaCategoryStyle.style(for: .savingsGoal),
                keyboardType: .decimalPad,
                accessibilityLabel: title
            )
        } else {
            CalderaTextEntryField(
                title: title,
                subtitle: "Use a short name you’ll recognize.",
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

    private func progressCard(
        draft: Binding<SavingsGoal>,
        progress: Double,
        remaining: Double
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            FormSectionHeader(
                title: "Details & Amount",
                systemImage: CalderaCategoryStyle.style(for: .savingsGoal).icon,
                color: CalderaCategoryStyle.style(for: .savingsGoal).primary
            )

            editableProgressTitle(
                draft: draft
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

                editableTargetAmount(
                    draft: draft
                )
            }
        }
        .standardGoalPanel()
        .accessibilityElement(children: .contain)
    }

    private func editableProgressTitle(
        draft: Binding<SavingsGoal>
    ) -> some View {
        Group {
            if editingField == .title {
                TextField(
                    "Goal name",
                    text: $titleDraft
                )
                .font(.title2.bold())
                .foregroundColor(AppColors.primaryText)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($isTitleFocused)
                .onSubmit {
                    commitTitleEdit(draft: draft)
                }
                .onChange(of: isTitleFocused) { _, isFocused in
                    if !isFocused,
                       editingField == .title {
                        commitTitleEdit(draft: draft)
                    }
                }
                .padding(.vertical, AppSpacing.xSmall)
                .accessibilityLabel("Goal name")
            } else {
                Button {
                    beginEditingTitle(
                        draft: draft.wrappedValue
                    )
                } label: {
                    HStack(spacing: AppSpacing.small) {
                        VStack(
                            alignment: .leading,
                            spacing: AppSpacing.xxSmall
                        ) {
                            Text("Goal name")
                                .font(.subheadline)
                                .foregroundColor(AppColors.secondaryText)

                            HStack(spacing: AppSpacing.xxSmall) {
                                Text(
                                    draft.wrappedValue.name.isEmpty
                                    ? "Untitled Goal"
                                    : draft.wrappedValue.name
                                )
                                .font(.title2.bold())
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(2)

                                Image(systemName: "pencil")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit goal name")
            }
        }
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

    private func editableTargetAmount(
        draft: Binding<SavingsGoal>
    ) -> some View {
        VStack(
            alignment: .trailing,
            spacing: AppSpacing.xxSmall
        ) {
            HStack(spacing: AppSpacing.xxSmall) {
                Text("Target amount")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)

                Image(systemName: "pencil")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppColors.secondaryText)
            }

            if editingField == .targetAmount {
                TextField(
                    "0.00",
                    text: $targetAmountDraft
                )
                .keyboardType(.decimalPad)
                .font(.subheadline.weight(.bold))
                .foregroundColor(AppColors.primaryText)
                .multilineTextAlignment(.trailing)
                .focused($isTargetAmountFocused)
                .onChange(of: isTargetAmountFocused) { _, isFocused in
                    if !isFocused,
                       editingField == .targetAmount {
                        commitTargetAmountEdit(draft: draft)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 124)
                .accessibilityLabel("Target amount")
            } else {
                Button {
                    beginEditingTargetAmount(
                        draft: draft.wrappedValue
                    )
                } label: {
                    Text(AppFormatters.currency(draft.wrappedValue.targetAmount))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit target amount")
            }
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
                    Text("Pin to Savings")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text("Pinned goals stay visible on the Savings screen.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle(
                "Pin to Savings",
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
                    Text("Save by date")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text("Optional")
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
                .accessibilityLabel("Add save-by date")
            } else {
                DatePicker(
                    "Save by date",
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
                .accessibilityLabel("Remove save-by date")
            }
        }
        .standardGoalPanel()
        .accessibilityElement(children: .contain)
    }

    private func beginEditingTitle(
        draft: SavingsGoal
    ) {
        editingField = .title
        titleDraft = draft.name

        DispatchQueue.main.async {
            isTitleFocused = true
        }
    }

    private func beginEditingTargetAmount(
        draft: SavingsGoal
    ) {
        editingField = .targetAmount
        targetAmountDraft = targetAmountText(
            draft.targetAmount
        )

        DispatchQueue.main.async {
            isTargetAmountFocused = true
        }
    }

    private func commitTitleEdit(
        draft: Binding<SavingsGoal>
    ) {
        guard editingField == .title else {
            return
        }

        let trimmedTitle = titleDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if !trimmedTitle.isEmpty {
            draft.wrappedValue.name = trimmedTitle
        }

        editingField = nil
        titleDraft = ""
        isTitleFocused = false
    }

    private func commitTargetAmountEdit(
        draft: Binding<SavingsGoal>
    ) {
        guard editingField == .targetAmount else {
            return
        }

        if let value = parsedDollarAmount(
            from: targetAmountDraft
        ),
           value > 0 {
            draft.wrappedValue.targetAmount = value
        }

        editingField = nil
        targetAmountDraft = ""
        isTargetAmountFocused = false
    }

    private func parsedDollarAmount(
        from input: String
    ) -> Double? {
        let sanitized = input
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value = Double(sanitized),
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

    private func commitActiveEdit(
        draft: Binding<SavingsGoal>
    ) {
        switch editingField {
        case .title:
            commitTitleEdit(draft: draft)

        case .targetAmount:
            commitTargetAmountEdit(draft: draft)

        case nil:
            return
        }
    }
}

private extension View {
    func standardGoalPanel() -> some View {
        calderaEditorPanel(
            color: CalderaCategoryStyle.style(for: .savingsGoal).primary
        )
    }
}
