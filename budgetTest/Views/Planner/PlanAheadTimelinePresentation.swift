import Foundation

struct PlanAheadPaymentPlan: Identifiable {
    let bucket: DebtPayoffBucket
    let dueDate: Date

    var id: UUID { bucket.id }
}

enum PlanAheadTimelineItem: Identifiable {
    case upcomingExpense(ForecastEvent)
    case paymentPlan(PlanAheadPaymentPlan)

    var id: String {
        switch self {
        case .upcomingExpense(let forecast):
            return "expense-\(forecast.occurrenceID)"
        case .paymentPlan(let paymentPlan):
            return "payment-plan-\(paymentPlan.bucket.id.uuidString)"
        }
    }

    var dueDate: Date {
        switch self {
        case .upcomingExpense(let forecast):
            return forecast.occurrenceDate
        case .paymentPlan(let paymentPlan):
            return paymentPlan.dueDate
        }
    }

    fileprivate var typeSortOrder: Int {
        switch self {
        case .upcomingExpense:
            return 0
        case .paymentPlan:
            return 1
        }
    }

    fileprivate var titleForSort: String {
        switch self {
        case .upcomingExpense(let forecast):
            return forecast.event.name
        case .paymentPlan(let paymentPlan):
            return paymentPlan.bucket.accountName
        }
    }
}

enum PlanAheadTimelineItems {

    static func upcoming(
        expenses: [ForecastEvent],
        paymentPlans: [PlanAheadPaymentPlan],
        startOfToday: Date,
        calendar: Calendar = .current
    ) -> [PlanAheadTimelineItem] {
        sorted(
            expenses: expenses.filter {
                calendar.startOfDay(for: $0.occurrenceDate) >= startOfToday
            },
            paymentPlans: paymentPlans.filter {
                calendar.startOfDay(for: $0.dueDate) >= startOfToday
            },
            calendar: calendar
        )
    }

    static func pastDue(
        expenses: [ForecastEvent],
        paymentPlans: [PlanAheadPaymentPlan],
        startOfToday: Date,
        calendar: Calendar = .current
    ) -> [PlanAheadTimelineItem] {
        sorted(
            expenses: expenses.filter {
                calendar.startOfDay(for: $0.occurrenceDate) < startOfToday
            },
            paymentPlans: paymentPlans.filter {
                calendar.startOfDay(for: $0.dueDate) < startOfToday
            },
            calendar: calendar
        )
    }

    private static func sorted(
        expenses: [ForecastEvent],
        paymentPlans: [PlanAheadPaymentPlan],
        calendar: Calendar
    ) -> [PlanAheadTimelineItem] {
        (expenses.map(PlanAheadTimelineItem.upcomingExpense) +
            paymentPlans.map(PlanAheadTimelineItem.paymentPlan))
            .sorted { lhs, rhs in
                let leftDate = calendar.startOfDay(for: lhs.dueDate)
                let rightDate = calendar.startOfDay(for: rhs.dueDate)

                if leftDate != rightDate {
                    return leftDate < rightDate
                }

                if lhs.typeSortOrder != rhs.typeSortOrder {
                    return lhs.typeSortOrder < rhs.typeSortOrder
                }

                let titleOrder = lhs.titleForSort.localizedCaseInsensitiveCompare(
                    rhs.titleForSort
                )

                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }

                return lhs.id < rhs.id
            }
    }
}
