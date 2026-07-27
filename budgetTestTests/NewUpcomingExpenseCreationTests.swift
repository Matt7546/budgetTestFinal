import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class NewUpcomingExpenseCreationTests: XCTestCase {

    func testCreationRequiresNameAndPositiveAmount() {
        var input = NewUpcomingExpenseCreationInput()

        XCTAssertNil(input.event)
        XCTAssertEqual(
            input.validationMessage,
            "Add an expense name and amount to save."
        )

        input.name = "Rent"
        input.amountText = "0"

        XCTAssertNil(input.event)
        XCTAssertEqual(
            input.validationMessage,
            "Enter an amount greater than $0."
        )

        input.name = ""
        input.amountText = "1700"

        XCTAssertNil(input.event)
        XCTAssertEqual(
            input.validationMessage,
            "Add an expense name to save."
        )
    }

    func testCreationPreservesDecimalDateAndExpenseType() throws {
        let id = UUID()
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let input = NewUpcomingExpenseCreationInput(
            id: id,
            name: "  Rent  ",
            amountText: "$1,700.25",
            dueDate: dueDate,
            frequency: .quarterly
        )

        let event = try XCTUnwrap(input.event)

        XCTAssertEqual(event.id, id)
        XCTAssertEqual(event.name, "Rent")
        XCTAssertEqual(event.amount, 1_700.25, accuracy: 0.001)
        XCTAssertEqual(event.date, dueDate)
        XCTAssertEqual(event.frequency, .quarterly)
        XCTAssertEqual(event.type, .expense)
        XCTAssertNil(event.accentColorID)
        XCTAssertNil(input.validationMessage)
    }

    func testCreationKeepsExistingMonthlyDefaultAndRepeatOptions() {
        let input = NewUpcomingExpenseCreationInput()

        XCTAssertEqual(input.frequency, .monthly)
        XCTAssertEqual(
            PlannerFrequency.allCases,
            [
                .once,
                .weekly,
                .biweekly,
                .monthly,
                .quarterly,
                .yearly
            ]
        )
    }

    func testAmountPresentationFormatsWholeAndDecimalValues() {
        XCTAssertEqual(
            NewUpcomingExpenseAmountPresentation.displayText(for: ""),
            "0"
        )
        XCTAssertEqual(
            NewUpcomingExpenseAmountPresentation.displayText(for: "1700"),
            "1,700"
        )
        XCTAssertEqual(
            NewUpcomingExpenseAmountPresentation.displayText(
                for: "$12,345.67"
            ),
            "12,345.67"
        )
    }

    func testFailedPersistenceKeepsExpenseCreationOnScreen() {
        let input = NewUpcomingExpenseCreationInput(
            name: "Rent",
            amountText: "1700.25",
            frequency: .monthly
        )
        let result = PlanningCreationPersistenceResult(
            didPersist: false,
            failureMessage: "Your expense wasn't saved. Please try again."
        )

        XCTAssertFalse(result.startsSuccessFlow)
        XCTAssertFalse(result.dismissesAfterSuccessFlow)
        XCTAssertEqual(
            result.errorMessage,
            "Your expense wasn't saved. Please try again."
        )
        XCTAssertEqual(input.name, "Rent")
        XCTAssertEqual(input.amountText, "1700.25")
        XCTAssertEqual(input.frequency, .monthly)
    }

    func testValidEventPersistsThroughSwiftData() throws {
        let schema = Schema([PlannerEvent.self])
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
        let input = NewUpcomingExpenseCreationInput(
            name: "Rent",
            amountText: "1700.25",
            frequency: .monthly
        )
        let event = try XCTUnwrap(input.event)

        context.insert(event)
        try context.save()

        let savedEvent = try XCTUnwrap(
            context.fetch(FetchDescriptor<PlannerEvent>()).first
        )
        XCTAssertEqual(savedEvent.id, event.id)
        XCTAssertEqual(savedEvent.amount, 1_700.25, accuracy: 0.001)
        XCTAssertEqual(savedEvent.frequency, .monthly)
        XCTAssertEqual(savedEvent.type, .expense)
    }
}
