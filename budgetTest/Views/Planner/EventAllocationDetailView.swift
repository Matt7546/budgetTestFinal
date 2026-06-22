import SwiftUI
import SwiftData

struct EventAllocationDetailView: View {

    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.dismiss)
    private var dismiss

    let forecast: ForecastEvent
    let onEditEvent: () -> Void

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @State private var amountText = ""

    init(
        forecast: ForecastEvent,
        onEditEvent: @escaping () -> Void
    ) {
        self.forecast = forecast
        self.onEditEvent = onEditEvent

        let occurrenceID = forecast.occurrenceID
        _allocations = Query(
            filter: #Predicate<EventAllocation> { allocation in
                allocation.occurrenceID == occurrenceID
            }
        )
        _occurrenceStatuses = Query(
            filter: #Predicate<ExpenseOccurrenceStatus> { status in
                status.occurrenceID == occurrenceID
            }
        )
    }

    private var allocation: EventAllocation? {
        allocations.first
    }

    private var occurrenceStatus: ExpenseOccurrenceStatus? {
        occurrenceStatuses.first
    }

    private var lifecycle: ExpenseOccurrenceLifecycle {
        ExpenseOccurrenceLifecycleResolver.lifecycle(
            for: forecast,
            statuses: occurrenceStatuses
        )
    }

    private var lifecycleTitle: String {
        switch lifecycle {
        case .upcoming:
            return "Upcoming"

        case .overdue:
            return "Overdue"

        case .paid:
            return "Paid"

        case .skipped:
            return "Skipped"
        }
    }

    private var lifecycleColor: Color {
        switch lifecycle {
        case .upcoming:
            return AppColors.accent

        case .overdue:
            return AppColors.warning

        case .paid:
            return AppColors.spendable

        case .skipped:
            return AppColors.secondaryText
        }
    }

    private var allocatedAmount: Double {
        min(
            max(allocation?.allocatedAmount ?? 0, 0),
            forecast.event.amount
        )
    }

    private var remainingAmount: Double {
        max(
            forecast.event.amount - allocatedAmount,
            0
        )
    }

    private var progress: Double {
        guard forecast.event.amount > 0 else {
            return 0
        }

        return min(
            max(allocatedAmount / forecast.event.amount, 0),
            1
        )
    }

    private var isCovered: Bool {
        remainingAmount <= 0
    }

    private var allocationAmount: Double? {
        Double(amountText)
    }

    private var canAddAllocation: Bool {
        guard let allocationAmount else {
            return false
        }

        return allocationAmount > 0 && remainingAmount > 0
    }

    private var eventColor: Color {
        forecast.event.type == .income
            ? AppColors.spendable
            : AppColors.obligation
    }

    var body: some View {
        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                contentPadding: .all,
                contentSpacing: AppSpacing.regular
            ) {
                ModalHeaderView(
                    eyebrow: "Upcoming Expense",
                    title: forecast.event.name,
                    subtitle: forecast.occurrenceDate.formatted(
                        .dateTime
                            .weekday(.wide)
                            .month(.wide)
                            .day()
                            .year()
                    ),
                    systemImage: "lock.shield.fill",
                    color: AppColors.protected
                )

                summaryCard

                lifecycleCard

                allocationCard

                noteCard

                SecondaryButton(
                    "Edit Event Details",
                    systemImage: "square.and.pencil",
                    trailingSystemImage: nil,
                    fillsWidth: true
                ) {
                    dismiss()
                    onEditEvent()
                }
                .accessibilityLabel("Edit event details")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Close allocation details")
                }
            }
        }
    }

    private var lifecycleCard: some View {
        GlassFormCard(color: lifecycleColor) {
            FormSectionHeader(
                title: lifecycleTitle,
                systemImage: lifecycleSystemImage,
                color: lifecycleColor
            )

            Text(lifecycleDescription)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if lifecycle != .paid &&
                lifecycle != .skipped {
                HStack(spacing: AppSpacing.medium) {
                    SecondaryButton(
                        "Mark Paid",
                        systemImage: "checkmark.circle.fill",
                        cornerRadius: AppRadii.button,
                        foregroundColor: AppColors.spendable,
                        fillsWidth: true
                    ) {
                        markOccurrence(.paid)
                    }
                    .accessibilityLabel("Mark expense paid")

                    DestructiveButton(
                        "Skip Expense",
                        systemImage: "forward.end.fill",
                        cornerRadius: AppRadii.button
                    ) {
                        markOccurrence(.skipped)
                    }
                    .accessibilityLabel("Skip expense")
                }
            }
        }
    }

    private var lifecycleSystemImage: String {
        switch lifecycle {
        case .upcoming:
            return "calendar.badge.clock"

        case .overdue:
            return "exclamationmark.triangle.fill"

        case .paid:
            return "checkmark.circle.fill"

        case .skipped:
            return "forward.end.fill"
        }
    }

    private var lifecycleDescription: String {
        switch lifecycle {
        case .upcoming:
            return "This upcoming expense is still active."

        case .overdue:
            return "This expense is overdue and remains active until it is paid or skipped."

        case .paid:
            return "This expense is paid. Set-aside money is no longer counted as protected."

        case .skipped:
            return "This expense was skipped. Set-aside money is no longer counted as protected."
        }
    }

    private var summaryCard: some View {
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
                        forecast.event.amount,
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

                if forecast.event.frequency != .once {
                    Text(forecast.event.frequency.rawValue)
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

            allocationProgressBar

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

    private var allocationCard: some View {
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

                addAllocation(allocationAmount)
            }
            .accessibilityLabel("Set aside money")

            if allocatedAmount > 0 {
                DestructiveButton(
                    "Reset Set Aside",
                    systemImage: "arrow.counterclockwise",
                    cornerRadius: AppRadii.button
                ) {
                    resetAllocation()
                }
                .accessibilityLabel("Reset set aside amount")
            }
        }
    }

    private var noteCard: some View {
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

    private var allocationProgressBar: some View {
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

    private func quickAddButton(
        amount: Double
    ) -> some View {
        allocationOptionButton(
            title: "+\(amount.formatted(.currency(code: "USD").precision(.fractionLength(0))))",
            systemImage: "plus",
            color: AppColors.accent
        ) {
            addAllocation(amount)
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
            addAllocation(remainingAmount)
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

    private func addAllocation(
        _ amount: Double
    ) {
        guard amount > 0,
              remainingAmount > 0
        else {
            return
        }

        let clampedAmount = min(
            amount,
            remainingAmount
        )

        if let allocation {
            allocation.apply(
                amount: clampedAmount,
                eventAmount: forecast.event.amount
            )
        } else {
            let newAllocation = EventAllocation(
                occurrenceID: forecast.occurrenceID,
                sourceEventID: forecast.event.id,
                occurrenceDate: forecast.normalizedOccurrenceDate,
                allocatedAmount: clampedAmount
            )

            modelContext.insert(newAllocation)
        }

        amountText = ""
    }

    private func resetAllocation() {
        guard let allocation else {
            return
        }

        modelContext.delete(allocation)
    }

    private func markOccurrence(
        _ resolution: ExpenseOccurrenceResolution
    ) {
        if let occurrenceStatus {
            occurrenceStatus.status = resolution
        } else {
            let status = ExpenseOccurrenceStatus(
                occurrenceID: forecast.occurrenceID,
                sourceEventID: forecast.event.id,
                occurrenceDate: forecast.normalizedOccurrenceDate,
                status: resolution
            )

            modelContext.insert(status)
        }
    }
}
