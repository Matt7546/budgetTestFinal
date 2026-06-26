import Foundation
import SwiftData

@Model
final class SavingsGoalRecord {

    @Attribute(.unique)
    var id: UUID

    var name: String
    var targetAmount: Double
    var currentAmount: Double
    var sortOrder: Int
    var isPinned: Bool = false
    var saveByDate: Date?

    init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Double,
        currentAmount: Double = 0,
        sortOrder: Int = 0,
        isPinned: Bool = false,
        saveByDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.sortOrder = sortOrder
        self.isPinned = isPinned
        self.saveByDate = saveByDate
    }

    init(
        goal: SavingsGoal,
        sortOrder: Int
    ) {
        self.id = goal.id
        self.name = goal.name
        self.targetAmount = goal.targetAmount
        self.currentAmount = goal.currentAmount
        self.sortOrder = sortOrder
        self.isPinned = goal.isPinned
        self.saveByDate = goal.saveByDate
    }

    var savingsGoal: SavingsGoal {
        SavingsGoal(
            id: id,
            name: name,
            targetAmount: targetAmount,
            currentAmount: currentAmount,
            isPinned: isPinned,
            saveByDate: saveByDate
        )
    }

    func update(
        from goal: SavingsGoal
    ) {
        name = goal.name
        targetAmount = goal.targetAmount
        currentAmount = goal.currentAmount
        isPinned = goal.isPinned
        saveByDate = goal.saveByDate
    }
}

@Model
final class ReserveSettings {

    static let defaultID = "default"

    @Attribute(.unique)
    var id: String

    var balance: Double

    init(
        id: String = ReserveSettings.defaultID,
        balance: Double = 0
    ) {
        self.id = id
        self.balance = balance
    }
}
