import XCTest
import SwiftData
@testable import Caldera_Money

@MainActor
final class PaymentPlanCycleTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCycleIdentityAndActiveUniqueness() {
        let bucket = paymentPlan(dueDate: date(2026, 7, 31))
        let first = PaymentPlanCycleStore.makeActiveCycle(
            for: bucket,
            dueDate: bucket.dueDate,
            targetAmount: 250,
            existingCycles: [],
            calendar: calendar
        )

        let cycle = try! XCTUnwrap(first)
        let duplicate = PaymentPlanCycleStore.makeActiveCycle(
            for: bucket,
            dueDate: bucket.dueDate,
            targetAmount: 250,
            existingCycles: [cycle],
            calendar: calendar
        )

        XCTAssertNil(duplicate)
        XCTAssertEqual(cycle.paymentPlanID, bucket.id)
        XCTAssertEqual(cycle.status, .active)
        XCTAssertEqual(cycle.frozenTargetAmount, 250, accuracy: 0.001)
    }

    func testNewPlanSaveFoundationCreatesOneActiveCycle() throws {
        let bucket = paymentPlan(dueDate: date(2026, 8, 15))
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        context.insert(bucket)

        let cycle = try XCTUnwrap(
            PaymentPlanCycleStore.makeActiveCycle(
                for: bucket,
                dueDate: bucket.dueDate,
                targetAmount: bucket.paymentTargetAmount,
                existingCycles: [],
                calendar: calendar
            )
        )
        context.insert(cycle)
        try context.save()

        let cycles = try context.fetch(FetchDescriptor<PaymentPlanCycle>())
        XCTAssertEqual(cycles.count, 1)
        XCTAssertTrue(cycles[0].isActive)
    }

    func testLegacyPlanRemainsVisibleWithoutCreatingCycle() {
        let legacy = paymentPlan(dueDate: date(2026, 8, 15))
        let cycles: [PaymentPlanCycle] = []

        XCTAssertNil(
            PaymentPlanCycleStore.activeCycle(
                for: legacy.id,
                in: cycles
            )
        )
        XCTAssertTrue(
            PaymentPlanCycleStore.isActiveOrLegacy(
                paymentPlanID: legacy.id,
                cycles: cycles
            )
        )
        XCTAssertEqual(legacy.paymentTargetAmount, 250, accuracy: 0.001)
        XCTAssertEqual(legacy.protectedAmount, 125, accuracy: 0.001)
    }

    func testHandledCycleReleasesSetAsideAndUndoRestoresExactly() {
        let bucket = paymentPlan(dueDate: date(2026, 7, 31))
        let originalUpdatedAt = bucket.updatedAt
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: bucket.paymentTargetAmount,
            calendar: calendar
        )
        let cycleUpdatedAt = cycle.updatedAt

        let undo = PaymentPlanCycleResolutionMutation.apply(
            .paid,
            to: cycle,
            bucket: bucket,
            handledAt: date(2026, 7, 31)
        )

        XCTAssertEqual(cycle.status, .handled)
        XCTAssertEqual(cycle.resolution, .paid)
        XCTAssertEqual(cycle.releasedSetAsideAmount, 125, accuracy: 0.001)
        XCTAssertEqual(bucket.protectedAmount, 0, accuracy: 0.001)
        XCTAssertEqual([bucket].totalProtectedAmount, 0, accuracy: 0.001)

        undo?.restore()

        XCTAssertEqual(cycle.status, .active)
        XCTAssertNil(cycle.resolution)
        XCTAssertNil(cycle.handledAt)
        XCTAssertEqual(cycle.releasedSetAsideAmount, 0, accuracy: 0.001)
        XCTAssertEqual(cycle.updatedAt, cycleUpdatedAt)
        XCTAssertEqual(bucket.protectedAmount, 125, accuracy: 0.001)
        XCTAssertEqual(bucket.updatedAt, originalUpdatedAt)
        XCTAssertEqual([bucket].totalProtectedAmount, 125, accuracy: 0.001)
    }

    func testHandledCycleNoLongerAppearsActiveOrPastDue() {
        let bucket = paymentPlan(dueDate: date(2026, 7, 1))
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: bucket.paymentTargetAmount,
            status: .handled,
            resolution: .paid,
            handledAt: date(2026, 7, 2),
            calendar: calendar
        )

        XCTAssertNil(
            PaymentPlanCycleStore.activeCycle(
                for: bucket.id,
                in: [cycle]
            )
        )
        XCTAssertFalse(
            PaymentPlanCycleStore.isActiveOrLegacy(
                paymentPlanID: bucket.id,
                cycles: [cycle]
            )
        )
    }

    func testPlanNextPaymentCreatesOneCycleOnlyWhenSaved() {
        let bucket = paymentPlan(dueDate: date(2026, 1, 31))
        let handled = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            dueDayAnchor: 31,
            frozenTargetAmount: bucket.paymentTargetAmount,
            status: .handled,
            resolution: .paid,
            handledAt: date(2026, 2, 1),
            calendar: calendar
        )
        let suggestedDueDate = PaymentPlanCycleSchedule.nextMonthlyDueDate(
            after: handled.dueDate,
            anchorDay: handled.dueDayAnchor,
            calendar: calendar
        )

        XCTAssertEqual([handled].count, 1)

        let next = PaymentPlanCycleStore.makeActiveCycle(
            for: bucket,
            dueDate: suggestedDueDate,
            targetAmount: bucket.paymentTargetAmount,
            dueDayAnchor: handled.dueDayAnchor,
            existingCycles: [handled],
            calendar: calendar
        )
        let nextCycle = try! XCTUnwrap(next)
        let duplicate = PaymentPlanCycleStore.makeActiveCycle(
            for: bucket,
            dueDate: suggestedDueDate,
            targetAmount: bucket.paymentTargetAmount,
            dueDayAnchor: handled.dueDayAnchor,
            existingCycles: [handled, nextCycle],
            calendar: calendar
        )

        XCTAssertTrue(nextCycle.isActive)
        XCTAssertNil(duplicate)
    }

    func testMonthEndSchedulePreservesAnchorDay() {
        let january31 = date(2026, 1, 31)
        let february = PaymentPlanCycleSchedule.nextMonthlyDueDate(
            after: january31,
            anchorDay: 31,
            calendar: calendar
        )
        let march = PaymentPlanCycleSchedule.nextMonthlyDueDate(
            after: february,
            anchorDay: 31,
            calendar: calendar
        )

        XCTAssertEqual(dateKey(february), "2026-02-28")
        XCTAssertEqual(dateKey(march), "2026-03-31")
    }

    func testManualAndLinkedPlansRetainTheirExistingIdentityAndProvenance() {
        let linked = paymentPlan(
            plaidAccountID: "card-1",
            dueDate: date(2026, 8, 15),
            kind: .linkedCreditCard,
            choice: .statementBalance
        )
        let manual = paymentPlan(
            plaidAccountID: "",
            dueDate: date(2026, 8, 20),
            kind: .other
        )

        let linkedCycle = PaymentPlanCycleStore.makeActiveCycle(
            for: linked,
            dueDate: linked.dueDate,
            targetAmount: linked.paymentTargetAmount,
            existingCycles: [],
            calendar: calendar
        )
        let manualCycle = PaymentPlanCycleStore.makeActiveCycle(
            for: manual,
            dueDate: manual.dueDate,
            targetAmount: manual.paymentTargetAmount,
            existingCycles: [],
            calendar: calendar
        )

        XCTAssertNotNil(linkedCycle)
        XCTAssertNotNil(manualCycle)
        XCTAssertEqual(linked.paymentTargetChoice, .statementBalance)
        XCTAssertEqual(linked.plaidAccountID, "card-1")
        XCTAssertEqual(manual.debtKind, .other)
        XCTAssertTrue(manual.plaidAccountID.isEmpty)
    }

    private func paymentPlan(
        plaidAccountID: String = "",
        dueDate: Date,
        kind: DebtPayoffKind = .other,
        choice: DebtPayoffLinkedCardPaymentTargetChoice? = nil
    ) -> DebtPayoffBucket {
        DebtPayoffBucket(
            plaidAccountID: plaidAccountID,
            accountName: plaidAccountID.isEmpty ? "Manual payment" : "Linked card",
            dueDate: dueDate,
            paymentTargetAmount: 250,
            protectedAmount: 125,
            debtKind: kind,
            paymentTargetChoice: choice,
            manualCurrentBalance: plaidAccountID.isEmpty ? 1_000 : nil,
            monthlyPayment: kind == .other ? 250 : nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dateKey(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
