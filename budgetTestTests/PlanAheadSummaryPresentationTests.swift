import XCTest
@testable import Caldera_Money

final class PlanAheadSummaryPresentationTests: XCTestCase {

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
}
