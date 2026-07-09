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
