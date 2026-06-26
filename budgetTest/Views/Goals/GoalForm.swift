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
                eyebrow: "Create New Savings",
                title: "Savings",
                subtitle: "Set money aside for something that matters."
            )

            textFieldSection(
                title: "Savings Name",
                placeholder: "Emergency Fund",
                text: name
            )

            textFieldSection(
                title: "Target Amount",
                placeholder: "10000",
                text: targetAmount,
                keyboardType: .decimalPad
            )

            impactCard(previewAvailable: previewAvailable)

            PrimaryButton(
                "Create Savings",
                systemImage: "target",
                trailingSystemImage: nil,
                isDisabled: !canSave,
                fillsWidth: true,
                action: onSave
            )
            .accessibilityLabel("Create savings")
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
                eyebrow: isNew
                ? "Create New Savings"
                : "Update Savings",
                title: isNew
                ? "New Savings Goal"
                : editTitle(
                    for: draft.wrappedValue
                ),
                subtitle: "Set money aside for something that matters."
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

            PrimaryButton(
                "Save Savings",
                systemImage: "checkmark.circle.fill",
                trailingSystemImage: nil,
                isDisabled: !canSave,
                fillsWidth: true,
                action: {
                    commitActiveEdit(
                        draft: draft
                    )
                    onSave()
                }
            )
            .accessibilityLabel("Save savings")

            if !isNew, let onDelete {
                DestructiveButton(
                    "Delete Savings",
                    systemImage: "trash.fill",
                    action: onDelete
                )
                .accessibilityLabel("Delete savings")
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
            systemImage: "target",
            color: AppColors.protected
        )
    }

    private func editTitle(
        for goal: SavingsGoal
    ) -> String {
        let trimmedName = goal.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedName.isEmpty else {
            return "Edit Savings Goal"
        }

        return "Edit \(trimmedName)"
    }

    private func textFieldSection(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.primaryText)

            TextField(
                placeholder,
                text: text
            )
            .keyboardType(keyboardType)
            .padding()
            .glassCard(
                cornerRadius: AppRadii.field,
                shadow: nil
            )
            .accessibilityLabel(title)
        }
    }

    private func impactCard(
        previewAvailable: Double
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            Text("Financial Impact")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            MetricValue(
                previewAvailable,
                font: .system(
                    size: 42,
                    weight: .bold
                ),
                color: previewAvailable >= 0
                ? AppColors.spendable
                : AppColors.negative
            )

            HStack {
                Text("Safe To Spend After Savings")

                Spacer()

                Image(
                    systemName:
                        previewAvailable >= 0
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .foregroundColor(
                    previewAvailable >= 0
                    ? AppColors.spendable
                    : AppColors.warning
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
            spacing: 18
        ) {
            editableProgressTitle(
                draft: draft
            )

            savedAmountDisplay(
                draft: draft
            )

            ProgressView(value: progress)
                .tint(AppColors.protected)

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
                    "Savings name",
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
                .accessibilityLabel("Savings name")
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
                            Text("Savings Progress")
                                .font(.subheadline)
                                .foregroundColor(AppColors.secondaryText)

                            HStack(spacing: AppSpacing.xxSmall) {
                                Text(
                                    draft.wrappedValue.name.isEmpty
                                    ? "Untitled Savings"
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
                .accessibilityLabel("Edit savings name")
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
            Text("Saved")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            Text(AppFormatters.currency(draft.wrappedValue.currentAmount))
                .font(
                    .system(
                        size: 42,
                        weight: .bold
                    )
                )
                .foregroundColor(AppColors.protected)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Saved amount")
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
                Text("Target")
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
                .keyboardType(.numberPad)
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
                .onChange(of: targetAmountDraft) { _, newValue in
                    let formattedValue = centsFormattedText(
                        from: newValue
                    )

                    if formattedValue != newValue {
                        targetAmountDraft = formattedValue
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
                color: AppColors.protected,
                size: 42,
                iconSize: 17
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("Pin to Savings Home")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)

                Text("Pinned goals stay visible on the Savings screen.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle(
                "Pin to Savings Home",
                isOn: isPinned
            )
            .labelsHidden()
            .tint(AppColors.protected)
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
                    color: AppColors.protected,
                    size: 42,
                    iconSize: 17
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Save by date")
                        .font(.headline)
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
                        "Add save-by date",
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
                .tint(AppColors.protected)

                Button {
                    saveByDate.wrappedValue = nil
                } label: {
                    Label(
                        "Remove save-by date",
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
        targetAmountDraft = ""

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

        if let value = parsedCentsAmount(
            from: targetAmountDraft
        ),
           value > 0 {
            draft.wrappedValue.targetAmount = value
        }

        editingField = nil
        targetAmountDraft = ""
        isTargetAmountFocused = false
    }

    private func parsedCentsAmount(
        from input: String
    ) -> Double? {
        let digits = digitsOnly(
            from: input
        )

        guard let cents = Double(digits),
              cents > 0 else {
            return nil
        }

        return cents / 100
    }

    private func centsFormattedText(
        from input: String
    ) -> String {
        let digits = digitsOnly(
            from: input
        )

        guard let cents = Double(digits),
              cents > 0 else {
            return ""
        }

        return String(
            format: "%.2f",
            cents / 100
        )
    }

    private func digitsOnly(
        from input: String
    ) -> String {
        input.filter(\.isNumber)
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
        padding(28)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .glassCard(
                cornerRadius: AppRadii.panel,
                overlay: .gradient(
                    colors: [
                        AppColors.glassOverlayWhite,
                        AppColors.glassOverlayProtected,
                        AppColors.protected.opacity(0.04)
                    ]
                ),
                shadow: AppShadows.softPanel
            )
    }
}
