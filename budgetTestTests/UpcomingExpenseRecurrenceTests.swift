import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class UpcomingExpenseRecurrenceTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testNewOneTimeExpensePersistsAsOneTime() throws {
        let context = try inMemoryContext()
        var state = newState()
        state.frequency = .once

        let event = try persist(state, in: context)
        let saved = try context.fetch(FetchDescriptor<PlannerEvent>())

        XCTAssertEqual(event.frequency, .once)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.frequency, .once)
    }

    func testNewMonthlyExpensePersistsAsMonthly() throws {
        let context = try inMemoryContext()
        var state = newState()
        state.frequency = .monthly

        let event = try persist(state, in: context)
        let saved = try context.fetch(FetchDescriptor<PlannerEvent>())

        XCTAssertEqual(event.frequency, .monthly)
        XCTAssertEqual(saved.first?.frequency, .monthly)
    }

    func testDateChangesDoNotMutateRecurrence() {
        var state = newState()
        state.frequency = .once

        state.date = date(2026, 8, 15)

        XCTAssertEqual(state.frequency, .once)
        XCTAssertEqual(dateKey(state.date), "2026-08-15")
    }

    func testDatePickerOpenAndDismissDoNotMutateRecurrence() {
        var state = newState()
        state.frequency = .once

        state.isDatePickerExpanded = true
        XCTAssertTrue(state.isDatePickerExpanded)
        XCTAssertEqual(state.frequency, .once)

        state.isDatePickerExpanded = false
        XCTAssertFalse(state.isDatePickerExpanded)
        XCTAssertEqual(state.frequency, .once)
    }

    func testPreSaveSummaryAndSubmissionUseSameRecurrence() throws {
        var state = newState()
        state.amountText = "1200.00"
        state.date = date(2026, 7, 25)
        state.frequency = .once

        let summary = state.preSaveSummary
        let submission = try XCTUnwrap(
            state.submission(editingEvent: nil)
        )

        XCTAssertEqual(summary.amount, submission.amount)
        XCTAssertEqual(summary.date, submission.date)
        XCTAssertEqual(summary.frequency, submission.frequency)
    }

    func testOneTimeGeneratesExactlyOneOccurrence() throws {
        let event = try event(from: newState())
        let forecasts = forecastEvents(
            for: event,
            now: date(2026, 7, 15)
        )

        XCTAssertEqual(event.frequency, .once)
        XCTAssertEqual(forecasts.count, 1)
        XCTAssertEqual(dateKey(forecasts[0].occurrenceDate), "2026-07-25")
    }

    func testOneTimeProducesNoFutureMonthlyPlanAheadEntries() throws {
        let event = try event(from: newState())
        let forecasts = forecastEvents(
            for: event,
            now: date(2026, 7, 15)
        )
        let items = PlanAheadTimelineItems.upcoming(
            expenses: forecasts,
            paymentPlans: [],
            startOfToday: date(2026, 7, 15),
            calendar: calendar
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.dueDate, date(2026, 7, 25))
    }

    func testMonthlyGenerationKeepsMonthEndAnchoring() {
        let event = PlannerEvent(
            name: "Monthly test",
            amount: 100,
            date: date(2026, 1, 31),
            frequency: .monthly,
            type: .expense
        )
        let keys = forecastEvents(
            for: event,
            now: date(2026, 1, 1)
        )
        .prefix(4)
        .map { dateKey($0.occurrenceDate) }

        XCTAssertEqual(
            keys,
            [
                "2026-01-31",
                "2026-02-28",
                "2026-03-31",
                "2026-04-30",
            ]
        )
    }

    func testEditNamePreservesRecurrenceAndAllocation() throws {
        let event = try event(from: newState())
        let forecast = try XCTUnwrap(
            forecastEvents(
                for: event,
                now: date(2026, 7, 15)
            ).first
        )
        let allocation = EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: 1_200
        )
        var state = PlannerEventEditorState(
            editingEvent: event,
            draft: nil
        )
        state.name = "Apartment Rent"
        let submission = try XCTUnwrap(
            state.submission(editingEvent: event)
        )

        PlannerEventSaveMutation.apply(
            submission,
            editingEvent: event,
            insert: { _ in XCTFail("Edit should not insert") }
        )

        XCTAssertEqual(event.name, "Apartment Rent")
        XCTAssertEqual(event.frequency, .once)
        XCTAssertEqual(allocation.allocatedAmount, 1_200)
        XCTAssertEqual(allocation.occurrenceID, forecast.occurrenceID)
    }

    func testEditDatePreservesRecurrenceAndRequiresExplicitAllocationReset() throws {
        let event = try event(from: newState())
        let forecast = try XCTUnwrap(
            forecastEvents(
                for: event,
                now: date(2026, 7, 15)
            ).first
        )
        let allocation = EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: 1_200
        )
        var state = PlannerEventEditorState(
            editingEvent: event,
            draft: nil
        )
        state.date = date(2026, 7, 26)
        let submission = try XCTUnwrap(
            state.submission(editingEvent: event)
        )
        let hasScheduleChange = PlannerEventScheduleChangePolicy
            .hasScheduleChange(
                originalDate: event.date,
                originalFrequency: event.frequency,
                proposedDate: submission.date,
                proposedFrequency: submission.frequency,
                calendar: calendar
            )

        XCTAssertTrue(
            PlannerEventScheduleChangePolicy.requiresOccurrenceReset(
                hasRelatedRecords: true,
                hasScheduleChange: hasScheduleChange
            )
        )
        XCTAssertEqual(submission.frequency, .once)
        XCTAssertEqual(allocation.allocatedAmount, 1_200)
    }

    func testEditRecurrenceIntentionallyFromMonthlyToOneTime() throws {
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_200,
            date: date(2026, 7, 25),
            frequency: .monthly,
            type: .expense
        )
        var state = PlannerEventEditorState(
            editingEvent: event,
            draft: nil
        )
        state.frequency = .once

        let submission = try XCTUnwrap(
            state.submission(editingEvent: event)
        )
        PlannerEventSaveMutation.apply(
            submission,
            editingEvent: event,
            insert: { _ in XCTFail("Edit should not insert") }
        )

        XCTAssertEqual(event.frequency, .once)
    }

    func testEditRecurrenceIntentionallyFromOneTimeToMonthly() throws {
        let event = try event(from: newState())
        var state = PlannerEventEditorState(
            editingEvent: event,
            draft: nil
        )
        state.frequency = .monthly

        let submission = try XCTUnwrap(
            state.submission(editingEvent: event)
        )
        PlannerEventSaveMutation.apply(
            submission,
            editingEvent: event,
            insert: { _ in XCTFail("Edit should not insert") }
        )

        XCTAssertEqual(event.frequency, .monthly)
    }

    func testColdRelaunchPreservesRecurrence() throws {
        let directory = try temporaryStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Caldera.store")

        try writeEvent(
            frequency: .monthly,
            allocationAmount: nil,
            to: storeURL
        )

        let container = try persistentContainer(at: storeURL)
        let context = ModelContext(container)
        let saved = try XCTUnwrap(
            context.fetch(FetchDescriptor<PlannerEvent>()).first
        )

        XCTAssertEqual(saved.frequency, .monthly)
    }

    func testPaidAndSkippedResolutionBehaviorRemainsUnchanged() throws {
        for resolution in ExpenseOccurrenceResolution.allCases {
            let event = try event(from: newState())
            let forecast = try XCTUnwrap(
                forecastEvents(
                    for: event,
                    now: date(2026, 7, 15)
                ).first
            )
            let status = ExpenseOccurrenceStatus(
                occurrenceID: forecast.occurrenceID,
                sourceEventID: event.id,
                occurrenceDate: forecast.normalizedOccurrenceDate,
                status: resolution
            )
            let inactiveIDs = ExpenseOccurrenceLifecycleResolver
                .resolvedOccurrenceIDs(from: [status])
            let active = [forecast].filter {
                !inactiveIDs.contains($0.occurrenceID)
            }

            XCTAssertTrue(active.isEmpty, resolution.rawValue)
            XCTAssertEqual(status.status, resolution)
        }
    }

    func testAccessibilityLayoutUsesFullWidthRowsAndSelectedValues() {
        XCTAssertFalse(
            PlannerEventRecurrenceControlPresentation.usesSingleColumn(
                isAccessibilitySize: false
            )
        )
        XCTAssertTrue(
            PlannerEventRecurrenceControlPresentation.usesSingleColumn(
                isAccessibilitySize: true
            )
        )
        XCTAssertEqual(
            PlannerEventRecurrenceControlPresentation.accessibilityValue(
                isSelected: true
            ),
            "Selected"
        )
        XCTAssertEqual(
            PlannerEventRecurrenceControlPresentation.accessibilityValue(
                isSelected: false
            ),
            "Not selected"
        )
    }

    func testRentRegressionSurvivesRelaunchWithOneOccurrenceAndFullSetAside() throws {
        let directory = try temporaryStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Caldera.store")

        try writeEvent(
            frequency: .once,
            allocationAmount: 1_200,
            to: storeURL
        )

        let container = try persistentContainer(at: storeURL)
        let context = ModelContext(container)
        let event = try XCTUnwrap(
            context.fetch(FetchDescriptor<PlannerEvent>()).first
        )
        let allocations = try context.fetch(
            FetchDescriptor<EventAllocation>()
        )
        let forecasts = forecastEvents(
            for: event,
            now: date(2026, 7, 15)
        )
        let planAheadItems = PlanAheadTimelineItems.upcoming(
            expenses: forecasts,
            paymentPlans: [],
            startOfToday: date(2026, 7, 15),
            calendar: calendar
        )

        XCTAssertEqual(event.name, "Rent")
        XCTAssertEqual(event.frequency, .once)
        XCTAssertEqual(forecasts.count, 1)
        XCTAssertEqual(planAheadItems.count, 1)
        XCTAssertEqual(
            EventAllocationTotals.activeTotal(
                allocations: allocations,
                forecastEvents: forecasts
            ),
            1_200,
            accuracy: 0.001
        )
    }

    private func newState() -> PlannerEventEditorState {
        var state = PlannerEventEditorState(
            editingEvent: nil,
            draft: nil,
            now: date(2026, 7, 15)
        )
        state.name = "Rent"
        state.amountText = "1200.00"
        state.date = date(2026, 7, 25)
        return state
    }

    private func event(
        from state: PlannerEventEditorState
    ) throws -> PlannerEvent {
        let submission = try XCTUnwrap(
            state.submission(editingEvent: nil)
        )
        return PlannerEventSaveMutation.apply(
            submission,
            editingEvent: nil,
            insert: { _ in }
        )
    }

    private func persist(
        _ state: PlannerEventEditorState,
        in context: ModelContext
    ) throws -> PlannerEvent {
        let submission = try XCTUnwrap(
            state.submission(editingEvent: nil)
        )
        let event = PlannerEventSaveMutation.apply(
            submission,
            editingEvent: nil,
            insert: context.insert
        )
        try context.save()
        return event
    }

    private func forecastEvents(
        for event: PlannerEvent,
        now: Date
    ) -> [ForecastEvent] {
        PlannerForecastCalculator(
            events: [event],
            totalAvailable: 0,
            totalGoalAllocated: 0,
            includeFutureIncome: true,
            protectGoals: true,
            now: now,
            calendar: calendar
        ).forecastEvents
    }

    private func inMemoryContext() throws -> ModelContext {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
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
        return ModelContext(container)
    }

    private func temporaryStoreDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func persistentContainer(
        at storeURL: URL
    ) throws -> ModelContainer {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
        ])
        let configuration = ModelConfiguration(
            "UpcomingExpenseRecurrenceTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private func writeEvent(
        frequency: PlannerFrequency,
        allocationAmount: Double?,
        to storeURL: URL
    ) throws {
        let container = try persistentContainer(at: storeURL)
        let context = ModelContext(container)
        var state = newState()
        state.frequency = frequency
        let event = try persist(state, in: context)

        if let allocationAmount {
            let forecast = try XCTUnwrap(
                forecastEvents(
                    for: event,
                    now: date(2026, 7, 15)
                ).first
            )
            context.insert(
                EventAllocation(
                    occurrenceID: forecast.occurrenceID,
                    sourceEventID: event.id,
                    occurrenceDate: forecast.normalizedOccurrenceDate,
                    allocatedAmount: allocationAmount
                )
            )
            try context.save()
        }
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        )!
    }

    private func dateKey(
        _ value: Date
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: value
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
