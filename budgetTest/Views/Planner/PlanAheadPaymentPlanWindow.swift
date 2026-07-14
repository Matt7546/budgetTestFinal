import Foundation

enum PlanAheadPaymentPlanWindow {

    static func effectiveDueDate(
        bucketDueDate: Date,
        activeCycle: PaymentPlanCycle?
    ) -> Date {
        activeCycle?.dueDate ?? bucketDueDate
    }

    static func isVisible(
        paymentPlanID: UUID,
        cycles: [PaymentPlanCycle]
    ) -> Bool {
        PaymentPlanCycleStore.isActiveOrLegacy(
            paymentPlanID: paymentPlanID,
            cycles: cycles
        )
    }

    static func isPastDue(
        dueDate: Date,
        startOfToday: Date,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: dueDate) <
            calendar.startOfDay(for: startOfToday)
    }

    static func isDueSoon(
        dueDate: Date,
        startOfToday: Date,
        endOfWindow: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let normalizedDueDate = calendar.startOfDay(for: dueDate)
        let normalizedStart = calendar.startOfDay(for: startOfToday)
        let normalizedEnd = calendar.startOfDay(for: endOfWindow)

        return normalizedDueDate >= normalizedStart &&
            normalizedDueDate <= normalizedEnd
    }
}
