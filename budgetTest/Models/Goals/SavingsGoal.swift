import Foundation

struct SavingsGoal: Identifiable, Codable, Equatable {

    let id: UUID
    var name: String
    var targetAmount: Double
    var currentAmount: Double

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentAmount / targetAmount, 1)
    }

    init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Double,
        currentAmount: Double = 0
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
    }
}
