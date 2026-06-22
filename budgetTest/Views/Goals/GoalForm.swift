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
            onSave: () -> Void,
            onDelete: (() -> Void)?
        )
    }

    private let mode: Mode

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
            let onSave,
            let onDelete
        ):
            editForm(
                draft: draft,
                isNew: isNew,
                progress: progress,
                remaining: remaining,
                canSave: canSave,
                onSave: onSave,
                onDelete: onDelete
            )
        }
    }

    private func addForm(
        name: Binding<String>,
        targetAmount: Binding<String>,
        previewAvailable: Double,
        canSave: Bool,
        onSave: @escaping () -> Void
    ) -> some View {
        Group {
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
        onSave: @escaping () -> Void,
        onDelete: (() -> Void)?
    ) -> some View {
        Group {
            header(
                eyebrow: isNew
                ? "Create New Savings"
                : "Update Savings",
                title: isNew
                ? "New Savings"
                : "Edit Savings",
                subtitle: "Set money aside for something that matters."
            )

            textFieldSection(
                title: "Savings Name",
                placeholder: "Emergency Fund",
                text: draft.name
            )

            numberFieldSection(
                title: "Target Amount",
                value: draft.targetAmount
            )

            numberFieldSection(
                title: "Saved So Far",
                value: draft.currentAmount
            )

            progressCard(
                draft: draft.wrappedValue,
                progress: progress,
                remaining: remaining
            )

            PrimaryButton(
                "Save Savings",
                systemImage: "checkmark.circle.fill",
                trailingSystemImage: nil,
                isDisabled: !canSave,
                fillsWidth: true,
                action: onSave
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

    private func numberFieldSection(
        title: String,
        value: Binding<Double>
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.primaryText)

            TextField(
                "$0.00",
                value: value,
                format: .number
            )
            .keyboardType(.decimalPad)
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
        draft: SavingsGoal,
        progress: Double,
        remaining: Double
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            Text("Savings Progress")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            MetricValue(
                draft.currentAmount,
                font: .system(
                    size: 42,
                    weight: .bold
                )
            )

            ProgressView(value: progress)
                .tint(AppColors.protected)

            HStack {
                MetricLabelValue(
                    label: "Remaining",
                    value: remaining,
                    spacing: nil
                )

                Spacer()

                MetricLabelValue(
                    label: "Target",
                    value: draft.targetAmount,
                    alignment: .trailing,
                    spacing: nil
                )
            }
        }
        .standardGoalPanel()
        .accessibilityElement(children: .contain)
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
