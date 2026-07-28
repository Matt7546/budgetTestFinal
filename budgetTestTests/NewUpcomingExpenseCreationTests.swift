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

    func testSetAsideInputSupportsAddUseAndBlocksNoOpChanges() throws {
        var input = UpcomingExpenseSetAsideInput()

        XCTAssertFalse(
            input.hasValidChange(
                currentSetAside: 600,
                amountNeeded: 1_700
            )
        )
        XCTAssertEqual(
            input.validationMessage(
                currentSetAside: 600,
                amountNeeded: 1_700
            ),
            "Enter an amount greater than $0."
        )

        input.amountText = "250.25"

        XCTAssertTrue(
            input.hasValidChange(
                currentSetAside: 600,
                amountNeeded: 1_700
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(
                input.projectedSetAsideAmount(
                    currentSetAside: 600,
                    amountNeeded: 1_700
                )
            ),
            850.25,
            accuracy: 0.001
        )

        input.changeMode = .use

        XCTAssertEqual(
            try XCTUnwrap(
                input.projectedSetAsideAmount(
                    currentSetAside: 600,
                    amountNeeded: 1_700
                )
            ),
            349.75,
            accuracy: 0.001
        )

        input.amountText = "700"

        XCTAssertFalse(
            input.hasValidChange(
                currentSetAside: 600,
                amountNeeded: 1_700
            )
        )
        XCTAssertEqual(
            input.validationMessage(
                currentSetAside: 600,
                amountNeeded: 1_700
            ),
            "You can use up to $600.00 from this expense."
        )
    }

    func testEditInputRequiresAValidChangeAndPreservesDecimalValues() throws {
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_700.25,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            frequency: .monthly,
            type: .expense,
            accentColorID: PlannerEventColor.orange.rawValue
        )
        var input = UpcomingExpenseEditInput(event: event)

        XCTAssertFalse(input.hasValidChange)
        XCTAssertEqual(input.validationMessage, "Make a change to save.")

        input.amountText = "$1,725.75"

        XCTAssertTrue(input.hasValidChange)
        XCTAssertNil(input.validationMessage)
        XCTAssertEqual(
            try XCTUnwrap(input.amount),
            1_725.75,
            accuracy: 0.001
        )

        input.name = "   "

        XCTAssertFalse(input.hasValidChange)
        XCTAssertEqual(
            input.validationMessage,
            "Add an expense name to save."
        )
    }

    func testEditInputIdentifiesOnlyDateOrFrequencyAsScheduleChanges() {
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_700,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            frequency: .monthly,
            type: .expense
        )
        var input = UpcomingExpenseEditInput(event: event)

        input.name = "Apartment Rent"
        input.amountText = "1800.50"

        XCTAssertTrue(input.hasValidChange)
        XCTAssertFalse(input.hasScheduleChange)

        input.frequency = .quarterly

        XCTAssertTrue(input.hasScheduleChange)
    }

    func testSavedExpenseRoutePreservesSelectedOccurrence() {
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_700,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            frequency: .monthly,
            type: .expense
        )
        let selectedOccurrence = event.date.addingTimeInterval(
            86_400 * 62
        )
        let forecast = ForecastEvent(
            event: event,
            occurrenceDate: selectedOccurrence
        )
        let destination = PlannerEventEditorDestination(
            editingEvent: event,
            forecast: forecast
        )
        let editor = EditUpcomingExpenseView(
            event: event,
            forecast: forecast
        )

        XCTAssertEqual(
            PlannerEventEditorKind(event: event),
            .upcomingExpense
        )
        XCTAssertEqual(
            destination.forecast?.occurrenceID,
            forecast.occurrenceID
        )
        XCTAssertEqual(editor.forecast.occurrenceID, forecast.occurrenceID)

        let income = PlannerEvent(
            name: "Legacy Income",
            amount: 500,
            date: event.date,
            frequency: .once,
            type: .income
        )
        XCTAssertEqual(
            PlannerEventEditorKind(event: income),
            .legacyIncome
        )
    }

    func testCompactContextAndOptionsUseTheDetailsBottomCard() {
        XCTAssertEqual(
            UpcomingExpenseDetailsCardTrigger.scheduleContext.id,
            .scheduleContext
        )
        XCTAssertEqual(
            UpcomingExpenseDetailsCardTrigger.options.id,
            .options
        )
        XCTAssertNotEqual(
            UpcomingExpenseDetailsCardTrigger.scheduleContext.id,
            UpcomingExpenseDetailsCardTrigger.options.id
        )
    }

    func testDetailsCardDraftStaysLocalUntilDone() {
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_700,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            frequency: .monthly,
            type: .expense
        )
        var saveInput = UpcomingExpenseEditInput(event: event)
        var cardDraft = saveInput
        cardDraft.name = "Apartment Rent"
        cardDraft.amountText = "1750.25"

        XCTAssertEqual(saveInput.name, "Rent")
        XCTAssertEqual(saveInput.amountText, "1700")
        XCTAssertEqual(event.name, "Rent")
        XCTAssertEqual(event.amount, 1_700, accuracy: 0.001)

        XCTAssertTrue(
            UpcomingExpenseDetailsDraftCoordinator.apply(
                draft: cardDraft,
                to: &saveInput
            )
        )
        XCTAssertEqual(saveInput.name, "Apartment Rent")
        XCTAssertEqual(saveInput.amountText, "1750.25")
        XCTAssertEqual(event.name, "Rent")
        XCTAssertEqual(event.amount, 1_700, accuracy: 0.001)
    }

    func testUnifiedPersistenceSavesDetailsAndAddedSetAsideTogether() throws {
        let container = try makePlannerContainer()
        let context = ModelContext(container)
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_700,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            frequency: .monthly,
            type: .expense
        )
        let forecast = ForecastEvent(
            event: event,
            occurrenceDate: event.date
        )
        let allocation = EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: 600
        )
        let status = ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            status: .paid
        )
        context.insert(event)
        context.insert(allocation)
        context.insert(status)
        try context.save()

        var details = UpcomingExpenseEditInput(event: event)
        details.name = "Apartment Rent"
        details.amountText = "1800.50"
        let setAside = UpcomingExpenseSetAsideInput(
            changeMode: .add,
            amountText: "125.25"
        )

        let result = UpcomingExpenseUnifiedPersistenceCoordinator.persist(
            details: details,
            setAside: setAside,
            event: event,
            forecast: forecast,
            allocation: allocation,
            currentSetAside: 600,
            resetOccurrenceTracking: false,
            relatedAllocations: [allocation],
            relatedStatuses: [status],
            insertAllocation: { context.insert($0) },
            deleteAllocation: { context.delete($0) },
            deleteStatus: { context.delete($0) },
            persistChanges: { try context.save() },
            rollback: { context.rollback() }
        )

        XCTAssertTrue(result.startsSuccessFlow)
        XCTAssertEqual(event.name, "Apartment Rent")
        XCTAssertEqual(event.amount, 1_800.50, accuracy: 0.001)
        XCTAssertEqual(allocation.allocatedAmount, 725.25, accuracy: 0.001)
        XCTAssertEqual(
            try context.fetch(
                FetchDescriptor<ExpenseOccurrenceStatus>()
            ).count,
            1
        )
    }

    func testUnifiedPersistenceUsesSetAsideWithoutChangingDetails() throws {
        let container = try makePlannerContainer()
        let context = ModelContext(container)
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_700,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            frequency: .monthly,
            type: .expense
        )
        let forecast = ForecastEvent(
            event: event,
            occurrenceDate: event.date
        )
        let allocation = EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: 600
        )
        context.insert(event)
        context.insert(allocation)
        try context.save()

        let result = UpcomingExpenseUnifiedPersistenceCoordinator.persist(
            details: UpcomingExpenseEditInput(event: event),
            setAside: UpcomingExpenseSetAsideInput(
                changeMode: .use,
                amountText: "175.50"
            ),
            event: event,
            forecast: forecast,
            allocation: allocation,
            currentSetAside: 600,
            resetOccurrenceTracking: false,
            relatedAllocations: [allocation],
            relatedStatuses: [],
            insertAllocation: { context.insert($0) },
            deleteAllocation: { context.delete($0) },
            deleteStatus: { context.delete($0) },
            persistChanges: { try context.save() },
            rollback: { context.rollback() }
        )

        XCTAssertTrue(result.startsSuccessFlow)
        XCTAssertEqual(allocation.allocatedAmount, 424.50, accuracy: 0.001)
        XCTAssertEqual(event.name, "Rent")
        XCTAssertEqual(event.amount, 1_700, accuracy: 0.001)
    }

    func testUnifiedScheduleChangeResetsRecordsAndAddsToNewSchedule() throws {
        let container = try makePlannerContainer()
        let context = ModelContext(container)
        let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_700,
            date: originalDate,
            frequency: .monthly,
            type: .expense
        )
        let forecast = ForecastEvent(
            event: event,
            occurrenceDate: originalDate
        )
        let allocation = EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: 600
        )
        let status = ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            status: .skipped
        )
        context.insert(event)
        context.insert(allocation)
        context.insert(status)
        try context.save()

        var details = UpcomingExpenseEditInput(event: event)
        details.dueDate = originalDate.addingTimeInterval(86_400 * 4)
        details.frequency = .quarterly

        let result = UpcomingExpenseUnifiedPersistenceCoordinator.persist(
            details: details,
            setAside: UpcomingExpenseSetAsideInput(
                changeMode: .add,
                amountText: "200"
            ),
            event: event,
            forecast: forecast,
            allocation: allocation,
            currentSetAside: 600,
            resetOccurrenceTracking: true,
            relatedAllocations: [allocation],
            relatedStatuses: [status],
            insertAllocation: { context.insert($0) },
            deleteAllocation: { context.delete($0) },
            deleteStatus: { context.delete($0) },
            persistChanges: { try context.save() },
            rollback: { context.rollback() }
        )

        XCTAssertTrue(result.startsSuccessFlow)
        XCTAssertEqual(event.date, details.dueDate)
        XCTAssertEqual(event.frequency, .quarterly)
        let savedAllocations = try context.fetch(
            FetchDescriptor<EventAllocation>()
        )
        XCTAssertEqual(savedAllocations.count, 1)
        XCTAssertEqual(
            savedAllocations.first?.allocatedAmount ?? 0,
            200,
            accuracy: 0.001
        )
        XCTAssertEqual(
            savedAllocations.first?.occurrenceID,
            ForecastEvent(
                event: event,
                occurrenceDate: details.dueDate
            ).occurrenceID
        )
        XCTAssertTrue(
            try context.fetch(
                FetchDescriptor<ExpenseOccurrenceStatus>()
            ).isEmpty
        )
    }

    func testUnifiedPersistenceFailureRestoresModelsAndKeepsInputs() throws {
        let container = try makePlannerContainer()
        let context = ModelContext(container)
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_700,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            frequency: .monthly,
            type: .expense
        )
        let forecast = ForecastEvent(
            event: event,
            occurrenceDate: event.date
        )
        let allocation = EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: 600
        )
        context.insert(event)
        context.insert(allocation)
        try context.save()

        var details = UpcomingExpenseEditInput(event: event)
        details.name = "Apartment Rent"
        let setAside = UpcomingExpenseSetAsideInput(
            changeMode: .add,
            amountText: "125.75"
        )

        let result = UpcomingExpenseUnifiedPersistenceCoordinator.persist(
            details: details,
            setAside: setAside,
            event: event,
            forecast: forecast,
            allocation: allocation,
            currentSetAside: 600,
            resetOccurrenceTracking: false,
            relatedAllocations: [allocation],
            relatedStatuses: [],
            insertAllocation: { context.insert($0) },
            deleteAllocation: { context.delete($0) },
            deleteStatus: { context.delete($0) },
            persistChanges: { throw EditPersistenceTestError.failed },
            rollback: { context.rollback() }
        )

        XCTAssertFalse(result.startsSuccessFlow)
        XCTAssertFalse(result.dismissesAfterSuccessFlow)
        XCTAssertEqual(
            result.errorMessage,
            "Your expense update wasn't saved. Please try again."
        )
        XCTAssertEqual(details.name, "Apartment Rent")
        XCTAssertEqual(setAside.amountText, "125.75")
        XCTAssertEqual(event.name, "Rent")
        XCTAssertEqual(allocation.allocatedAmount, 600, accuracy: 0.001)
    }

    func testUnifiedScheduleFailureRestoresOccurrenceRecords() throws {
        let container = try makePlannerContainer()
        let context = ModelContext(container)
        let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_700,
            date: originalDate,
            frequency: .monthly,
            type: .expense
        )
        let forecast = ForecastEvent(
            event: event,
            occurrenceDate: originalDate
        )
        let allocation = EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: 600
        )
        let status = ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            status: .paid
        )
        context.insert(event)
        context.insert(allocation)
        context.insert(status)
        try context.save()

        var details = UpcomingExpenseEditInput(event: event)
        details.dueDate = originalDate.addingTimeInterval(86_400 * 4)

        let result = UpcomingExpenseUnifiedPersistenceCoordinator.persist(
            details: details,
            setAside: UpcomingExpenseSetAsideInput(
                changeMode: .add,
                amountText: "200"
            ),
            event: event,
            forecast: forecast,
            allocation: allocation,
            currentSetAside: 600,
            resetOccurrenceTracking: true,
            relatedAllocations: [allocation],
            relatedStatuses: [status],
            insertAllocation: { context.insert($0) },
            deleteAllocation: { context.delete($0) },
            deleteStatus: { context.delete($0) },
            persistChanges: { throw EditPersistenceTestError.failed },
            rollback: { context.rollback() }
        )

        XCTAssertFalse(result.startsSuccessFlow)
        XCTAssertEqual(event.date, originalDate)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<EventAllocation>()).count,
            1
        )
        XCTAssertEqual(
            try context.fetch(
                FetchDescriptor<ExpenseOccurrenceStatus>()
            ).count,
            1
        )
    }

    private func makePlannerContainer() throws -> ModelContainer {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}

private enum EditPersistenceTestError: Error {
    case failed
}
