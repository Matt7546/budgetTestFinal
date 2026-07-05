import SwiftUI

struct SavingsGoalCard: View {

    let goal: SavingsGoal
    let onAdd: () -> Void
    let onEdit: () -> Void

    private var progress: Double {
        guard goal.targetAmount > 0 else { return 0 }

        let value = goal.currentAmount / goal.targetAmount
        guard value.isFinite else { return 0 }

        return min(
            max(value, 0),
            1
        )
    }

    private var remainingAmount: Double {
        max(goal.targetAmount - goal.currentAmount, 0)
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 14
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

                    Text("Savings")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                ZStack {

                    Circle()
                        .fill(
                            AppColors.protected.opacity(0.12)
                        )
                        .frame(
                            width: 46,
                            height: 46
                        )

                    Image(systemName: "target")
                        .font(.body.weight(.semibold))
                        .foregroundColor(AppColors.protected)
                }
            }

            // MARK: Amount

            MetricLabelValue(
                label: "Saved So Far",
                value: goal.currentAmount,
                spacing: 6,
                valueFont: .system(
                        size: 32,
                        weight: .bold
                ),
                labelColor: AppColors.secondaryText,
                valueColor: AppColors.ink
            )

            // MARK: Progress

            VStack(
                alignment: .leading,
                spacing: 6
            ) {

                CalderaProgressBar(
                    progress: progress,
                    colors: CalderaCategoryStyle.style(for: .savingsGoal).gradient
                )

                HStack {

                    Text(
                        "\(Int(progress * 100))% Complete"
                    )
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)

                    Spacer()

                    Text(
                        AppFormatters.currency(
                            goal.targetAmount
                        )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                }
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.protected.opacity(0.25),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // MARK: Details

            HStack {

                MetricLabelValue(
                    label: "Remaining",
                    value: remainingAmount,
                    labelColor: AppColors.secondaryText
                )

                Spacer()

                MetricLabelValue(
                    label: "Target",
                    value: goal.targetAmount,
                    alignment: .trailing,
                    labelColor: AppColors.secondaryText
                )
            }

            // MARK: Actions

            HStack(spacing: 10) {

                SecondaryButton(
                    "Edit",
                    systemImage: "pencil",
                    cornerRadius: AppRadii.button,
                    fillsWidth: true
                ) {
                    onEdit()
                }
                .accessibilityLabel("Edit \(goal.name)")

                PrimaryButton(
                    "Add Money",
                    systemImage: "plus.circle.fill",
                    trailingSystemImage: nil,
                    cornerRadius: AppRadii.button,
                    fillsWidth: true
                ) {
                    onAdd()
                }
                .accessibilityLabel("Add money to \(goal.name)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.glassOverlayProtected,
                    AppColors.protected.opacity(0.04)
                ]
            ),
            accent: AppColors.protected,
            shadow: AppShadows.softPanel
        )
    }
}
