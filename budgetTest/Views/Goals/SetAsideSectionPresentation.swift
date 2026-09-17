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
                title: "Bills",
                purpose: "Dated costs you are preparing for.",
                emptyTitle: "No Bills yet",
                emptyDetail: "Add a dated cost you want to prepare for.",
                quickAddTitle: "Add Bill"
            )
        case .paymentPlans:
            return SetAsideSectionPresentation(
                title: "Credit & Loans",
                purpose: "Payments you are funding.",
                emptyTitle: "No accounts yet",
                emptyDetail: "Create a plan for a payment you want to fund.",
                quickAddTitle: "Add Credit or Loan"
            )
        case .savingsGoals:
            return SetAsideSectionPresentation(
                title: "Goals",
                purpose: "Money set aside for something meaningful.",
                emptyTitle: "No Goals yet",
                emptyDetail: "Create a goal for something meaningful to you.",
                quickAddTitle: "Create Goal"
            )
        case .cashCushion:
            return SetAsideSectionPresentation(
                title: "Cushion",
                purpose: "Flexible money for the unexpected.",
                emptyTitle: "",
                emptyDetail: "",
                quickAddTitle: "Add money"
            )
        }
    }
}
