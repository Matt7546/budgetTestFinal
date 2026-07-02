import Foundation

struct ForecastEvent: Identifiable {

    let event: PlannerEvent
    let occurrenceDate: Date

    private static let occurrenceCalendar = Calendar(
        identifier: .gregorian
    )

    var id: String {
        occurrenceID
    }

    var occurrenceID: String {
        "\(event.id.uuidString)_\(occurrenceDateKey)"
    }

    var normalizedOccurrenceDate: Date {
        Self.occurrenceCalendar.startOfDay(
            for: occurrenceDate
        )
    }

    private var occurrenceDateKey: String {
        let components = Self.occurrenceCalendar.dateComponents(
            [
                .year,
                .month,
                .day
            ],
            from: normalizedOccurrenceDate
        )

        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

enum PlannerForecastStatus {
    case safeThrough(Date)
    case nextExpenseCovered
    case enoughForNextExpense
    case lowBufferUntilPayday
    case protectedByReserve
    case shortfallBefore(String)
    case noUpcomingExpenses

    var text: String {
        switch self {
        case .safeThrough(let date):
            return "Covered Through \(AppFormatters.abbreviatedMonthDay(date))"

        case .nextExpenseCovered:
            return "Next expense covered"

        case .enoughForNextExpense:
            return "Enough available for next expense"

        case .lowBufferUntilPayday:
            return "Low Buffer Until Payday"

        case .protectedByReserve:
            return "Covered By Cash Cushion"

        case .shortfallBefore(let expenseName):
            return "Needs Money Before \(expenseName)"

        case .noUpcomingExpenses:
            return "No Upcoming Expenses"
        }
    }
}

struct PlannerForecastCalculator {

    let events: [PlannerEvent]
    let totalAvailable: Double
    let totalGoalAllocated: Double
    let reserveBalance: Double
    let protectedEventAllocations: Double
    let includeFutureIncome: Bool
    let protectGoals: Bool
    let now: Date
    let calendar: Calendar
    let allocatedAmountProvider: ((ForecastEvent) -> Double)?
    let inactiveOccurrenceIDs: Set<String>
    let forecastEvents: [ForecastEvent]

    init(
        events: [PlannerEvent],
        totalAvailable: Double,
        totalGoalAllocated: Double,
        reserveBalance: Double = 0,
        protectedEventAllocations: Double = 0,
        includeFutureIncome: Bool,
        protectGoals: Bool,
        now: Date = Date(),
        calendar: Calendar = .current,
        allocatedAmountProvider: ((ForecastEvent) -> Double)? = nil,
        inactiveOccurrenceIDs: Set<String> = []
    ) {
        self.events = events
        self.totalAvailable = totalAvailable
        self.totalGoalAllocated = totalGoalAllocated
        self.reserveBalance = reserveBalance
        self.protectedEventAllocations = protectedEventAllocations
        self.includeFutureIncome = includeFutureIncome
        self.protectGoals = protectGoals
        self.now = now
        self.calendar = calendar
        self.allocatedAmountProvider = allocatedAmountProvider
        self.inactiveOccurrenceIDs = inactiveOccurrenceIDs
        self.forecastEvents = Self.makeForecastEvents(
            events: events,
            includeFutureIncome: includeFutureIncome,
            now: now,
            calendar: calendar,
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
    }

    var plannerAvailable: Double {
        if protectGoals {
            return totalAvailable - protectedEventAllocations
        }

        return totalAvailable + totalGoalAllocated - protectedEventAllocations
    }

    private static func makeForecastEvents(
        events: [PlannerEvent],
        includeFutureIncome: Bool,
        now: Date,
        calendar: Calendar,
        inactiveOccurrenceIDs: Set<String>
    ) -> [ForecastEvent] {
        var generated: [ForecastEvent] = []

        for event in events {
            if !includeFutureIncome && event.type == .income {
                continue
            }

            switch event.frequency {
            case .once:
                appendOccurrence(
                    event,
                    on: event.date,
                    to: &generated
                )

            case .weekly:
                appendRecurringOccurrences(
                    event,
                    component: .weekOfYear,
                    futureCount: 12,
                    now: now,
                    calendar: calendar,
                    to: &generated
                )

            case .biweekly:
                appendRecurringOccurrences(
                    event,
                    component: .day,
                    futureCount: 12,
                    step: 14,
                    now: now,
                    calendar: calendar,
                    to: &generated
                )

            case .monthly:
                appendAnchoredMonthOccurrences(
                    event,
                    monthStep: 1,
                    futureCount: 12,
                    now: now,
                    calendar: calendar,
                    to: &generated
                )

            case .quarterly:
                appendAnchoredMonthOccurrences(
                    event,
                    monthStep: 3,
                    futureCount: 8,
                    now: now,
                    calendar: calendar,
                    to: &generated
                )

            case .yearly:
                appendRecurringOccurrences(
                    event,
                    component: .year,
                    futureCount: 5,
                    now: now,
                    calendar: calendar,
                    to: &generated
                )
            }
        }

        return generated
            .filter {
                !inactiveOccurrenceIDs.contains($0.occurrenceID)
            }
            .sorted {
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
            .filter {
                $0.event.type == .expense
            }
            .prefix(30)
            .reduce(0) { total, forecast in
                total + forecast.event.amount
            }
    }

    var safeToSpend: Double {
        plannerAvailable
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

    var status: PlannerForecastStatus {
        guard let nextExpense else {
            return .noUpcomingExpenses
        }

        let allocatedAmount = allocatedAmountProvider?(nextExpense) ?? 0
        let remainingAmount = max(
            nextExpense.event.amount - allocatedAmount,
            0
        )

        if remainingAmount <= 0.005 {
            return .nextExpenseCovered
        }

        if safeToSpend >= remainingAmount {
            return .enoughForNextExpense
        }

        if safeToSpend < 0 {
            return .shortfallBefore(nextExpense.event.name)
        }

        if reserveBalance > 0,
           safeToSpend < 500,
           safeToSpend + reserveBalance >= 500 {
            return .protectedByReserve
        }

        if safeToSpend < 500 {
            return .lowBufferUntilPayday
        }

        return .safeThrough(nextExpense.occurrenceDate)
    }

    var plannerStatusText: String {
        status.text
    }

    func projectedAvailable(
        after forecast: ForecastEvent
    ) -> Double {

        var balance = plannerAvailable

        for occurrence in forecastEvents {

            switch occurrence.event.type {
            case .income:
                balance += occurrence.event.amount

            case .expense:
                balance -= occurrence.event.amount
            }

            if occurrence.id == forecast.id {
                return balance
            }
        }

        return balance
    }

    private static func appendRecurringOccurrences(
        _ event: PlannerEvent,
        component: Calendar.Component,
        futureCount: Int,
        step: Int = 1,
        now: Date,
        calendar: Calendar,
        to generated: inout [ForecastEvent]
    ) {
        let startOfToday = calendar.startOfDay(for: now)
        var occurrenceDate = event.date
        var mostRecentPastDate: Date?
        var iterationCount = 0

        while calendar.startOfDay(for: occurrenceDate) < startOfToday,
              iterationCount < 600 {
            mostRecentPastDate = occurrenceDate

            guard let nextDate = calendar.date(
                byAdding: component,
                value: step,
                to: occurrenceDate
            ) else {
                break
            }

            occurrenceDate = nextDate
            iterationCount += 1
        }

        if let mostRecentPastDate {
            appendOccurrence(
                event,
                on: mostRecentPastDate,
                to: &generated
            )
        }

        for _ in 0..<futureCount {
            appendOccurrence(
                event,
                on: occurrenceDate,
                to: &generated
            )

            guard let nextDate = calendar.date(
                byAdding: component,
                value: step,
                to: occurrenceDate
            ) else {
                break
            }

            occurrenceDate = nextDate
        }
    }

    private static func appendAnchoredMonthOccurrences(
        _ event: PlannerEvent,
        monthStep: Int,
        futureCount: Int,
        now: Date,
        calendar: Calendar,
        to generated: inout [ForecastEvent]
    ) {
        let startOfToday = calendar.startOfDay(for: now)
        var offset = 0
        var mostRecentPastDate: Date?

        while let occurrenceDate = anchoredMonthOccurrenceDate(
            for: event,
            offset: offset,
            monthStep: monthStep,
            calendar: calendar
        ),
              calendar.startOfDay(for: occurrenceDate) < startOfToday,
              offset < 600 {
            mostRecentPastDate = occurrenceDate
            offset += 1
        }

        if let mostRecentPastDate {
            appendOccurrence(
                event,
                on: mostRecentPastDate,
                to: &generated
            )
        }

        for futureOffset in offset..<(offset + futureCount) {
            guard let occurrenceDate = anchoredMonthOccurrenceDate(
                for: event,
                offset: futureOffset,
                monthStep: monthStep,
                calendar: calendar
            ) else {
                break
            }

            appendOccurrence(
                event,
                on: occurrenceDate,
                to: &generated
            )
        }
    }

    private static func anchoredMonthOccurrenceDate(
        for event: PlannerEvent,
        offset: Int,
        monthStep: Int,
        calendar: Calendar
    ) -> Date? {
        let anchorComponents = calendar.dateComponents(
            [
                .year,
                .month,
                .day,
                .hour,
                .minute,
                .second,
                .nanosecond
            ],
            from: event.date
        )

        guard let anchorMonthDate = calendar.date(
            from: DateComponents(
                year: anchorComponents.year,
                month: anchorComponents.month,
                day: 1,
                hour: anchorComponents.hour,
                minute: anchorComponents.minute,
                second: anchorComponents.second,
                nanosecond: anchorComponents.nanosecond
            )
        ),
              let targetMonthDate = calendar.date(
                byAdding: .month,
                value: offset * monthStep,
                to: anchorMonthDate
              ),
              let dayRange = calendar.range(
                of: .day,
                in: .month,
                for: targetMonthDate
              )
        else {
            return nil
        }

        let intendedDay = anchorComponents.day ?? 1
        let clampedDay = min(
            intendedDay,
            dayRange.count
        )
        let targetMonthComponents = calendar.dateComponents(
            [
                .year,
                .month
            ],
            from: targetMonthDate
        )

        return calendar.date(
            from: DateComponents(
                year: targetMonthComponents.year,
                month: targetMonthComponents.month,
                day: clampedDay,
                hour: anchorComponents.hour,
                minute: anchorComponents.minute,
                second: anchorComponents.second,
                nanosecond: anchorComponents.nanosecond
            )
        )
    }

    private static func appendOccurrence(
        _ event: PlannerEvent,
        on date: Date,
        to generated: inout [ForecastEvent]
    ) {
        generated.append(
            ForecastEvent(
                event: event,
                occurrenceDate: date
            )
        )
    }
}
