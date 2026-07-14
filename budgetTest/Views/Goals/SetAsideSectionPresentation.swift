import Foundation

enum SetAsideSectionKind: CaseIterable, Equatable, Hashable {
    case upcomingExpenses
    case paymentPlans
    case savingsGoals
    case cashCushion

    static let displayOrder: [SetAsideSectionKind] = [
        .upcomingExpenses,
        .paymentPlans,
        .savingsGoals,
        .cashCushion
    ]
}

struct SetAsideSectionPresentation: Equatable {
    let title: String
    let purpose: String
    let emptyTitle: String
    let emptyDetail: String
    let quickAddTitle: String?

    static func content(
        for kind: SetAsideSectionKind
    ) -> SetAsideSectionPresentation {
        switch kind {
        case .upcomingExpenses:
            return SetAsideSectionPresentation(
                title: "Upcoming Expenses",
                purpose: "Dated costs you are preparing for.",
                emptyTitle: "No Upcoming Expenses yet",
                emptyDetail: "Add a dated cost you want to prepare for.",
                quickAddTitle: "Add Upcoming Expense"
            )
        case .paymentPlans:
            return SetAsideSectionPresentation(
                title: "Payment Plans",
                purpose: "Payments you are funding.",
                emptyTitle: "No Payment Plans yet",
                emptyDetail: "Create a plan for a payment you want to fund.",
                quickAddTitle: "Create Payment Plan"
            )
        case .savingsGoals:
            return SetAsideSectionPresentation(
                title: "Savings Goals",
                purpose: "Money set aside for something meaningful.",
                emptyTitle: "No Savings Goals yet",
                emptyDetail: "Create a goal for something meaningful to you.",
                quickAddTitle: "Create Savings Goal"
            )
        case .cashCushion:
            return SetAsideSectionPresentation(
                title: "Cash Cushion",
                purpose: "Flexible money for the unexpected.",
                emptyTitle: "",
                emptyDetail: "",
                quickAddTitle: "Add money"
            )
        }
    }
}
