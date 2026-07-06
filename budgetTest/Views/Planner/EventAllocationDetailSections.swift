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
        GlassFormCard(color: CalderaCategoryStyle.style(for: .upcomingExpense).primary) {
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
                        .foregroundColor(CalderaCategoryStyle.style(for: .upcomingExpense).primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(CalderaCategoryStyle.style(for: .upcomingExpense).primary.opacity(0.12))
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
                        color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
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
                            .foregroundColor(CalderaCategoryStyle.style(for: .covered).primary)
                    } else {
                        MetricValue(
                            remainingAmount,
                            font: .headline,
                            color: CalderaCategoryStyle.style(for: .needsMoney).primary
                        )
                    }
                }
            }

            Text("\(Int(progress * 100))% covered")
                .font(.caption.weight(.semibold))
                .foregroundColor(
                    isCovered
                        ? CalderaCategoryStyle.style(for: .covered).primary
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
                Text("More actions")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppColors.secondaryText)
                    .textCase(.uppercase)
                    .padding(.top, AppSpacing.xSmall)

                HStack(spacing: AppSpacing.medium) {
                    secondaryActionButton(
                        title: "Mark Paid",
                        systemImage: "checkmark.circle.fill",
                        color: AppColors.spendable
                    ) {
                        onMarkPaid()
                    }
                    .accessibilityLabel("Mark expense paid")

                    secondaryActionButton(
                        title: "Skip",
                        systemImage: "forward.end.fill",
                        color: AppColors.secondaryText
                    ) {
                        onSkipExpense()
                    }
                    .accessibilityLabel("Skip expense")
                }
            }
        }
    }

    private func secondaryActionButton(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, AppSpacing.small)
                .background(
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.10))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(color.opacity(0.16), lineWidth: 1)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
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

            AmountEntryField(
                title: "Amount to Set Aside",
                subtitle: "Money to keep out of Available to Spend for this expense.",
                placeholder: "0.00",
                text: $amountText,
                style: CalderaCategoryStyle.style(for: .upcomingExpense),
                accessibilityLabel: "Set aside amount"
            )

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

            if remainingAmount > 0 {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.small
                ) {
                    Text("Shortcuts")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppColors.secondaryText)
                        .textCase(.uppercase)

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
                }
                .padding(.top, AppSpacing.xSmall)
            }

            if allocatedAmount > 0 {
                Button {
                    onReset()
                } label: {
                    Label("Clear Set Aside", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear set aside amount")
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
            title: "Set Aside Full",
            systemImage: "checkmark.shield.fill",
            color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
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
            .frame(minHeight: 44)
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
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct EventAllocationNoteCard: View {

    var body: some View {
        GlassFormCard(color: CalderaCategoryStyle.style(for: .upcomingExpense).primary) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                IconBadge(
                    systemImage: "info.circle.fill",
                    color: CalderaCategoryStyle.style(for: .upcomingExpense).primary,
                    size: 34,
                    iconSize: 14
                )

                Text("Each future due date can have its own Set Aside amount.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct EventAllocationProgressBar: View {

    let progress: Double

    private var safeProgress: Double {
        guard progress.isFinite else {
            return 0
        }

        return min(
            max(progress, 0),
            1
        )
    }

    var body: some View {
        CalderaProgressBar(
            progress: safeProgress,
            colors: [
                CalderaCategoryStyle.style(for: .upcomingExpense).primary,
                CalderaCategoryStyle.style(for: .safeToSpend).primary
            ]
        )
        .frame(height: 10)
        .accessibilityLabel("Set aside progress")
        .accessibilityValue("\(Int(safeProgress * 100)) percent covered")
    }
}
