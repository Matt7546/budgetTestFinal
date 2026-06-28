import SwiftUI
import SwiftData
import UIKit

struct AddPlannerEventView: View {

    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.dismiss)
    private var dismiss

    let editingEvent: PlannerEvent?

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @State private var name = ""
    @State private var amount = ""

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
        Double(amount) != nil
        &&
        Double(amount) ?? 0 > 0
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
                    eyebrow: isEditing ? "Update Upcoming Event" : "New Upcoming Event",
                    title: isEditing ? "Edit Event" : "Add Event",
                    subtitle: "Add income or bills to your timeline.",
                    systemImage: type == .income
                        ? CalderaCategoryStyle.style(for: .income).icon
                        : CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                    color: typeColor
                )

                detailsCard

                scheduleCard

                if hasRelatedOccurrenceRecords {
                    occurrenceRecordsWarningCard
                }

                if editingEvent != nil {
                    deleteCard
                }

                PrimaryButton(
                    isEditing ? "Save Changes" : "Add Event",
                    systemImage: "checkmark.circle.fill",
                    trailingSystemImage: nil,
                    isDisabled: !canSave,
                    fillsWidth: true,
                    action: saveEvent
                )
                .accessibilityLabel(isEditing ? "Save planner event changes" : "Add planner event")
            }
            .keyboardDismissToolbar()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {

                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel planner event")
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {

                    Button(isEditing ? "Save" : "Add") {
                        saveEvent()
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(isEditing ? "Save planner event changes" : "Add planner event")
                }
            }
            .onAppear {
                loadEditingEvent()
            }
        }
    }

    private var detailsCard: some View {
        GlassFormCard(color: typeColor) {
            FormSectionHeader(
                title: "Details",
                systemImage: "square.and.pencil",
                color: typeColor
            )

            labeledTextField(
                title: "Event Name",
                placeholder: "Rent, Paycheck, Utilities",
                text: $name
            )

            labeledTextField(
                title: "Event Amount",
                placeholder: "0.00",
                text: $amount,
                keyboardType: .decimalPad,
                subtitle: type == .income
                    ? "Money added to your timeline."
                    : "Amount used for upcoming expense planning.",
                systemImage: type == .income
                    ? CalderaCategoryStyle.style(for: .income).icon
                    : CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                colors: type == .income
                    ? CalderaCategoryStyle.style(for: .income).gradient
                    : CalderaCategoryStyle.style(for: .upcomingExpense).gradient
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                Text("Money Flow")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                HStack(spacing: AppSpacing.small) {
                    eventTypeButton(.expense)
                    eventTypeButton(.income)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Money Flow")
            }

            if type == .expense {
                eventColorSelector
            }
        }
    }

    private var scheduleCard: some View {
        GlassFormCard(color: AppColors.warning) {
            FormSectionHeader(
                title: "Schedule",
                systemImage: "calendar",
                color: AppColors.warning
            )

            DatePicker(
                "Date",
                selection: $date,
                displayedComponents: .date
            )
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppColors.primaryText)
            .padding()
            .glassCard(
                cornerRadius: AppRadii.field,
                shadow: nil
            )
            .accessibilityLabel("Event date")

            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                Text("Repeats")
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
                .accessibilityLabel("Repeats")
            }
        }
    }

    private var deleteCard: some View {
        GlassFormCard(color: AppColors.negative) {
            FormSectionHeader(
                title: "Remove Event",
                systemImage: "trash.fill",
                color: AppColors.negative
            )

            Text("Delete this upcoming event from your timeline.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)

            DestructiveButton(
                "Delete Event",
                systemImage: "trash",
                cornerRadius: AppRadii.button,
                action: deleteEvent
            )
            .accessibilityLabel("Delete planner event")
        }
    }

    private var occurrenceRecordsWarningCard: some View {
        GlassFormCard(color: AppColors.warning) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                IconBadge(
                    systemImage: "exclamationmark.triangle.fill",
                    color: AppColors.warning,
                    size: 34,
                    iconSize: 14
                )

                Text("Changing the date, repeat schedule, or money flow may separate this event from existing set-aside money for previous occurrences.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var typeColor: Color {
        switch type {
        case .expense:
            return CalderaCategoryStyle.style(for: .upcomingExpense).primary

        case .income:
            return CalderaCategoryStyle.style(for: .income).primary
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
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)

            TextField(
                placeholder,
                text: text
            )
            .keyboardType(keyboardType)
            .padding()
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.86,
                strokeOpacity: 0.68,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: colors.first ?? AppColors.accent
            )
            .accessibilityLabel(title)
        }
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
                ? AppColors.spendable
                : AppColors.obligation,
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
            color: AppColors.warning,
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
            Text("Event Color")
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
            .accessibilityLabel("Event Color")
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

    private func saveEvent() {
        guard
            let amountValue =
                Double(amount)
        else {
            return
        }

        let savedAccentColorID = type == .expense
            ? accentColorID
            : nil

        if let editingEvent {

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

        dismiss()
    }

    private func deleteEvent() {
        guard let editingEvent else {
            return
        }

        deleteRelatedOccurrenceRecords(
            for: editingEvent
        )

        modelContext.delete(
            editingEvent
        )

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
