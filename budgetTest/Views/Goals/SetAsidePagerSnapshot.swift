import Foundation

enum SetAsidePagerSection: String, CaseIterable, Identifiable, Equatable {
    case upcomingExpenses
    case paymentPlans
    case savingsGoals

    var id: String { rawValue }

    static let defaultSelection: SetAsidePagerSection = .savingsGoals
}

enum SetAsidePagerStyleIdentity: String, Equatable {
    case cashCushion
    case savingsGoals
    case paymentPlans
    case upcomingExpenses
}

enum SetAsidePagerPaymentPlanEditor: Equatable {
    case modernCard
    case legacyDebt
}

enum SetAsidePagerDestination: Equatable {
    case addCashCushion
    case useCashCushion
    case createSavingsGoal
    case seeAllSavingsGoals
    case updateSavingsGoal(goalID: UUID)
    case contributeToSavingsGoal(goalID: UUID)
    case createPaymentPlan
    case seeAllPaymentPlans
    case updatePaymentPlan(
        bucketID: UUID,
        cycleID: UUID?,
        editor: SetAsidePagerPaymentPlanEditor
    )
    case contributeToPaymentPlan(
        bucketID: UUID,
        cycleID: UUID?,
        editor: SetAsidePagerPaymentPlanEditor
    )
    case createUpcomingExpense
    case seeAllUpcomingExpenses
    case updateUpcomingExpense(eventID: UUID, occurrenceID: String)
    case contributeToUpcomingExpense(eventID: UUID, occurrenceID: String)
}

struct SetAsidePagerEmptyStateSnapshot: Equatable {
    let title: String
    let detail: String
}

struct SetAsidePagerSnapshot: Equatable {
    let cashCushion: SetAsidePagerCashCushionSnapshot
    let goals: SetAsidePagerGoalsSnapshot
    let payments: SetAsidePagerPaymentsSnapshot
    let upcomingExpenses: SetAsidePagerUpcomingSnapshot
}

struct SetAsidePagerCashCushionSnapshot: Equatable {
    let title: String
    let currentAmount: Double
    let targetAmount: Double?
    let progress: Double?
    let style: SetAsidePagerStyleIdentity
    let isEmpty: Bool
    let addDestination: SetAsidePagerDestination
    let useDestination: SetAsidePagerDestination?
    let accessibilityLabel: String
}

struct SetAsidePagerGoalsSnapshot: Equatable {
    let title: String
    let totalSaved: Double
    let totalTarget: Double
    let remainingAmount: Double
    let progress: Double
    let activeCount: Int
    let allGoalsCount: Int
    let style: SetAsidePagerStyleIdentity
    let rows: [SetAsidePagerGoalRowSnapshot]
    let isEmpty: Bool
    let emptyState: SetAsidePagerEmptyStateSnapshot
    let hasAdditionalItems: Bool
    let createDestination: SetAsidePagerDestination
    let seeAllDestination: SetAsidePagerDestination
    let accessibilityLabel: String
}

struct SetAsidePagerGoalRowSnapshot: Identifiable, Equatable {
    let id: UUID
    let title: String
    let savedAmount: Double
    let targetAmount: Double
    let remainingAmount: Double
    let progress: Double
    let updateDestination: SetAsidePagerDestination
    let contributeDestination: SetAsidePagerDestination
    let accessibilityLabel: String
}

struct PaymentPlanFundingSummary: Equatable {
    let totalPlanned: Double
    let totalSetAside: Double
    let remainingAmount: Double
    let progress: Double

