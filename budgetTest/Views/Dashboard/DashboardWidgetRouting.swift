import Foundation

enum DashboardWidgetAction: Hashable {
    case openSetAside
    case openBankSync
    case openReviewUpdates
    case openSavingsGoal(UUID)
    case openUpcomingExpense(eventID: UUID, occurrenceID: String)
    case openPaymentPlan(bucketID: UUID, cycleID: UUID?)
    case openPlanAhead
}

enum DashboardPaymentPlanEditorRoute: Equatable {
    case modern(bucketID: UUID, cycleID: UUID?)
    case legacy(bucketID: UUID, cycleID: UUID?)
}

enum DashboardWidgetActionResolver {

    static func parentAction(
        for snapshot: DashboardWidgetSnapshot
    ) -> DashboardWidgetAction? {
        guard snapshot.contentState != .hidden,
              let destination = snapshot.destination else {
            return nil
        }

        if snapshot.kind == .reviewUpdates && snapshot.items.isEmpty {
            return nil
        }

        return action(for: destination)
    }

    static func childAction(
        for item: DashboardWidgetItemSnapshot,
        in snapshot: DashboardWidgetSnapshot
    ) -> DashboardWidgetAction? {
        guard snapshot.contentState != .hidden,
              snapshot.kind == .upcomingExpenses ||
                snapshot.kind == .paymentPlans,
              let targetAmount = item.targetAmount,
              targetAmount.isFinite,
              targetAmount > 0,
              let destination = item.destination else {
            return nil
        }

        return action(for: destination)
    }

    static func paymentPlanEditorRoute(
        for action: DashboardWidgetAction,
        in buckets: [DebtPayoffBucket]
    ) -> DashboardPaymentPlanEditorRoute? {
        guard case .openPaymentPlan(let bucketID, let cycleID) = action,
              let bucket = buckets.first(where: { $0.id == bucketID }) else {
            return nil
        }

        if PaymentPlanUpdateRouting.usesModernEditor(for: bucket) {
            return .modern(bucketID: bucketID, cycleID: cycleID)
        }

        return .legacy(bucketID: bucketID, cycleID: cycleID)
    }

    private static func action(
        for destination: DashboardWidgetDestinationIdentity
    ) -> DashboardWidgetAction {
        switch destination {
        case .setAside:
            return .openSetAside

        case .bankSync:
            return .openBankSync

        case .reviewUpdates:
            return .openReviewUpdates

        case .savingsGoal(let goalID):
            return .openSavingsGoal(goalID)

        case .upcomingExpense(let eventID, let occurrenceID):
            return .openUpcomingExpense(
                eventID: eventID,
                occurrenceID: occurrenceID
            )

        case .paymentPlan(let bucketID, let cycleID):
            return .openPaymentPlan(
                bucketID: bucketID,
                cycleID: cycleID
            )

        case .planAhead:
            return .openPlanAhead
        }
    }
}
