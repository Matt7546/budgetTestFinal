import XCTest
@testable import Caldera_Money

@MainActor
final class EditPaymentPlanTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testAddSetAsideUsesDecimalChangeAndPreservesTarget() throws {
        let bucket = paymentPlan(
            target: 500,
            protectedAmount: 100
        )
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        input.setAsideChangeMode = .add
        input.setAsideAmountText = "$125.25"

        XCTAssertTrue(input.hasValidChange)
        XCTAssertEqual(
            try XCTUnwrap(input.projectedSetAsideAmount),
            225.25,
            accuracy: 0.001
        )
        XCTAssertEqual(input.remainingAmount, 274.75, accuracy: 0.001)

        let draft = try XCTUnwrap(
            input.draft(
                for: bucket,
                calendar: calendar
            )
        )
        XCTAssertEqual(draft.protectedAmount, 225.25, accuracy: 0.001)
        XCTAssertEqual(draft.paymentTargetAmount, 500, accuracy: 0.001)
    }

    func testUseSetAsideCannotExceedExistingAmount() throws {
        let bucket = paymentPlan(
            target: 500,
            protectedAmount: 300
        )
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        input.setAsideChangeMode = .use
        input.setAsideAmountText = "75.50"

        XCTAssertEqual(
            try XCTUnwrap(input.projectedSetAsideAmount),
            224.50,
            accuracy: 0.001
        )
        XCTAssertTrue(input.hasValidChange)

        input.setAsideAmountText = "300.01"
        XCTAssertFalse(input.hasValidChange)
        XCTAssertEqual(
            input.validationMessage,
            "You can use up to $300.00 from this plan."
        )
    }

    func testNoOpUpdateDoesNotEnableSwipeSave() {
        let input = EditPaymentPlanInput(
            bucket: paymentPlan(),
            calendar: calendar
        )

        XCTAssertFalse(input.hasDetailsChange)
        XCTAssertFalse(input.hasSetAsideChange)
        XCTAssertFalse(input.hasValidChange)
        XCTAssertEqual(input.validationMessage, "Make a change to save.")
    }

    func testDetailsCardDoneUpdatesOnlyUnsavedInputDraft() throws {
        let bucket = paymentPlan(
            name: "Amex Gold",
            target: 866.04,
            protectedAmount: 200,
            choice: .statementBalance
        )
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        var details = PaymentPlanDetailsDraft(
            input: input,
            calendar: calendar
        )
        details.name = "Everyday Card"
        details.paymentTargetAmountText = "202.59"
        details.paymentTargetChoice = .minimumPayment
        details.didExplicitlyChooseTarget = true
        details.targetStatementIssueDate = nil
        details.dueDate = date(2026, 9, 22)

        XCTAssertTrue(
            PaymentPlanDetailsDraftCoordinator.apply(
                draft: details,
                to: &input
            )
        )

        XCTAssertEqual(input.name, "Everyday Card")
        XCTAssertEqual(
            try XCTUnwrap(input.paymentTargetAmount),
            202.59,
            accuracy: 0.001
        )
        XCTAssertEqual(input.paymentTargetChoice, .minimumPayment)
        XCTAssertTrue(input.hasDetailsChange)

        XCTAssertEqual(bucket.accountName, "Amex Gold")
        XCTAssertEqual(bucket.paymentTargetAmount, 866.04, accuracy: 0.001)
        XCTAssertEqual(bucket.paymentTargetChoice, .statementBalance)
        XCTAssertEqual(bucket.dueDate, date(2026, 8, 14))
    }

    func testMarkHandledPreservesActiveDetailsDraftAndRequiresSwipeSave() {
        let bucket = paymentPlan()
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        var details = PaymentPlanDetailsDraft(
            input: input,
            calendar: calendar
        )
        details.name = "Everyday Card"
        details.paymentTargetAmountText = "625.50"

        let result =
            PaymentPlanLifecycleDraftCoordinator.prepareMarkAsHandled(
                draft: details,
                input: &input
            )

        XCTAssertEqual(result, .requiresSwipeSave)
        XCTAssertEqual(input.name, "Everyday Card")
        XCTAssertEqual(input.paymentTargetAmount, 625.50)
        XCTAssertTrue(input.hasDetailsChange)
        XCTAssertEqual(bucket.accountName, "Amex Gold")
        XCTAssertEqual(bucket.paymentTargetAmount, 500, accuracy: 0.001)
    }

    func testMarkHandledAllowsUnchangedValidDetailsDraft() {
        let bucket = paymentPlan()
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        let details = PaymentPlanDetailsDraft(
            input: input,
            calendar: calendar
        )

        let result =
            PaymentPlanLifecycleDraftCoordinator.prepareMarkAsHandled(
                draft: details,
                input: &input
            )

        XCTAssertEqual(result, .ready)
        XCTAssertFalse(input.hasValidChange)
    }

    func testPlanNextPaymentPreservesActiveDetailsDraft() throws {
        let bucket = paymentPlan(protectedAmount: 100)
        let handledCycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: bucket.paymentTargetAmount,
            status: .handled,
            resolution: .paid,
            calendar: calendar
        )
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        var details = PaymentPlanDetailsDraft(
            input: input,
            calendar: calendar
        )
        details.name = "Next Statement"
        details.paymentTargetAmountText = "700.25"

        let result =
            PaymentPlanLifecycleDraftCoordinator.preparePlanNextPayment(
                draft: details,
                latestCycle: handledCycle,
                input: &input
            )

        XCTAssertEqual(result, .requiresSwipeSave)
        XCTAssertEqual(input.name, "Next Statement")
        XCTAssertEqual(
            try XCTUnwrap(input.paymentTargetAmount),
            700.25,
            accuracy: 0.001
        )
        XCTAssertTrue(
            calendar.isDate(
                input.dueDate,
                inSameDayAs: date(2026, 9, 14)
            )
        )
        XCTAssertEqual(input.cycleDueDayAnchor, 14)
        XCTAssertEqual(input.setAsideChangeMode, .use)
        XCTAssertEqual(input.setAsideAmountText, "100.00")
        XCTAssertTrue(input.shouldCreateActiveCycle)
        XCTAssertEqual(bucket.accountName, "Amex Gold")
    }

    func testTrackPaymentPreservesActiveDetailsDraft() {
        let bucket = paymentPlan()
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        var details = PaymentPlanDetailsDraft(
            input: input,
            calendar: calendar
        )
        details.name = "Tracked Card"
        details.paymentTargetAmountText = "550.75"

        let result =
            PaymentPlanLifecycleDraftCoordinator.prepareTrackPayment(
                draft: details,
                input: &input
            )

        XCTAssertEqual(result, .requiresSwipeSave)
        XCTAssertEqual(input.name, "Tracked Card")
        XCTAssertEqual(input.paymentTargetAmount, 550.75)
        XCTAssertTrue(input.shouldCreateActiveCycle)
        XCTAssertEqual(bucket.accountName, "Amex Gold")
    }

    func testInvalidDetailsDraftBlocksEveryLifecyclePreparation() {
        let bucket = paymentPlan()
        let handledCycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: bucket.paymentTargetAmount,
            status: .handled,
            resolution: .paid,
            calendar: calendar
        )
        let original = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        var invalidDetails = PaymentPlanDetailsDraft(
            input: original,
            calendar: calendar
        )
        invalidDetails.name = " "

        var markInput = original
        XCTAssertEqual(
            PaymentPlanLifecycleDraftCoordinator.prepareMarkAsHandled(
                draft: invalidDetails,
                input: &markInput
            ),
            .blockedInvalidDetails
        )
        XCTAssertEqual(markInput, original)

        var nextInput = original
        XCTAssertEqual(
            PaymentPlanLifecycleDraftCoordinator.preparePlanNextPayment(
                draft: invalidDetails,
                latestCycle: handledCycle,
                input: &nextInput
            ),
            .blockedInvalidDetails
        )
        XCTAssertEqual(nextInput, original)

        var trackInput = original
        XCTAssertEqual(
            PaymentPlanLifecycleDraftCoordinator.prepareTrackPayment(
                draft: invalidDetails,
                input: &trackInput
            ),
            .blockedInvalidDetails
        )
        XCTAssertEqual(trackInput, original)
    }

    func testExplicitTargetChoicePreservesChoiceAwareProvenance() throws {
        let originalChosenAt = date(2026, 7, 1)
        let originalIssueDate = date(2026, 7, 3)
        let saveDate = date(2026, 7, 27)
        let newIssueDate = date(2026, 7, 20)
        let bucket = paymentPlan(
            target: 866.04,
            choice: .statementBalance,
            targetChosenAt: originalChosenAt,
            statementIssueDate: originalIssueDate
        )

        var unchanged = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        unchanged.setAsideAmountText = "1"
        let unchangedDraft = try XCTUnwrap(
            unchanged.draft(
                for: bucket,
                now: saveDate,
                calendar: calendar
            )
        )
        XCTAssertEqual(unchangedDraft.paymentTargetChoice, .statementBalance)
        XCTAssertEqual(unchangedDraft.targetChosenAt, originalChosenAt)
        XCTAssertEqual(
            unchangedDraft.targetStatementIssueDate,
            originalIssueDate
        )

        var statement = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        statement.paymentTargetAmountText = "900"
        statement.paymentTargetChoice = .statementBalance
        statement.targetStatementIssueDate = newIssueDate
        statement.didExplicitlyChooseTarget = true
        let statementDraft = try XCTUnwrap(
            statement.draft(
                for: bucket,
                now: saveDate,
                calendar: calendar
            )
        )
        XCTAssertEqual(statementDraft.paymentTargetChoice, .statementBalance)
        XCTAssertEqual(statementDraft.targetChosenAt, saveDate)
        XCTAssertEqual(statementDraft.targetStatementIssueDate, newIssueDate)

        var minimum = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        minimum.paymentTargetAmountText = "202.59"
        minimum.paymentTargetChoice = .minimumPayment
        minimum.targetStatementIssueDate = newIssueDate
        minimum.didExplicitlyChooseTarget = true
        let minimumDraft = try XCTUnwrap(
            minimum.draft(
                for: bucket,
                now: saveDate,
                calendar: calendar
            )
        )
        XCTAssertEqual(minimumDraft.paymentTargetChoice, .minimumPayment)
        XCTAssertEqual(minimumDraft.targetChosenAt, saveDate)
        XCTAssertNil(minimumDraft.targetStatementIssueDate)
    }

    func testManualCardPlanDoesNotInventLinkedTargetProvenance() throws {
        let bucket = paymentPlan(
            plaidAccountID: "",
            target: 300,
            choice: nil
        )
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        input.paymentTargetAmountText = "350.75"
        input.paymentTargetChoice = .customAmount
        input.didExplicitlyChooseTarget = true

        let draft = try XCTUnwrap(
            input.draft(
                for: bucket,
                now: date(2026, 7, 27),
                calendar: calendar
            )
        )
        XCTAssertNil(draft.paymentTargetChoice)
        XCTAssertNil(draft.targetChosenAt)
        XCTAssertNil(draft.targetStatementIssueDate)
    }

    func testSuccessfulPersistenceUpdatesBucketAndActiveCycleTogether() throws {
        let bucket = paymentPlan(
            target: 500,
            protectedAmount: 100
        )
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: bucket.paymentTargetAmount,
            calendar: calendar
        )
        let saveDate = date(2026, 7, 27)
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        input.name = "Updated Card"
        input.paymentTargetAmountText = "600.50"
        input.dueDate = date(2026, 9, 22)
        input.setAsideAmountText = "125.25"
        let draft = try XCTUnwrap(
            input.draft(
                for: bucket,
                now: saveDate,
                calendar: calendar
            )
        )
        var didPersist = false

        let result = PaymentPlanUpdatePersistenceCoordinator.persist(
            draft: draft,
            bucket: bucket,
            activeCycle: cycle,
            existingCycles: [cycle],
            now: saveDate,
            insertCycle: { _ in XCTFail("Existing active cycle should update") },
            persistChanges: { didPersist = true },
            rollback: { XCTFail("Successful save should not roll back") }
        )

        XCTAssertTrue(result.startsSuccessFlow)
        XCTAssertTrue(didPersist)
        XCTAssertEqual(bucket.accountName, "Updated Card")
        XCTAssertEqual(bucket.paymentTargetAmount, 600.50, accuracy: 0.001)
        XCTAssertEqual(bucket.protectedAmount, 225.25, accuracy: 0.001)
        XCTAssertEqual(bucket.dueDate, date(2026, 9, 22))
        XCTAssertEqual(cycle.dueDate, date(2026, 9, 22))
        XCTAssertEqual(cycle.dueDayAnchor, 22)
        XCTAssertEqual(cycle.frozenTargetAmount, 600.50, accuracy: 0.001)
    }

    func testFailedPersistenceRestoresBucketAndCycleAndPreservesInput() throws {
        let bucket = paymentPlan(
            name: "Amex Gold",
            target: 500,
            protectedAmount: 100
        )
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: bucket.paymentTargetAmount,
            calendar: calendar
        )
        let originalCycleKey = cycle.cycleKey
        let originalInputAmount = "125.25"
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        input.name = "Updated Card"
        input.paymentTargetAmountText = "600.50"
        input.dueDate = date(2026, 9, 22)
        input.setAsideAmountText = originalInputAmount
        let draft = try XCTUnwrap(
            input.draft(
                for: bucket,
                calendar: calendar
            )
        )
        var didRollback = false

        let result = PaymentPlanUpdatePersistenceCoordinator.persist(
            draft: draft,
            bucket: bucket,
            activeCycle: cycle,
            existingCycles: [cycle],
            insertCycle: { _ in XCTFail("Existing active cycle should update") },
            persistChanges: { throw TestPersistenceError.failed },
            rollback: { didRollback = true }
        )

        XCTAssertFalse(result.startsSuccessFlow)
        XCTAssertFalse(result.dismissesAfterSuccessFlow)
        XCTAssertEqual(
            result.errorMessage,
            "Your Payment Plan update wasn't saved. Please try again."
        )
        XCTAssertTrue(didRollback)
        XCTAssertEqual(bucket.accountName, "Amex Gold")
        XCTAssertEqual(bucket.paymentTargetAmount, 500, accuracy: 0.001)
        XCTAssertEqual(bucket.protectedAmount, 100, accuracy: 0.001)
        XCTAssertEqual(bucket.dueDate, date(2026, 8, 14))
        XCTAssertEqual(cycle.dueDate, date(2026, 8, 14))
        XCTAssertEqual(cycle.frozenTargetAmount, 500, accuracy: 0.001)
        XCTAssertEqual(cycle.cycleKey, originalCycleKey)
        XCTAssertEqual(input.name, "Updated Card")
        XCTAssertEqual(input.setAsideAmountText, originalInputAmount)
    }

    func testPlanningNextPaymentCreatesOneActiveCycleOnlyAfterSave() throws {
        let bucket = paymentPlan(
            target: 500,
            protectedAmount: 100
        )
        let handledCycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: bucket.paymentTargetAmount,
            status: .handled,
            resolution: .paid,
            calendar: calendar
        )
        var input = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
        input.shouldCreateActiveCycle = true
        input.dueDate = date(2026, 9, 14)
        input.cycleDueDayAnchor = 14
        input.setAsideChangeMode = .use
        input.setAsideAmountText = "100"
        let draft = try XCTUnwrap(
            input.draft(
                for: bucket,
                calendar: calendar
            )
        )
        var insertedCycles: [PaymentPlanCycle] = []

        XCTAssertTrue(insertedCycles.isEmpty)
        let result = PaymentPlanUpdatePersistenceCoordinator.persist(
            draft: draft,
            bucket: bucket,
            activeCycle: nil,
            existingCycles: [handledCycle],
            insertCycle: { insertedCycles.append($0) },
            persistChanges: {},
            rollback: { XCTFail("Successful save should not roll back") }
        )

        XCTAssertTrue(result.startsSuccessFlow)
        XCTAssertEqual(insertedCycles.count, 1)
        XCTAssertTrue(try XCTUnwrap(insertedCycles.first).isActive)
        XCTAssertEqual(bucket.protectedAmount, 0, accuracy: 0.001)
    }

    func testModernEditorRoutesCardPlansAndKeepsLegacyOtherDebtSafe() {
        let linkedCard = paymentPlan(plaidAccountID: "card-1")
        let manualCard = paymentPlan(plaidAccountID: "")
        let otherDebt = DebtPayoffBucket(
            plaidAccountID: "",
            accountName: "Student Loan",
            dueDate: date(2026, 8, 14),
            paymentTargetAmount: 300,
            debtKind: .studentLoan,
            monthlyPayment: 300
        )

        XCTAssertTrue(
            PaymentPlanUpdateRouting.usesModernEditor(for: linkedCard)
        )
        XCTAssertTrue(
            PaymentPlanUpdateRouting.usesModernEditor(for: manualCard)
        )
        XCTAssertFalse(
            PaymentPlanUpdateRouting.usesModernEditor(for: otherDebt)
        )
    }

    private func paymentPlan(
        plaidAccountID: String = "card-1",
        name: String = "Amex Gold",
        target: Double = 500,
        protectedAmount: Double = 100,
        choice: DebtPayoffLinkedCardPaymentTargetChoice? = .currentBalance,
        targetChosenAt: Date? = nil,
        statementIssueDate: Date? = nil
    ) -> DebtPayoffBucket {
        DebtPayoffBucket(
            plaidAccountID: plaidAccountID,
            accountName: name,
            institutionName: plaidAccountID.isEmpty ? nil : "Test Bank",
            dueDate: date(2026, 8, 14),
            paymentTargetAmount: target,
            protectedAmount: protectedAmount,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: choice,
            targetChosenAt: targetChosenAt,
            targetStatementIssueDate: statementIssueDate,
            manualCurrentBalance: plaidAccountID.isEmpty ? target : nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day
            )
        )!
    }
}

private enum TestPersistenceError: Error {
    case failed
}
