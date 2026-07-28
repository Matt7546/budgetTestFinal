import SwiftUI
import SwiftData
import UIKit

struct AddPlannerEventView: View {

    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    let editingEvent: PlannerEvent?
    private let draft: PlannerEventDraft?
    private let onSaved: ((PlannerEventType, Bool) -> Void)?
    private let onCreatedEventPersisted: ((UUID) -> Void)?
    private let onScheduleReset: (() -> Void)?
    private let onDeleted: ((PlannerEventType) -> Void)?

    init(
        editingEvent: PlannerEvent?,
        draft: PlannerEventDraft? = nil,
        onSaved: ((PlannerEventType, Bool) -> Void)? = nil,
        onCreatedEventPersisted: ((UUID) -> Void)? = nil,
        onScheduleReset: (() -> Void)? = nil,
        onDeleted: ((PlannerEventType) -> Void)? = nil
    ) {
        self.editingEvent = editingEvent
        self.draft = draft
        self.onSaved = onSaved
        self.onCreatedEventPersisted = onCreatedEventPersisted
        self.onScheduleReset = onScheduleReset
        self.onDeleted = onDeleted
        _editorState = State(
            initialValue: PlannerEventEditorState(
                editingEvent: editingEvent,
                draft: draft
            )
        )
    }

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @State private var editorState: PlannerEventEditorState
    @State private var showsDeleteConfirmation = false
    @State private var showsScheduleUpdateConfirmation = false
    @State private var saveErrorMessage: String?
    @State private var isSaving = false

    private var isEditing: Bool {
        editingEvent != nil
    }

    private var canSave: Bool {
        editorState.submission(
            editingEvent: editingEvent
        ) != nil && !isSaving
    }

    var body: some View {

        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                backgroundStyle: .editorModal(
                    editorState.type == .income
                        ? .general
                        : .upcomingExpense
                ),
                contentPadding: .all,
                contentSpacing: AppSpacing.regular
            ) {
                ModalHeaderView(
                    eyebrow: editorState.type == .income
                        ? "Income"
                        : "Upcoming Expenses",
                    title: editorTitle,
                    subtitle: editorSubtitle,
                    systemImage: eventStyle.icon,
                    color: eventStyle.primary
                )

                detailsCard

                scheduleCard

                if editorState.type == .expense {
                    optionsCard
                }

                if editorState.type == .income {
                    legacyIncomeNoticeCard
                }

                if hasRelatedOccurrenceRecords {
                    occurrenceRecordsWarningCard
                }

                preSaveSummaryCard

                if editingEvent != nil {
                    deleteCard
                }

                if !canSave && !isSaving {
                    Text(editorState.type == .income
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
                Text(scheduleResetConfirmationMessage)
            }
        }
    }

