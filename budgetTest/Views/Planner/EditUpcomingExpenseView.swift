import SwiftData
import SwiftUI
import UIKit

enum UpcomingExpenseSetAsideChangeMode: String, CaseIterable, Identifiable {
    case add
    case use

    var id: Self { self }

    var title: String {
        switch self {
        case .add:
            return "Add"
        case .use:
            return "Use"
        }
    }

    var heroTitle: String {
        switch self {
        case .add:
            return "Add to Set Aside"
        case .use:
            return "Use Set Aside"
        }
    }
}

struct UpcomingExpenseSetAsideInput: Equatable {
    var changeMode: UpcomingExpenseSetAsideChangeMode = .add
    var amountText = ""

    var changeAmount: Double? {
        let trimmedAmount = amountText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedAmount.isEmpty else {
            return 0
        }

        guard let amount = MoneyAmountParser.parse(trimmedAmount),
              amount.isFinite,
              amount >= 0 else {
            return nil
        }

        return amount
    }

    func projectedSetAsideAmount(
        currentSetAside: Double,
        amountNeeded: Double
    ) -> Double? {
        guard let changeAmount else {
            return nil
        }

        let current = min(
            max(currentSetAside, 0),
            max(amountNeeded, 0)
        )

        switch changeMode {
        case .add:
            guard changeAmount <= max(amountNeeded - current, 0) else {
                return nil
            }

            return current + changeAmount

        case .use:
            guard changeAmount <= current else {
                return nil
            }

            return max(current - changeAmount, 0)
        }
    }

    func projectedProgress(
        currentSetAside: Double,
        amountNeeded: Double
    ) -> Double {
        guard amountNeeded > 0,
              let projectedAmount = projectedSetAsideAmount(
                currentSetAside: currentSetAside,
                amountNeeded: amountNeeded
              ) else {
            return amountNeeded > 0
                ? min(max(currentSetAside / amountNeeded, 0), 1)
                : 0
        }

        return min(max(projectedAmount / amountNeeded, 0), 1)
    }

    func hasValidChange(
        currentSetAside: Double,
        amountNeeded: Double
    ) -> Bool {
        guard let changeAmount,
              changeAmount > 0 else {
            return false
        }

        return projectedSetAsideAmount(
            currentSetAside: currentSetAside,
            amountNeeded: amountNeeded
        ) != nil
    }

    func validationMessage(
        currentSetAside: Double,
        amountNeeded: Double
    ) -> String? {
        guard let changeAmount else {
            return "Enter a valid Set Aside amount."
        }

        let current = min(
            max(currentSetAside, 0),
            max(amountNeeded, 0)
        )
        let remaining = max(amountNeeded - current, 0)

        guard changeAmount > 0 else {
            if changeMode == .add && remaining <= 0 {
                return "This expense is fully set aside."
            }

            if changeMode == .use && current <= 0 {
                return "There isn't any Set Aside to use."
            }

            return "Enter an amount greater than $0."
        }

        switch changeMode {
        case .add where changeAmount > remaining:
            return "You can add up to \(AppFormatters.currency(remaining)) for this expense."

        case .use where changeAmount > current:
            return "You can use up to \(AppFormatters.currency(current)) from this expense."

        default:
            return nil
        }
    }
}

@MainActor
enum UpcomingExpenseSetAsidePersistenceCoordinator {

    static func persist(
        input: UpcomingExpenseSetAsideInput,
        event: PlannerEvent,
        forecast: ForecastEvent,
        allocation: EventAllocation?,
        currentSetAside: Double,
        insertAllocation: (EventAllocation) -> Void,
        deleteAllocation: (EventAllocation) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> PlanningCreationPersistenceResult {
        guard event.type == .expense,
              forecast.event.id == event.id,
              input.hasValidChange(
                currentSetAside: currentSetAside,
                amountNeeded: event.amount
              ),
              let projectedAmount = input.projectedSetAsideAmount(
                currentSetAside: currentSetAside,
                amountNeeded: event.amount
              ) else {
            return .failed(
                message: "Make a valid Set Aside change before saving."
            )
        }

        let originalAllocatedAmount = allocation?.allocatedAmount
        let originalUpdatedAt = allocation?.updatedAt

        if projectedAmount <= 0.000_001 {
            if let allocation {
                deleteAllocation(allocation)
            }
        } else if let allocation {
            allocation.allocatedAmount = projectedAmount
            allocation.updatedAt = Date()
        } else {
            insertAllocation(
                EventAllocation(
                    occurrenceID: forecast.occurrenceID,
                    sourceEventID: event.id,
                    occurrenceDate: forecast.normalizedOccurrenceDate,
                    allocatedAmount: projectedAmount
                )
            )
        }

        do {
            try persistChanges()
            return .saved
        } catch {
            rollback()

            if let allocation,
               let originalAllocatedAmount,
               let originalUpdatedAt {
                allocation.allocatedAmount = originalAllocatedAmount
                allocation.updatedAt = originalUpdatedAt
            }

            return .failed(
                message: "Your Set Aside update wasn't saved. Please try again."
            )
        }
    }
}

struct UpcomingExpenseEditInput: Equatable {

