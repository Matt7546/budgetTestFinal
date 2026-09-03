import XCTest
@testable import Caldera_Money

final class CoverInFullPolicyTests: XCTestCase {

    func testPartialFundingReturnsExactRemainingAmount() {
        XCTAssertEqual(
            CoverInFullPolicy.remainingAmount(
                target: 1_000,
                current: 275
            ),
            725,
            accuracy: 0.001
        )
    }

    func testFullyCoveredAndOverTargetAmountsReturnZero() {
        XCTAssertEqual(
            CoverInFullPolicy.remainingAmount(
                target: 500,
                current: 500
            ),
            0
        )
        XCTAssertEqual(
            CoverInFullPolicy.remainingAmount(
                target: 500,
                current: 725
            ),
            0
        )
    }

    func testCurrencyToleranceTreatsTinyRemainderAsCovered() {
        XCTAssertEqual(
            CoverInFullPolicy.remainingAmount(
                target: 100,
                current: 99.996
            ),
            0
        )
        XCTAssertEqual(
            CoverInFullPolicy.remainingAmount(
                target: 100,
                current: 99.994
            ),
            0.006,
            accuracy: 0.0001
        )
    }

    func testConfirmationExplainsPlanningOnlyImpact() {
        XCTAssertEqual(
            CoverInFullPolicy.confirmationMessage(
                amount: 725,
                name: "Rent"
            ),
            "Set aside $725.00 to cover Rent in full? This updates your plan; no money moves."
        )
    }

    func testSuccessMessageUsesItemName() {
        XCTAssertEqual(
            CoverInFullPolicy.successMessage(name: "Rent"),
            "Rent fully covered"
        )
    }

    func testEarlyHoldReleaseDoesNotComplete() {
        var gate = HoldToConfirmActionGate()

        XCTAssertTrue(gate.begin())
        gate.cancel()

        XCTAssertFalse(gate.complete())
        XCTAssertFalse(gate.didComplete)
        XCTAssertTrue(gate.didCancel)
        XCTAssertFalse(gate.begin())

        gate.reset()
        XCTAssertTrue(gate.begin())
    }

    func testCompletedHoldTriggersOnce() {
        var gate = HoldToConfirmActionGate()

        XCTAssertTrue(gate.begin())
        XCTAssertTrue(gate.complete())
        XCTAssertFalse(gate.complete())
        XCTAssertFalse(gate.begin())

        gate.reset()
        XCTAssertTrue(gate.begin())
    }
}
