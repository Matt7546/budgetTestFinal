import Foundation

enum PlannerFrequency: String, Codable, CaseIterable, Identifiable {

    case once = "One Time"
    case weekly = "Weekly"
    case biweekly = "Bi-Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"

    var id: String {
        rawValue
    }
}
