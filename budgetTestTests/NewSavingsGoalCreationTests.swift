import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class NewSavingsGoalCreationTests: XCTestCase {

    func testCreationRequiresNameAndPositiveTarget() {
        let draft = SavingsGoal(
            name: "",
            targetAmount: 0
        )
        var input = NewSavingsGoalCreationInput(
            goal: draft
        )

        XCTAssertNil(input.goal)
        XCTAssertEqual(
            input.validationMessage,
            "Add a goal name and target amount to save."
        )

        input.name = "Vacation"
        input.targetAmountText = "0"

        XCTAssertNil(input.goal)
        XCTAssertEqual(
            input.validationMessage,
            "Enter a target amount greater than $0."
        )
    }

    func testCreationPreservesDecimalDateAndDefaultsPinOffWhileStartingAtZero() throws {
        let id = UUID()
        let targetDate = Date(timeIntervalSince1970: 1_800_000_000)
        var input = NewSavingsGoalCreationInput(
            goal: SavingsGoal(
                id: id,
                name: "",
                targetAmount: 0,
                isPinned: true
            )
        )

        input.name = "  Vacation  "
        input.targetAmountText = "$1,234.56"
        input.saveByDate = targetDate

        let goal = try XCTUnwrap(input.goal)

        XCTAssertEqual(goal.id, id)
        XCTAssertEqual(goal.name, "Vacation")
        XCTAssertEqual(goal.targetAmount, 1_234.56, accuracy: 0.001)
        XCTAssertEqual(goal.currentAmount, 0)
        XCTAssertEqual(goal.saveByDate, targetDate)
        XCTAssertFalse(goal.isPinned)
        XCTAssertNil(input.validationMessage)
    }

    func testCreationKeepsTargetDateOptional() throws {
        var input = NewSavingsGoalCreationInput(
            goal: SavingsGoal(
                name: "",
                targetAmount: 0
            )
        )

        input.name = "Laptop"
        input.targetAmountText = "950.25"

        let goal = try XCTUnwrap(input.goal)

        XCTAssertNil(goal.saveByDate)
        XCTAssertFalse(goal.isPinned)
        XCTAssertEqual(goal.currentAmount, 0)
    }

    func testAmountPresentationFormatsWholeAndDecimalValuesWithoutEllipsis() {
        XCTAssertEqual(
            NewSavingsGoalAmountPresentation.displayText(
                for: ""
            ),
            "0"
        )
        XCTAssertEqual(
            NewSavingsGoalAmountPresentation.displayText(
                for: "5"
            ),
            "5"
        )
        XCTAssertEqual(
            NewSavingsGoalAmountPresentation.displayText(
                for: "50"
            ),
            "50"
        )
        XCTAssertEqual(
            NewSavingsGoalAmountPresentation.displayText(
                for: "500"
            ),
            "500"
        )
        XCTAssertEqual(
            NewSavingsGoalAmountPresentation.displayText(
                for: "5000"
            ),
            "5,000"
        )
        XCTAssertEqual(
            NewSavingsGoalAmountPresentation.displayText(
                for: "50000"
            ),
            "50,000"
        )
        XCTAssertEqual(
            NewSavingsGoalAmountPresentation.displayText(
                for: "$5,000.25"
            ),
            "5,000.25"
        )
    }

    func testFailedPersistenceKeepsGoalCreationOnScreen() {
        var input = NewSavingsGoalCreationInput(
            goal: SavingsGoal(name: "Vacation", targetAmount: 0)
        )
        input.targetAmountText = "1234.56"
        let originalName = input.name
        let originalAmount = input.targetAmountText

        let result = PlanningCreationPersistenceResult(
            didPersist: false,
            failureMessage: "Your goal wasn't saved. Please try again."
        )

        XCTAssertFalse(result.startsSuccessFlow)
        XCTAssertFalse(result.dismissesAfterSuccessFlow)
        XCTAssertEqual(
            result.errorMessage,
            "Your goal wasn't saved. Please try again."
        )
        XCTAssertEqual(input.name, originalName)
        XCTAssertEqual(input.targetAmountText, originalAmount)
    }

    func testAddGoalReportsSuccessfulSwiftDataPersistence() throws {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self,
            IncomeSchedule.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let service = PlaidService()
        service.configurePersistence(
            modelContext: context
        )
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 1_234.56,
            currentAmount: 0,
            isPinned: true
        )

        XCTAssertTrue(service.addGoal(goal))

        let record = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<SavingsGoalRecord>()
            ).first {
                $0.id == goal.id
            }
        )
        XCTAssertEqual(record.name, goal.name)
        XCTAssertEqual(record.targetAmount, goal.targetAmount, accuracy: 0.001)
        XCTAssertEqual(record.currentAmount, 0)
        XCTAssertTrue(record.isPinned)
    }

    func testQuickContributionRoutesToModernGoalUpdateFlow() {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )

        let route = SavingsGoalSheetRoute.quickContribution(to: goal)

        XCTAssertTrue(route.usesModernUpdateFlow)
        XCTAssertEqual(route.goalID, goal.id)
    }

    func testSavingsGoalRowRoutesToModernGoalUpdateFlow() {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )

        let route = SavingsGoalSheetRoute.existingGoal(goal)

        XCTAssertTrue(route.usesModernUpdateFlow)
        XCTAssertEqual(route.goalID, goal.id)
    }

    func testNewSavingsGoalKeepsDedicatedCreateRoute() {
        let draft = SavingsGoal(
            name: "",
            targetAmount: 0,
            currentAmount: 0
        )
        let route = SavingsGoalSheetRoute.create(draft)

        XCTAssertFalse(route.usesModernUpdateFlow)
        XCTAssertEqual(route.goalID, draft.id)
    }

    func testDeleteGoalReportsSuccessOnlyAfterPersistenceCompletes() {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        let service = PlaidService()
        service.savingsGoals = [goal]
        var didPersist = false

        let didDelete = service.deleteGoal(
            goal,
            persistDeletion: { persistedGoal in
                XCTAssertEqual(persistedGoal, goal)
                didPersist = true
                return true
            }
        )

        XCTAssertTrue(didPersist)
        XCTAssertTrue(didDelete)
        XCTAssertTrue(service.savingsGoals.isEmpty)
    }

    func testFailedDeleteDoesNotDismissAndRestoresInMemoryGoals() {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        let otherGoal = SavingsGoal(
            name: "Laptop",
            targetAmount: 1_500,
            currentAmount: 250
        )
        let service = PlaidService()
        let originalGoals = [goal, otherGoal]
        service.savingsGoals = originalGoals

        let didDelete = service.deleteGoal(
            goal,
            persistDeletion: { _ in false }
        )
        let presentationResult = PlanningCreationPersistenceResult(
            didPersist: didDelete,
            failureMessage: "This goal wasn't deleted. Please try again."
        )

        XCTAssertFalse(didDelete)
        XCTAssertFalse(presentationResult.dismissesAfterSuccessFlow)
        XCTAssertEqual(
            presentationResult.errorMessage,
            "This goal wasn't deleted. Please try again."
        )
        XCTAssertEqual(service.savingsGoals, originalGoals)
    }

    func testDeleteGoalRemovesPersistedSwiftDataRecord() throws {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self,
            IncomeSchedule.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let service = PlaidService()
        service.configurePersistence(modelContext: context)
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        XCTAssertTrue(service.addGoal(goal))

        XCTAssertTrue(service.deleteGoal(goal))

        let records = try context.fetch(
            FetchDescriptor<SavingsGoalRecord>()
        )
        XCTAssertFalse(records.contains(where: { $0.id == goal.id }))
        XCTAssertFalse(service.savingsGoals.contains(where: {
            $0.id == goal.id
        }))
    }

    func testEditInputAddsDecimalSetAsideAndPreservesGoalDetails() throws {
        let targetDate = Date(timeIntervalSince1970: 1_800_000_000)
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400,
            isPinned: true,
            saveByDate: targetDate
        )
        var input = EditSavingsGoalInput(goal: goal)

        input.setAsideAmountText = "$125.75"

        let updatedGoal = try XCTUnwrap(input.updatedGoal)
        XCTAssertEqual(updatedGoal.currentAmount, 3_525.75, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.targetAmount, 5_000, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.saveByDate, targetDate)
        XCTAssertTrue(updatedGoal.isPinned)
        XCTAssertTrue(input.hasValidChange)
        XCTAssertNil(input.validationMessage)
    }

    func testEditInputAllowsAddingExactlyTheRemainingGoalAmount() throws {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        var input = EditSavingsGoalInput(goal: goal)
        input.setAsideAmountText = "1600"

        let updatedGoal = try XCTUnwrap(input.updatedGoal)

        XCTAssertEqual(updatedGoal.currentAmount, 5_000, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.currentAmount, updatedGoal.targetAmount)
        XCTAssertTrue(input.hasValidChange)
        XCTAssertNil(input.validationMessage)
    }

    func testEditInputRejectsAddingMoreThanTheGoalStillNeeds() {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        var input = EditSavingsGoalInput(goal: goal)
        input.setAsideAmountText = "1600.01"

        XCTAssertEqual(input.remainingSetAsideAmount, 1_600)
        XCTAssertNil(input.updatedGoal)
        XCTAssertFalse(input.hasValidChange)
        XCTAssertEqual(
            input.validationMessage,
            "You can add up to $1,600.00 to this goal."
        )
        XCTAssertEqual(goal.currentAmount, 3_400)
    }

    func testEditInputBlocksAddingToAnAlreadyCoveredGoal() {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 5_000
        )
        var input = EditSavingsGoalInput(goal: goal)
        input.setAsideAmountText = "25"

        XCTAssertEqual(input.remainingSetAsideAmount, 0)
        XCTAssertNil(input.updatedGoal)
        XCTAssertFalse(input.hasValidChange)
        XCTAssertEqual(
            input.validationMessage,
            "This goal is already covered."
        )
        XCTAssertEqual(goal.currentAmount, goal.targetAmount)
    }

    func testCoverInFullRequestUsesExactRemainingAmount() throws {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        let input = EditSavingsGoalInput(goal: goal)

        let request = try XCTUnwrap(
            input.coverInFullRequest(latestGoal: goal)
        )
        let rebased = try XCTUnwrap(
            input.rebasedForCoverInFull(latestGoal: goal)
        )
        let updatedGoal = try XCTUnwrap(rebased.updatedGoal)

        XCTAssertEqual(request.amount, 1_600, accuracy: 0.001)
        XCTAssertEqual(rebased.setAsideAmountText, "1600.00")
        XCTAssertEqual(rebased.setAsideChangeMode, .add)
        XCTAssertEqual(updatedGoal.id, goal.id)
        XCTAssertEqual(updatedGoal.currentAmount, 5_000, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.currentAmount, updatedGoal.targetAmount)
    }

    func testCoverInFullRebasesAgainstLatestSavedAmount() throws {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        let input = EditSavingsGoalInput(goal: goal)
        var latestGoal = goal
        latestGoal.currentAmount = 3_850

        let request = try XCTUnwrap(
            input.coverInFullRequest(latestGoal: latestGoal)
        )
        let rebased = try XCTUnwrap(
            input.rebasedForCoverInFull(latestGoal: latestGoal)
        )

        XCTAssertEqual(request.amount, 1_150, accuracy: 0.001)
        XCTAssertEqual(rebased.setAsideAmountText, "1150.00")
        XCTAssertEqual(
            try XCTUnwrap(rebased.updatedGoal).currentAmount,
            5_000,
            accuracy: 0.001
        )
    }

    func testCoverInFullPreservesGoalDetailsAndExactID() throws {
        let id = UUID()
        let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
        let updatedDate = Date(timeIntervalSince1970: 1_900_000_000)
        let goal = SavingsGoal(
            id: id,
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400,
            isPinned: false,
            saveByDate: originalDate
        )
        var input = EditSavingsGoalInput(goal: goal)
        input.name = "Summer Vacation"
        input.targetAmountText = "5500.00"
        input.saveByDate = updatedDate
        input.isPinned = true

        let rebased = try XCTUnwrap(
            input.rebasedForCoverInFull(latestGoal: goal)
        )
        let updatedGoal = try XCTUnwrap(rebased.updatedGoal)

        XCTAssertEqual(updatedGoal.id, id)
        XCTAssertEqual(updatedGoal.name, "Summer Vacation")
        XCTAssertEqual(updatedGoal.targetAmount, 5_500, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.currentAmount, 5_500, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.saveByDate, updatedDate)
        XCTAssertTrue(updatedGoal.isPinned)
    }

    func testCoverInFullIsUnavailableForCoveredOrDifferentGoal() {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 5_000
        )
        let input = EditSavingsGoalInput(goal: goal)
        let otherGoal = SavingsGoal(
            name: "Laptop",
            targetAmount: 2_000,
            currentAmount: 500
        )

        XCTAssertNil(input.coverInFullRequest(latestGoal: goal))
        XCTAssertNil(input.rebasedForCoverInFull(latestGoal: goal))
        XCTAssertNil(input.coverInFullRequest(latestGoal: otherGoal))
        XCTAssertNil(input.rebasedForCoverInFull(latestGoal: otherGoal))
    }

    func testEditInputUsesSetAsideWithoutGoingBelowZero() throws {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        var input = EditSavingsGoalInput(goal: goal)
        input.setAsideChangeMode = .use
        input.setAsideAmountText = "400.25"

        let updatedGoal = try XCTUnwrap(input.updatedGoal)
        XCTAssertEqual(updatedGoal.currentAmount, 2_999.75, accuracy: 0.001)

        input.setAsideAmountText = "3400"

        XCTAssertEqual(
            try XCTUnwrap(input.updatedGoal).currentAmount,
            0,
            accuracy: 0.001
        )

        input.setAsideAmountText = "3400.01"

        XCTAssertNil(input.updatedGoal)
        XCTAssertFalse(input.hasValidChange)
        XCTAssertEqual(
            input.validationMessage,
            "You can use up to $3,400.00 from this goal."
        )
    }

    func testEditInputSupportsDetailOnlyChangesAndBlocksNoOpSave() throws {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400,
            isPinned: false
        )
        var input = EditSavingsGoalInput(goal: goal)

        XCTAssertFalse(input.hasValidChange)
        XCTAssertEqual(input.validationMessage, "Make a change to save.")

        input.name = "Summer Vacation"
        input.targetAmountText = "5500.50"
        input.isPinned = true
        let updatedDate = Date(timeIntervalSince1970: 1_900_000_000)
        input.saveByDate = updatedDate

        let updatedGoal = try XCTUnwrap(input.updatedGoal)
        XCTAssertEqual(updatedGoal.name, "Summer Vacation")
        XCTAssertEqual(updatedGoal.targetAmount, 5_500.50, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.currentAmount, 3_400, accuracy: 0.001)
        XCTAssertTrue(updatedGoal.isPinned)
        XCTAssertEqual(updatedGoal.saveByDate, updatedDate)
        XCTAssertTrue(input.hasValidChange)
    }

    func testGoalDetailsCardTriggersRemainDistinct() {
        XCTAssertEqual(
            SavingsGoalDetailsCardTrigger.goalName.id,
            .goalName
        )
        XCTAssertEqual(
            SavingsGoalDetailsCardTrigger.goalContext.id,
            .goalContext
        )
        XCTAssertEqual(
            SavingsGoalDetailsCardTrigger.options.id,
            .options
        )
    }

    func testGoalDetailsDraftDoesNotChangePageDraftUntilApplied() {
        let targetDate = Date(timeIntervalSince1970: 1_800_000_000)
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400,
            isPinned: false
        )
        let input = EditSavingsGoalInput(goal: goal)
        var cardDraft = SavingsGoalDetailsDraft(input: input)

        cardDraft.name = "Summer Vacation"
        cardDraft.targetAmountText = "5500.50"
        cardDraft.saveByDate = targetDate
        cardDraft.isPinned = true

        XCTAssertEqual(input.name, "Vacation")
        XCTAssertEqual(input.targetAmountText, "5000.00")
        XCTAssertNil(input.saveByDate)
        XCTAssertFalse(input.isPinned)
        XCTAssertEqual(input.originalGoal, goal)
    }

    func testGoalDetailsDoneAppliesOnlyToUnsavedPageDraft() throws {
        let targetDate = Date(timeIntervalSince1970: 1_800_000_000)
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400,
            isPinned: false
        )
        var input = EditSavingsGoalInput(goal: goal)
        var cardDraft = SavingsGoalDetailsDraft(input: input)
        cardDraft.name = "Summer Vacation"
        cardDraft.targetAmountText = "5500.50"
        cardDraft.saveByDate = targetDate
        cardDraft.isPinned = true

        XCTAssertTrue(
            SavingsGoalDetailsDraftCoordinator.apply(
                draft: cardDraft,
                to: &input
            )
        )

        XCTAssertEqual(input.originalGoal, goal)
        XCTAssertEqual(input.name, "Summer Vacation")
        XCTAssertEqual(input.targetAmountText, "5500.50")
        XCTAssertEqual(input.saveByDate, targetDate)
        XCTAssertTrue(input.isPinned)
        XCTAssertTrue(input.hasValidChange)

        let updatedGoal = try XCTUnwrap(input.updatedGoal)
        XCTAssertEqual(updatedGoal.name, "Summer Vacation")
        XCTAssertEqual(updatedGoal.targetAmount, 5_500.50, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.currentAmount, 3_400, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.saveByDate, targetDate)
        XCTAssertTrue(updatedGoal.isPinned)
    }

    func testGoalDetailsCancelOrDismissLeavesPageDraftUnchanged() {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        let input = EditSavingsGoalInput(goal: goal)
        var discardedDraft = SavingsGoalDetailsDraft(input: input)
        discardedDraft.name = "Discarded Name"
        discardedDraft.targetAmountText = "6500"
        discardedDraft.isPinned = true

        XCTAssertEqual(input, EditSavingsGoalInput(goal: goal))
        XCTAssertNotEqual(discardedDraft.name, input.name)
        XCTAssertNotEqual(
            discardedDraft.targetAmountText,
            input.targetAmountText
        )
        XCTAssertNotEqual(discardedDraft.isPinned, input.isPinned)
    }

    func testGoalDetailsRejectInvalidDraftWithoutChangingPageDraft() {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        var input = EditSavingsGoalInput(goal: goal)
        let unchangedInput = input
        var cardDraft = SavingsGoalDetailsDraft(input: input)
        cardDraft.name = "   "
        cardDraft.targetAmountText = "0"

        XCTAssertFalse(cardDraft.isValid)
        XCTAssertFalse(
            SavingsGoalDetailsDraftCoordinator.apply(
                draft: cardDraft,
                to: &input
            )
        )
        XCTAssertEqual(input, unchangedInput)
    }

    func testSwipeDraftCombinesDetailsAndSetAsideContribution() throws {
        let targetDate = Date(timeIntervalSince1970: 1_900_000_000)
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400,
            isPinned: false
        )
        var input = EditSavingsGoalInput(goal: goal)
        var cardDraft = SavingsGoalDetailsDraft(input: input)
        cardDraft.name = "Summer Vacation"
        cardDraft.targetAmountText = "6000.75"
        cardDraft.saveByDate = targetDate
        cardDraft.isPinned = true

        XCTAssertTrue(
            SavingsGoalDetailsDraftCoordinator.apply(
                draft: cardDraft,
                to: &input
            )
        )
        input.setAsideAmountText = "125.25"

        let updatedGoal = try XCTUnwrap(input.updatedGoal)
        XCTAssertEqual(updatedGoal.name, "Summer Vacation")
        XCTAssertEqual(updatedGoal.targetAmount, 6_000.75, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.currentAmount, 3_525.25, accuracy: 0.001)
        XCTAssertEqual(updatedGoal.saveByDate, targetDate)
        XCTAssertTrue(updatedGoal.isPinned)
        XCTAssertTrue(input.hasValidChange)
    }

    func testFailedEditPersistenceDoesNotStartSuccessOrDiscardInput() {
        var input = EditSavingsGoalInput(
            goal: SavingsGoal(
                name: "Vacation",
                targetAmount: 5_000,
                currentAmount: 3_400
            )
        )
        input.setAsideAmountText = "250.25"
        let unchangedInput = input

        XCTAssertLessThanOrEqual(
            input.updatedGoal?.currentAmount ?? .infinity,
            input.updatedGoal?.targetAmount ?? 0
        )

        let result = PlanningCreationPersistenceResult(
            didPersist: false,
            failureMessage: "Your goal updates weren't saved. Please try again."
        )

        XCTAssertFalse(result.startsSuccessFlow)
        XCTAssertFalse(result.dismissesAfterSuccessFlow)
        XCTAssertEqual(
            result.errorMessage,
            "Your goal updates weren't saved. Please try again."
        )
        XCTAssertEqual(input, unchangedInput)
    }

    func testCoverInFullFailureRestoresPriorEditorAndDetailsDraft() throws {
        let goal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        var input = EditSavingsGoalInput(goal: goal)
        input.name = "Summer Vacation"
        input.saveByDate = Date(timeIntervalSince1970: 1_800_000_000)
        input.isPinned = true
        input.setAsideChangeMode = .use
        input.setAsideAmountText = "125.50"
        var detailsDraft = SavingsGoalDetailsDraft(input: input)
        detailsDraft.name = "Unsaved details card name"
        let unchangedInput = input
        let unchangedDetailsDraft = detailsDraft
        let preparation = try XCTUnwrap(
            SavingsGoalCoverInFullEditorCoordinator.prepare(
                input: input,
                detailsDraft: detailsDraft,
                latestGoal: goal
            )
        )

        input = preparation.rebasedInput
        detailsDraft = SavingsGoalDetailsDraft(input: input)
        let result = PlanningCreationPersistenceResult(
            didPersist: false,
            failureMessage: CoverInFullPolicy.failureMessage
        )

        if !result.startsSuccessFlow {
            preparation.restorePoint.restore(
                input: &input,
                detailsDraft: &detailsDraft
            )
        }

        XCTAssertFalse(result.startsSuccessFlow)
        XCTAssertFalse(result.dismissesAfterSuccessFlow)
        XCTAssertEqual(
            result.errorMessage,
            "This update wasn’t saved. Please try again."
        )
        XCTAssertEqual(input, unchangedInput)
        XCTAssertEqual(detailsDraft, unchangedDetailsDraft)
        XCTAssertEqual(goal.currentAmount, 3_400, accuracy: 0.001)
    }

    func testUpdateGoalReportsSuccessfulSwiftDataPersistence() throws {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self,
            IncomeSchedule.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let service = PlaidService()
        service.configurePersistence(
            modelContext: context
        )
        let originalGoal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        XCTAssertTrue(service.addGoal(originalGoal))

        var updatedGoal = originalGoal
        updatedGoal.name = "Summer Vacation"
        updatedGoal.targetAmount = 5_500.50
        updatedGoal.currentAmount = 3_650.25
        updatedGoal.isPinned = true

        XCTAssertTrue(service.updateGoal(updatedGoal))

        let record = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<SavingsGoalRecord>()
            ).first {
                $0.id == originalGoal.id
            }
        )
        XCTAssertEqual(record.name, updatedGoal.name)
        XCTAssertEqual(record.targetAmount, 5_500.50, accuracy: 0.001)
        XCTAssertEqual(record.currentAmount, 3_650.25, accuracy: 0.001)
        XCTAssertTrue(record.isPinned)
        XCTAssertEqual(
            service.savingsGoals.first {
                $0.id == originalGoal.id
            },
            updatedGoal
        )
    }

    func testUpdateGoalRejectsUnknownGoalWithoutChangingStoredGoals() {
        let service = PlaidService()
        let existingGoal = SavingsGoal(
            name: "Vacation",
            targetAmount: 5_000,
            currentAmount: 3_400
        )
        XCTAssertTrue(service.addGoal(existingGoal))

        XCTAssertFalse(
            service.updateGoal(
                SavingsGoal(
                    name: "Unknown",
                    targetAmount: 1_000
                )
            )
        )
        XCTAssertEqual(service.savingsGoals, [existingGoal])
    }
}
