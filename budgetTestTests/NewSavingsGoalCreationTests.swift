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
