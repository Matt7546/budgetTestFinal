import SwiftUI
import SwiftData
import UIKit

struct AddPlannerEventView: View {

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var plaid: PlaidService

    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.dismiss)
    private var dismiss

    let editingEvent: PlannerEvent?
    private let draft: PlannerEventDraft?
    private let onSaved: ((PlannerEventType, Bool) -> Void)?
    private let recommendationAcceptance: RecurringExpenseRecommendationAcceptance?
    private let recommendationHistoryRequired: Bool
    private let onRecommendationHistoryPending: (() -> Void)?
    private let onScheduleReset: (() -> Void)?
    private let onDeleted: ((PlannerEventType) -> Void)?

    init(
        editingEvent: PlannerEvent?,
        draft: PlannerEventDraft? = nil,
        onSaved: ((PlannerEventType, Bool) -> Void)? = nil,
        recommendationAcceptance: RecurringExpenseRecommendationAcceptance? = nil,
        recommendationHistoryRequired: Bool = false,
        onRecommendationHistoryPending: (() -> Void)? = nil,
        onScheduleReset: (() -> Void)? = nil,
        onDeleted: ((PlannerEventType) -> Void)? = nil
    ) {
        self.editingEvent = editingEvent
        self.draft = draft
        self.onSaved = onSaved
        self.recommendationAcceptance = recommendationAcceptance
        self.recommendationHistoryRequired = recommendationHistoryRequired
        self.onRecommendationHistoryPending = onRecommendationHistoryPending
        self.onScheduleReset = onScheduleReset
        self.onDeleted = onDeleted
    }

    @Query
    private var allAllocations: [EventAllocation]

    @Query
    private var allOccurrenceStatuses: [ExpenseOccurrenceStatus]

    @State private var name = ""
    @State private var amount = ""
    @State private var showsDeleteConfirmation = false
    @State private var showsScheduleUpdateConfirmation = false
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @State private var completedIncomeAction = false
    @State private var incomeEditorEventID: UUID?
    @State private var incomeEditorOwnerScopeID: String?
    @State private var incomeEditorGeneration: UInt64?

    @State private var date = Date()

    @State private var type: PlannerEventType = .expense

    @State private var frequency: PlannerFrequency = .monthly

    @State private var accentColorID: String?

    private var planningOwnerScopeID: String {
        editingEvent?.ownerScopeID ?? PlanningOwnerScope.current(
            authenticatedUserID: auth.user?.id
        )
    }

    private var allocations: [EventAllocation] {
        allAllocations.owned(by: planningOwnerScopeID)
    }

    private var occurrenceStatuses: [ExpenseOccurrenceStatus] {
        allOccurrenceStatuses.owned(by: planningOwnerScopeID)
    }

    private var planningAvailability: PlanningSnapshotAvailability {
        var failures = Set<PlanningPersistenceReadDomain>()
        if _allAllocations.fetchError != nil { failures.insert(.eventAllocations) }
        if _allOccurrenceStatuses.fetchError != nil {
            failures.insert(.occurrenceStatuses)
        }
        return PlanningSnapshotAvailability.resolving(
            base: plaid.planningSnapshotAvailability(
                authenticatedUserID: auth.user?.id
            ),
            failedRequiredReads: failures,
            hasBillRecordConflict: BillOccurrenceRecordIntegrity.hasConflict(
                allocations: allocations, statuses: occurrenceStatuses
            )
        )
    }

    private var isEditing: Bool {
        editingEvent != nil
    }

    private var canSave: Bool {

        !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        &&
        MoneyAmountParser.parse(amount) != nil
        &&
        MoneyAmountParser.parse(amount) ?? 0 > 0
        &&
        planningAvailability == .available
        &&
        !isSaving
    }

    var body: some View {

        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                backgroundStyle: .editorModal(
                    type == .income ? .general : .upcomingExpense
                ),
                contentPadding: .all,
                contentSpacing: AppSpacing.regular
            ) {
                ModalHeaderView(
                    eyebrow: type == .income ? "Income" : "Bills",
                    title: editorTitle,
                    subtitle: editorSubtitle,
                    systemImage: eventStyle.icon,
                    color: eventStyle.primary
                )

                detailsCard

                scheduleCard

                if type == .expense {
                    optionsCard
                }

                if type == .income {
                    legacyIncomeNoticeCard
                }

                if hasRelatedOccurrenceRecords {
                    occurrenceRecordsWarningCard
                }

                if editingEvent != nil {
                    deleteCard
                }

                if !canSave && !isSaving {
                    Text(type == .income
                        ? "Add a name and amount to save."
                        : "Add a name, amount, and due date to save.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if let saveErrorMessage {
                    Text(saveErrorMessage)
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
            }
            .keyboardDismissToolbar()
            .navigationTitle(editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {

                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel")
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {

                    Button("Save") {
                        handleSaveTapped()
                    }
                    .disabled(!canSave)
                    .accessibilityLabel("Save")
                }
            }
            .confirmationDialog(
                "Update schedule?",
                isPresented: $showsScheduleUpdateConfirmation,
                titleVisibility: .visible
            ) {
                Button("Update Expense") {
                    saveEvent(resetOccurrenceTracking: true)
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Changing the date, repeat pattern, or type may reset set-aside tracking for this expense. You can set money aside again after saving.")
            }
            .onAppear {
                loadInitialValues()
            }
        }
    }

    private var detailsCard: some View {
        PlannerEditorCard(color: eventStyle.primary) {
            FormSectionHeader(
                title: type == .income ? "What are you expecting?" : "What are you planning?",
                systemImage: "square.and.pencil",
                color: eventStyle.primary
            )

            labeledTextField(
                title: type == .income ? "Income name" : "Expense name",
                placeholder: "Rent, Paycheck, Utilities",
                text: $name
            )

            labeledTextField(
                title: type == .income ? "Amount expected" : "Amount needed",
                placeholder: "0.00",
                text: $amount,
                keyboardType: .decimalPad,
                subtitle: type == .income
                    ? "Money expected on this date."
                    : "How much you want visible before the due date.",
                systemImage: type == .income
                    ? CalderaCategoryStyle.style(for: .income).icon
                    : CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                colors: type == .income
                    ? CalderaCategoryStyle.style(for: .income).gradient
                    : CalderaCategoryStyle.style(for: .upcomingExpense).gradient
            )
        }
    }

    private var optionsCard: some View {
        PlannerEditorCard(color: eventStyle.primary) {
            FormSectionHeader(
                title: "Appearance",
                systemImage: "paintpalette.fill",
                color: eventStyle.primary
            )

            eventColorSelector
        }
    }

    private var legacyIncomeNoticeCard: some View {
        PlannerEditorCard(color: CalderaCategoryStyle.style(for: .income).primary) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                IconBadge(
                    systemImage: "info.circle.fill",
                    color: CalderaCategoryStyle.style(for: .income).primary,
                    size: 34,
                    iconSize: 14
                )

                Text("Income planning isn't currently supported. This existing entry is available to review, update, or delete.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scheduleCard: some View {
        PlannerEditorCard(color: CalderaCategoryStyle.style(for: .upcomingExpense).primary) {
            FormSectionHeader(
                title: type == .income ? "When is it expected?" : "When is it needed?",
                systemImage: "calendar",
                color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
            )

            DatePicker(
                type == .income ? "Expected date" : "Due date",
                selection: $date,
                displayedComponents: .date
            )
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppColors.primaryText)
            .padding()
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.88,
                strokeOpacity: 0.70,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: CalderaCategoryStyle.style(for: .upcomingExpense).primary
            )
            .accessibilityLabel(type == .income ? "Date" : "Due date")

            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                Text("Repeat")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: AppSpacing.small
                ) {
                    ForEach(
                        PlannerFrequency.allCases
                    ) { option in
                        frequencyButton(option)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Repeat")
            }
        }
    }

    private var deleteCard: some View {
        PlannerEditorCard(color: CalderaCategoryStyle.style(for: .shortfall).primary) {
            FormSectionHeader(
                title: type == .income ? "Remove Income" : "Remove Expense",
                systemImage: "trash.fill",
                color: CalderaCategoryStyle.style(for: .shortfall).primary
            )

            Text(type == .income ? "Delete this income from Plan Ahead." : "Delete this Bill from Plan Ahead.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)

            DestructiveButton(
                type == .income ? "Delete Income" : "Delete Expense",
                systemImage: "trash",
                cornerRadius: AppRadii.button
            ) {
                showsDeleteConfirmation = true
            }
            .accessibilityLabel(type == .income ? "Delete income" : "Delete expense")
            .confirmationDialog(
                type == .income ? "Delete income?" : "Delete Bill?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    type == .income ? "Delete Income" : "Delete Expense",
                    role: .destructive
                ) {
                    deleteEvent()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text(type == .income
                    ? "This removes the income from Plan Ahead."
                    : "This removes the expense and its set-aside plan.")
            }
        }
    }

    private var occurrenceRecordsWarningCard: some View {
        PlannerEditorCard(color: CalderaCategoryStyle.style(for: .needsMoney).primary) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                IconBadge(
                    systemImage: "exclamationmark.triangle.fill",
                    color: CalderaCategoryStyle.style(for: .needsMoney).primary,
                    size: 34,
                    iconSize: 14
                )

                Text("Changing the date or repeat pattern will ask before resetting set-aside tracking for this expense.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var eventStyle: CalderaCategoryStyle {
        switch type {
        case .expense:
            return CalderaCategoryStyle.style(for: .upcomingExpense)

        case .income:
            return CalderaCategoryStyle.style(for: .income)
        }
    }

    private var editorTitle: String {
        switch type {
        case .expense:
            return isEditing ? "Edit Bill" : "New Bill"

        case .income:
            return isEditing ? "Edit Income" : "New Income"
        }
    }

    private var editorSubtitle: String {
        switch type {
        case .expense:
            return "Plan for something before it arrives."

        case .income:
            return "Income planning isn't currently supported. You can review, update, or delete this existing entry."
        }
    }

    @ViewBuilder
    private func labeledTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        subtitle: String? = nil,
        systemImage: String = "text.cursor",
        colors: [Color] = CalderaVisualStyle.dashboardProgressGradient
    ) -> some View {
        if keyboardType == .decimalPad || keyboardType == .numberPad {
            AmountEntryField(
                title: title,
                subtitle: subtitle,
                placeholder: placeholder,
                text: text,
                systemImage: systemImage,
                colors: colors,
                keyboardType: keyboardType,
                accessibilityLabel: title
            )
        } else {
            CalderaTextEntryField(
                title: title,
                subtitle: subtitle,
                placeholder: placeholder,
                text: text,
                keyboardType: keyboardType,
                color: colors.first ?? AppColors.accent,
                accessibilityLabel: title
            )
        }
    }

    private func frequencyButton(
        _ option: PlannerFrequency
    ) -> some View {
        optionButton(
            title: option.rawValue,
            systemImage: "repeat",
            color: CalderaCategoryStyle.style(for: .upcomingExpense).primary,
            isSelected: frequency == option
        ) {
            frequency = option
        }
    }

    private var eventColorSelector: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            Text("Accent color")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.small) {
                    eventColorButton(nil)

                    ForEach(PlannerEventColor.allCases) { option in
                        eventColorButton(option)
                    }
                }
                .padding(.vertical, 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Accent color")
        }
    }

    private func eventColorButton(
        _ option: PlannerEventColor?
    ) -> some View {
        let isSelected = accentColorID == option?.rawValue
        let color = option?.color ?? AppColors.secondaryText
        let title = option?.label ?? "Default"

        return Button {
            accentColorID = option?.rawValue
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
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(
                        isSelected
                        ? color.opacity(0.12)
                        : AppColors.secondaryText.opacity(0.10)
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected
                        ? color.opacity(0.30)
                        : AppColors.glassSubtleHighlight,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func optionButton(
        title: String,
        systemImage: String,
        color: Color,
        isSelected: Bool,
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
            .foregroundColor(isSelected ? color : AppColors.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(
                        isSelected
                        ? color.opacity(0.12)
                        : AppColors.secondaryText.opacity(0.10)
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected
                        ? color.opacity(0.30)
                        : AppColors.glassSubtleHighlight,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func loadInitialValues() {
        if let event = editingEvent {
            if event.type == .income,
               incomeEditorOwnerScopeID == nil {
                incomeEditorEventID = event.id
                incomeEditorOwnerScopeID = PlanningOwnerScope.current(
                    authenticatedUserID: auth.user?.id
                )
                incomeEditorGeneration =
                    plaid.planningMutationAuthorizationGeneration
            }
            name = event.name
            amount = String(event.amount)
            date = event.date
            type = event.type
            frequency = event.frequency
            accentColorID = event.accentColorID
            return
        }

        guard let draft else {
            return
        }

        name = draft.name
        amount = String(format: "%.2f", draft.amount)
        date = draft.date
        type = .expense
        frequency = draft.frequency
        accentColorID = draft.accentColorID
    }

    private func handleSaveTapped() {
        if shouldConfirmScheduleChange {
            showsScheduleUpdateConfirmation = true
        } else {
            saveEvent()
        }
    }

    private func saveEvent(
        resetOccurrenceTracking: Bool = false
    ) {
        guard !isSaving else { return }
        saveErrorMessage = nil

        guard planningAvailability == .available,
              editingEvent == nil || PlanningMutationAuthorization.isAllowed(
                  recordOwnerScopeID: editingEvent?.ownerScopeID,
                  currentOwnerScopeID: PlanningOwnerScope.current(
                      authenticatedUserID: auth.user?.id
                  ),
                  availability: planningAvailability
              ) else {
            saveErrorMessage = "Reload this account’s saved plan before making changes."
            return
        }

        guard !recommendationHistoryRequired || recommendationAcceptance != nil else {
            saveErrorMessage = "This recommendation is no longer available. Reopen Plan Ahead before saving it."
            return
        }

        guard
            let amountValue =
                MoneyAmountParser.parse(amount)
        else {
            return
        }

        let savedType = PlannerEventEditingPolicy.typeForSave(
            editingEvent: editingEvent
        )
        let savedAccentColorID = savedType == .expense
            ? accentColorID
            : editingEvent?.accentColorID
        let wasEditing = editingEvent != nil
        var createdEvent: PlannerEvent?

        if let editingEvent,
           savedType == .income {
            isSaving = true
            let result = incomePersistenceCoordinator.edit(
                event: editingEvent,
                name: name,
                amount: amountValue,
                date: date,
                frequency: frequency,
                completed: &completedIncomeAction,
                persistChanges: modelContext.save,
                rollback: modelContext.rollback
            ) {
                onSaved?(.income, true)
                dismiss()
            }
            isSaving = false
            switch result {
            case .saved:
                break
            case .rejected:
                saveErrorMessage =
                    "Reload this account’s saved income before making changes."
            case .failed:
                saveErrorMessage = "This income wasn't saved. Please try again."
            }
            return
        }

        if let editingEvent {

            if resetOccurrenceTracking {
                deleteRelatedOccurrenceRecords(
                    for: editingEvent
                )
            }

            editingEvent.name = name
            editingEvent.amount = amountValue
            editingEvent.date = date
            editingEvent.frequency = frequency
            editingEvent.accentColorID = savedAccentColorID

        } else {

            let newEvent =
                PlannerEvent(
                    ownerScopeID: PlanningOwnerScope.current(
                        authenticatedUserID: auth.user?.id
                    ),
                    name: name,
                    amount: amountValue,
                    date: date,
                    frequency: frequency,
                    type: savedType,
                    accentColorID: savedAccentColorID
                )

            if recommendationAcceptance == nil {
                modelContext.insert(newEvent)
            }
            createdEvent = newEvent
        }

        if let createdEvent,
           let recommendationAcceptance {
            isSaving = true
            var persistenceAttempted = false

            do {
                let outcome = try RecurringExpenseRecommendationSaveCoordinator
                    .persistThenRecord(
                        eventID: createdEvent.id,
                        acceptance: recommendationAcceptance,
                        isOwnerCurrent: {
                            auth.isSignedIn &&
                                auth.user?.id == recommendationAcceptance.ownerUserID
                        },
                        persist: {
                            persistenceAttempted = true
                            modelContext.insert(createdEvent)
                            try modelContext.save()
                        }
                    )
                isSaving = false
                if outcome == .billSavedHistoryPending {
                    onRecommendationHistoryPending?()
                    dismiss()
                    return
                }
            } catch {
                if persistenceAttempted {
                    modelContext.rollback()
                }
                isSaving = false
                saveErrorMessage =
                    "Couldn’t confirm this Bill. Check Plan Ahead before trying again."
                return
            }
        }

        if resetOccurrenceTracking,
           let onScheduleReset {
            onScheduleReset()
        } else {
            onSaved?(savedType, wasEditing)
        }

        dismiss()
    }

    private func deleteEvent() {
        guard !isSaving else { return }
        guard let editingEvent else { return }

        if editingEvent.type == .income {
            saveErrorMessage = nil
            isSaving = true
            let result = incomePersistenceCoordinator.delete(
                event: editingEvent,
                completed: &completedIncomeAction,
                persistChanges: modelContext.save,
                rollback: modelContext.rollback
            ) {
                onDeleted?(.income)
                dismiss()
            }
            isSaving = false
            switch result {
            case .saved:
                break
            case .rejected:
                saveErrorMessage =
                    "Reload this account’s saved income before deleting it."
            case .failed:
                saveErrorMessage = "This income wasn't deleted. Please try again."
            }
            return
        }

        guard PlanningMutationAuthorization.isAllowed(
                  recordOwnerScopeID: editingEvent.ownerScopeID,
                  currentOwnerScopeID: PlanningOwnerScope.current(
                      authenticatedUserID: auth.user?.id
                  ),
                  availability: planningAvailability
              ) else {
            return
        }

        let deletedType = editingEvent.type

        deleteRelatedOccurrenceRecords(
            for: editingEvent
        )

        modelContext.delete(
            editingEvent
        )

        onDeleted?(deletedType)

        dismiss()
    }

    private var incomePersistenceCoordinator:
        LegacyIncomeEventPersistenceCoordinator {
        LegacyIncomeEventPersistenceCoordinator(
            modelContext: modelContext,
            preparedEventID: incomeEditorEventID,
            preparedOwnerScopeID: incomeEditorOwnerScopeID,
            currentOwnerScopeID: PlanningOwnerScope.current(
                authenticatedUserID: auth.user?.id
            ),
            preparedGeneration: incomeEditorGeneration,
            currentGeneration: plaid.planningMutationAuthorizationGeneration,
            availability: planningAvailability
        )
    }

    private var relatedAllocations: [EventAllocation] {
        guard let editingEvent else {
            return []
        }

        return allocations.filter {
            $0.sourceEventID == editingEvent.id
        }
    }

    private var relatedOccurrenceStatuses: [ExpenseOccurrenceStatus] {
        guard let editingEvent else {
            return []
        }

        return occurrenceStatuses.filter {
            $0.sourceEventID == editingEvent.id
        }
    }

    private var hasRelatedOccurrenceRecords: Bool {
        !relatedAllocations.isEmpty ||
        !relatedOccurrenceStatuses.isEmpty
    }

    private var hasScheduleChange: Bool {
        guard let editingEvent else {
            return false
        }

        let dateChanged = !Calendar.current.isDate(
            date,
            inSameDayAs: editingEvent.date
        )

        return dateChanged ||
            frequency != editingEvent.frequency
    }

    private var shouldConfirmScheduleChange: Bool {
        guard let editingEvent,
              editingEvent.type == .expense else {
            return false
        }

        return hasRelatedOccurrenceRecords &&
            hasScheduleChange
    }

    private func deleteRelatedOccurrenceRecords(
        for event: PlannerEvent
    ) {
        allocations
            .filter {
                $0.sourceEventID == event.id
            }
            .forEach {
                modelContext.delete($0)
            }

        occurrenceStatuses
            .filter {
                $0.sourceEventID == event.id
            }
            .forEach {
                modelContext.delete($0)
            }
    }
}

enum LegacyIncomeEventPersistenceResult: Equatable {
    case saved
    case rejected
    case failed
}

/// The legacy Income sheet calls this at the final, synchronous mutation
/// boundary. The stored row is read again before an edit or deletion; a view's
/// retained model reference is never enough to authorize either action.
@MainActor
struct LegacyIncomeEventPersistenceCoordinator {
    let modelContext: ModelContext
    let preparedEventID: UUID?
    let preparedOwnerScopeID: String?
    let currentOwnerScopeID: String
    let preparedGeneration: UInt64?
    let currentGeneration: UInt64
    let availability: PlanningSnapshotAvailability
    var readEvents: ((ModelContext, UUID) throws -> [PlannerEvent])? = nil

    private func currentIncome(
        for event: PlannerEvent,
        completed: Bool
    ) throws -> PlannerEvent? {
        guard !completed,
              preparedEventID == event.id,
              let preparedOwnerScopeID,
              preparedOwnerScopeID == currentOwnerScopeID,
              let preparedGeneration,
              preparedGeneration == currentGeneration,
              PlanningMutationAuthorization.isAllowed(
                  recordOwnerScopeID: event.ownerScopeID,
                  currentOwnerScopeID: currentOwnerScopeID,
                  availability: availability
              ),
              event.type == .income else {
            return nil
        }

        let eventID = event.id
        let rows: [PlannerEvent]
        if let readEvents {
            rows = try readEvents(modelContext, eventID)
        } else {
            rows = try modelContext.fetch(
                FetchDescriptor<PlannerEvent>(
                    predicate: #Predicate { $0.id == eventID }
                )
            )
        }
        guard rows.count == 1,
              let row = rows.first,
              row.id == eventID,
              row.persistentModelID == event.persistentModelID,
              row.ownerScopeID == currentOwnerScopeID,
              row.type == .income else {
            return nil
        }
        return row
    }

    func edit(
        event: PlannerEvent,
        name: String,
        amount: Double,
        date: Date,
        frequency: PlannerFrequency,
        completed: inout Bool,
        persistChanges: () throws -> Void,
        rollback: () -> Void,
        onSuccess: () -> Void
    ) -> LegacyIncomeEventPersistenceResult {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              amount.isFinite,
              amount > 0 else {
            return .rejected
        }

        let row: PlannerEvent
        do {
            guard let current = try currentIncome(
                for: event, completed: completed
            ) else { return .rejected }
            row = current
        } catch {
            return .rejected
        }

        let originalName = row.name
        let originalAmount = row.amount
        let originalDate = row.date
        let originalFrequency = row.frequency
        row.name = name
        row.amount = amount
        row.date = date
        row.frequency = frequency

        do {
            try persistChanges()
        } catch {
            row.name = originalName
            row.amount = originalAmount
            row.date = originalDate
            row.frequency = originalFrequency
            rollback()
            return .failed
        }

        completed = true
        onSuccess()
        return .saved
    }

    func delete(
        event: PlannerEvent,
        completed: inout Bool,
        persistChanges: () throws -> Void,
        rollback: () -> Void,
        onSuccess: () -> Void
    ) -> LegacyIncomeEventPersistenceResult {
        let row: PlannerEvent
        let allocations: [EventAllocation]
        let statuses: [ExpenseOccurrenceStatus]
        do {
            guard let current = try currentIncome(
                for: event, completed: completed
            ) else { return .rejected }
            row = current
            let eventID = row.id
            allocations = try modelContext.fetch(
                FetchDescriptor<EventAllocation>(
                    predicate: #Predicate { $0.sourceEventID == eventID }
                )
            ).filter { $0.ownerScopeID == currentOwnerScopeID }
            statuses = try modelContext.fetch(
                FetchDescriptor<ExpenseOccurrenceStatus>(
                    predicate: #Predicate { $0.sourceEventID == eventID }
                )
            ).filter { $0.ownerScopeID == currentOwnerScopeID }
        } catch {
            return .rejected
        }

        // Preserve the F6 rule: ambiguous physical occurrence rows require
        // review and cannot be chosen or deleted by this legacy editor.
        guard !BillOccurrenceRecordIntegrity.hasConflict(
            allocations: allocations, statuses: statuses
        ), !BillOccurrenceRecordIntegrity.hasDuplicateRows(
            allocations: allocations, statuses: statuses
        ) else { return .rejected }

        allocations.forEach(modelContext.delete)
        statuses.forEach(modelContext.delete)
        modelContext.delete(row)

        do {
            try persistChanges()
        } catch {
            rollback()
            return .failed
        }

        completed = true
        onSuccess()
        return .saved
    }
}

private struct PlannerEditorCard<Content: View>: View {

    let color: Color
    let content: Content

    init(
        color: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.color = color
        self.content = content()
    }

    var body: some View {
        CalderaEditorFormCard(color: color) {
            content
        }
    }
}
