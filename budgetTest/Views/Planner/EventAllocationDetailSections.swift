import SwiftUI

struct EventAllocationSummaryCard: View {

    let eventAmount: Double
    let eventFrequency: PlannerFrequency
    let eventColor: Color
    let allocatedAmount: Double
    let remainingAmount: Double
    let progress: Double
    let isCovered: Bool

    var body: some View {
        GlassFormCard(color: AppColors.protected) {
            HStack(alignment: .top) {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.small
                ) {
                    Text("Amount Due")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.secondaryText)

                    MetricValue(
                        eventAmount,
                        font: .system(
                            size: 34,
                            weight: .bold,
                            design: .rounded
                        ),
                        color: eventColor,
                        minimumScaleFactor: 0.55,
                        lineLimit: 1
                    )
                }

                Spacer()

                if eventFrequency != .once {
                    Text(eventFrequency.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.protected)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(AppColors.protected.opacity(0.12))
                        )
                }
            }

            EventAllocationProgressBar(progress: progress)

            HStack(alignment: .top) {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Set Aside")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)

                    MetricValue(
                        allocatedAmount,
                        font: .headline,
                        color: AppColors.protected
                    )
                }

                Spacer()

                VStack(
                    alignment: .trailing,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(isCovered ? "Status" : "Remaining")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)

                    if isCovered {
                        Text("Covered")
                            .font(.headline)
                            .foregroundColor(AppColors.spendable)
                    } else {
                        MetricValue(
                            remainingAmount,
                            font: .headline,
                            color: AppColors.warning
                        )
                    }
                }
            }

            Text("\(Int(progress * 100))% covered")
                .font(.caption.weight(.semibold))
                .foregroundColor(
                    isCovered
                        ? AppColors.spendable
                        : AppColors.secondaryText
                )
        }
    }
}

struct EventAllocationLifecycleCard: View {

    let title: String
    let systemImage: String
    let color: Color
    let description: String
    let showsActions: Bool
    let onMarkPaid: () -> Void
    let onSkipExpense: () -> Void

    var body: some View {
        GlassFormCard(color: color) {
            FormSectionHeader(
                title: title,
                systemImage: systemImage,
                color: color
            )

            Text(description)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if showsActions {
                HStack(spacing: AppSpacing.medium) {
                    SecondaryButton(
                        "Mark Paid",
                        systemImage: "checkmark.circle.fill",
                        cornerRadius: AppRadii.button,
                        foregroundColor: AppColors.spendable,
                        fillsWidth: true
                    ) {
                        onMarkPaid()
                    }
                    .accessibilityLabel("Mark expense paid")

                    DestructiveButton(
                        "Skip Expense",
                        systemImage: "forward.end.fill",
                        cornerRadius: AppRadii.button
                    ) {
                        onSkipExpense()
                    }
                    .accessibilityLabel("Skip expense")
                }
            }
        }
    }
}

struct EventAllocationInputCard: View {

    @Binding var amountText: String

    let canAddAllocation: Bool
    let allocatedAmount: Double
    let remainingAmount: Double
    let onSetAside: (Double) -> Void
    let onQuickAdd: (Double) -> Void
    let onCoverFull: () -> Void
    let onReset: () -> Void

    private var allocationAmount: Double? {
        Double(amountText)
    }

    var body: some View {
        GlassFormCard(color: AppColors.accent) {
            FormSectionHeader(
                title: "Set Aside Money",
                systemImage: "plus.circle.fill",
                color: AppColors.accent
            )

            TextField(
                "0.00",
                text: $amountText
            )
            .keyboardType(.decimalPad)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundColor(AppColors.primaryText)
            .padding()
            .glassCard(
                cornerRadius: AppRadii.field,
                shadow: nil
            )
            .accessibilityLabel("Set aside amount")

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: AppSpacing.small
            ) {
                quickAddButton(amount: 50)
                quickAddButton(amount: 100)
                quickAddButton(amount: 250)
                coverFullButton
            }

            PrimaryButton(
                "Set Aside Money",
                systemImage: "lock.shield.fill",
                trailingSystemImage: nil,
                isDisabled: !canAddAllocation,
                fillsWidth: true
            ) {
                guard let allocationAmount else {
                    return
                }

                onSetAside(allocationAmount)
            }
            .accessibilityLabel("Set aside money")

            if allocatedAmount > 0 {
                DestructiveButton(
                    "Reset Set Aside",
                    systemImage: "arrow.counterclockwise",
                    cornerRadius: AppRadii.button
                ) {
                    onReset()
                }
                .accessibilityLabel("Reset set aside amount")
            }
        }
    }

    private func quickAddButton(
        amount: Double
    ) -> some View {
        allocationOptionButton(
            title: "+\(AppFormatters.wholeCurrency(amount))",
            systemImage: "plus",
            color: AppColors.accent
        ) {
            onQuickAdd(amount)
        }
        .disabled(remainingAmount <= 0)
        .opacity(remainingAmount <= 0 ? 0.55 : 1)
    }

    private var coverFullButton: some View {
        allocationOptionButton(
            title: "Cover Full",
            systemImage: "checkmark.shield.fill",
            color: AppColors.protected
        ) {
            onCoverFull()
        }
        .disabled(remainingAmount <= 0)
        .opacity(remainingAmount <= 0 ? 0.55 : 1)
    }

    private func allocationOptionButton(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(
                title,
                systemImage: systemImage
            )
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(
                        color.opacity(0.25),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct EventAllocationNoteCard: View {

    var body: some View {
        GlassFormCard(color: AppColors.protected) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                IconBadge(
                    systemImage: "info.circle.fill",
                    color: AppColors.protected,
                    size: 34,
                    iconSize: 14
                )

                Text("This applies only to this upcoming expense. Future recurring expenses are separate.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct EventAllocationProgressBar: View {

    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.secondaryText.opacity(0.14))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.protected,
                                AppColors.accent
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: proxy.size.width * progress
                    )
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Set aside progress")
        .accessibilityValue("\(Int(progress * 100)) percent covered")
    }
}
