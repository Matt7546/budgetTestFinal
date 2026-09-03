import XCTest
@testable import Caldera_Money

final class PlannerEventRowPresentationTests: XCTestCase {

    func testFullyFundedPastDueExpenseUsesAttentionTimingTone() {
        XCTAssertEqual(
            PlannerExpenseStatusTone.resolve(
                isOverdue: true,
                isCovered: true
            ),
            .attention
        )
    }

    func testFullyFundedPastDueExpenseStillShowsCoveredFundingStatus() {
        XCTAssertEqual(
            PlannerExpenseFundingStatus.resolve(
                isCovered: true,
                remainingAmount: 0
            ),
            .covered
        )
        XCTAssertEqual(
            PlannerExpenseFundingStatus.resolve(
                isCovered: true,
                remainingAmount: 0
            ).text,
            "Covered"
        )
    }

    func testFutureFullyFundedExpenseKeepsCoveredTone() {
        XCTAssertEqual(
            PlannerExpenseStatusTone.resolve(
                isOverdue: false,
                isCovered: true
            ),
            .covered
        )
    }

    func testUnderfundedExpenseKeepsRemainingFundingStatus() {
        let fundingStatus = PlannerExpenseFundingStatus.resolve(
            isCovered: false,
            remainingAmount: 86.50
        )

        XCTAssertEqual(fundingStatus, .stillNeeded(86.50))
        XCTAssertEqual(
            fundingStatus.text,
            "\(AppFormatters.currency(86.50)) still needed"
        )
    }
}
