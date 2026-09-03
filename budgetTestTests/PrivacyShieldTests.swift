import XCTest
@testable import Caldera_Money

@MainActor
final class PrivacyShieldTests: XCTestCase {
    func testAmountFormatterShowsNormalValueWhenPrivacyShieldIsOff() {
        XCTAssertEqual(
            SensitiveValueFormatter.amount(1_234.56, isHidden: false),
            AppFormatters.currency(1_234.56)
        )
    }

    func testAmountFormatterHidesValueWhenPrivacyShieldIsOn() {
        XCTAssertEqual(
            SensitiveValueFormatter.amount(1_234.56, isHidden: true),
            SensitiveValueFormatter.hiddenValue
        )
    }

    func testTextFormatterRedactsEachCurrencyValueButKeepsContext() {
        let value = "$125.00 set aside · $75.50 still needed"

        XCTAssertEqual(
            SensitiveValueFormatter.text(value, isHidden: true),
            "•••• set aside · •••• still needed"
        )
    }

    func testTextFormatterHandlesTrailingDollarAndNegativeFormats() {
        XCTAssertEqual(
            SensitiveValueFormatter.text(
                "Down −$40.00 · 1 234,56 $US remaining",
                isHidden: true
            ),
            "Down •••• · •••• remaining"
        )
    }

    func testManualOrScreenSharingStateEnablesPrivacyShield() {
        XCTAssertFalse(
            SensitiveDataVisibility.shouldHide(
                manuallyHidden: false,
                isSceneCaptured: false
            )
        )
        XCTAssertTrue(
            SensitiveDataVisibility.shouldHide(
                manuallyHidden: true,
                isSceneCaptured: false
            )
        )
        XCTAssertTrue(
            SensitiveDataVisibility.shouldHide(
                manuallyHidden: false,
                isSceneCaptured: true
            )
        )
    }

    func testAccountMaskIsHiddenWithoutChangingStoredValue() {
        let storedMask = "••••1234"

        XCTAssertEqual(
            SensitiveValueFormatter.accountMask(
                storedMask,
                isHidden: true
            ),
            SensitiveValueFormatter.hiddenValue
        )
        XCTAssertEqual(storedMask, "••••1234")
    }

    func testCoverInFullConfirmationHidesAmountButKeepsActionContext() {
        let message = CoverInFullPolicy.confirmationMessage(
            amount: 725,
            name: "Vacation"
        )
        let hidden = SensitiveValueFormatter.text(
            message,
            isHidden: true
        )

        XCTAssertTrue(hidden.contains("Vacation"))
        XCTAssertTrue(hidden.contains(SensitiveValueFormatter.hiddenValue))
        XCTAssertFalse(hidden.contains("$725.00"))
        XCTAssertTrue(hidden.contains("no money moves"))
    }
}