    struct Original: Equatable {
        let id: UUID
        let name: String
        let amount: Double
        let dueDate: Date
        let frequency: PlannerFrequency
        let accentColorID: String?
    }

    let original: Original
    var name: String
    var amountText: String
    var dueDate: Date
    var frequency: PlannerFrequency
    var accentColorID: String?

    init(event: PlannerEvent) {
        original = Original(
            id: event.id,
            name: event.name,
            amount: event.amount,
            dueDate: event.date,
            frequency: event.frequency,
            accentColorID: event.accentColorID
        )
        name = event.name
        amountText = Self.editingText(for: event.amount)
        dueDate = event.date
        frequency = event.frequency
        accentColorID = event.accentColorID
    }

    var amount: Double? {
        guard let value = MoneyAmountParser.parse(amountText),
              value.isFinite,
              value > 0 else {
            return nil
        }

        return value
    }

    var hasValidChange: Bool {
        guard validationMessageWithoutChangeCheck == nil,
              let amount else {
            return false
        }

        return name != original.name
            || abs(amount - original.amount) > 0.000_001
            || dueDate != original.dueDate
            || frequency != original.frequency
            || accentColorID != original.accentColorID
    }

    var isValid: Bool {
        validationMessageWithoutChangeCheck == nil
    }

    var hasScheduleChange: Bool {
        let dateChanged = !Calendar.current.isDate(
            dueDate,
            inSameDayAs: original.dueDate
        )

        return dateChanged || frequency != original.frequency
    }

    var validationMessage: String? {
        if let validationMessageWithoutChangeCheck {
            return validationMessageWithoutChangeCheck
        }

        return hasValidChange
            ? nil
            : "Make a change to save."
    }

    func apply(to event: PlannerEvent) {
        guard let amount else { return }

        event.name = name
        event.amount = amount
        event.date = dueDate
        event.frequency = frequency
        event.accentColorID = accentColorID
    }

    func restoreOriginal(on event: PlannerEvent) {
        event.name = original.name
        event.amount = original.amount
        event.date = original.dueDate
        event.frequency = original.frequency
        event.accentColorID = original.accentColorID
    }

    private var validationMessageWithoutChangeCheck: String? {
        guard !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return "Add an expense name to save."
        }

        guard amount != nil else {
            return "Enter an amount greater than $0."
        }

        return nil
    }

    private static func editingText(for amount: Double) -> String {
        let text = String(amount)

        return text.hasSuffix(".0")
            ? String(text.dropLast(2))
            : text
    }
}

@MainActor
enum UpcomingExpenseEditPersistenceCoordinator {

    static func persist(
        input: UpcomingExpenseEditInput,
        event: PlannerEvent,
        resetOccurrenceTracking: Bool,
        relatedAllocations: [EventAllocation],
        relatedStatuses: [ExpenseOccurrenceStatus],
        deleteAllocation: (EventAllocation) -> Void,
        deleteStatus: (ExpenseOccurrenceStatus) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> PlanningCreationPersistenceResult {
        guard event.id == input.original.id,
              event.type == .expense,
              input.hasValidChange else {
            return .failed(
                message: "Make a valid change before saving."
            )
        }

        input.apply(to: event)

        if resetOccurrenceTracking {
            relatedAllocations.forEach(deleteAllocation)
            relatedStatuses.forEach(deleteStatus)
        }

        do {
            try persistChanges()
            return .saved
        } catch {
            input.restoreOriginal(on: event)
            rollback()
            return .failed(
                message: "Your expense updates weren't saved. Please try again."
            )
        }
    }
}

enum UpcomingExpenseInlinePanel: Equatable {
    case none
    case details
    case options

    mutating func toggle(_ panel: Self) {
        self = self == panel ? .none : panel
    }
}

@MainActor
enum UpcomingExpenseUnifiedPersistenceCoordinator {

