import Foundation

enum PlanAheadPresentationMode: String, CaseIterable, Identifiable {
    case cards
    case list

    var id: Self { self }

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .list: return "List"
        }
    }
}

struct PlanAheadPresentationNavigationState: Equatable {
    var selectedMode: PlanAheadPresentationMode
    private(set) var pastDueFocusRequestID: Int

    init(
        selectedMode: PlanAheadPresentationMode = .list,
        pastDueFocusRequestID: Int = 0
    ) {
        self.selectedMode = selectedMode
        self.pastDueFocusRequestID = pastDueFocusRequestID
    }

    mutating func requestPastDueFocus() {
        selectedMode = .list
        pastDueFocusRequestID = pastDueFocusRequestID == Int.max
            ? 1
            : pastDueFocusRequestID + 1
    }
}

enum PlanAheadSummaryHorizon: Int, CaseIterable, Identifiable {
    case days7 = 7
    case days30 = 30
    case days90 = 90

    var id: Int { rawValue }
    var dayCount: Int { rawValue }
    var shortTitle: String { "\(rawValue)d" }
    var title: String { "Next \(rawValue) days" }
}

enum PlanAheadPresentedEventKind: Int, Equatable {
    case upcomingExpense
    case paymentPlan
    case expectedIncome
}

enum PlanAheadPresentedRoute: Equatable {
    case upcomingExpense(eventID: UUID, occurrenceID: String)
    case paymentPlan(paymentPlanID: UUID, cycleID: UUID?)
    case expectedIncome(scheduleID: UUID)
}

enum PlanAheadFundingState: Equatable {
    case covered
    case partial
    case notStarted
    case amountNeeded
}

/// Read-only presentation of authoritative allocation or Payment Plan values.
/// It formats values for Plan Ahead but never creates or mutates funding.
struct PlanAheadFundingPresentation: Equatable {
    let dueAmount: Double?
    let setAsideAmount: Double
    let remainingAmount: Double
    let progress: Double
    let state: PlanAheadFundingState
    let statusLine: String

    static func upcomingExpense(
        amount: Double,
        allocatedAmount: Double
    ) -> Self {
        let target = amount.isFinite ? max(amount, 0) : 0
        let allocation = allocatedAmount.isFinite
            ? min(max(allocatedAmount, 0), target)
            : 0
        let remaining = CoverInFullPolicy.remainingAmount(
            target: target,
            current: allocation
        )
        let progress = target > 0 ? allocation / target : 0

        if remaining <= CoverInFullPolicy.amountTolerance {
            return Self(
                dueAmount: target,
                setAsideAmount: allocation,
                remainingAmount: 0,
                progress: progress,
                state: .covered,
                statusLine: "Covered"
            )
        }

        if allocation > CoverInFullPolicy.amountTolerance {
            return Self(
                dueAmount: target,
                setAsideAmount: allocation,
                remainingAmount: remaining,
                progress: progress,
                state: .partial,
                statusLine: "\(AppFormatters.wholeCurrency(allocation)) set aside · \(AppFormatters.wholeCurrency(remaining)) needed"
            )
        }

        return Self(
            dueAmount: target,
            setAsideAmount: 0,
            remainingAmount: remaining,
            progress: 0,
            state: .notStarted,
            statusLine: "\(AppFormatters.wholeCurrency(remaining)) needed"
        )
    }

    static func paymentPlan(_ display: DebtPayoffDisplayModel) -> Self {
        let target = display.plannedPaymentAmount
        let covered = display.coveredPaymentAmount
        let remaining = display.remainingPaymentAmount
        let progress = target > 0 ? covered / target : 0

        guard target > CoverInFullPolicy.amountTolerance else {
            return Self(
                dueAmount: nil,
                setAsideAmount: covered,
                remainingAmount: remaining,
                progress: 0,
                state: .amountNeeded,
                statusLine: display.presentationStatusValue
            )
        }

        if remaining <= CoverInFullPolicy.amountTolerance {
            return Self(
                dueAmount: target,
                setAsideAmount: covered,
                remainingAmount: 0,
                progress: progress,
                state: .covered,
                statusLine: "Covered"
            )
        }

        if covered > CoverInFullPolicy.amountTolerance {
            return Self(
                dueAmount: target,
                setAsideAmount: covered,
                remainingAmount: remaining,
                progress: progress,
                state: .partial,
                statusLine: "\(AppFormatters.wholeCurrency(covered)) set aside · \(AppFormatters.wholeCurrency(remaining)) needed"
            )
        }

        return Self(
            dueAmount: target,
            setAsideAmount: 0,
            remainingAmount: remaining,
            progress: 0,
            state: .notStarted,
            statusLine: "\(AppFormatters.wholeCurrency(remaining)) needed"
        )
    }

    var summaryEntry: PlanAheadSummaryEntry {
        PlanAheadSummaryEntry(
            dueAmount: dueAmount,
            coveredAmount: setAsideAmount,
            stillNeededAmount: remainingAmount
        )
    }
}

