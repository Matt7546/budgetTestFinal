#if DEBUG
import Foundation
import SwiftData

/// A Lab-only visual scenario. It deliberately writes the same models that
/// Plan Ahead reads so the timeline exercises occurrence IDs, funding, cycles,
/// and income scheduling without inventing a second forecast system.
enum LabPlanAheadTimelineFixture {
    private enum ID {
        static let pastDueExpense = UUID(uuidString: "A0C88D65-7E4B-4E22-8ED6-3E78D6A1E001")!
        static let coveredExpense = UUID(uuidString: "A0C88D65-7E4B-4E22-8ED6-3E78D6A1E002")!
        static let underfundedExpense = UUID(uuidString: "A0C88D65-7E4B-4E22-8ED6-3E78D6A1E003")!
        static let nextMonthExpense = UUID(uuidString: "A0C88D65-7E4B-4E22-8ED6-3E78D6A1E004")!
        static let paymentPlan = UUID(uuidString: "B1D99E76-8F5C-4F33-9FE7-4F89E7B2F001")!
        static let paymentCycle = UUID(uuidString: "C2EA0F87-9A6D-4054-A0F8-509AF8C3F001")!
        static let income = UUID(uuidString: "D3FB1098-AB7E-4165-B109-61AB09D4F001")!
    }

    static func contains(event: PlannerEvent) -> Bool {
        [
            ID.pastDueExpense,
            ID.coveredExpense,
            ID.underfundedExpense,
            ID.nextMonthExpense
        ].contains(event.id)
    }

    static func contains(paymentPlan: DebtPayoffBucket) -> Bool {
        paymentPlan.id == ID.paymentPlan
    }

    static func contains(incomeSchedule: IncomeSchedule) -> Bool {
        incomeSchedule.id == ID.income
    }

    static func load(
        into context: ModelContext,
        ownerScopeID: String,
        events: [PlannerEvent],
        allocations: [EventAllocation],
        paymentPlans: [DebtPayoffBucket],
        cycles: [PaymentPlanCycle],
        incomeSchedules: [IncomeSchedule],
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        let startOfToday = calendar.startOfDay(for: today)
        let sameDay = calendar.date(byAdding: .day, value: 5, to: startOfToday)!
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfToday)!
        let nextMonthDate = calendar.date(byAdding: .day, value: 8, to: nextMonth)!

        let pastDue = upsertEvent(
            id: ID.pastDueExpense,
            name: "Water bill",
            amount: 145,
            date: calendar.date(byAdding: .day, value: -3, to: startOfToday)!,
            events: events,
            context: context
        )
        let covered = upsertEvent(
            id: ID.coveredExpense,
            name: "Home insurance",
            amount: 240,
            date: sameDay,
            events: events,
            context: context
        )
        let underfunded = upsertEvent(
            id: ID.underfundedExpense,
            name: "Phone bill",
            amount: 96,
            date: sameDay,
            events: events,
            context: context
        )
        let nextMonthEvent = upsertEvent(
            id: ID.nextMonthExpense,
            name: "Annual membership",
            amount: 180,
            date: nextMonthDate,
            events: events,
            context: context
        )

        upsertAllocation(
            for: pastDue,
            amount: 45,
            allocations: allocations,
            context: context
        )
        upsertAllocation(
            for: covered,
            amount: 240,
            allocations: allocations,
            context: context
        )
        upsertAllocation(
            for: underfunded,
            amount: 28,
            allocations: allocations,
            context: context
        )
        upsertAllocation(
            for: nextMonthEvent,
            amount: 0,
            allocations: allocations,
            context: context
        )

        let paymentPlan = upsertPaymentPlan(
            dueDate: nextMonthDate,
            paymentPlans: paymentPlans,
            context: context
        )
        upsertCycle(
            for: paymentPlan,
            dueDate: nextMonthDate,
            cycles: cycles,
            context: context,
            calendar: calendar
        )
        upsertIncome(
            ownerScopeID: ownerScopeID,
            today: startOfToday,
            incomeSchedules: incomeSchedules,
            context: context,
            calendar: calendar
        )