    static func persist(
        details: UpcomingExpenseEditInput,
        setAside: UpcomingExpenseSetAsideInput,
        event: PlannerEvent,
        forecast: ForecastEvent,
        allocation: EventAllocation?,
        currentSetAside: Double,
        resetOccurrenceTracking: Bool,
        relatedAllocations: [EventAllocation],
        relatedStatuses: [ExpenseOccurrenceStatus],
        insertAllocation: (EventAllocation) -> Void,
        deleteAllocation: (EventAllocation) -> Void,
        deleteStatus: (ExpenseOccurrenceStatus) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> PlanningCreationPersistenceResult {
        guard event.id == details.original.id,
              event.type == .expense,
              forecast.event.id == event.id,
              details.isValid,
              let amountNeeded = details.amount else {
            return .failed(
                message: "Make valid expense changes before saving."
            )
        }

        let requestedSetAside = setAside.changeAmount
        guard requestedSetAside != nil else {
            return .failed(message: "Enter a valid Set Aside amount.")
        }

        let hasSetAsideChange = (requestedSetAside ?? 0) > 0
        guard details.hasValidChange || hasSetAsideChange else {
            return .failed(message: "Make a change before saving.")
        }

        if resetOccurrenceTracking,
           hasSetAsideChange,
           setAside.changeMode == .use {
            return .failed(
                message: "Save the new schedule before using Set Aside."
            )
        }

        let setAsideStartingAmount = resetOccurrenceTracking
            ? 0
            : currentSetAside
        let projectedSetAside = hasSetAsideChange
            ? setAside.projectedSetAsideAmount(
                currentSetAside: setAsideStartingAmount,
                amountNeeded: amountNeeded
            )
            : nil

        guard !hasSetAsideChange || projectedSetAside != nil else {
            return .failed(
                message: "Make a valid Set Aside change before saving."
            )
        }

        let originalAllocatedAmount = allocation?.allocatedAmount
        let originalUpdatedAt = allocation?.updatedAt

        if details.hasValidChange {
            details.apply(to: event)
        }

        if resetOccurrenceTracking {
            relatedAllocations.forEach(deleteAllocation)
            relatedStatuses.forEach(deleteStatus)
        }

        if let projectedSetAside {
            let targetAllocation = resetOccurrenceTracking
                ? nil
                : allocation

            if projectedSetAside <= 0.000_001 {
                if let targetAllocation {
                    deleteAllocation(targetAllocation)
                }
            } else if let targetAllocation {
                targetAllocation.allocatedAmount = projectedSetAside
                targetAllocation.updatedAt = Date()
            } else {
                let targetForecast = resetOccurrenceTracking
                    ? ForecastEvent(
                        event: event,
                        occurrenceDate: details.dueDate
                    )
                    : forecast

                insertAllocation(
                    EventAllocation(
                        occurrenceID: targetForecast.occurrenceID,
                        sourceEventID: event.id,
                        occurrenceDate:
                            targetForecast.normalizedOccurrenceDate,
                        allocatedAmount: projectedSetAside
                    )
                )
            }
        }

        do {
            try persistChanges()
            return .saved
        } catch {
            details.restoreOriginal(on: event)
            rollback()

            if !resetOccurrenceTracking,
               let allocation,
               let originalAllocatedAmount,
               let originalUpdatedAt {
                allocation.allocatedAmount = originalAllocatedAmount
                allocation.updatedAt = originalUpdatedAt
            }

            return .failed(
                message: "Your expense update wasn't saved. Please try again."
            )
        }
    }
}

enum PlannerEventEditorKind: Equatable {
    case upcomingExpense
    case legacyIncome

    init(event: PlannerEvent) {
        self = event.type == .expense
            ? .upcomingExpense
            : .legacyIncome
    }
}

struct PlannerEventEditorDestination: View {

    let editingEvent: PlannerEvent
    let forecast: ForecastEvent?
    let onSaved: ((PlannerEventType, Bool) -> Void)?
    let onScheduleReset: (() -> Void)?
    let onDeleted: ((PlannerEventType) -> Void)?

    init(
        editingEvent: PlannerEvent,
        forecast: ForecastEvent? = nil,
        onSaved: ((PlannerEventType, Bool) -> Void)? = nil,
        onScheduleReset: (() -> Void)? = nil,
        onDeleted: ((PlannerEventType) -> Void)? = nil
    ) {
        self.editingEvent = editingEvent
        self.forecast = forecast
        self.onSaved = onSaved
        self.onScheduleReset = onScheduleReset
        self.onDeleted = onDeleted
    }

    @ViewBuilder
    var body: some View {
        switch PlannerEventEditorKind(event: editingEvent) {
        case .upcomingExpense:
            EditUpcomingExpenseView(
                event: editingEvent,
                forecast: forecast,
                onSaved: onSaved,
                onScheduleReset: onScheduleReset,
                onDeleted: onDeleted
            )

        case .legacyIncome:
            AddPlannerEventView(
                editingEvent: editingEvent,
                onSaved: onSaved,
                onScheduleReset: onScheduleReset,
                onDeleted: onDeleted
            )
        }
    }
}

struct EditUpcomingExpenseView: View {

    private enum SavePhase {
        case idle
        case completing
        case success
    }

    private enum FocusedField: Hashable {
        case setAsideAmount
        case name
        case expenseAmount
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var allocations: [EventAllocation]
    @Query private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    let event: PlannerEvent
    let forecast: ForecastEvent
    private let onSaved: ((PlannerEventType, Bool) -> Void)?
    private let onScheduleReset: (() -> Void)?
    private let onDeleted: ((PlannerEventType) -> Void)?

