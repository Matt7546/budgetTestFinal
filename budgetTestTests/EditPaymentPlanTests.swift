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

    func testCoverInFullUsesActiveCycleFrozenTargetAndPreservesLifecycle() throws {
        let chosenAt = date(2026, 7, 1)
        let statementDate = date(2026, 7, 3)
        let bucket = paymentPlan(
            target: 800,
            protectedAmount: 275,
            choice: .statementBalance,
            targetChosenAt: chosenAt,
            statementIssueDate: statementDate
        )
        let cycleID = UUID()
        let cycleCreatedAt = date(2026, 7, 2)
        let cycleUpdatedAt = date(2026, 7, 4)
        let cycle = PaymentPlanCycle(
            id: cycleID,
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: 1_000,
            releasedSetAsideAmount: 0,
            createdAt: cycleCreatedAt,
            updatedAt: cycleUpdatedAt,
            calendar: calendar
        )
        let originalCycleKey = cycle.cycleKey
        let saveDate = date(2026, 7, 27)
        let request = try XCTUnwrap(
            PaymentPlanCoverInFullCoordinator.request(
                for: bucket,
                activeCycle: cycle,
                cycles: [cycle]
            )
        )

        XCTAssertEqual(request.paymentPlanID, bucket.id)
        XCTAssertEqual(request.cycleID, cycleID)
        XCTAssertEqual(request.coverRequest.amount, 725, accuracy: 0.001)

        let result = PaymentPlanCoverInFullCoordinator.persist(
            request,
            bucket: bucket,
            activeCycle: cycle,
            cycles: [cycle],
            now: saveDate,
            persistChanges: {},
            rollback: { XCTFail("Successful cover should not roll back") }
        )

        guard case .saved(let amount) = result else {
            return XCTFail("Expected Cover in Full to save")
        }
        XCTAssertEqual(amount, 725, accuracy: 0.001)
        XCTAssertEqual(bucket.protectedAmount, 1_000, accuracy: 0.001)
        XCTAssertEqual(bucket.paymentTargetAmount, 800, accuracy: 0.001)
        XCTAssertEqual(bucket.paymentTargetChoice, .statementBalance)
        XCTAssertEqual(bucket.targetChosenAt, chosenAt)
        XCTAssertEqual(bucket.targetStatementIssueDate, statementDate)
        XCTAssertEqual(bucket.updatedAt, saveDate)

        XCTAssertEqual(cycle.id, cycleID)
        XCTAssertEqual(cycle.paymentPlanID, bucket.id)
        XCTAssertEqual(cycle.status, .active)
        XCTAssertNil(cycle.resolution)
        XCTAssertNil(cycle.handledAt)
        XCTAssertEqual(cycle.releasedSetAsideAmount, 0, accuracy: 0.001)
        XCTAssertEqual(cycle.frozenTargetAmount, 1_000, accuracy: 0.001)
        XCTAssertEqual(cycle.cycleKey, originalCycleKey)
        XCTAssertEqual(cycle.createdAt, cycleCreatedAt)
        XCTAssertEqual(cycle.updatedAt, cycleUpdatedAt)
    }

    func testCoverPresentationMatchesFrozenActiveCycleAmounts() throws {
        let bucket = paymentPlan(
            target: 800,
            protectedAmount: 275
        )
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: 1_000,
            calendar: calendar
        )
        let snapshot = try XCTUnwrap(
            PaymentPlanCoverInFullCoordinator.snapshot(
                for: bucket,
                activeCycle: cycle,
                cycles: [cycle]
            )
        )
        let presentation = PaymentPlanCoverInFullPresentation.make(
            input: EditPaymentPlanInput(
                bucket: bucket,
                calendar: calendar
            ),
            snapshot: snapshot
        )

        XCTAssertEqual(presentation.targetAmount, 1_000, accuracy: 0.001)
        XCTAssertEqual(presentation.currentAmount, 275, accuracy: 0.001)
        XCTAssertEqual(presentation.remainingAmount, 725, accuracy: 0.001)
    }

    func testExactCycleEntryDoesNotAutomaticallyOpenDeeperDetails() {
        XCTAssertNil(
            PaymentPlanUpdateEntryPolicy.initialDetailsTrigger(
                requestedCycleID: UUID()
            )
        )
        XCTAssertNil(
            PaymentPlanUpdateEntryPolicy.initialDetailsTrigger(
                requestedCycleID: nil
            )
        )
    }

    func testCoverInFullSupportsTrulyCyclelessManualPlan() throws {
        let bucket = DebtPayoffBucket(
            plaidAccountID: "",
            accountName: "Student Loan",
            dueDate: date(2026, 8, 14),
            paymentTargetAmount: 500,
            protectedAmount: 125,
            debtKind: .studentLoan,
            monthlyPayment: 500
        )
        let request = try XCTUnwrap(
            PaymentPlanCoverInFullCoordinator.request(
                for: bucket,
                activeCycle: nil,
                cycles: []
            )
        )

        XCTAssertNil(request.cycleID)
        XCTAssertEqual(request.coverRequest.amount, 375, accuracy: 0.001)
        let presentation = PaymentPlanCoverInFullPresentation.make(
            input: EditPaymentPlanInput(
                bucket: bucket,
                calendar: calendar
            ),
            snapshot: PaymentPlanCoverInFullCoordinator.snapshot(
                for: bucket,
                activeCycle: nil,
                cycles: []
            )
        )
        XCTAssertEqual(presentation.targetAmount, 500, accuracy: 0.001)
        XCTAssertEqual(presentation.currentAmount, 125, accuracy: 0.001)
        XCTAssertEqual(presentation.remainingAmount, 375, accuracy: 0.001)

        let result = PaymentPlanCoverInFullCoordinator.persist(
            request,
            bucket: bucket,
            activeCycle: nil,
            cycles: [],
            persistChanges: {},
            rollback: { XCTFail("Successful cover should not roll back") }
        )

        XCTAssertTrue(result.didSave)
        XCTAssertEqual(bucket.protectedAmount, 500, accuracy: 0.001)
    }

    func testCoverInFullUsesLegacyManualMonthlyPaymentFallback() throws {
        let bucket = DebtPayoffBucket(
            plaidAccountID: "",
            accountName: "Other Debt",
            dueDate: date(2026, 8, 14),
            paymentTargetAmount: 0,
            protectedAmount: 75,
            debtKind: .other,
            monthlyPayment: 300
        )

        let request = try XCTUnwrap(
            PaymentPlanCoverInFullCoordinator.request(
                for: bucket,
                activeCycle: nil,
                cycles: []
            )
        )

        XCTAssertNil(request.cycleID)
        XCTAssertEqual(request.coverRequest.amount, 225, accuracy: 0.001)
    }

    func testCoverInFullDoesNotUseManualDebtFallbackForCreditCard() {
        let bucket = DebtPayoffBucket(
            plaidAccountID: "",
            accountName: "Manual Card",
            dueDate: date(2026, 8, 14),
            paymentTargetAmount: 0,
            protectedAmount: 0,
            debtKind: .linkedCreditCard,
            monthlyPayment: 300
        )

        XCTAssertNil(
            PaymentPlanCoverInFullCoordinator.request(
                for: bucket,
                activeCycle: nil,
                cycles: []
            )
        )
    }

    func testHandledPaymentPlanCycleDoesNotOfferCoverInFull() {
        let bucket = paymentPlan(target: 500, protectedAmount: 100)
        let handledCycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: 500,
            status: .handled,
            resolution: .paid,
            handledAt: date(2026, 8, 15),
            releasedSetAsideAmount: 100,
            calendar: calendar
        )

        XCTAssertNil(
            PaymentPlanCoverInFullCoordinator.request(
                for: bucket,
                activeCycle: nil,
                cycles: [handledCycle]
            )
        )
        XCTAssertNil(
            PaymentPlanCoverInFullCoordinator.request(
                for: bucket,
                activeCycle: handledCycle,
                cycles: [handledCycle]
            )
        )
    }

    func testCoverInFullSaveFailureRestoresPaymentPlanExactly() throws {
        let originalUpdatedAt = date(2026, 7, 1)
        let bucket = DebtPayoffBucket(
            plaidAccountID: "card-1",
            accountName: "Amex Gold",
            dueDate: date(2026, 8, 14),
            paymentTargetAmount: 500,
            protectedAmount: 100,
            debtKind: .linkedCreditCard,
            updatedAt: originalUpdatedAt
        )
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: 500,
            calendar: calendar
        )
        let request = try XCTUnwrap(
            PaymentPlanCoverInFullCoordinator.request(
                for: bucket,
                activeCycle: cycle,
                cycles: [cycle]
            )
        )
        var didRollback = false

        let result = PaymentPlanCoverInFullCoordinator.persist(
            request,
            bucket: bucket,
            activeCycle: cycle,
            cycles: [cycle],
            now: date(2026, 7, 27),
            persistChanges: { throw TestPersistenceError.failed },
            rollback: { didRollback = true }
        )

        XCTAssertFalse(result.didSave)
        XCTAssertEqual(result.errorMessage, CoverInFullPolicy.failureMessage)
        XCTAssertTrue(didRollback)
        XCTAssertEqual(bucket.protectedAmount, 100, accuracy: 0.001)
        XCTAssertEqual(bucket.updatedAt, originalUpdatedAt)
        XCTAssertEqual(cycle.status, .active)
        XCTAssertEqual(cycle.releasedSetAsideAmount, 0, accuracy: 0.001)
    }

    func testCoverInFullCannotDoubleApplyOrSaveStaleCycleRequest() throws {
        let bucket = paymentPlan(target: 500, protectedAmount: 100)
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: 500,
            calendar: calendar
        )
        let request = try XCTUnwrap(
            PaymentPlanCoverInFullCoordinator.request(
                for: bucket,
                activeCycle: cycle,
                cycles: [cycle]
            )
        )
        var persistenceCount = 0
        let persist: () throws -> Void = { persistenceCount += 1 }

        let first = PaymentPlanCoverInFullCoordinator.persist(
            request,
            bucket: bucket,
            activeCycle: cycle,
            cycles: [cycle],
            persistChanges: persist,
            rollback: {}
        )
        let second = PaymentPlanCoverInFullCoordinator.persist(
            request,
            bucket: bucket,
            activeCycle: cycle,
            cycles: [cycle],
            persistChanges: persist,
            rollback: {}
        )

        XCTAssertTrue(first.didSave)
        XCTAssertFalse(second.didSave)
        XCTAssertEqual(persistenceCount, 1)
        XCTAssertEqual(bucket.protectedAmount, 500, accuracy: 0.001)

        let otherCycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: date(2026, 9, 14),
            frozenTargetAmount: 600,
            calendar: calendar
        )
        let staleResult = PaymentPlanCoverInFullCoordinator.persist(
            request,
            bucket: bucket,
            activeCycle: otherCycle,
            cycles: [otherCycle],
            persistChanges: { persistenceCount += 1 },
            rollback: {}
        )

        XCTAssertFalse(staleResult.didSave)
        XCTAssertEqual(persistenceCount, 1)
    }

    func testLegacyCoverRequiresEverySavedDraftFieldToRemainClean() {
        let dueDate = date(2026, 8, 14)
        let startDate = date(2026, 1, 1)
        let endDate = date(2027, 1, 1)
        let bucket = DebtPayoffBucket(
            plaidAccountID: "",
            accountName: "Car loan",
            dueDate: dueDate,
            paymentTargetAmount: 300,
            protectedAmount: 100,
            debtKind: .other,
            manualCurrentBalance: 1_200,
            monthlyPayment: 300,
            originalBalance: 2_000,
            interestRate: 5.5,
            notes: "Saved note",
            hasPaymentDueDate: true,
            startDate: startDate,
            endDate: endDate
        )

        func state(
            name: String = "Car loan",
            due: Date = dueDate,
            balance: Double = 1_200,
            notes: String? = "Saved note",
            start: Date? = startDate,
            end: Date? = endDate
        ) -> LegacyPaymentPlanCoverInFullDraftState {
            LegacyPaymentPlanCoverInFullDraftState(
                debtKind: .other,
                plaidAccountID: "",
                accountName: name,
                dueDate: due,
                paymentTargetAmount: 300,
                protectedAmount: 100,
                manualCurrentBalance: balance,
                originalBalance: 2_000,
                interestRate: 5.5,
                notes: notes,
                hasPaymentDueDate: true,
                startDate: start,
                endDate: end,
                shouldCreateActiveCycle: false
            )
        }

        XCTAssertTrue(state().matchesSavedBucket(bucket, calendar: calendar))
        XCTAssertFalse(
            state(name: "Renamed").matchesSavedBucket(
                bucket,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            state(due: date(2026, 8, 15)).matchesSavedBucket(
                bucket,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            state(balance: 1_100).matchesSavedBucket(
                bucket,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            state(notes: "Unsaved note").matchesSavedBucket(
                bucket,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            state(start: nil).matchesSavedBucket(
                bucket,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            state(end: date(2027, 2, 1)).matchesSavedBucket(
                bucket,
                calendar: calendar
            )
        )
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