enum PlanAheadPresentedEventSource {
    case upcomingExpense(ForecastEvent)
    case paymentPlan(PlanAheadPaymentPlan, cycle: PaymentPlanCycle?)
    case expectedIncome(IncomeSchedule, date: Date)
}

struct PlanAheadExpectedIncomeUpdate: Identifiable {
    let id: String
    let title: String
    let statusValue: String
    let detail: String
    let route: PlanAheadPresentedRoute
    let schedule: IncomeSchedule
}

struct PlanAheadPresentedEvent: Identifiable {
    let id: String
    let kind: PlanAheadPresentedEventKind
    let typeTitle: String
    let date: Date
    let title: String
    let amountValue: String
    let statusValue: String
    let funding: PlanAheadFundingPresentation?
    let isPastDue: Bool
    let route: PlanAheadPresentedRoute
    let source: PlanAheadPresentedEventSource

}

struct PlanAheadPresentedMonth: Identifiable {
    let date: Date
    let items: [PlanAheadPresentedEvent]

    var id: Date { date }

    func title(relativeTo referenceDate: Date, calendar: Calendar) -> String {
        calendar.isDate(date, equalTo: referenceDate, toGranularity: .month)
            ? "This month"
            : date.formatted(.dateTime.month(.wide).year())
    }
}

struct PlanAheadPresentedDay: Identifiable {
    let date: Date
    let items: [PlanAheadPresentedEvent]

    var id: Date { date }
}

struct PlanAheadProductionComposition {
    let pastDueObligations: [PlanAheadPresentedEvent]
    let upcomingObligations: [PlanAheadPresentedEvent]
    let incoming: [PlanAheadPresentedEvent]
    let expectedIncomeUpdate: PlanAheadExpectedIncomeUpdate?

    var cardsEventIDs: [String] {
        (pastDueObligations + upcomingObligations + incoming).map(\.id) +
            [expectedIncomeUpdate?.id].compactMap { $0 }
    }

    var listEventIDs: [String] {
        (pastDueObligations + upcomingObligations + incoming).map(\.id) +
            [expectedIncomeUpdate?.id].compactMap { $0 }
    }

    func upcomingMonths(
        calendar: Calendar = .current
    ) -> [PlanAheadPresentedMonth] {
        Dictionary(grouping: upcomingObligations) { item in
            calendar.dateComponents([.year, .month], from: item.date)
        }
        .compactMap { components, items in
            guard let date = calendar.date(from: components) else { return nil }
            return PlanAheadPresentedMonth(
                date: date,
                items: items.sorted(by: Self.eventSort)
            )
        }
        .sorted { $0.date < $1.date }
    }

    func groupedPastDue(
        calendar: Calendar = .current
    ) -> [PlanAheadPresentedDay] {
        Self.group(pastDueObligations, calendar: calendar)
    }

    func groupedUpcomingIncludingIncome(
        calendar: Calendar = .current
    ) -> [PlanAheadPresentedDay] {
        Self.group(upcomingObligations + incoming, calendar: calendar)
    }

