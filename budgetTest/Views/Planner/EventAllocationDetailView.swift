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
            ? CalderaCategoryStyle.style(for: .income).primary
            : CalderaCategoryStyle.style(for: .upcomingExpense).primary
    }

    var body: some View {
        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                backgroundStyle: .staticGradient,
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
                    systemImage: CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                    color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
                )

                EventAllocationSummaryCard(
                    eventAmount: forecast.event.amount,
                    eventFrequency: forecast.event.frequency,
                    eventColor: eventColor,
                    allocatedAmount: allocatedAmount,
                    remainingAmount: remainingAmount,
                    progress: progress,
                    isCovered: isCovered
                )

                EventAllocationLifecycleCard(
                    title: lifecycleTitle,
                    systemImage: lifecycleSystemImage,
                    color: lifecycleColor,
                    description: lifecycleDescription,
                    showsActions: lifecycle != .paid &&
                        lifecycle != .skipped,
                    onMarkPaid: {
                        markOccurrence(.paid)
                    },
                    onSkipExpense: {
                        markOccurrence(.skipped)
                    }
                )

                EventAllocationInputCard(
                    amountText: $amountText,
                    canAddAllocation: canAddAllocation,
                    allocatedAmount: allocatedAmount,
                    remainingAmount: remainingAmount,
                    onSetAside: { amount in
                        addAllocation(amount)
                    },
                    onQuickAdd: { amount in
                        addAllocation(amount)
                    },
                    onCoverFull: {
                        addAllocation(remainingAmount)
                    },
                    onReset: {
                        resetAllocation()
                    }
                )

                EventAllocationNoteCard()

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
            .keyboardDismissToolbar()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Close set-aside details")
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
            return "This expense is paid. Set-aside money is no longer counted as set aside."

        case .skipped:
            return "This expense was skipped. Set-aside money is no longer counted as set aside."
        }
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
