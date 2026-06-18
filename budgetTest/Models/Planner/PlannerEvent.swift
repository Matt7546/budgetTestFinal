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

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        date: Date,
        frequency: PlannerFrequency = .once,
        type: PlannerEventType
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
        self.frequency = frequency
        self.type = type
    }
}
