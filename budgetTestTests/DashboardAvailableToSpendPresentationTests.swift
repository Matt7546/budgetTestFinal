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

    func testUnavailablePlanningSnapshotIsNotPresentedAsCalculatedZero() {
        let presentation = DashboardAvailableToSpendPresentation.make(
            canShowBankData: true,
            planningSnapshotAvailability: .unavailable,
            safeToSpend: 0
        )

        XCTAssertEqual(
            presentation,
            .planningUnavailable(isLoading: false)
        )
        XCTAssertEqual(presentation.amountText(), "—")
        XCTAssertNotEqual(presentation.amountText(), "$0.00")
        XCTAssertEqual(
            presentation.unavailableGuidance,
            "Your Set Aside plan couldn’t load, so this amount is paused. Your saved plan is unchanged."
        )
    }

    func testLoadingPlanningSnapshotIsDistinctFromSuccessfulEmptyPlan() {
        let loading = DashboardAvailableToSpendPresentation.make(
            canShowBankData: true,
            planningSnapshotAvailability: .loading,
            safeToSpend: 0
        )
        let loaded = DashboardAvailableToSpendPresentation.make(
            canShowBankData: true,
            planningSnapshotAvailability: .available,
            safeToSpend: 0
        )

        XCTAssertEqual(loading, .planningUnavailable(isLoading: true))
        XCTAssertEqual(loading.amountText(), "—")
        XCTAssertEqual(loaded, .calculated(0))
        XCTAssertEqual(loaded.amountText(), "$0.00")
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
