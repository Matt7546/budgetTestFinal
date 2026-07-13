import Foundation

enum DashboardNextActionPriority {

    static func resolve(
        hasBankRefreshWarning: Bool,
        needsAccountScope: Bool,
        reviewItem: ReviewUpdateItem?,
        upcomingExpenseNeedingMoney: ForecastEvent?,
        hasPaymentPlanNeedingMoney: Bool
    ) -> DashboardNextAction {
        if hasBankRefreshWarning {
            return .bankSync
        }

        if needsAccountScope {
            return .accountScope
        }

        if let reviewItem {
            return DashboardNextAction.reviewItemAction(
                reviewItem
            )
        }

        if let upcomingExpenseNeedingMoney {
            return .upcomingNeedsMoney(
                upcomingExpenseNeedingMoney
            )
        }

        if hasPaymentPlanNeedingMoney {
            return .paymentPlanNeedsMoney
        }

        return .allClear
    }

    static func resolve(
        hasBankRefreshWarning: Bool,
        needsAccountScope: Bool,
        pastDueExpense: ForecastEvent?,
        paymentDetectionCandidate: PaymentPlanPaymentCandidate? = nil,
        hasSuggestedUpdate: Bool,
        upcomingExpenseNeedingMoney: ForecastEvent?,
        hasPaymentPlanNeedingMoney: Bool
    ) -> DashboardNextAction {
        if hasBankRefreshWarning {
            return .bankSync
        }

        if needsAccountScope {
            return .accountScope
        }

        if let pastDueExpense {
            return .pastDueExpense(pastDueExpense)
        }

        if let paymentDetectionCandidate {
            return .possibleCardPayment(
                paymentDetectionCandidate
            )
        }

        if hasSuggestedUpdate {
            return .suggestedUpdate
        }

        if let upcomingExpenseNeedingMoney {
            return .upcomingNeedsMoney(upcomingExpenseNeedingMoney)
        }

        if hasPaymentPlanNeedingMoney {
            return .paymentPlanNeedsMoney
        }

        return .allClear
    }
}

enum DashboardNextAction {

    case bankSync
    case accountScope
    case possibleCardPayment(PaymentPlanPaymentCandidate)
    case suggestedUpdate
    case paymentPlanSuggestedUpdate(UUID)
    case recurringExpenseRecommendation(String)
    case pastDueExpense(ForecastEvent)
    case pastDuePaymentPlan
    case upcomingNeedsMoney(ForecastEvent)
    case paymentPlanNeedsMoney
    case allClear

    var title: String {
        switch self {
        case .bankSync:
            return "Check Bank Sync"

        case .accountScope:
            return "Choose cash accounts"

        case .suggestedUpdate,
             .paymentPlanSuggestedUpdate:
            return "Review Payment Plan update"

        case .possibleCardPayment:
            return "Review possible card payment"

        case .recurringExpenseRecommendation:
            return "Review recurring expense"

        case .pastDueExpense:
            return "Review past-due expense"

        case .pastDuePaymentPlan:
            return "Review past-due Payment Plan"

        case .upcomingNeedsMoney,
             .paymentPlanNeedsMoney:
            return "Still needs money"

        case .allClear:
            return "You're set for now"
        }
    }

    var message: String {
        switch self {
        case .bankSync:
            return "Some balances may need refreshing before your spending picture is complete."

        case .accountScope:
            return "No linked cash accounts are currently counted in Available to Spend."

        case .suggestedUpdate,
             .paymentPlanSuggestedUpdate:
            return "Caldera found card details to review before you decide whether to update a Payment Plan."

        case .possibleCardPayment(let candidate):
            return "A payment of \(AppFormatters.currency(candidate.amount)) dated \(AppFormatters.abbreviatedMonthDay(candidate.postedDate)) may have posted after your last Bank Sync."

        case .recurringExpenseRecommendation:
            return "Caldera found a recurring expense that may help you plan ahead."

        case .pastDueExpense(let forecast):
            return "\(forecast.event.name) was due \(AppFormatters.abbreviatedMonthDay(forecast.occurrenceDate)). Review what happened and update your plan."

        case .pastDuePaymentPlan:
            return "A Payment Plan is past due. Open Past Due to review it and keep your plan current."

        case .upcomingNeedsMoney:
            return "One planned item needs more set aside."

        case .paymentPlanNeedsMoney:
            return "One payment plan needs more set aside."

        case .allClear:
            return "Your planned expenses are covered based on your current setup."
        }
    }

