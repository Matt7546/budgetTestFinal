import Foundation

enum SetAsidePagerExperience: Equatable {
    case legacy
    case pager
}

enum SetAsidePagerBuildMode {
    case debug
    case production
}

enum SetAsidePagerFeature {
    static let storageKey = "caldera.setAside.pager.enabled"
    static let defaultStoredValue = true

    static func experience(
        storedValue: Bool
    ) -> SetAsidePagerExperience {
        #if DEBUG
        experience(storedValue: storedValue, buildMode: .debug)
        #else
        experience(storedValue: storedValue, buildMode: .production)
        #endif
    }

    static func experience(
        storedValue: Bool,
        buildMode: SetAsidePagerBuildMode
    ) -> SetAsidePagerExperience {
        switch buildMode {
        case .production:
            return .pager
        case .debug:
            return storedValue ? .pager : .legacy
        }
    }
}

enum SetAsidePagerRoute: Equatable {
    case adjustCashCushion(CashCushionAdjustmentMode)
    case createSavingsGoal
    case seeAllSavingsGoals
    case editSavingsGoal(goalID: UUID)
    case createPaymentPlan
    case seeAllPaymentPlans
    case editPaymentPlan(
        bucketID: UUID,
        cycleID: UUID?,
        editor: SetAsidePagerPaymentPlanEditor
    )
    case createUpcomingExpense
    case seeAllUpcomingExpenses
    case editUpcomingExpense(eventID: UUID, occurrenceID: String)
}

enum SetAsidePagerRouteResolver {
    static func resolve(
        _ destination: SetAsidePagerDestination
    ) -> SetAsidePagerRoute {
        switch destination {
        case .addCashCushion:
            return .adjustCashCushion(.add)

        case .useCashCushion:
            return .adjustCashCushion(.use)

        case .createSavingsGoal:
            return .createSavingsGoal

        case .seeAllSavingsGoals:
            return .seeAllSavingsGoals

        case .updateSavingsGoal(let goalID),
             .contributeToSavingsGoal(let goalID):
            return .editSavingsGoal(goalID: goalID)

        case .createPaymentPlan:
            return .createPaymentPlan

        case .seeAllPaymentPlans:
            return .seeAllPaymentPlans

        case .updatePaymentPlan(let bucketID, let cycleID, let editor),
             .contributeToPaymentPlan(let bucketID, let cycleID, let editor):
            return .editPaymentPlan(
                bucketID: bucketID,
                cycleID: cycleID,
                editor: editor
            )

        case .createUpcomingExpense:
            return .createUpcomingExpense

        case .seeAllUpcomingExpenses:
            return .seeAllUpcomingExpenses

        case .updateUpcomingExpense(let eventID, let occurrenceID),
             .contributeToUpcomingExpense(let eventID, let occurrenceID):
            return .editUpcomingExpense(
                eventID: eventID,
                occurrenceID: occurrenceID
            )
        }
    }
}
