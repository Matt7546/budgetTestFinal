import Foundation
import SwiftData

enum PlannerEventType: String, Codable, CaseIterable, Identifiable {

    case expense = "Expense"
    case income = "Income"

    var id: String {
        rawValue
    }
}

@Model
final class PlannerEvent {

    @Attribute(.unique)
    var id: UUID

    var name: String
    var amount: Double
    var date: Date

    var frequency: PlannerFrequency
    var type: PlannerEventType
    var accentColorID: String?

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        date: Date,
        frequency: PlannerFrequency = .once,
        type: PlannerEventType,
        accentColorID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.frequency = frequency
        self.type = type
        self.accentColorID = accentColorID
    }
}

enum PlannerEventEditingPolicy {

    static func typeForSave(
        editingEvent: PlannerEvent?
    ) -> PlannerEventType {
        editingEvent?.type ?? .expense
    }
}

enum PlannerEventManagement {

    static func legacyIncomeEvents(
        from events: [PlannerEvent]
    ) -> [PlannerEvent] {
        events
            .filter { $0.type == .income }
            .sorted { $0.date < $1.date }
    }
}