    private var detailsCard: some View {
        PlannerEditorCard(color: eventStyle.primary) {
            FormSectionHeader(
                title: editorState.type == .income
                    ? "What are you expecting?"
                    : "What are you planning?",
                systemImage: "square.and.pencil",
                color: eventStyle.primary
            )

            labeledTextField(
                title: editorState.type == .income
                    ? "Income name"
                    : "Expense name",
                placeholder: "Rent, Paycheck, Utilities",
                text: $editorState.name
            )

            labeledTextField(
                title: editorState.type == .income
                    ? "Amount expected"
                    : "Amount needed",
                placeholder: "0.00",
                text: $editorState.amountText,
                keyboardType: .decimalPad,
                subtitle: editorState.type == .income
                    ? "Money expected on this date."
                    : "How much you want visible before the due date.",
                systemImage: editorState.type == .income
                    ? CalderaCategoryStyle.style(for: .income).icon
                    : CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                colors: editorState.type == .income
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
                title: editorState.type == .income
                    ? "When is it expected?"
                    : "When is it needed?",
                systemImage: "calendar",
                color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
            )

            inlineDatePicker

            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                Text("Repeat")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                recurrenceChoices
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Repeat")
            }
        }
    }

    private var inlineDatePicker: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editorState.isDatePickerExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppSpacing.small) {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.xxSmall
                    ) {
                        Text(editorState.type == .income
                            ? "Expected date"
                            : "Due date")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.secondaryText)

                        Text(editorState.date.formatted(
                            .dateTime
                                .month(.wide)
                                .day()
                                .year()
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: AppSpacing.small)

                    Image(systemName: editorState.isDatePickerExpanded
                        ? "chevron.up"
                        : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(AppColors.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.88,
                strokeOpacity: 0.70,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: CalderaCategoryStyle.style(for: .upcomingExpense).primary
            )
            .accessibilityLabel(editorState.type == .income
                ? "Expected date"
                : "Due date")
            .accessibilityValue(editorState.date.formatted(
                .dateTime.month(.wide).day().year()
            ))
            .accessibilityHint(editorState.isDatePickerExpanded
                ? "Hides the calendar"
                : "Shows the calendar")

            if editorState.isDatePickerExpanded {
                DatePicker(
                    editorState.type == .income
                        ? "Choose expected date"
                        : "Choose due date",
                    selection: $editorState.date,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .accessibilityLabel(editorState.type == .income
                    ? "Choose expected date"
                    : "Choose due date")

                Button("Hide calendar") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        editorState.isDatePickerExpanded = false
                    }
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("Hide date calendar")
            }
        }
    }

    @ViewBuilder
    private var recurrenceChoices: some View {
        if PlannerEventRecurrenceControlPresentation.usesSingleColumn(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        ) {
            VStack(spacing: AppSpacing.small) {
                ForEach(PlannerFrequency.allCases) { option in
                    frequencyButton(option)
                }
            }
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: AppSpacing.small
            ) {
                ForEach(PlannerFrequency.allCases) { option in
                    frequencyButton(option)
                }
            }
        }
    }

    private var preSaveSummaryCard: some View {
        let summary = editorState.preSaveSummary
        let formattedAmount: String

        if let amount = summary.amount {
            formattedAmount = AppFormatters.currency(amount)
        } else {
            formattedAmount = "Not set"
        }

        return PlannerEditorCard(color: eventStyle.primary) {
            FormSectionHeader(
                title: "Review before saving",
                systemImage: "checklist",
                color: eventStyle.primary
            )

            preSaveSummaryRow(
                title: "Amount",
                value: formattedAmount
            )
            preSaveSummaryRow(
                title: editorState.type == .income
                    ? "Expected date"
                    : "Due date",
                value: summary.date.formatted(
                    .dateTime.month(.wide).day().year()
                )
            )
            preSaveSummaryRow(
                title: "Schedule",
                value: summary.frequency.rawValue
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Amount, \(formattedAmount). " +
            "\(editorState.type == .income ? "Expected date" : "Due date"), " +
            "\(summary.date.formatted(.dateTime.month(.wide).day().year())). " +
            "Schedule, \(summary.frequency.rawValue)."
        )
    }

    private func preSaveSummaryRow(
        title: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deleteCard: some View {
        PlannerEditorCard(color: CalderaCategoryStyle.style(for: .shortfall).primary) {
            FormSectionHeader(
                title: editorState.type == .income
                    ? "Remove Income"
                    : "Remove Expense",
                systemImage: "trash.fill",
                color: CalderaCategoryStyle.style(for: .shortfall).primary
            )

            Text(editorState.type == .income
                ? "Delete this income from Plan Ahead."
                : "Delete this upcoming expense from Plan Ahead.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)

            DestructiveButton(
                editorState.type == .income
                    ? "Delete Income"
                    : "Delete Expense",
                systemImage: "trash",
                cornerRadius: AppRadii.button
            ) {
                showsDeleteConfirmation = true
            }
            .accessibilityLabel(editorState.type == .income
                ? "Delete income"
                : "Delete expense")
            .confirmationDialog(
                editorState.type == .income
                    ? "Delete income?"
                    : "Delete upcoming expense?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    editorState.type == .income
                        ? "Delete Income"
                        : "Delete Expense",
                    role: .destructive
                ) {
                    deleteEvent()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text(editorState.type == .income
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

                Text(scheduleResetWarningMessage)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var eventStyle: CalderaCategoryStyle {
        switch editorState.type {
        case .expense:
            return CalderaCategoryStyle.style(for: .upcomingExpense)

        case .income:
            return CalderaCategoryStyle.style(for: .income)
        }
    }

    private var editorTitle: String {
        switch editorState.type {
        case .expense:
            return isEditing ? "Edit Upcoming Expense" : "New Upcoming Expense"

        case .income:
            return isEditing ? "Edit Income" : "New Income"
        }
    }

    private var editorSubtitle: String {
        switch editorState.type {
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
            isSelected: editorState.frequency == option
        ) {
            editorState.frequency = option
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
        let isSelected = editorState.accentColorID == option?.rawValue
        let color = option?.color ?? AppColors.secondaryText
        let title = option?.label ?? "Default"

        return Button {
            editorState.accentColorID = option?.rawValue
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
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundColor(isSelected ? color : AppColors.secondaryText)
            .frame(
                maxWidth: .infinity,
                minHeight: 52,
                alignment: .leading
            )
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.xSmall)
            .contentShape(Rectangle())
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
        .accessibilityValue(
            PlannerEventRecurrenceControlPresentation
                .accessibilityValue(isSelected: isSelected)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        saveErrorMessage = nil

        guard let submission = editorState.submission(
            editingEvent: editingEvent
        ) else {
            return
        }

        let wasEditing = editingEvent != nil
        if resetOccurrenceTracking,
           let editingEvent {
            deleteRelatedOccurrenceRecords(
                for: editingEvent
            )
        }

        let savedEvent = PlannerEventSaveMutation.apply(
            submission,
            editingEvent: editingEvent,
            insert: modelContext.insert
        )
        let createdEvent = wasEditing ? nil : savedEvent
        isSaving = true

        do {
            if let createdEvent,
               let onCreatedEventPersisted {
                try RecurringExpenseRecommendationSaveCoordinator
                    .persistThenRecord(
                        eventID: createdEvent.id,
                        persist: {
                            try modelContext.save()
                        },
                        onPersisted: onCreatedEventPersisted
                    )
            } else {
                try modelContext.save()
            }

            isSaving = false
        } catch {
            modelContext.rollback()
            isSaving = false
            saveErrorMessage =
                "Couldn’t save this Upcoming Expense. Try again."
            return
        }

        if resetOccurrenceTracking,
           let onScheduleReset {
            onScheduleReset()
        } else {
            onSaved?(submission.type, wasEditing)
        }

        dismiss()
    }

    private func deleteEvent() {
        guard let editingEvent else {
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

        return PlannerEventScheduleChangePolicy.hasScheduleChange(
            originalDate: editingEvent.date,
            originalFrequency: editingEvent.frequency,
            proposedDate: editorState.date,
            proposedFrequency: editorState.frequency
        )
    }

    private var shouldConfirmScheduleChange: Bool {
        guard let editingEvent,
              editingEvent.type == .expense else {
            return false
        }

        return PlannerEventScheduleChangePolicy.requiresOccurrenceReset(
            hasRelatedRecords: hasRelatedOccurrenceRecords,
            hasScheduleChange: hasScheduleChange
        )
    }

    private var activeRelatedSetAsideAmount: Double {
        let resolvedOccurrenceIDs = ExpenseOccurrenceLifecycleResolver
            .resolvedOccurrenceIDs(from: relatedOccurrenceStatuses)

        return relatedAllocations
            .filter {
                !resolvedOccurrenceIDs.contains($0.occurrenceID)
            }
            .reduce(0) {
                $0 + max($1.allocatedAmount, 0)
            }
    }

    private var scheduleResetWarningMessage: String {
        if activeRelatedSetAsideAmount > 0.005 {
            return "Changing the due date or schedule will ask before removing \(AppFormatters.currency(activeRelatedSetAsideAmount)) currently counted as Set Aside for this expense."
        }

        return "Changing the due date or schedule will ask before clearing tracked occurrences for this expense."
    }

    private var scheduleResetConfirmationMessage: String {
        let historyImpact = relatedOccurrenceStatuses.isEmpty
            ? ""
            : " Paid or skipped tracking will also be cleared."

        if activeRelatedSetAsideAmount > 0.005 {
            return "Changing the due date or schedule changes occurrence tracking. \(AppFormatters.currency(activeRelatedSetAsideAmount)) currently counted as Set Aside will no longer be attached to this expense.\(historyImpact) No money moves. You can set it aside again after saving."
        }

        return "Changing the due date or schedule will clear tracked occurrences for this expense.\(historyImpact) No money moves."
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