    @State private var setAsideInput = UpcomingExpenseSetAsideInput()
    @State private var detailsInput: UpcomingExpenseEditInput
    @State private var activeInlinePanel: UpcomingExpenseInlinePanel = .none
    @State private var isShowingScheduleConfirmation = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var swipeProgress: CGFloat = 0
    @State private var circleCompletionProgress: CGFloat = 0
    @State private var foregroundOpacity: CGFloat = 1
    @State private var savePhase: SavePhase = .idle
    @State private var didResetOccurrenceTracking = false
    @State private var saveCompletionTask: Task<Void, Never>?
    @FocusState private var focusedField: FocusedField?

    private let controlWidth: CGFloat = 320

    init(
        event: PlannerEvent,
        forecast: ForecastEvent? = nil,
        onSaved: ((PlannerEventType, Bool) -> Void)? = nil,
        onScheduleReset: (() -> Void)? = nil,
        onDeleted: ((PlannerEventType) -> Void)? = nil
    ) {
        self.event = event
        self.forecast = forecast
            ?? ForecastEvent(
                event: event,
                occurrenceDate: event.date
            )
        self.onSaved = onSaved
        self.onScheduleReset = onScheduleReset
        self.onDeleted = onDeleted
        _detailsInput = State(
            initialValue: UpcomingExpenseEditInput(event: event)
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let circleLayout = NewUpcomingExpenseCircleLayout(
                    size: proxy.size,
                    projectedProgress: projectedProgress,
                    swipeProgress: swipeProgress,
                    completionProgress: circleCompletionProgress
                )

                ZStack {
                    CalderaModalBackground(mood: .upcomingExpense)

                    NewUpcomingExpenseConcentricCircles(
                        layout: circleLayout,
                        swipeProgress: swipeProgress,
                        completionProgress: circleCompletionProgress
                    )
                    .animation(
                        .easeInOut(duration: 0.42),
                        value: projectedProgress
                    )

                    VStack(spacing: 0) {
                        topControls

                        contributionContent(
                            usesCompactSpacing: proxy.size.height < 740
                        )
                        .padding(
                            .top,
                            proxy.size.height < 740 ? 18 : 30
                        )

                        Spacer(minLength: AppSpacing.screen)
                    }
                    .padding(.horizontal, AppSpacing.regular)
                    .padding(.top, AppSpacing.medium)
                    .padding(.bottom, AppSpacing.panel)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .dismissKeyboardOnBackgroundTap()
                    .opacity(foregroundOpacity)
                    .allowsHitTesting(
                        savePhase == .idle && !isSaving
                    )

                    if isSwipeAffordanceVisible {
                        PlanningSwipeToSaveInteraction(
                            circleCenter: circleLayout.center,
                            circleDiameter: circleLayout.innerDiameter,
                            affordanceCenter: CGPoint(
                                x: proxy.size.width / 2,
                                y: swipeAffordanceCenterY(
                                    layout: circleLayout,
                                    size: proxy.size
                                )
                            ),
                            isEnabled: true,
                            accessibilityLabel: "Save expense update",
                            accessibilityHint: "Swipe up or activate to save Set Aside and expense detail changes.",
                            swipeProgress: $swipeProgress,
                            onSaveTriggered: handleSaveTriggered
                        )
                        .opacity(foregroundOpacity)
                        .transition(.opacity)
                    }

                    if savePhase == .success {
                        PlanningCreationSuccessOverlay(
                            title: "Expense updated",
                            isPresented: true,
                            showsConfetti: !reduceMotion
                        )
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.94)
                            )
                        )
                    }
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button {
                        focusedField = nil
                    } label: {
                        Label(
                            "Done",
                            systemImage: "keyboard.chevron.compact.down"
                        )
                    }
                    .accessibilityLabel("Hide keyboard")
                }
            }
        }
        .calderaTransparentNavigationSurface()
        .confirmationDialog(
            "Update schedule?",
            isPresented: $isShowingScheduleConfirmation,
            titleVisibility: .visible
        ) {
            Button("Update Expense") {
                saveExpense(resetOccurrenceTracking: true)
            }

            Button("Cancel", role: .cancel) {
                resetSwipeProgress()
            }
        } message: {
            Text("Changing the date or repeat pattern resets existing Set Aside and status tracking for this expense. Any new Add Set Aside amount will apply to the updated schedule.")
        }
        .confirmationDialog(
            "Delete upcoming expense?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Expense", role: .destructive) {
                deleteExpense()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the expense and its Set Aside plan.")
        }
        .alert(
            "Couldn't Update Expense",
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
                    ?? "Your expense update wasn't saved. Please try again."
            )
        }
        .onDisappear {
            saveCompletionTask?.cancel()
        }
    }

    private var currentAllocation: EventAllocation? {
        allocations.first {
            $0.occurrenceID == forecast.occurrenceID
        }
    }

    private var currentSetAsideAmount: Double {
        min(
            max(currentAllocation?.allocatedAmount ?? 0, 0),
            max(effectiveAmountNeeded, 0)
        )
    }

    private var remainingAmount: Double {
        max(effectiveAmountNeeded - currentSetAsideAmount, 0)
    }

    private var effectiveAmountNeeded: Double {
        detailsInput.amount ?? event.amount
    }

    private var projectedSetAsideAmount: Double {
        setAsideInput.projectedSetAsideAmount(
            currentSetAside: currentSetAsideAmount,
            amountNeeded: effectiveAmountNeeded
        ) ?? currentSetAsideAmount
    }

    private var projectedProgress: Double {
        setAsideInput.projectedProgress(
            currentSetAside: currentSetAsideAmount,
            amountNeeded: effectiveAmountNeeded
        )
    }

    private var hasValidSetAsideChange: Bool {
        setAsideInput.hasValidChange(
            currentSetAside: currentSetAsideAmount,
            amountNeeded: effectiveAmountNeeded
        )
    }

    private var hasMeaningfulChange: Bool {
        detailsInput.hasValidChange || hasValidSetAsideChange
    }

    private var hasValidUnifiedChange: Bool {
        guard detailsInput.isValid else {
            return false
        }

        let trimmedSetAside = setAsideInput.amountText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if trimmedSetAside.isEmpty
            || setAsideInput.changeAmount == 0 {
            return detailsInput.hasValidChange
        }

        guard hasValidSetAsideChange else {
            return false
        }

        return !detailsInput.hasScheduleChange
            || setAsideInput.changeMode == .add
    }

    private var relatedAllocations: [EventAllocation] {
        allocations.filter { $0.sourceEventID == event.id }
    }

    private var relatedOccurrenceStatuses: [ExpenseOccurrenceStatus] {
        occurrenceStatuses.filter { $0.sourceEventID == event.id }
    }

    private var hasRelatedOccurrenceRecords: Bool {
        !relatedAllocations.isEmpty
            || !relatedOccurrenceStatuses.isEmpty
    }

    private var shouldConfirmScheduleChange: Bool {
        hasRelatedOccurrenceRecords && detailsInput.hasScheduleChange
    }

    private var expenseStyle: CalderaCategoryStyle {
        CalderaCategoryStyle.style(for: .upcomingExpense)
    }

    private var expenseAccentGradient: LinearGradient {
        LinearGradient(
            colors: expenseStyle.gradient,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var pillSurface: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.10))
            : AnyShapeStyle(Color.white.opacity(0.70))
    }

    private var topControls: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .editUpcomingExpensePillControl(
                colorScheme: colorScheme
            )
            .accessibilityLabel("Cancel Set Aside update")

            Spacer()

            Button(action: toggleInlineOptions) {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .editUpcomingExpensePillControl(
                colorScheme: colorScheme
            )
            .accessibilityLabel("Expense options")
            .accessibilityHint("Show inline expense options")
        }
    }

    private func contributionContent(
        usesCompactSpacing: Bool
    ) -> some View {
        VStack(
            spacing: usesCompactSpacing
                ? AppSpacing.small
                : AppSpacing.regular
        ) {
            expenseNamePill

            switch activeInlinePanel {
            case .none:
                expenseContextPill
                setAsideModePicker
                setAsideAmountHero
                scheduleContext
            case .details:
                inlineExpenseDetails
            case .options:
                expenseContextPill
                inlineExpenseOptions
            }

            Text(helperMessage)
                .font(.caption.weight(.medium))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )
                .multilineTextAlignment(.center)
                .frame(minHeight: 18)
                .padding(.horizontal, AppSpacing.regular)
                .accessibilityLabel(helperMessage)
        }
        .frame(maxWidth: .infinity)
    }

    private var expenseNamePill: some View {
        Button(action: toggleInlineDetails) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: expenseStyle.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(expenseAccentGradient)

                Text(detailsInput.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(
                        CalderaVisualStyle.primaryText(colorScheme)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)

                Image(systemName: "pencil")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
            }
            .padding(.horizontal, AppSpacing.regular)
            .frame(maxWidth: controlWidth)
            .frame(height: 52)
            .background(pillSurface)
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        Color.white.opacity(
                            colorScheme == .dark ? 0.20 : 0.72
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(Capsule(style: .continuous))
            .shadow(
                color: expenseStyle.primary.opacity(
                    colorScheme == .dark ? 0.16 : 0.08
                ),
                radius: 14,
                y: 8
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expense \(detailsInput.name)")
        .accessibilityHint("Double tap to show inline expense details")
    }

    private var expenseContextPill: some View {
        Button(action: toggleInlineDetails) {
            HStack(spacing: AppSpacing.small) {
                contextMetric(
                    title: "Amount needed",
                    amount: effectiveAmountNeeded
                )

                contextDivider

                contextMetric(
                    title: "Already set aside",
                    amount: currentSetAsideAmount
                )

                contextDivider

                contextMetric(
                    title: "Remaining",
                    amount: remainingAmount
                )
            }
            .padding(.horizontal, AppSpacing.medium)
            .frame(maxWidth: controlWidth)
            .frame(height: 52)
            .background(pillSurface.opacity(0.86))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        Color.white.opacity(
                            colorScheme == .dark ? 0.15 : 0.58
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Amount needed \(AppFormatters.currency(effectiveAmountNeeded)), already set aside \(AppFormatters.currency(currentSetAsideAmount)), remaining \(AppFormatters.currency(remainingAmount))"
        )
        .accessibilityHint("Double tap to show inline expense details")
    }

    private func contextMetric(
        title: String,
        amount: Double
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(AppFormatters.currency(amount))
                .font(.caption.weight(.bold))
                .foregroundColor(
                    CalderaVisualStyle.primaryText(colorScheme)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private var contextDivider: some View {
        Rectangle()
            .fill(
                CalderaVisualStyle.secondaryText(colorScheme)
                    .opacity(0.22)
            )
            .frame(width: 1, height: 26)
    }

    private var setAsideModePicker: some View {
        Picker(
            "Set Aside change",
            selection: $setAsideInput.changeMode
        ) {
            ForEach(UpcomingExpenseSetAsideChangeMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 228)
        .accessibilityLabel("Set Aside change")
        .accessibilityValue(setAsideInput.changeMode.heroTitle)
    }

    private var setAsideAmountHero: some View {
        VStack(spacing: AppSpacing.xSmall) {
            Text(setAsideInput.changeMode.heroTitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )
                .textCase(.uppercase)

            Button {
                focusedField = .setAsideAmount
            } label: {
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: AppSpacing.xSmall
                ) {
                    Text("$")
                        .font(
                            .system(
                                size: heroCurrencyFontSize,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            expenseAccentGradient.opacity(
                                setAsideInput.amountText.isEmpty
                                    ? 0.50
                                    : 0.78
                            )
                        )

                    Text(heroAmountDisplayText)
                        .font(
                            .system(
                                size: heroAmountFontSize,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(
                            setAsideInput.amountText.isEmpty
                                ? AnyShapeStyle(
                                    CalderaVisualStyle.secondaryText(
                                        colorScheme
                                    ).opacity(0.42)
                                )
                                : AnyShapeStyle(expenseAccentGradient)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .padding(.horizontal, AppSpacing.small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(setAsideInput.changeMode.heroTitle)
            .accessibilityValue("$\(heroAmountDisplayText)")
            .accessibilityHint("Double tap to enter dollars and cents")
            .background {
                TextField("", text: $setAsideInput.amountText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .setAsideAmount)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)
            }

            Text(
                "New total: \(AppFormatters.currency(projectedSetAsideAmount)) of \(AppFormatters.currency(effectiveAmountNeeded))"
            )
            .font(.caption.weight(.medium))
            .foregroundColor(
                CalderaVisualStyle.secondaryText(colorScheme)
            )
            .accessibilityLabel(
                "New Set Aside total \(AppFormatters.currency(projectedSetAsideAmount)) of \(AppFormatters.currency(effectiveAmountNeeded))"
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var scheduleContext: some View {
        Button(action: toggleInlineDetails) {
            HStack(spacing: AppSpacing.small) {
                Text("Expense details")
                    .foregroundColor(
                        CalderaVisualStyle.primaryText(colorScheme)
                    )

                Rectangle()
                    .fill(
                        CalderaVisualStyle.secondaryText(colorScheme)
                            .opacity(0.24)
                    )
                    .frame(width: 1, height: 16)

                Label(
                    detailsInput.dueDate.formatted(
                        .dateTime.month(.abbreviated).day()
                    ),
                    systemImage: "calendar"
                )

                Rectangle()
                    .fill(
                        CalderaVisualStyle.secondaryText(colorScheme)
                            .opacity(0.24)
                    )
                    .frame(width: 1, height: 16)

                Label(detailsInput.frequency.rawValue, systemImage: "repeat")

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(
                CalderaVisualStyle.secondaryText(colorScheme)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 38)
            .background(pillSurface.opacity(0.84))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        Color.white.opacity(
                            colorScheme == .dark ? 0.15 : 0.58
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Due \(detailsInput.dueDate.formatted(.dateTime.month(.wide).day().year())), repeats \(detailsInput.frequency.rawValue)"
        )
        .accessibilityHint("Double tap to show inline expense details")
    }

    private var inlineExpenseDetails: some View {
        VStack(spacing: AppSpacing.small) {
            inlinePanelHeader(
                title: "Expense details",
                systemImage: "pencil"
            ) {
                activeInlinePanel = .none
            }

            HStack(spacing: AppSpacing.small) {
                Image(systemName: "text.cursor")
                    .foregroundStyle(expenseAccentGradient)

                TextField("Expense name", text: $detailsInput.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .name)
                    .onSubmit {
                        focusedField = .expenseAmount
                    }
                    .accessibilityLabel("Expense name")
            }
            .inlineExpenseFieldSurface(
                colorScheme: colorScheme
            )

            HStack(spacing: AppSpacing.small) {
                Image(systemName: "dollarsign")
                    .foregroundStyle(expenseAccentGradient)

                TextField(
                    "Amount needed",
                    text: $detailsInput.amountText
                )
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .expenseAmount)
                .accessibilityLabel("Amount needed")

                Text(AppFormatters.currency(effectiveAmountNeeded))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
                    .lineLimit(1)
            }
            .inlineExpenseFieldSurface(
                colorScheme: colorScheme
            )

            HStack(spacing: AppSpacing.small) {
                Label("Due", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )

                DatePicker(
                    "Due date",
                    selection: $detailsInput.dueDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(expenseStyle.primary)
                .accessibilityLabel("Due date")

                Spacer(minLength: AppSpacing.xSmall)

                Menu {
                    ForEach(PlannerFrequency.allCases) { frequency in
                        Button(frequency.rawValue) {
                            detailsInput.frequency = frequency
                        }
                    }
                } label: {
                    Label(
                        detailsInput.frequency.rawValue,
                        systemImage: "repeat"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(expenseAccentGradient)
                    .lineLimit(1)
                }
                .accessibilityLabel(
                    "Repeat \(detailsInput.frequency.rawValue)"
                )
            }
            .inlineExpenseFieldSurface(
                colorScheme: colorScheme
            )

            accentColorSelector
        }
        .padding(AppSpacing.small)
        .frame(maxWidth: controlWidth)
        .background(pillSurface.opacity(0.88))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    Color.white.opacity(
                        colorScheme == .dark ? 0.18 : 0.62
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var inlineExpenseOptions: some View {
        VStack(spacing: AppSpacing.small) {
            inlinePanelHeader(
                title: "Expense options",
                systemImage: "ellipsis"
            ) {
                activeInlinePanel = .none
            }

            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                Label("Delete Expense", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityLabel("Delete expense")
        }
        .padding(AppSpacing.small)
        .frame(maxWidth: controlWidth)
        .background(pillSurface.opacity(0.88))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    Color.white.opacity(
                        colorScheme == .dark ? 0.18 : 0.62
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func inlinePanelHeader(
        title: String,
        systemImage: String,
        close: @escaping () -> Void
    ) -> some View {
        HStack(spacing: AppSpacing.small) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundColor(
                    CalderaVisualStyle.primaryText(colorScheme)
                )

            Spacer()

            Button(action: close) {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(title)")
        }
    }

    private var accentColorSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.small) {
                accentColorButton(nil)

                ForEach(PlannerEventColor.allCases) { option in
                    accentColorButton(option)
                }
            }
            .padding(.vertical, 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accent color")
    }

    private func accentColorButton(
        _ option: PlannerEventColor?
    ) -> some View {
        let isSelected = detailsInput.accentColorID == option?.rawValue
        let color = option?.color ?? AppColors.secondaryText
        let title = option?.label ?? "Default"

        return Button {
            detailsInput.accentColorID = option?.rawValue
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(option?.color ?? Color.clear)
                    .frame(width: 10, height: 10)
                    .overlay {
                        if option == nil {
                            Circle()
                                .stroke(
                                    AppColors.secondaryText.opacity(0.45),
                                    lineWidth: 1
                                )
                        }
                    }

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(isSelected ? color : AppColors.secondaryText)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, 9)
            .background {
                Capsule()
                    .fill(
                        isSelected
                            ? color.opacity(0.12)
                            : AppColors.secondaryText.opacity(0.10)
                    )
            }
            .overlay {
                Capsule()
                    .stroke(
                        isSelected
                            ? color.opacity(0.30)
                            : AppColors.glassSubtleHighlight,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var heroAmountDisplayText: String {
        NewUpcomingExpenseAmountPresentation.displayText(
            for: setAsideInput.amountText
        )
    }

    private var heroAmountFontSize: CGFloat {
        switch max(heroAmountDisplayText.count, 1) {
        case ...4:
            return 82
        case 5...7:
            return 68
        case 8...10:
            return 52
        default:
            return 38
        }
    }

    private var heroCurrencyFontSize: CGFloat {
        max(heroAmountFontSize * 0.54, 28)
    }

    private var helperMessage: String {
        if let detailsValidation = detailsInput.validationMessage,
           detailsInput.hasValidChange || !detailsInput.isValid {
            return detailsValidation
        }

        if let validationMessage = setAsideInput.validationMessage(
            currentSetAside: currentSetAsideAmount,
            amountNeeded: effectiveAmountNeeded
        ), !setAsideInput.amountText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            return validationMessage
        }

        if focusedField != nil {
            return "Hide the keyboard when you're ready to save."
        }

        if detailsInput.hasScheduleChange,
           setAsideInput.changeMode == .use,
           (setAsideInput.changeAmount ?? 0) > 0 {
            return "Save the new schedule before using Set Aside."
        }

        if shouldConfirmScheduleChange {
            return "You'll confirm before the schedule resets Set Aside and status tracking."
        }

        if detailsInput.hasValidChange {
            return "Swipe to save these expense details."
        }

        return "Set Aside is virtual planning. No money moves."
    }

    private var isSwipeAffordanceVisible: Bool {
        hasMeaningfulChange
            && hasValidUnifiedChange
            && focusedField == nil
            && !isShowingScheduleConfirmation
            && !isShowingDeleteConfirmation
            && !isSaving
            && savePhase == .idle
    }

    private func swipeAffordanceCenterY(
        layout: NewUpcomingExpenseCircleLayout,
        size: CGSize
    ) -> CGFloat {
        let circleTop = layout.center.y
            - (layout.innerDiameter / 2)

        return min(
            max(circleTop + 154, size.height - 145),
            size.height - 124
        )
    }

    private func toggleInlineDetails() {
        focusedField = nil
        withAnimation(.easeInOut(duration: 0.22)) {
            activeInlinePanel.toggle(.details)
        }
    }

    private func toggleInlineOptions() {
        focusedField = nil
        withAnimation(.easeInOut(duration: 0.22)) {
            activeInlinePanel.toggle(.options)
        }
    }

    private func handleSaveTriggered() {
        guard hasValidUnifiedChange else {
            resetSwipeProgress()
            return
        }

        if shouldConfirmScheduleChange {
            resetSwipeProgress()
            isShowingScheduleConfirmation = true
        } else {
            saveExpense(resetOccurrenceTracking: false)
        }
    }

    private func saveExpense(
        resetOccurrenceTracking: Bool
    ) {
        guard !isSaving,
              savePhase == .idle,
              hasValidUnifiedChange else {
            resetSwipeProgress()
            return
        }

        focusedField = nil
        saveErrorMessage = nil
        isSaving = true

        let persistenceResult =
            UpcomingExpenseUnifiedPersistenceCoordinator.persist(
                details: detailsInput,
                setAside: setAsideInput,
                event: event,
                forecast: forecast,
                allocation: currentAllocation,
                currentSetAside: currentSetAsideAmount,
                resetOccurrenceTracking: resetOccurrenceTracking,
                relatedAllocations: relatedAllocations,
                relatedStatuses: relatedOccurrenceStatuses,
                insertAllocation: modelContext.insert,
                deleteAllocation: modelContext.delete,
                deleteStatus: modelContext.delete,
                persistChanges: modelContext.save,
                rollback: modelContext.rollback
            )

        isSaving = false

        guard persistenceResult.startsSuccessFlow else {
            saveErrorMessage = persistenceResult.errorMessage
            resetSwipeProgress()
            return
        }

        didResetOccurrenceTracking = resetOccurrenceTracking
        beginSuccessfulSaveAnimation()
    }

    private func beginSuccessfulSaveAnimation() {
        savePhase = .completing
        saveCompletionTask?.cancel()

        withAnimation(.easeOut(duration: 0.22)) {
            foregroundOpacity = 0
            swipeProgress = 1
        }

        saveCompletionTask = Task {
            if reduceMotion {
                try? await Task.sleep(nanoseconds: 140_000_000)
            } else {
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(
                        .spring(
                            response: 0.62,
                            dampingFraction: 0.80
                        )
                    ) {
                        circleCompletionProgress = 1
                    }
                }

                try? await Task.sleep(nanoseconds: 520_000_000)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) {
                    savePhase = .success
                }

                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Expense updated"
                )
            }

            try? await Task.sleep(
                nanoseconds: reduceMotion
                    ? 560_000_000
                    : 720_000_000
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if didResetOccurrenceTracking {
                    onScheduleReset?()
                } else {
                    onSaved?(.expense, true)
                }

                dismiss()
            }
        }
    }

    private func deleteExpense() {
        saveErrorMessage = nil
        isSaving = true

        relatedAllocations.forEach(modelContext.delete)
        relatedOccurrenceStatuses.forEach(modelContext.delete)
        modelContext.delete(event)

        do {
            try modelContext.save()
            isSaving = false
            onDeleted?(.expense)
            dismiss()
        } catch {
            modelContext.rollback()
            isSaving = false
            saveErrorMessage =
                "This expense wasn't deleted. Please try again."
        }
    }

    private func resetSwipeProgress() {
        withAnimation(
            .spring(
                response: 0.34,
                dampingFraction: 0.82
            )
        ) {
            swipeProgress = 0
        }
    }
}

private extension View {

    func inlineExpenseFieldSurface(
        colorScheme: ColorScheme
    ) -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundColor(
                CalderaVisualStyle.primaryText(colorScheme)
            )
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 44)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.09)
                            : Color.white.opacity(0.66)
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        Color.white.opacity(
                            colorScheme == .dark ? 0.15 : 0.56
                        ),
                        lineWidth: 1
                    )
            }
    }

    func editUpcomingExpensePillControl(
        colorScheme: ColorScheme
    ) -> some View {
        font(.subheadline.weight(.bold))
            .foregroundColor(
                CalderaVisualStyle.primaryText(colorScheme)
            )
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, AppSpacing.small)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.10)
                            : Color.white.opacity(0.72)
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        Color.white.opacity(
                            colorScheme == .dark ? 0.20 : 0.68
                        ),
                        lineWidth: 1
                    )
            }
    }
}
