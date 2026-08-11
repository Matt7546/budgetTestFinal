import Foundation

enum DashboardNextActionCollapsePreference {
    static let storageKey = "dashboard.nextAction.isCollapsed"
}

struct DashboardNextActionPresentation: Equatable {
    let isCollapsed: Bool
    let showsExpandedMessage: Bool
    let showsPrimaryAction: Bool
    let toggleTitle: String
    let toggleSystemImage: String
    let compactMessage: String

    static func make(
        for action: DashboardNextAction,
        isCollapsed: Bool
    ) -> DashboardNextActionPresentation {
        DashboardNextActionPresentation(
            isCollapsed: isCollapsed,
            showsExpandedMessage: !isCollapsed,
            showsPrimaryAction: action.actionTitle != nil,
            toggleTitle: isCollapsed ? "Show" : "Collapse",
            toggleSystemImage: isCollapsed ? "chevron.down" : "chevron.up",
            compactMessage: compactMessage(for: action)
        )
    }

    private static func compactMessage(
        for action: DashboardNextAction
    ) -> String {
        switch action {
        case .bankSync:
            return "Balances may need a refresh."

        case .accountScope:
            return "Choose accounts for Available to Spend."

        case .suggestedUpdate,
             .paymentPlanSuggestedUpdate:
            return "A Payment Plan update is ready."

        case .possibleCardPayment:
            return "A possible card payment is ready."

        case .recurringExpenseRecommendation:
            return "A recurring expense is ready."

        case .pastDueExpense(let forecast):
            return "\(forecast.event.name) needs review."

        case .pastDuePaymentPlan:
            return "A past-due Payment Plan needs review."

        case .upcomingNeedsMoney:
            return "1 item needs set aside."

        case .paymentPlanNeedsMoney:
            return "1 Payment Plan needs set aside."

        case .allClear:
            return "Planned expenses are covered."
        }
    }
}
