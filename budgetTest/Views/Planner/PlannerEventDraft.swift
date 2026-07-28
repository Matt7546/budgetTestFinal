import Foundation

struct PlannerEventDraft {
    let name: String
    let amount: Double
    let date: Date
    let type: PlannerEventType
    let frequency: PlannerFrequency
    let accentColorID: String?

    init(
        name: String,
        amount: Double,
        date: Date,
        type: PlannerEventType = .expense,
        frequency: PlannerFrequency = .monthly,
        accentColorID: String? = nil
    ) {
        self.name = name
        self.amount = amount
        self.date = date
        self.type = type
        self.frequency = frequency
        self.accentColorID = accentColorID
    }
}

struct PlannerEventEditorState: Equatable {

    var name: String
    var amountText: String
    var date: Date
    var type: PlannerEventType
    var frequency: PlannerFrequency
    var accentColorID: String?
    var isDatePickerExpanded: Bool

    init(
        editingEvent: PlannerEvent?,
        draft: PlannerEventDraft?,
        now: Date = Date()
    ) {
        if let editingEvent {
            name = editingEvent.name
            amountText = String(editingEvent.amount)
            date = editingEvent.date
            type = editingEvent.type
            frequency = editingEvent.frequency
            accentColorID = editingEvent.accentColorID
        } else if let draft {
            name = draft.name
            amountText = String(format: "%.2f", draft.amount)
            date = draft.date
            type = .expense
            frequency = draft.frequency
            accentColorID = draft.accentColorID
        } else {
            name = ""
            amountText = ""
            date = now
            type = .expense
            frequency = .once
            accentColorID = nil
        }

        isDatePickerExpanded = false
    }

    var preSaveSummary: PlannerEventPreSaveSummary {
        PlannerEventPreSaveSummary(
            amount: MoneyAmountParser.parse(amountText),
            date: date,
            frequency: frequency
        )
    }

    func submission(
        editingEvent: PlannerEvent?
    ) -> PlannerEventEditorSubmission? {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedName.isEmpty,
              let amount = MoneyAmountParser.parse(amountText),
              amount > 0 else {
            return nil
        }

        let savedType = PlannerEventEditingPolicy.typeForSave(
            editingEvent: editingEvent
        )

        return PlannerEventEditorSubmission(
            name: name,
            amount: amount,
            date: date,
            frequency: frequency,
            type: savedType,
            accentColorID: savedType == .expense
                ? accentColorID
                : editingEvent?.accentColorID
        )
    }
}

struct PlannerEventEditorSubmission: Equatable {
    let name: String
    let amount: Double
    let date: Date
    let frequency: PlannerFrequency
    let type: PlannerEventType
    let accentColorID: String?
}

struct PlannerEventPreSaveSummary: Equatable {
    let amount: Double?
    let date: Date
    let frequency: PlannerFrequency
}

enum PlannerEventSaveMutation {

    @discardableResult
    static func apply(
        _ submission: PlannerEventEditorSubmission,
        editingEvent: PlannerEvent?,
        insert: (PlannerEvent) -> Void
    ) -> PlannerEvent {
        if let editingEvent {
            editingEvent.name = submission.name
            editingEvent.amount = submission.amount
            editingEvent.date = submission.date
            editingEvent.frequency = submission.frequency
            editingEvent.accentColorID = submission.accentColorID
            return editingEvent
        }

        let event = PlannerEvent(
            name: submission.name,
            amount: submission.amount,
            date: submission.date,
            frequency: submission.frequency,
            type: submission.type,
            accentColorID: submission.accentColorID
        )
        insert(event)
        return event
    }
}

enum PlannerEventScheduleChangePolicy {

    static func hasScheduleChange(
        originalDate: Date,
        originalFrequency: PlannerFrequency,
        proposedDate: Date,
        proposedFrequency: PlannerFrequency,
        calendar: Calendar = .current
    ) -> Bool {
        !calendar.isDate(
            proposedDate,
            inSameDayAs: originalDate
        ) || proposedFrequency != originalFrequency
    }

    static func requiresOccurrenceReset(
        hasRelatedRecords: Bool,
        hasScheduleChange: Bool
    ) -> Bool {
        hasRelatedRecords && hasScheduleChange
    }
}

enum PlannerEventRecurrenceControlPresentation {

    static func usesSingleColumn(
        isAccessibilitySize: Bool
    ) -> Bool {
        isAccessibilitySize
    }

    static func accessibilityValue(
        isSelected: Bool
    ) -> String {
        isSelected ? "Selected" : "Not selected"
    }
}
