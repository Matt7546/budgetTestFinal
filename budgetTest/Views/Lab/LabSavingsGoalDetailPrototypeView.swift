#if DEBUG

import SwiftUI

struct LabSavingsGoalDetailPrototypeView: View {

    enum EditingField {
        case title
        case targetAmount
        case savedAmount
    }

    @Environment(\.dismiss) private var dismiss

    let goal: SavingsGoal

    @State private var draftTitle: String
    @State private var draftTargetAmount: Double
    @State private var draftSavedAmount: Double
    @State private var editingField: EditingField?
    @State private var textDraft = ""
    @State private var titleDraft = ""
    @State private var targetAmountDraft = ""
    @FocusState private var isInputFocused: Bool
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isTargetAmountFocused: Bool

    init(goal: SavingsGoal) {
        self.goal = goal
        _draftTitle = State(
            initialValue: goal.name.isEmpty
            ? "Untitled Savings Goal"
            : goal.name
        )
        _draftTargetAmount = State(initialValue: goal.targetAmount)
        _draftSavedAmount = State(initialValue: goal.currentAmount)
    }

    private var progress: Double {
        guard draftTargetAmount > 0 else {
            return 0
        }

        let value = draftSavedAmount / draftTargetAmount
        guard value.isFinite else {
            return 0
        }

        return min(
            max(value, 0),
            1
        )
    }

    private var remaining: Double {
        max(draftTargetAmount - draftSavedAmount, 0)
    }

