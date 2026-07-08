import SwiftUI
import SwiftData
import UIKit

struct AddPlannerEventView: View {

    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.dismiss)
    private var dismiss

    let editingEvent: PlannerEvent?
    private let onSaved: ((PlannerEventType, Bool) -> Void)?
    private let onScheduleReset: (() -> Void)?
    private let onDeleted: ((PlannerEventType) -> Void)?

    init(
        editingEvent: PlannerEvent?,
        onSaved: ((PlannerEventType, Bool) -> Void)? = nil,
        onScheduleReset: (() -> Void)? = nil,
        onDeleted: ((PlannerEventType) -> Void)? = nil
    ) {
        self.editingEvent = editingEvent
        self.onSaved = onSaved
        self.onScheduleReset = onScheduleReset
        self.onDeleted = onDeleted
    }

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @State private var name = ""
    @State private var amount = ""
    @State private var showsDeleteConfirmation = false
    @State private var showsScheduleUpdateConfirmation = false

    @State private var date = Date()

    @State private var type: PlannerEventType = .expense

    @State private var frequency: PlannerFrequency = .monthly

    @State private var accentColorID: String?

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
                    eyebrow: type == .income ? "Income" : "Upcoming Expenses",
                    title: editorTitle,
                    subtitle: editorSubtitle,
                    systemImage: eventStyle.icon,
                    color: eventStyle.primary
                )

                detailsCard

                scheduleCard

                optionsCard

                if hasRelatedOccurrenceRecords {
                    occurrenceRecordsWarningCard
                }

                if editingEvent != nil {
                    deleteCard
                }

                if !canSave {
                    Text(type == .income
                        ? "Add a name and amount to save."
                        : "Add a name, amount, and due date to save.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
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
                loadEditingEvent()
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
                title: "Options",
                systemImage: "slider.horizontal.3",
                color: eventStyle.primary
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                Text("Type")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                HStack(spacing: AppSpacing.small) {
                    eventTypeButton(.expense)
                    eventTypeButton(.income)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Type")
            }

            if type == .expense {
                eventColorSelector
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

            Text(type == .income ? "Delete this income from your timeline." : "Delete this upcoming expense from your timeline.")
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
                type == .income ? "Delete income?" : "Delete upcoming expense?",
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
                    ? "This removes the income from your timeline."
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

                Text("Changing the date, repeat pattern, or type will ask before resetting set-aside tracking for this expense.")
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
            return isEditing ? "Edit Upcoming Expense" : "New Upcoming Expense"

        case .income:
            return isEditing ? "Edit Income" : "New Income"
        }
    }

    private var editorSubtitle: String {
        switch type {
        case .expense:
            return "Plan for something before it arrives."

        case .income:
            return "Add income to your timeline."
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

    private func eventTypeButton(
        _ option: PlannerEventType
    ) -> some View {
        optionButton(
            title: option.rawValue,
            systemImage: option == .income
                ? "arrow.down.circle.fill"
                : "minus.circle.fill",
            color: option == .income
                ? CalderaCategoryStyle.style(for: .income).primary
                : CalderaCategoryStyle.style(for: .upcomingExpense).primary,
            isSelected: type == option
        ) {
            type = option
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

    private func loadEditingEvent() {
        guard let event = editingEvent else {
            return
        }

        name = event.name
        amount = String(event.amount)
        date = event.date
        type = event.type
        frequency = event.frequency
        accentColorID = event.accentColorID
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
        guard
            let amountValue =
                MoneyAmountParser.parse(amount)
        else {
            return
        }

        let savedAccentColorID = type == .expense
            ? accentColorID
            : nil
        let wasEditing = editingEvent != nil

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
            editingEvent.type = type
            editingEvent.accentColorID = savedAccentColorID

        } else {

            let newEvent =
                PlannerEvent(
                    name: name,
                    amount: amountValue,
                    date: date,
                    frequency: frequency,
                    type: type,
                    accentColorID: savedAccentColorID
                )

            modelContext.insert(
                newEvent
            )
        }

        if resetOccurrenceTracking,
           let onScheduleReset {
            onScheduleReset()
        } else {
            onSaved?(type, wasEditing)
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

        let dateChanged = !Calendar.current.isDate(
            date,
            inSameDayAs: editingEvent.date
        )

        return dateChanged ||
            frequency != editingEvent.frequency ||
            type != editingEvent.type
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
