import SwiftUI
import SwiftData

struct EventAllocationDetailView: View {

    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.isSensitiveDataHidden)
    private var isSensitiveDataHidden

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
    @State private var saveGate = UpcomingExpenseActionSaveGate()
    @State private var saveErrorMessage: String?

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

        case .chargedToCard:
            return "Charged to card"

        case .postedFromChecking:
            return "Posted from checking"
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

        case .chargedToCard:
            return AppColors.accent

        case .postedFromChecking:
            return AppColors.spendable
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
        coverInFullAmount <= 0
    }

    private var coverInFullAmount: Double {
        CoverInFullPolicy.remainingAmount(
            target: forecast.event.amount,
            current: allocation?.allocatedAmount ?? 0
        )
    }

    private var coverInFullLifecycleIsEligible: Bool {
        !lifecycle.isResolved
    }

    private var showsCoverInFullAction: Bool {
        coverInFullLifecycleIsEligible
    }

    private var coverInFullRequest: CoverInFullRequest? {
        guard coverInFullLifecycleIsEligible,
              coverInFullAmount > 0 else {
            return nil
        }

        return CoverInFullRequest(
            name: forecast.event.name,
            amount: coverInFullAmount
        )
    }

    private var isCoverInFullEnabled: Bool {
        coverInFullRequest != nil &&
            pendingResolution == nil &&
            !saveGate.isSaving
    }

    private var allocationAmount: Double? {
        MoneyAmountParser.parse(amountText)
    }

    private var canAddAllocation: Bool {
        guard let allocationAmount else {
            return false
        }

        return allocationAmount > 0 &&
            coverInFullAmount > 0 &&
            !saveGate.isSaving
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
                    showsCoverInFullAction: showsCoverInFullAction,
                    isCoverInFullCovered: isCovered,
                    isCoverInFullEnabled: isCoverInFullEnabled,
                    isCoverInFullSaving: saveGate.isSaving,
                    coverInFullConfirmationMessage:
                        coverInFullRequest?
                            .confirmationMessage ?? "",
                    onSetAside: { amount in
                        addAllocation(amount)
                    },
                    onCoverInFull: coverInFull
                )

                EventAllocationNoteCard()

                EventAllocationLifecycleCard(
                    title: lifecycleTitle,
                    systemImage: lifecycleSystemImage,
                    color: lifecycleColor,
                    description: lifecycleDescription,
                    showsActions: !lifecycle.isResolved,
                    resolutionActionsDisabled: pendingResolution != nil ||
                        saveGate.isSaving,
                    onMarkPaid: {
                        requestResolution(.paid)
                    }
                )

                EventAllocationMoreActionsCard(
                    remainingAmount: coverInFullAmount,
                    allocatedAmount: allocatedAmount,
                    showsSkipAction: !lifecycle.isResolved,
                    actionsDisabled: pendingResolution != nil ||
                        saveGate.isSaving,
                    onQuickAdd: { amount in
                        addAllocation(amount)
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
                    .disabled(saveGate.isSaving)
                    .accessibilityLabel("Close set-aside details")
                }
            }
        }
        .alert(item: $pendingResolution, content: resolutionAlert)
        .alert(
            "Couldn’t Save Update",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        saveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                saveErrorMessage
                    ?? UpcomingExpenseActionPersistenceCoordinator
                        .failureMessage
            )
        }
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
                SensitiveValueFormatter.text(
                    request.message(setAsideAmount: allocatedAmount),
                    isHidden: isSensitiveDataHidden
                )
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

        case .chargedToCard:
            return "creditcard.fill"

        case .postedFromChecking:
            return "building.columns.fill"
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

        case .chargedToCard:
            return "This expense was charged to a card. This does not mean the card was paid."

        case .postedFromChecking:
            return "This expense posted from checking. Caldera did not move money."
        }
    }

    private func addAllocation(
        _ amount: Double
    ) {
        guard amount > 0,
              coverInFullAmount > 0,
              saveGate.begin()
        else {
            return
        }

        let clampedAmount = min(
            amount,
            coverInFullAmount
        )

        let result = UpcomingExpenseActionPersistenceCoordinator
            .addSetAside(
                amount,
                to: forecast,
                existingAllocation: allocation,
                insertAllocation: modelContext.insert,
                persistChanges: modelContext.save,
                rollback: modelContext.rollback
            )
        saveGate.finish()

        guard result.didSave else {
            saveErrorMessage = result.errorMessage
            return
        }

        amountText = ""
        showConfirmation(
            "You planned \(AppFormatters.currency(clampedAmount)) for this expense."
        )
    }

    private func resetAllocation() {
        guard let allocation,
              saveGate.begin() else {
            return
        }

        let result = UpcomingExpenseActionPersistenceCoordinator
            .resetSetAside(
                allocation,
                deleteAllocation: modelContext.delete,
                persistChanges: modelContext.save,
                rollback: modelContext.rollback
            )
        saveGate.finish()

        guard result.didSave else {
            saveErrorMessage = result.errorMessage
            return
        }

        showConfirmation("Set Aside updated.")
    }

    private func coverInFull() {
        guard coverInFullLifecycleIsEligible else {
            saveErrorMessage = CoverInFullPolicy.failureMessage
            return
        }

        guard coverInFullAmount > 0 else {
            showConfirmation("This expense is already covered.")
            return
        }

        guard saveGate.begin() else {
            return
        }

        let result = UpcomingExpenseActionPersistenceCoordinator
            .coverInFull(
                forecast: forecast,
                existingAllocation: allocation,
                insertAllocation: modelContext.insert,
                persistChanges: modelContext.save,
                rollback: modelContext.rollback
            )
        saveGate.finish()

        guard result.didSave else {
            saveErrorMessage = result.errorMessage
            return
        }

        amountText = ""
        showConfirmation(
            CoverInFullPolicy.successMessage(
                name: forecast.event.name
            )
        )
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
        _ resolution: ManualExpenseResolution
    ) {
        guard pendingResolution == nil,
              !saveGate.isSaving,
              !lifecycle.isResolved else {
            return
        }

        pendingResolution = PendingExpenseResolution(
            resolution: resolution
        )
    }

    private func confirmResolution(
        _ resolution: ManualExpenseResolution
    ) {
        guard !lifecycle.isResolved,
              saveGate.begin() else {
            pendingResolution = nil
            return
        }

        pendingResolution = nil

        let result = UpcomingExpenseActionPersistenceCoordinator.resolve(
            resolution.occurrenceResolution,
            forecast: forecast,
            existingStatus: occurrenceStatus,
            modelContext: modelContext,
            persistChanges: modelContext.save,
            rollback: modelContext.rollback
        )
        saveGate.finish()

        guard case let .saved(undo) = result else {
            saveErrorMessage = result.errorMessage
            return
        }

        resolutionUndo = undo

        let message = resolution == .paid
            ? "Marked as paid. \(AppFormatters.currency(allocatedAmount)) is no longer counted in Set Aside."
            : "Occurrence skipped. \(AppFormatters.currency(allocatedAmount)) is no longer counted in Set Aside."
        showConfirmation(
            message,
            preservesResolutionUndo: true
        )
    }

    private func undoResolution() {
        guard let resolutionUndo,
              saveGate.begin() else {
            return
        }

        let result = UpcomingExpenseActionPersistenceCoordinator
            .undoResolution(
                resolutionUndo,
                modelContext: modelContext,
                persistChanges: modelContext.save,
                rollback: modelContext.rollback
            )
        saveGate.finish()

        guard result.didSave else {
            saveErrorMessage = result.errorMessage
            return
        }

        self.resolutionUndo = nil
        showConfirmation(
            "Expense restored. \(AppFormatters.currency(allocatedAmount)) is counted in Set Aside again."
        )
    }
}

private enum ManualExpenseResolution: String {
    case paid
    case skipped

    var occurrenceResolution: ExpenseOccurrenceResolution {
        switch self {
        case .paid:
            return .paid

        case .skipped:
            return .skipped
        }
    }
}

private struct PendingExpenseResolution: Identifiable {

    let resolution: ManualExpenseResolution

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
