import XCTest
@testable import Caldera_Money

final class PlanAheadSummaryPresentationTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCombinedUpcomingExpenseAndPaymentPlanUseProvidedValues() {
        let presentation = PlanAheadSummaryPresentation(
            entries: [
                entry(due: 120, covered: 20, needed: 100),
                entry(due: 150, covered: 60, needed: 90)
            ],
            pastDueCount: 0
        )

        XCTAssertEqual(presentation.dueSoonAmount, 270, accuracy: 0.001)
        XCTAssertEqual(presentation.coveredAmount, 80, accuracy: 0.001)
        XCTAssertEqual(presentation.stillNeededAmount, 190, accuracy: 0.001)
        XCTAssertEqual(presentation.state, .partlyCovered)
        XCTAssertEqual(presentation.stateTitle, "Partly covered")
    }

    func testFullyCoveredStateIsReassuring() {
        let presentation = PlanAheadSummaryPresentation(
            entries: [entry(due: 270, covered: 270, needed: 0)],
            pastDueCount: 0
        )

        XCTAssertEqual(presentation.state, .fullyCovered)
        XCTAssertEqual(presentation.stateTitle, "Fully covered")
        XCTAssertEqual(presentation.detail, "Everything due soon is covered.")
        XCTAssertTrue(
            presentation.accessibilitySummary.contains("Fully covered")
        )
    }

    func testNothingDueSoonHasCalmZeroState() {
        let presentation = PlanAheadSummaryPresentation(
            entries: [],
            pastDueCount: 0
        )

        XCTAssertEqual(presentation.state, .nothingDueSoon)
        XCTAssertEqual(presentation.stateTitle, "Nothing due soon")
        XCTAssertEqual(presentation.dueSoonAmount, 0, accuracy: 0.001)
        XCTAssertEqual(presentation.detail, "No Upcoming Expenses or Payment Plans in the next 30 days.")
    }

    func testPastDueCountOverridesCoverageState() {
        let presentation = PlanAheadSummaryPresentation(
            entries: [entry(due: 120, covered: 120, needed: 0)],
            pastDueCount: 2
        )

        XCTAssertEqual(presentation.pastDueCount, 2)
        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.detail, "2 items are past due.")
        XCTAssertTrue(
            presentation.accessibilitySummary.contains("2 items are past due.")
        )
    }

    func testMissingPaymentAmountDoesNotInventDueAmount() {
        let presentation = PlanAheadSummaryPresentation(
            entries: [
                entry(due: 100, covered: 25, needed: 75),
                PlanAheadSummaryEntry(
                    dueAmount: nil,
                    coveredAmount: 0,
                    stillNeededAmount: 0
                )
            ],
            pastDueCount: 0
        )

        XCTAssertEqual(presentation.dueSoonAmount, 100, accuracy: 0.001)
        XCTAssertEqual(presentation.missingAmountCount, 1)
        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(
            presentation.detail,
            "1 Payment Plan needs a planned payment."
        )
    }

    func testActiveCycleDueDateOverridesBucketDueDate() {
        let bucketDueDate = date(2026, 7, 20)
        let cycleDueDate = date(2026, 7, 5)
        let cycle = PaymentPlanCycle(
            paymentPlanID: UUID(),
            dueDate: cycleDueDate,
            frozenTargetAmount: 100,
            calendar: calendar
        )

        XCTAssertEqual(
            PlanAheadPaymentPlanWindow.effectiveDueDate(
                bucketDueDate: bucketDueDate,
                activeCycle: cycle
            ),
            cycleDueDate
        )
    }

    func testActiveCycleDateInsideWindowOverridesBucketDateOutside() {
        let start = date(2026, 7, 10)
        let end = date(2026, 8, 9)
        let cycle = PaymentPlanCycle(
            paymentPlanID: UUID(),
            dueDate: date(2026, 7, 15),
            frozenTargetAmount: 100,
            calendar: calendar
        )
        let effectiveDueDate = PlanAheadPaymentPlanWindow.effectiveDueDate(
            bucketDueDate: date(2026, 8, 10),
            activeCycle: cycle
        )

        XCTAssertTrue(
            PlanAheadPaymentPlanWindow.isDueSoon(
                dueDate: effectiveDueDate,
                startOfToday: start,
                endOfWindow: end,
                calendar: calendar
            )
        )
    }

    func testActiveCycleDateOutsideWindowOverridesBucketDateInside() {
        let start = date(2026, 7, 10)
        let end = date(2026, 8, 9)
        let cycle = PaymentPlanCycle(
            paymentPlanID: UUID(),
            dueDate: date(2026, 8, 10),
            frozenTargetAmount: 100,
            calendar: calendar
        )
        let effectiveDueDate = PlanAheadPaymentPlanWindow.effectiveDueDate(
            bucketDueDate: date(2026, 7, 15),
            activeCycle: cycle
        )

        XCTAssertFalse(
            PlanAheadPaymentPlanWindow.isDueSoon(
                dueDate: effectiveDueDate,
                startOfToday: start,
                endOfWindow: end,
                calendar: calendar
            )
        )
    }

    func testHandledCycleRemainsExcludedFromPlanAhead() {
        let paymentPlanID = UUID()
        let handledCycle = PaymentPlanCycle(
            paymentPlanID: paymentPlanID,
            dueDate: date(2026, 7, 5),
            frozenTargetAmount: 100,
            status: .handled,
            resolution: .paid,
            calendar: calendar
        )

        XCTAssertFalse(
            PlanAheadPaymentPlanWindow.isVisible(
                paymentPlanID: paymentPlanID,
                cycles: [handledCycle]
            )
        )
    }

    func testPastDueAndDueSoonAreMutuallyExclusiveAtInclusiveBoundaries() {
        let start = date(2026, 7, 10)
        let end = date(2026, 8, 9)
        let dates = [date(2026, 7, 9), start, end]

        XCTAssertTrue(
            PlanAheadPaymentPlanWindow.isPastDue(
                dueDate: dates[0],
                startOfToday: start,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            PlanAheadPaymentPlanWindow.isDueSoon(
                dueDate: dates[0],
                startOfToday: start,
                endOfWindow: end,
                calendar: calendar
            )
        )

        for dueDate in dates.dropFirst() {
            XCTAssertTrue(
                PlanAheadPaymentPlanWindow.isDueSoon(
                    dueDate: dueDate,
                    startOfToday: start,
                    endOfWindow: end,
                    calendar: calendar
                )
            )
            XCTAssertFalse(
                PlanAheadPaymentPlanWindow.isPastDue(
                    dueDate: dueDate,
                    startOfToday: start,
                    calendar: calendar
                )
            )
        }
    }

    private func entry(
        due: Double,
        covered: Double,
        needed: Double
    ) -> PlanAheadSummaryEntry {
        PlanAheadSummaryEntry(
            dueAmount: due,
            coveredAmount: covered,
            stillNeededAmount: needed
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )
        )!
    }
}
