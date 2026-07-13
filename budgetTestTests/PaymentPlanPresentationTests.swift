import XCTest
@testable import Caldera_Money

@MainActor
final class PaymentPlanPresentationTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testNotYetFundedPlanExplainsAmountAndSafeNextStep() {
        let bucket = paymentPlan(
            target: 150,
            setAside: 0,
            dueDate: date(2026, 7, 15),
            choice: .statementBalance
        )
        let display = display(
            bucket: bucket,
            cycle: activeCycle(for: bucket),
            today: date(2026, 7, 10)
        )

        XCTAssertEqual(display.plannedPaymentValue, AppFormatters.currency(150))
        XCTAssertEqual(display.plannedPaymentMeaningValue, "Statement balance")
        XCTAssertEqual(
            display.dueDateValue,
            "Due \(AppFormatters.abbreviatedMonthDay(bucket.dueDate))"
        )
        XCTAssertEqual(display.setAsideValue, AppFormatters.currency(0))
        XCTAssertEqual(
            display.remainingValue,
            "\(AppFormatters.currency(150)) still needed"
        )
        XCTAssertEqual(display.presentationStatus, .notYetFunded)
        XCTAssertEqual(display.presentationStatusValue, "Not yet funded")
        XCTAssertEqual(display.nextActionValue, "Set money aside")
    }

    func testPartlyFundedPlanShowsSetAsideAndRemainingSeparately() {
        let bucket = paymentPlan(
            target: 150,
            setAside: 60,
            dueDate: date(2026, 7, 15),
            choice: .minimumPayment
        )
        let display = display(
            bucket: bucket,
            cycle: activeCycle(for: bucket),
            today: date(2026, 7, 10)
        )

        XCTAssertEqual(display.setAsideValue, AppFormatters.currency(60))
        XCTAssertEqual(
            display.remainingValue,
            "\(AppFormatters.currency(90)) still needed"
        )
        XCTAssertEqual(display.presentationStatus, .partlyFunded)
        XCTAssertEqual(display.nextActionValue, "Add more to Set Aside")
    }

    func testFullyCoveredPlanIsReassuringAndDoesNotCreateAFalseTask() {
        let bucket = paymentPlan(
            target: 150,
            setAside: 150,
            dueDate: date(2026, 7, 15),
            choice: .currentBalance
        )
        let display = display(
            bucket: bucket,
            cycle: activeCycle(for: bucket),
            today: date(2026, 7, 10)
        )

        XCTAssertEqual(display.presentationStatus, .fullyCovered)
        XCTAssertEqual(display.presentationStatusValue, "Fully covered")
        XCTAssertEqual(display.remainingValue, "\(AppFormatters.currency(0)) still needed")
        XCTAssertEqual(display.nextActionValue, "No action needed")
        XCTAssertTrue(display.presentationStatus.isReassuring)
        XCTAssertFalse(
            display.accessibilitySummary.contains("Next: No action needed")
        )
        XCTAssertTrue(
            display.accessibilitySummary.contains("No further action needed.")
        )
    }

    func testPastDuePlansRemainTruthfulWhetherCoveredOrNeedingMoney() {
        let needsMoney = paymentPlan(
            target: 150,
            setAside: 60,
            dueDate: date(2026, 7, 5)
        )
        let covered = paymentPlan(
            target: 150,
            setAside: 150,
            dueDate: date(2026, 7, 5)
        )

        let needsMoneyDisplay = display(
            bucket: needsMoney,
            cycle: activeCycle(for: needsMoney),
            today: date(2026, 7, 10)
        )
        let coveredDisplay = display(
            bucket: covered,
            cycle: activeCycle(for: covered),
            today: date(2026, 7, 10)
        )

        XCTAssertEqual(
            needsMoneyDisplay.presentationStatus,
            .pastDue(isFullyCovered: false)
        )
        XCTAssertEqual(needsMoneyDisplay.presentationStatusValue, "Past due")
        XCTAssertEqual(
            needsMoneyDisplay.nextActionValue,
            "Review past-due plan"
        )
        XCTAssertEqual(
            coveredDisplay.presentationStatus,
            .pastDue(isFullyCovered: true)
        )
        XCTAssertEqual(
            coveredDisplay.presentationStatusValue,
            "Past due · Fully covered"
        )
    }

    func testHandledPlanUsesTheExistingCycleAmountAndNeedsNoMoreMoney() {
        let bucket = paymentPlan(
            target: 175,
            setAside: 0,
            dueDate: date(2026, 7, 5),
            choice: .customAmount
        )
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: 150,
            status: .handled,
            resolution: .paid,
            calendar: calendar
        )
        let display = display(
            bucket: bucket,
            cycle: cycle,
            today: date(2026, 7, 10)
        )

        XCTAssertEqual(display.plannedPaymentValue, AppFormatters.currency(150))
        XCTAssertEqual(display.presentationStatus, .handled)
        XCTAssertEqual(display.presentationStatusValue, "Payment handled")
        XCTAssertEqual(display.remainingValue, "No amount needed")
        XCTAssertEqual(display.nextActionValue, "Plan next payment")
        XCTAssertTrue(
            display.accessibilitySummary.contains("Next: Plan next payment")
        )
    }

    func testMissingPaymentAmountUsesCalmEditState() {
        let bucket = paymentPlan(
            target: 0,
            setAside: 0,
            dueDate: date(2026, 7, 15)
        )
        let display = display(
            bucket: bucket,
            cycle: nil,
            today: date(2026, 7, 10)
        )

        XCTAssertEqual(display.plannedPaymentValue, "Not set")
        XCTAssertEqual(display.presentationStatus, .paymentAmountNeeded)
        XCTAssertEqual(display.presentationStatusValue, "Planned payment needed")
        XCTAssertEqual(display.nextActionValue, "Edit payment plan")
    }

    func testLinkedCardWithoutAnExplicitPaymentAmountDoesNotUseFullBalance() {
        let bucket = paymentPlan(
            target: 0,
            setAside: 0,
            dueDate: date(2026, 7, 15),
            choice: nil
        )
        let linkedAccount = PlaidAccount(
            account_id: bucket.plaidAccountID,
            name: bucket.accountName,
            official_name: nil,
            type: "credit",
            subtype: "credit card",
            mask: nil,
            balances: PlaidBalance(available: nil, current: 900)
        )
        let display = display(
            bucket: bucket,
            cycle: nil,
            today: date(2026, 7, 10),
            linkedAccount: linkedAccount
        )

        XCTAssertEqual(display.plannedPaymentValue, "Not set")
        XCTAssertNotEqual(
            display.plannedPaymentValue,
            AppFormatters.currency(900)
        )
        XCTAssertEqual(display.presentationStatus, .paymentAmountNeeded)
        XCTAssertEqual(display.presentationStatusValue, "Planned payment needed")
    }

    func testOverfundedPlanShowsFullSetAsideAndCapsProgress() {
        let bucket = paymentPlan(
            target: 150,
            setAside: 225,
            dueDate: date(2026, 7, 15)
        )
        let display = display(
            bucket: bucket,
            cycle: activeCycle(for: bucket),
            today: date(2026, 7, 10)
        )

        XCTAssertEqual(display.setAsideValue, AppFormatters.currency(225))
        XCTAssertEqual(display.remainingValue, "\(AppFormatters.currency(0)) still needed")
        XCTAssertEqual(display.presentationStatus, .fullyCovered)
        XCTAssertEqual(display.presentationStatusValue, "Fully covered")
        XCTAssertEqual(display.progressValue, 1)
    }

    func testLegacyPlanRemainsUnderstandableWithoutAStoredTargetChoice() {
        let bucket = paymentPlan(
            target: 150,
            setAside: 75,
            dueDate: date(2026, 7, 15),
            choice: nil
        )
        let display = display(
            bucket: bucket,
            cycle: nil,
            today: date(2026, 7, 10)
        )

        XCTAssertNil(display.targetBasisValue)
        XCTAssertEqual(display.plannedPaymentMeaningValue, "Payment amount")
        XCTAssertEqual(display.presentationStatus, .partlyFunded)
        XCTAssertFalse(display.accessibilitySummary.contains("provenance"))
        XCTAssertFalse(display.accessibilitySummary.contains("legacy"))
    }

    private func display(
        bucket: DebtPayoffBucket,
        cycle: PaymentPlanCycle?,
        today: Date,
        linkedAccount: PlaidAccount? = nil
    ) -> DebtPayoffDisplayModel {
        DebtPayoffDisplayModel(
            bucket: bucket,
            linkedAccount: linkedAccount,
            cycle: cycle,
            today: today,
            calendar: calendar
        )
    }

    private func activeCycle(
        for bucket: DebtPayoffBucket
    ) -> PaymentPlanCycle {
        PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: bucket.paymentTargetAmount,
            calendar: calendar
        )
    }

    private func paymentPlan(
        target: Double,
        setAside: Double,
        dueDate: Date,
        choice: DebtPayoffLinkedCardPaymentTargetChoice? = .statementBalance
    ) -> DebtPayoffBucket {
        DebtPayoffBucket(
            plaidAccountID: "card-1",
            accountName: "Blue Cash",
            dueDate: dueDate,
            paymentTargetAmount: target,
            protectedAmount: setAside,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: choice
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