    func summary(
        for horizon: PlanAheadSummaryHorizon,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> PlanAheadSummaryPresentation {
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(
            byAdding: .day,
            value: horizon.dayCount,
            to: start
        ) ?? start
        let entries = upcomingObligations.compactMap { item -> PlanAheadSummaryEntry? in
            let day = calendar.startOfDay(for: item.date)
            guard day >= start, day <= end else { return nil }
            return item.funding?.summaryEntry
        }

        return PlanAheadSummaryPresentation(
            entries: entries,
            pastDueCount: pastDueObligations.count,
            periodTitle: horizon.title
        )
    }

    private static func group(
        _ items: [PlanAheadPresentedEvent],
        calendar: Calendar
    ) -> [PlanAheadPresentedDay] {
        struct MutableDay {
            let date: Date
            var items: [PlanAheadPresentedEvent]
        }

        var groups: [MutableDay] = []
        for item in items.sorted(by: eventSort) {
            let day = calendar.startOfDay(for: item.date)
            if let index = groups.indices.last,
               calendar.isDate(groups[index].date, inSameDayAs: day) {
                groups[index].items.append(item)
            } else {
                groups.append(MutableDay(date: day, items: [item]))
            }
        }
        return groups.map {
            PlanAheadPresentedDay(date: $0.date, items: $0.items)
        }
    }

    nonisolated fileprivate static func eventSort(
        _ lhs: PlanAheadPresentedEvent,
        _ rhs: PlanAheadPresentedEvent
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}

enum PlanAheadProductionCompositionBuilder {
    static func make(
        pastDueItems: [PlanAheadTimelineItem],
        upcomingItems: [PlanAheadTimelineItem],
        allocationAmounts: EventAllocationAmountLookup,
        accountByID: [String: PlaidAccount],
        cycles: [PaymentPlanCycle],
        expectedIncomeSchedule: IncomeSchedule?,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> PlanAheadProductionComposition {
        let pastDue = unique(
            pastDueItems.map {
                presentedEvent(
                    from: $0,
                    isPastDue: true,
                    allocationAmounts: allocationAmounts,
                    accountByID: accountByID,
                    cycles: cycles,
                    today: today,
                    calendar: calendar
                )
            }
        )
        .sorted(by: PlanAheadProductionComposition.eventSort)

        let upcoming = unique(
            upcomingItems.map {
                presentedEvent(
                    from: $0,
                    isPastDue: false,
                    allocationAmounts: allocationAmounts,
                    accountByID: accountByID,
                    cycles: cycles,
                    today: today,
                    calendar: calendar
                )
            }
        )
        .sorted(by: PlanAheadProductionComposition.eventSort)

        let incoming: [PlanAheadPresentedEvent]
        let expectedIncomeUpdate: PlanAheadExpectedIncomeUpdate?
        if let schedule = expectedIncomeSchedule,
           let date = IncomeScheduleCalendar.nextDisplayDate(
            for: schedule,
            today: today,
            calendar: calendar
           ) {
            let isPastDue = calendar.startOfDay(for: date) <
                calendar.startOfDay(for: today)
            incoming = [
                PlanAheadPresentedEvent(
                    id: "expected-income-\(schedule.id.uuidString)-\(IncomeScheduleCalendar.dateKey(for: date))",
                    kind: .expectedIncome,
                    typeTitle: "Expected Income",
                    date: date,
                    title: schedule.sourceLabel,
                    amountValue: AppFormatters.currency(schedule.takeHomeAmount),
                    statusValue: "Planning estimate",
                    funding: nil,
                    isPastDue: isPastDue,
                    route: .expectedIncome(scheduleID: schedule.id),
                    source: .expectedIncome(schedule, date: date)
                )
            ]
            expectedIncomeUpdate = nil
        } else if let schedule = expectedIncomeSchedule,
                  IncomeScheduleCalendar.needsExplicitPaydayUpdate(
                    schedule,
                    today: today,
                    calendar: calendar
                  ) {
            incoming = []
            expectedIncomeUpdate = PlanAheadExpectedIncomeUpdate(
                id: "expected-income-update-\(schedule.id.uuidString)",
                title: schedule.sourceLabel,
                statusValue: "Update your next payday",
                detail: "Your saved next payday has passed. Tap to update it before relying on this plan.",
                route: .expectedIncome(scheduleID: schedule.id),
                schedule: schedule
            )
        } else {
            incoming = []
            expectedIncomeUpdate = nil
        }

        return PlanAheadProductionComposition(
            pastDueObligations: pastDue,
            upcomingObligations: upcoming,
            incoming: incoming,
            expectedIncomeUpdate: expectedIncomeUpdate
        )
    }

    private static func presentedEvent(
        from item: PlanAheadTimelineItem,
        isPastDue: Bool,
        allocationAmounts: EventAllocationAmountLookup,
        accountByID: [String: PlaidAccount],
        cycles: [PaymentPlanCycle],
        today: Date,
        calendar: Calendar
    ) -> PlanAheadPresentedEvent {
        switch item {
        case .upcomingExpense(let forecast):
            let funding = PlanAheadFundingPresentation.upcomingExpense(
                amount: forecast.event.amount,
                allocatedAmount: allocationAmounts.allocatedAmount(for: forecast)
            )
            return PlanAheadPresentedEvent(
                id: item.id,
                kind: .upcomingExpense,
                typeTitle: "Bill",
                date: forecast.occurrenceDate,
                title: forecast.event.name,
                amountValue: AppFormatters.currency(forecast.event.amount),
                statusValue: isPastDue ? "Past Due" : funding.statusLine,
                funding: funding,
                isPastDue: isPastDue,
                route: .upcomingExpense(
                    eventID: forecast.event.id,
                    occurrenceID: forecast.occurrenceID
                ),
                source: .upcomingExpense(forecast)
            )

        case .paymentPlan(let paymentPlan):
            let cycle = PaymentPlanCycleStore.activeCycle(
                for: paymentPlan.bucket.id,
                in: cycles
            )
            let display = DebtPayoffDisplayModel(
                bucket: paymentPlan.bucket,
                linkedAccount: accountByID[paymentPlan.bucket.plaidAccountID],
                cycle: cycle,
                today: today,
                calendar: calendar
            )
            let funding = PlanAheadFundingPresentation.paymentPlan(display)
            return PlanAheadPresentedEvent(
                id: item.id,
                kind: .paymentPlan,
                typeTitle: CreditLoanPresentationType(
                    bucket: paymentPlan.bucket,
                    linkedAccount: accountByID[paymentPlan.bucket.plaidAccountID]
                ).title,
                date: paymentPlan.dueDate,
                title: display.title,
                amountValue: display.plannedPaymentValue,
                statusValue: isPastDue ? "Past Due" : display.presentationStatusValue,
                funding: funding,
                isPastDue: isPastDue,
                route: .paymentPlan(
                    paymentPlanID: paymentPlan.bucket.id,
                    cycleID: cycle?.id
                ),
                source: .paymentPlan(paymentPlan, cycle: cycle)
            )
        }
    }

    private static func unique(
        _ items: [PlanAheadPresentedEvent]
    ) -> [PlanAheadPresentedEvent] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

enum PlanAheadCardLayout {
    static func columnCount(isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? 1 : 2
    }
}