    var actionTitle: String? {
        switch self {
        case .bankSync:
            return "Check Bank Sync"

        case .accountScope:
            return "Review Bank Sync"

        case .suggestedUpdate,
             .paymentPlanSuggestedUpdate:
            return "Review Payment Plan update"

        case .possibleCardPayment:
            return "Review payment"

        case .recurringExpenseRecommendation:
            return "Review recommendation"

        case .pastDueExpense:
            return "Review expense"

        case .pastDuePaymentPlan:
            return "Open Past Due"

        case .upcomingNeedsMoney:
            return "Set Aside"

        case .paymentPlanNeedsMoney:
            return "Open Set Aside"

        case .allClear:
            return nil
        }
    }

    var style: CalderaCategoryStyle {
        switch self {
        case .bankSync,
             .accountScope:
            return CalderaCategoryStyle.style(for: .bankAccount)

        case .suggestedUpdate,
             .paymentPlanSuggestedUpdate,
             .possibleCardPayment:
            return CalderaCategoryStyle.style(for: .debtPayoff)

        case .recurringExpenseRecommendation:
            return CalderaCategoryStyle.style(for: .upcomingExpense)

        case .pastDueExpense,
             .pastDuePaymentPlan,
             .upcomingNeedsMoney,
             .paymentPlanNeedsMoney:
            return CalderaCategoryStyle.style(for: .needsMoney)

        case .allClear:
            return CalderaCategoryStyle.style(for: .covered)
        }
    }

    var icon: String {
        switch self {
        case .bankSync,
             .accountScope:
            return "building.columns.fill"

        case .suggestedUpdate,
             .paymentPlanSuggestedUpdate,
             .possibleCardPayment:
            return "creditcard.fill"

        case .recurringExpenseRecommendation:
            return CalderaCategoryStyle.style(
                for: .upcomingExpense
            ).icon

        case .pastDueExpense,
             .pastDuePaymentPlan,
             .upcomingNeedsMoney,
             .paymentPlanNeedsMoney:
            return "calendar.badge.exclamationmark"

        case .allClear:
            return "checkmark.circle.fill"
        }
    }

    var paymentPlanIDForReview: UUID? {
        switch self {
        case .possibleCardPayment(let candidate):
            return candidate.paymentPlanID
        case .paymentPlanSuggestedUpdate(let paymentPlanID):
            return paymentPlanID
        case .bankSync,
             .accountScope,
             .suggestedUpdate,
             .recurringExpenseRecommendation,
             .pastDueExpense,
             .pastDuePaymentPlan,
             .upcomingNeedsMoney,
             .paymentPlanNeedsMoney,
             .allClear:
            return nil
        }
    }

    static func reviewItemAction(
        _ item: ReviewUpdateItem
    ) -> DashboardNextAction {
        switch item.destination {
        case .upcomingExpense(let forecast):
            return .pastDueExpense(forecast)
        case .pastDuePaymentPlan:
            return .pastDuePaymentPlan
        case .likelyPostedCardPayment(let candidate):
            return .possibleCardPayment(candidate)
        case .paymentPlanUpdate(let paymentPlanID):
            return .paymentPlanSuggestedUpdate(paymentPlanID)
        case .recurringExpenseRecommendation(let historyID):
            return .recurringExpenseRecommendation(historyID)
        }
    }
}
