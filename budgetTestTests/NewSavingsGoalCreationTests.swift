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
}