        try? context.save()
    }

    private static func upsertEvent(
        id: UUID,
        name: String,
        amount: Double,
        date: Date,
        events: [PlannerEvent],
        context: ModelContext
    ) -> PlannerEvent {
        let event = events.first(where: { $0.id == id }) ?? PlannerEvent(
            id: id,
            name: name,
            amount: amount,
            date: date,
            type: .expense
        )
        event.name = name
        event.amount = amount
        event.date = date
        event.frequency = .once
        event.type = .expense
        if !events.contains(where: { $0.id == id }) {
            context.insert(event)
        }
        return event
    }

    private static func upsertAllocation(
        for event: PlannerEvent,
        amount: Double,
        allocations: [EventAllocation],
        context: ModelContext
    ) {
        let forecast = ForecastEvent(event: event, occurrenceDate: event.date)
        let allocation = allocations.first(where: { $0.sourceEventID == event.id }) ?? EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: amount
        )
        allocation.occurrenceID = forecast.occurrenceID
        allocation.sourceEventID = event.id
        allocation.occurrenceDate = forecast.normalizedOccurrenceDate
        allocation.allocatedAmount = amount
        allocation.updatedAt = Date()
        if !allocations.contains(where: { $0.sourceEventID == event.id }) {
            context.insert(allocation)
        }
    }

    private static func upsertPaymentPlan(
        dueDate: Date,
        paymentPlans: [DebtPayoffBucket],
        context: ModelContext
    ) -> DebtPayoffBucket {
        let plan = paymentPlans.first(where: { $0.id == ID.paymentPlan }) ?? DebtPayoffBucket(
            id: ID.paymentPlan,
            plaidAccountID: "",
            accountName: "Travel Card",
            dueDate: dueDate,
            dueDateSource: .custom,
            paymentTargetAmount: 380,
            protectedAmount: 140,
            debtKind: .other,
            manualCurrentBalance: 2_400
        )
        plan.accountName = "Travel Card"
        plan.dueDate = dueDate
        plan.dueDateSourceRawValue = PaymentPlanDueDateSource.custom.rawValue
        plan.paymentTargetAmount = 380
        plan.protectedAmount = 140
        plan.debtKind = .other
        plan.manualCurrentBalance = 2_400
        plan.hasPaymentDueDate = true
        if !paymentPlans.contains(where: { $0.id == ID.paymentPlan }) {
            context.insert(plan)
        }
        return plan
    }

    private static func upsertCycle(
        for paymentPlan: DebtPayoffBucket,
        dueDate: Date,
        cycles: [PaymentPlanCycle],
        context: ModelContext,
        calendar: Calendar
    ) {
        let cycle = cycles.first(where: { $0.id == ID.paymentCycle }) ?? PaymentPlanCycle(
            id: ID.paymentCycle,
            paymentPlanID: paymentPlan.id,
            dueDate: dueDate,
            frozenTargetAmount: 380,
            calendar: calendar
        )
        cycle.paymentPlanID = paymentPlan.id
        cycle.dueDate = dueDate
        cycle.dueDayAnchor = calendar.component(.day, from: dueDate)
        cycle.frozenTargetAmount = 380
        cycle.statusRawValue = PaymentPlanCycleStatus.active.rawValue
        cycle.cycleKey = PaymentPlanCycle.identityKey(
            paymentPlanID: paymentPlan.id,
            dueDate: dueDate,
            calendar: calendar
        )
        cycle.updatedAt = Date()
        if !cycles.contains(where: { $0.id == ID.paymentCycle }) {
            context.insert(cycle)
        }
    }

    private static func upsertIncome(
        ownerScopeID: String,
        today: Date,
        incomeSchedules: [IncomeSchedule],
        context: ModelContext,
        calendar: Calendar
    ) {
        let nextPayday = calendar.date(byAdding: .day, value: 3, to: today)!
        let schedule = incomeSchedules.first(where: { $0.id == ID.income }) ?? IncomeSchedule(
            id: ID.income,
            ownerScopeID: ownerScopeID,
            sourceLabel: "Caldera Payroll",
            takeHomeAmountCents: 2_850_00,
            frequency: .monthly,
            lastPaydayDateKey: IncomeScheduleCalendar.dateKey(for: today, calendar: calendar),
            nextExpectedPaydayDateKey: IncomeScheduleCalendar.dateKey(for: nextPayday, calendar: calendar),
            dateBasis: .explicit
        )
        schedule.ownerScopeID = ownerScopeID
        schedule.sourceLabel = "Caldera Payroll"
        schedule.takeHomeAmountCents = 2_850_00
        schedule.frequencyRawValue = IncomeScheduleFrequency.monthly.rawValue
        schedule.lastPaydayDateKey = IncomeScheduleCalendar.dateKey(for: today, calendar: calendar)
        schedule.nextExpectedPaydayDateKey = IncomeScheduleCalendar.dateKey(for: nextPayday, calendar: calendar)
        schedule.dateBasisRawValue = IncomeScheduleDateBasis.explicit.rawValue
        schedule.sortOrder = -10_000
        schedule.updatedAt = Date()
        if !incomeSchedules.contains(where: { $0.id == ID.income }) {
            context.insert(schedule)
        }
    }
}
#endif
