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

        XCTAssertEqual(upcoming.emptyTitle, "No Bills yet")
        XCTAssertEqual(upcoming.quickAddTitle, "Add Bill")
        XCTAssertEqual(paymentPlans.emptyTitle, "No accounts yet")
        XCTAssertEqual(paymentPlans.quickAddTitle, "Add Credit or Loan")
        XCTAssertEqual(savingsGoals.emptyTitle, "No Goals yet")
        XCTAssertEqual(savingsGoals.quickAddTitle, "Create Goal")
    }

    func testCreditLoanCountCopyUsesNaturalAccountLanguage() {
        let values = [
            CreditLoanPresentationCopy.activeAccountCount(1),
            CreditLoanPresentationCopy.activeAccountCount(2),
            CreditLoanPresentationCopy.plannedPaymentNeeded(1),
            CreditLoanPresentationCopy.plannedPaymentNeeded(2)
        ]

        XCTAssertEqual(values[0], "1 active account")
        XCTAssertEqual(values[1], "2 active accounts")
        XCTAssertEqual(values[2], "1 account needs a planned payment.")
        XCTAssertEqual(values[3], "2 accounts need a planned payment.")
        XCTAssertFalse(values.contains { $0.contains("Credit or Loans") })
    }
}
