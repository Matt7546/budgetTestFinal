import Foundation
import SwiftUI

struct ForecastEvent: Identifiable {


let id = UUID()
let event: PlannerEvent
let occurrenceDate: Date


}

extension PlannerView {

    var plannerAvailable: Double {

        if protectGoals {

            return summary.totalAvailable
        }

        return summary.totalAvailable
            + summary.totalGoalAllocated
    }
    
var forecastEvents: [ForecastEvent] {

    var generated: [ForecastEvent] = []

    let calendar = Calendar.current

    for event in events {

        if !includeFutureIncome && event.type == .income {
            continue
        }

        switch event.frequency {

        case .once:

            if event.date >= Date() {

                generated.append(
                    ForecastEvent(
                        event: event,
                        occurrenceDate: event.date
                    )
                )
            }

        case .weekly:

            for offset in 0..<12 {

                if let nextDate = calendar.date(
                    byAdding: .weekOfYear,
                    value: offset,
                    to: event.date
                ) {

                    if nextDate >= Date() {

                        generated.append(
                            ForecastEvent(
                                event: event,
                                occurrenceDate: nextDate
                            )
                        )
                    }
                }
            }

        case .monthly:

            for offset in 0..<12 {

                if let nextDate = calendar.date(
                    byAdding: .month,
                    value: offset,
                    to: event.date
                ) {

                    if nextDate >= Date() {

                        generated.append(
                            ForecastEvent(
                                event: event,
                                occurrenceDate: nextDate
                            )
                        )
                    }
                }
            }

        case .yearly:

            for offset in 0..<5 {

                if let nextDate = calendar.date(
                    byAdding: .year,
                    value: offset,
                    to: event.date
                ) {

                    if nextDate >= Date() {

                        generated.append(
                            ForecastEvent(
                                event: event,
                                occurrenceDate: nextDate
                            )
                        )
                    }
                }
            }

        default:
            break
        }
    }

    return generated.sorted {
        $0.occurrenceDate < $1.occurrenceDate
    }
}

var nextExpense: ForecastEvent? {

    forecastEvents.first {
        $0.event.type == .expense
    }
}

var upcomingBills: Double {

    forecastEvents
        .filter { $0.event.type == .expense }
        .prefix(30)
        .reduce(0) { total, forecast in
            total + forecast.event.amount
        }
}

var safeToSpend: Double {

    plannerAvailable - upcomingBills
}

var expensesCovered: Int {

    var remaining = plannerAvailable
    var covered = 0

    let upcomingExpenses =
        forecastEvents
            .filter {
                $0.event.type == .expense
            }

    for forecast in upcomingExpenses {

        if remaining >= forecast.event.amount {

            remaining -= forecast.event.amount
            covered += 1

        } else {

            break
        }
    }

    return covered
}

var plannerStatusText: String {

    if safeToSpend < 0 {
        return "Shortfall Expected"
    }

    if safeToSpend < 500 {
        return "Watch Spending"
    }

    return "On Track"
}

var plannerStatusColor: Color {

    if safeToSpend < 0 {
        return .red
    }

    if safeToSpend < 500 {
        return .orange
    }

    return .green
}

func projectedAvailable(
    for event: PlannerEvent
) -> Double {

    let income =
        forecastEvents
            .filter {
                $0.event.type == .income
            }
            .reduce(0) {
                $0 + $1.event.amount
            }

    let expenses =
        forecastEvents
            .filter {
                $0.event.type == .expense
            }
            .reduce(0) {
                $0 + $1.event.amount
            }

    return plannerAvailable
        + (includeFutureIncome ? income : 0)
        - expenses
}


}