    init(
        paymentPlans: [DebtPayoffBucket],
        paymentPlanCycles: [PaymentPlanCycle],
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        let activePlans = paymentPlans.filter { bucket in
            PaymentPlanCycleStore.isActiveOrLegacy(
                paymentPlanID: bucket.id,
                cycles: paymentPlanCycles
            )
        }
        let entries = activePlans.map { bucket in
            DebtPayoffDisplayModel(
                bucket: bucket,
                linkedAccount: nil,
                cycle: PaymentPlanCycleStore.activeCycle(
                    for: bucket.id,
                    in: paymentPlanCycles
                ),
                today: today,
                calendar: calendar
            )
        }

        totalPlanned = entries.reduce(0) {
            $0 + Self.normalized($1.plannedPaymentAmount)
        }
        totalSetAside = activePlans.reduce(0) {
            $0 + Self.normalized($1.protectedAmount)
        }
        remainingAmount = entries.reduce(0) {
            $0 + Self.normalized($1.remainingPaymentAmount)
        }
        let totalCovered = entries.reduce(0) {
            $0 + Self.normalized($1.coveredPaymentAmount)
        }
        progress = totalPlanned > 0
            ? min(max(totalCovered / totalPlanned, 0), 1)
            : 0
    }

    private static func normalized(
        _ amount: Double
    ) -> Double {
        guard amount.isFinite else {
            return 0
        }

        return max(amount, 0)
    }
}

struct SetAsidePagerPaymentsSnapshot: Equatable {
    let title: String
    let totalSetAside: Double
    let totalPlanned: Double
    let remainingAmount: Double
    let progress: Double
    let activeCount: Int
    let allPaymentPlanCount: Int
    let style: SetAsidePagerStyleIdentity
    let rows: [SetAsidePagerPaymentRowSnapshot]
    let segments: [SetAsidePagerPaymentSegmentSnapshot]
    let isEmpty: Bool
    let emptyState: SetAsidePagerEmptyStateSnapshot
    let hasAdditionalItems: Bool
    let createDestination: SetAsidePagerDestination
    let seeAllDestination: SetAsidePagerDestination
    let accessibilityLabel: String
}

struct SetAsidePagerPaymentRowSnapshot: Identifiable, Equatable {
    var id: UUID { bucketID }

    let bucketID: UUID
    let cycleID: UUID?
    let title: String
    let plannedAmount: Double
    let setAsideAmount: Double
    let remainingAmount: Double
    let progress: Double
    let dueDate: Date
    let targetBasis: String
    let status: String
    let editor: SetAsidePagerPaymentPlanEditor
    let updateDestination: SetAsidePagerDestination
    let contributeDestination: SetAsidePagerDestination
    let accessibilityLabel: String
}

struct SetAsidePagerPaymentSegmentSnapshot: Identifiable, Equatable {
    var id: String {
        "\(bucketID.uuidString.lowercased())|\(cycleID?.uuidString.lowercased() ?? "legacy")"
    }

    let bucketID: UUID
    let cycleID: UUID?
    let title: String
    let targetAmount: Double
    let setAsideAmount: Double
    let progress: Double
    let dueDate: Date
}

struct SetAsidePagerUpcomingSnapshot: Equatable {
    static let summaryLimit = 3

    let title: String
    let summaryLabel: String
    /// The existing next-three preview subtotal, not the financial deduction.
    let totalSetAside: Double
    /// All valid unresolved funding, independent of the displayed rows.
    let totalActiveSetAside: Double
    let totalNeeded: Double
    let remainingAmount: Double
    let progress: Double
    let activeDisplayedCount: Int
    let allUpcomingOccurrenceCount: Int
    let style: SetAsidePagerStyleIdentity
    let rows: [SetAsidePagerUpcomingRowSnapshot]
    let isEmpty: Bool
    let emptyState: SetAsidePagerEmptyStateSnapshot
    let hasAdditionalItems: Bool
    let createDestination: SetAsidePagerDestination
    let seeAllDestination: SetAsidePagerDestination
    let accessibilityLabel: String
}

struct SetAsidePagerUpcomingRowSnapshot: Identifiable, Equatable {
    var id: String { occurrenceID }

    let eventID: UUID
    let occurrenceID: String
    let title: String
    let amountNeeded: Double
    let setAsideAmount: Double
    let remainingAmount: Double
    let progress: Double
    let occurrenceDate: Date
    let recurrence: String
    let updateDestination: SetAsidePagerDestination
    let contributeDestination: SetAsidePagerDestination
    let accessibilityLabel: String
}
