import XCTest
@testable import Caldera_Money

@MainActor
final class DashboardAvailableToSpendPresentationTests: XCTestCase {

    func testSignedOutPresentationUsesUnavailableAmountInsteadOfZero() {
        let presentation = DashboardAvailableToSpendPresentation.make(
            canShowBankData: false,
            safeToSpend: 0
        )

        XCTAssertEqual(presentation, .unavailable)
        XCTAssertEqual(presentation.amountText(), "—")
        XCTAssertNotEqual(presentation.amountText(), "$0.00")
        XCTAssertEqual(
            presentation.amountText(isSensitiveDataHidden: true),
            "—"
        )
    }

    func testSignedOutPresentationKeepsCalmSignInGuidance() {
        let presentation = DashboardAvailableToSpendPresentation.make(
            canShowBankData: false,
            safeToSpend: 0
        )

        XCTAssertEqual(
            presentation.unavailableGuidance,
            "Sign in and link accounts to estimate from your balances."
        )
        XCTAssertEqual(
            presentation.accessibilityValue(),
            "Not ready yet. Sign in and link accounts to calculate Available to Spend."
        )
    }

    func testAuthenticatedCalculatedZeroRemainsZeroDollars() {
        let presentation = DashboardAvailableToSpendPresentation.make(
            canShowBankData: true,
            safeToSpend: 0
        )

        XCTAssertEqual(presentation, .calculated(0))
        XCTAssertEqual(presentation.amountText(), "$0.00")
        XCTAssertNil(presentation.unavailableGuidance)
    }

    func testCalculatedAmountIsHiddenWhenPrivacyShieldIsOn() {
        let presentation = DashboardAvailableToSpendPresentation.make(
            canShowBankData: true,
            safeToSpend: 642.15
        )

        XCTAssertEqual(
            presentation.amountText(isSensitiveDataHidden: true),
            SensitiveValueFormatter.hiddenValue
        )
        XCTAssertEqual(
            presentation.accessibilityValue(isSensitiveDataHidden: true),
            "Hidden"
        )
    }
}
