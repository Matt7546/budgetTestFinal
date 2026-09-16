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

    func testPlanAheadListStandardPartialStatusMasksCurrency() {
        assertPlanAheadFundingStatusIsMasked(
            PlanAheadFundingPresentation.upcomingExpense(
                amount: 120,
                allocatedAmount: 45
            ).statusLine
        )
    }

    func testPlanAheadListAccessibilityStatusMasksCurrency() {
        assertPlanAheadFundingStatusIsMasked(
            "$40 set aside · $160 needed"
        )
    }

    func testPlanAheadCardsStatusMasksCurrency() {
        assertPlanAheadFundingStatusIsMasked(
            PlanAheadFundingPresentation.upcomingExpense(
                amount: 100,
                allocatedAmount: 0
            ).statusLine
        )
    }

    func testPlanAheadPastDueStatusMasksCurrencyAndKeepsContext() {
        let status = "Past Due · " + PlanAheadFundingPresentation
            .upcomingExpense(amount: 120, allocatedAmount: 45)
            .statusLine
        let hidden = SensitiveValueFormatter.text(status, isHidden: true)

        XCTAssertTrue(hidden.contains("Past Due"))
        XCTAssertTrue(hidden.contains("set aside"))
        XCTAssertTrue(hidden.contains("needed"))
        XCTAssertFalse(hidden.contains(AppFormatters.wholeCurrency(45)))
        XCTAssertFalse(hidden.contains(AppFormatters.wholeCurrency(75)))
    }

    func testPlanAheadVoiceOverAndCaptureProtectionDoNotLeakAmounts() {
        let status = PlanAheadFundingPresentation.upcomingExpense(
            amount: 120,
            allocatedAmount: 45
        ).statusLine
        let accessibilityLabel =
            "Upcoming Expense, Water bill, $120.00, due September 12 2026, \(status)"
        let captureRequiresMasking = SensitiveDataVisibility.shouldHide(
            manuallyHidden: false,
            isSceneCaptured: true
        )
        let hidden = SensitiveValueFormatter.text(
            accessibilityLabel,
            isHidden: captureRequiresMasking
        )

        XCTAssertTrue(captureRequiresMasking)
        XCTAssertFalse(hidden.contains("$120.00"))
        XCTAssertFalse(hidden.contains(AppFormatters.wholeCurrency(45)))
        XCTAssertFalse(hidden.contains(AppFormatters.wholeCurrency(75)))
        XCTAssertTrue(hidden.contains("Water bill"))
    }

    private func assertPlanAheadFundingStatusIsMasked(
        _ status: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let hidden = SensitiveValueFormatter.text(status, isHidden: true)

        XCTAssertTrue(
            hidden.contains(SensitiveValueFormatter.hiddenValue),
            file: file,
            line: line
        )
        XCTAssertFalse(hidden.contains("$"), file: file, line: line)
    }
}