    var body: some View {
        AppScreen(
            usesNavigationStack: false
        ) {
            header

            progressCard

            prototypeNote
        }
        .navigationTitle("Goal Prototype")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
                .accessibilityLabel("Close goal prototype")
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    if editingField == .title {
                        commitTitleEdit()
                    } else if editingField == .targetAmount {
                        commitTargetAmountEdit()
                    } else {
                        commitInlineEdit()
                    }

                    isTitleFocused = false
                    isTargetAmountFocused = false
                    isInputFocused = false
                }
            }
        }
    }

    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            Text("Local Edit Experiment")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            Text("Goal Progress Card")
                .font(
                    .system(
                        size: 34,
                        weight: .bold
                    )
                )
                .foregroundColor(AppColors.primaryText)

            Text("Tap the title, target, or saved amount to test inline editing without changing real data.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progressCard: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            editableTitle

            editableSavedAmount

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

                editableTargetAmount
            }

            if editingField == .savedAmount {
                inlineEditor
            }
        }
        .padding(AppSpacing.card)
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.protected.opacity(0.06),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: AppShadows.softPanelCompact
        )
    }

    private var editableTitle: some View {
        Group {
            if editingField == .title {
                TextField(
                    "Goal title",
                    text: $titleDraft
                )
                .font(.title2.bold())
                .foregroundColor(AppColors.primaryText)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($isTitleFocused)
                .onSubmit {
                    commitTitleEdit()
                }
                .onChange(of: isTitleFocused) { _, isFocused in
                    if !isFocused,
                       editingField == .title {
                        commitTitleEdit()
                    }
                }
                .padding(.vertical, AppSpacing.xSmall)
                .accessibilityLabel("Goal title")
            } else {
                Button {
                    beginEditing(.title)
                } label: {
                    editableTitleLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit goal title")
            }
        }
    }

    private var editableTitleLabel: some View {
        HStack(spacing: AppSpacing.small) {
            Text(draftTitle)
                .font(.title2.bold())
                .foregroundColor(AppColors.primaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            editHint
        }
    }

    private var editableSavedAmount: some View {
        Button {
            beginEditing(.savedAmount)
        } label: {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                HStack(spacing: AppSpacing.xxSmall) {
                    Text("Saved")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.secondaryText)

                    Image(systemName: "pencil")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppColors.secondaryText)
                }

                Text(AppFormatters.currency(draftSavedAmount))
                    .font(
                        .system(
                            size: 42,
                            weight: .bold
                        )
                    )
                    .foregroundColor(AppColors.protected)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit saved amount")
    }

    private var editableTargetAmount: some View {
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
                .keyboardType(.decimalPad)
                .font(.subheadline.weight(.bold))
                .foregroundColor(AppColors.primaryText)
                .multilineTextAlignment(.trailing)
                .focused($isTargetAmountFocused)
                .onChange(of: isTargetAmountFocused) { _, isFocused in
                    if !isFocused,
                       editingField == .targetAmount {
                        commitTargetAmountEdit()
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 124)
                .accessibilityLabel("Target amount")
            } else {
                Button {
                    beginEditing(.targetAmount)
                } label: {
                    Text(AppFormatters.currency(draftTargetAmount))
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

    private var editHint: some View {
        HStack(spacing: AppSpacing.xxSmall) {
            Image(systemName: "pencil")
                .font(.caption.weight(.bold))

            Text("Tap to edit")
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(AppColors.accent)
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xSmall)
        .glassCard(
            cornerRadius: AppRadii.button,
            shadow: nil
        )
    }

    private var inlineEditor: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            Text(inlineEditorTitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            TextField(
                inlineEditorPlaceholder,
                text: $textDraft
            )
            .keyboardType(
                editingField == .title
                ? .default
                : .decimalPad
            )
            .focused($isInputFocused)
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.medium)
            .glassCard(
                cornerRadius: AppRadii.field,
                shadow: nil
            )
            .accessibilityLabel(inlineEditorTitle)

            HStack(spacing: AppSpacing.medium) {
                SecondaryButton(
                    "Cancel",
                    systemImage: "xmark.circle",
                    cornerRadius: AppRadii.button,
                    fillsWidth: true
                ) {
                    editingField = nil
                    textDraft = ""
                    isInputFocused = false
                }

                PrimaryButton(
                    "Apply",
                    systemImage: "checkmark.circle.fill",
                    trailingSystemImage: nil,
                    cornerRadius: AppRadii.button,
                    fillsWidth: true,
                    action: commitInlineEdit
                )
            }
        }
        .padding(AppSpacing.medium)
        .glassCard(
            cornerRadius: AppRadii.field,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.accent.opacity(0.04),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: nil
        )
    }

    private var prototypeNote: some View {
        HStack(spacing: AppSpacing.medium) {
            IconBadge(
                systemImage: "testtube.2",
                color: AppColors.warning,
                size: 36,
                iconSize: 15
            )

            Text("Prototype edits are local to this Lab screen and do not save to your real Savings Goals.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.medium)
        .glassCard(
            cornerRadius: AppRadii.field,
            shadow: nil
        )
    }

    private var inlineEditorTitle: String {
        switch editingField {
        case .title:
            return "Goal title"

        case .targetAmount:
            return "Target amount"

        case .savedAmount:
            return "Saved amount"

        case nil:
            return ""
        }
    }

    private var inlineEditorPlaceholder: String {
        switch editingField {
        case .title:
            return "Emergency Fund"

        case .targetAmount,
             .savedAmount:
            return "0.00"

        case nil:
            return ""
        }
    }

    private func beginEditing(
        _ field: EditingField
    ) {
        editingField = field

        switch field {
        case .title:
            titleDraft = draftTitle

            DispatchQueue.main.async {
                isTitleFocused = true
            }

        case .targetAmount:
            targetAmountDraft = String(format: "%.2f", draftTargetAmount)

            DispatchQueue.main.async {
                isTargetAmountFocused = true
            }

        case .savedAmount:
            textDraft = String(format: "%.2f", draftSavedAmount)

            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }

    private func commitInlineEdit() {
        guard let editingField else {
            return
        }

        switch editingField {
        case .title:
            let trimmedTitle = textDraft.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if !trimmedTitle.isEmpty {
                draftTitle = trimmedTitle
            }

        case .targetAmount:
            if let value = parsedCurrencyAmount(from: textDraft),
               value > 0 {
                draftTargetAmount = value
            }

        case .savedAmount:
            if let value = Double(textDraft),
               value >= 0 {
                draftSavedAmount = value
            }
        }

        self.editingField = nil
        textDraft = ""
        isInputFocused = false
    }

    private func commitTargetAmountEdit() {
        guard editingField == .targetAmount else {
            return
        }

        if let value = parsedCurrencyAmount(from: targetAmountDraft),
           value > 0 {
            draftTargetAmount = value
        }

        editingField = nil
        targetAmountDraft = ""
        isTargetAmountFocused = false
    }

    private func commitTitleEdit() {
        guard editingField == .title else {
            return
        }

        let trimmedTitle = titleDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if !trimmedTitle.isEmpty {
            draftTitle = trimmedTitle
        }

        editingField = nil
        titleDraft = ""
        isTitleFocused = false
    }

    private func parsedCurrencyAmount(
        from input: String
    ) -> Double? {
        let sanitized = input
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .replacingOccurrences(
                of: "$",
                with: ""
            )
            .replacingOccurrences(
                of: ",",
                with: ""
            )

        return Double(sanitized)
    }
}

#endif
