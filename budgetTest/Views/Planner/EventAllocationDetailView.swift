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
    @State private var confirmationMessage: String?
    @State private var confirmationID = UUID()
    @State private var pendingResolution: PendingExpenseResolution?
    @State private var resolutionUndo: ExpenseOccurrenceResolutionUndo?
    @State private var isApplyingResolution = false

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
            return "Past due"

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
        MoneyAmountParser.parse(amountText)
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

                EventAllocationInputCard(
                    amountText: $amountText,
                    canAddAllocation: canAddAllocation,
                    onSetAside: { amount in
                        addAllocation(amount)
                    }
                )

                EventAllocationNoteCard()

                EventAllocationLifecycleCard(
                    title: lifecycleTitle,
                    systemImage: lifecycleSystemImage,
                    color: lifecycleColor,
                    description: lifecycleDescription,
                    showsActions: lifecycle != .paid &&
                        lifecycle != .skipped,
                    resolutionActionsDisabled: pendingResolution != nil ||
                        isApplyingResolution,
                    onMarkPaid: {
                        requestResolution(.paid)
                    }
                )

                EventAllocationMoreActionsCard(
                    remainingAmount: remainingAmount,
                    allocatedAmount: allocatedAmount,
                    showsSkipAction: lifecycle != .paid &&
                        lifecycle != .skipped,
                    resolutionActionsDisabled: pendingResolution != nil ||
                        isApplyingResolution,
                    onQuickAdd: { amount in
                        addAllocation(amount)
                    },
                    onCoverFull: {
                        addAllocation(remainingAmount)
                    },
                    onReset: {
                        resetAllocation()
                    },
                    onSkipExpense: {
                        requestResolution(.skipped)
                    },
                    onEditExpense: {
                        dismiss()
                        onEditEvent()
                    }
                )
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
        .alert(item: $pendingResolution, content: resolutionAlert)
        .calderaConfirmationOverlay(
            message: confirmationMessage,
            actionTitle: resolutionUndo == nil ? nil : "Undo",
            action: undoResolution
        )
    }

    private func resolutionAlert(
        _ request: PendingExpenseResolution
    ) -> Alert {
        Alert(
            title: Text(request.title),
            message: Text(
                request.message(setAsideAmount: allocatedAmount)
            ),
            primaryButton: .default(Text(request.confirmationTitle)) {
                confirmResolution(request.resolution)
            },
            secondaryButton: .cancel()
        )
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
            return "This expense is due \(AppFormatters.abbreviatedMonthDay(forecast.occurrenceDate))."

        case .overdue:
            return "This expense is past due. You can still plan money for it or mark it handled."

        case .paid:
            return "You marked this expense as paid outside Caldera. Money you set aside for it is no longer counted as Set Aside."

        case .skipped:
            return "This expense was skipped. Money you set aside for it is no longer counted as Set Aside."
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
        showConfirmation(
            "You planned \(AppFormatters.currency(clampedAmount)) for this expense."
        )
    }

    private func resetAllocation() {
        guard let allocation else {
            return
        }

        modelContext.delete(allocation)
        showConfirmation("Set Aside updated.")
    }

    private func showConfirmation(
        _ message: String,
        preservesResolutionUndo: Bool = false
    ) {
        if !preservesResolutionUndo {
            resolutionUndo = nil
        }

        let id = UUID()
        confirmationID = id
        confirmationMessage = message
        let displayDuration: UInt64 = preservesResolutionUndo
            ? 6_000_000_000
            : 2_400_000_000

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: displayDuration)

            if confirmationID == id {
                confirmationMessage = nil
                resolutionUndo = nil
            }
        }
    }

    private func requestResolution(
        _ resolution: ExpenseOccurrenceResolution
    ) {
        guard pendingResolution == nil,
              !isApplyingResolution,
              lifecycle != .paid,
              lifecycle != .skipped else {
            return
        }

        pendingResolution = PendingExpenseResolution(
            resolution: resolution
        )
    }

    private func confirmResolution(
        _ resolution: ExpenseOccurrenceResolution
    ) {
        guard !isApplyingResolution,
              lifecycle != .paid,
              lifecycle != .skipped else {
            pendingResolution = nil
            return
        }

        isApplyingResolution = true
        pendingResolution = nil

        resolutionUndo = ExpenseOccurrenceResolutionMutation.apply(
            resolution,
            to: forecast,
            existingStatus: occurrenceStatus,
            in: modelContext
        )

        let message = resolution == .paid
            ? "Marked as paid. \(AppFormatters.currency(allocatedAmount)) is no longer counted in Set Aside."
            : "Occurrence skipped. \(AppFormatters.currency(allocatedAmount)) is no longer counted in Set Aside."
        showConfirmation(
            message,
            preservesResolutionUndo: true
        )
        isApplyingResolution = false
    }

    private func undoResolution() {
        guard let resolutionUndo else {
            return
        }

        resolutionUndo.restore(in: modelContext)
        self.resolutionUndo = nil
        showConfirmation(
            "Expense restored. \(AppFormatters.currency(allocatedAmount)) is counted in Set Aside again."
        )
    }
}

private struct PendingExpenseResolution: Identifiable {

    let resolution: ExpenseOccurrenceResolution

    var id: String {
        resolution.rawValue
    }

    var title: String {
        switch resolution {
        case .paid:
            return "Mark as paid?"
        case .skipped:
            return "Skip this occurrence?"
        }
    }

    var confirmationTitle: String {
        switch resolution {
        case .paid:
            return "Mark as Paid"
        case .skipped:
            return "Skip Occurrence"
        }
    }

    func message(setAsideAmount: Double) -> String {
        let impact = "This will stop counting \(AppFormatters.currency(setAsideAmount)) set aside for this expense in Available to Spend."

        switch resolution {
        case .paid:
            return "Only continue if you paid this expense outside Caldera. \(impact)"
        case .skipped:
            return "This skips only this planned occurrence, not the recurring expense. \(impact)"
        }
    }
}
