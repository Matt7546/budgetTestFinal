import Foundation
import SwiftData

@Model
final class SavingsGoalRecord {

    @Attribute(.unique)
    var id: UUID

    var ownerScopeID: String?

    var name: String
    var targetAmount: Double
    var currentAmount: Double
    var sortOrder: Int
    var isPinned: Bool = false
    var saveByDate: Date?

    init(
        id: UUID = UUID(),
        ownerScopeID: String? = PlanningOwnerScope.local,
        name: String,
        targetAmount: Double,
        currentAmount: Double = 0,
        sortOrder: Int = 0,
        isPinned: Bool = false,
        saveByDate: Date? = nil
    ) {
        self.id = id
        self.ownerScopeID = ownerScopeID
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.sortOrder = sortOrder
        self.isPinned = isPinned
        self.saveByDate = saveByDate
    }

    init(
        goal: SavingsGoal,
        sortOrder: Int,
        ownerScopeID: String? = PlanningOwnerScope.local
    ) {
        self.id = goal.id
        self.ownerScopeID = ownerScopeID
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

extension SavingsGoalRecord: PlanningOwnedRecord {}

@Model
final class ReserveSettings {

    static let defaultID = "default"

    var id: String

    var ownerScopeID: String?
    var balance: Double

    init(
        id: String = ReserveSettings.defaultID,
        ownerScopeID: String? = PlanningOwnerScope.local,
        balance: Double = 0
    ) {
        self.id = id
        self.ownerScopeID = ownerScopeID
        self.balance = balance
    }
}

extension ReserveSettings: PlanningOwnedRecord {}

enum CashCushionBalancePolicy {

    static func normalized(
        _ balance: Double
    ) -> Double {
        guard balance.isFinite else {
            return 0
        }

        return max(balance, 0)
    }

    static func adding(
        _ amount: Double,
        to balance: Double
    ) -> Double {
        let currentBalance = normalized(balance)

        guard amount.isFinite,
              amount > 0 else {
            return currentBalance
        }

        let updatedBalance = currentBalance + amount
        return updatedBalance.isFinite
            ? updatedBalance
            : currentBalance
    }

    static func using(
        _ amount: Double,
        from balance: Double
    ) -> Double {
        let currentBalance = normalized(balance)

        guard amount.isFinite,
              amount > 0 else {
            return currentBalance
        }

        return max(currentBalance - amount, 0)
    }
}
