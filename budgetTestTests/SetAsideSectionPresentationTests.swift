import XCTest
@testable import Caldera_Money

final class SetAsideSectionPresentationTests: XCTestCase {

    func testSectionOrderPutsDatedAndFundedWorkBeforeFlexiblePlanning() {
        XCTAssertEqual(
            SetAsideSectionKind.displayOrder,
            [
                .upcomingExpenses,
                .paymentPlans,
                .savingsGoals,
                .cashCushion
            ]
        )
    }

    func testEachSectionUsesDistinctPlainLanguagePurpose() {
        XCTAssertEqual(
            SetAsideSectionPresentation.content(for: .upcomingExpenses).purpose,
            "Dated costs you are preparing for."
        )
        XCTAssertEqual(
            SetAsideSectionPresentation.content(for: .paymentPlans).purpose,
            "Payments you are funding."
        )
        XCTAssertEqual(
            SetAsideSectionPresentation.content(for: .savingsGoals).purpose,
            "Money set aside for something meaningful."
        )
        XCTAssertEqual(
            SetAsideSectionPresentation.content(for: .cashCushion).purpose,
            "Flexible money for the unexpected."
        )
    }

    func testEmptyAndQuickAddCopyNamesTheCorrectDestination() {
        let upcoming = SetAsideSectionPresentation.content(
            for: .upcomingExpenses
        )
        let paymentPlans = SetAsideSectionPresentation.content(
            for: .paymentPlans
        )
        let savingsGoals = SetAsideSectionPresentation.content(
            for: .savingsGoals
        )

        XCTAssertEqual(upcoming.emptyTitle, "No Upcoming Expenses yet")
        XCTAssertEqual(upcoming.quickAddTitle, "Add Upcoming Expense")
        XCTAssertEqual(paymentPlans.emptyTitle, "No Payment Plans yet")
        XCTAssertEqual(paymentPlans.quickAddTitle, "Create Payment Plan")
        XCTAssertEqual(savingsGoals.emptyTitle, "No Savings Goals yet")
        XCTAssertEqual(savingsGoals.quickAddTitle, "Create Savings Goal")
    }
}
