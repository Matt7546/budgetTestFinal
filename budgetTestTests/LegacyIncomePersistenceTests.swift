import Foundation
import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class LegacyIncomePersistenceTests: XCTestCase {
    private enum InjectedFailure: Error { case save, read }

    private let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let updatedDate = Date(timeIntervalSince1970: 1_802_592_000)

    func testEditSavesOnceBeforeSuccessAndRejectsRepeatedAction() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let event = income(owner: "owner-a")
        XCTAssertEqual(PlannerEventEditorKind(event: event), .legacyIncome)
        context.insert(event)
        try context.save()

        var completed = false
        var saves = 0
        var callbacks = 0
        let action = coordinator(context: context, event: event)
        let result = action.edit(
            event: event, name: "New paycheck", amount: 925,
            date: updatedDate, frequency: .weekly, completed: &completed,
            persistChanges: {
                saves += 1
                try context.save()
            }, rollback: { context.rollback() },
            onSuccess: {
                XCTAssertEqual(saves, 1)
                callbacks += 1
            }
        )

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(callbacks, 1)
        let fresh = ModelContext(container)
        let persisted = try XCTUnwrap(fresh.fetch(FetchDescriptor<PlannerEvent>()).first)
        XCTAssertEqual(persisted.name, "New paycheck")
        XCTAssertEqual(persisted.amount, 925)
        XCTAssertEqual(persisted.date, updatedDate)
        XCTAssertEqual(persisted.frequency, .weekly)

        XCTAssertEqual(action.edit(
            event: event, name: "Duplicate", amount: 1,
            date: updatedDate, frequency: .once, completed: &completed,
            persistChanges: { saves += 1; try context.save() },
            rollback: { context.rollback() },
            onSuccess: { callbacks += 1 }
        ), .rejected)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(callbacks, 1)
    }

    func testEditSaveFailureRollsBackWithoutSuccess() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let event = income(owner: "owner-a")
        context.insert(event)
        try context.save()

        var completed = false
        var saveAttempts = 0
        var rollbacks = 0
        var callbacks = 0
        XCTAssertEqual(coordinator(context: context, event: event).edit(
            event: event, name: "Not saved", amount: 999,
            date: updatedDate, frequency: .yearly, completed: &completed,
            persistChanges: {
                saveAttempts += 1
                throw InjectedFailure.save
            }, rollback: {
                rollbacks += 1
                context.rollback()
            }, onSuccess: { callbacks += 1 }
        ), .failed)

        XCTAssertEqual(saveAttempts, 1)
        XCTAssertEqual(rollbacks, 1)
        XCTAssertEqual(callbacks, 0)
        XCTAssertFalse(completed)
        let fresh = ModelContext(container)
        let persisted = try XCTUnwrap(fresh.fetch(FetchDescriptor<PlannerEvent>()).first)
        XCTAssertEqual(persisted.name, "Paycheck")
        XCTAssertEqual(persisted.amount, 900)
        XCTAssertEqual(persisted.date, originalDate)
        XCTAssertEqual(persisted.frequency, .monthly)
    }

    func testDeleteSuccessAndFailureSurviveFileBackedReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("LegacyIncome.store")
        let deletedID = UUID()
        let preservedID = UUID()

        try autoreleasepool {
            let container = try makeContainer(at: url)
            let context = ModelContext(container)
            let deleted = income(id: deletedID, owner: "owner-a")
            let preserved = income(id: preservedID, owner: "owner-a")
            context.insert(deleted)
            context.insert(preserved)
            context.insert(EventAllocation(
                ownerScopeID: "owner-a", occurrenceID: "income-deleted",
                sourceEventID: deletedID, occurrenceDate: originalDate,
                allocatedAmount: 10
            ))
            context.insert(ExpenseOccurrenceStatus(
                ownerScopeID: "owner-a", occurrenceID: "income-deleted",
                sourceEventID: deletedID, occurrenceDate: originalDate,
                status: .paid
            ))
            context.insert(EventAllocation(
                ownerScopeID: "owner-a", occurrenceID: "income-preserved",
                sourceEventID: preservedID, occurrenceDate: originalDate,
                allocatedAmount: 20
            ))
            try context.save()

            var deletedComplete = false
            var successSaves = 0
            var successCallbacks = 0
            XCTAssertEqual(coordinator(context: context, event: deleted).delete(
                event: deleted, completed: &deletedComplete,
                persistChanges: {
                    successSaves += 1
                    try context.save()
                }, rollback: { context.rollback() },
                onSuccess: {
                    XCTAssertEqual(successSaves, 1)
                    successCallbacks += 1
                }
            ), .saved)
            XCTAssertEqual(successCallbacks, 1)
            XCTAssertEqual(successSaves, 1)

            var failedComplete = false
            var failureAttempts = 0
            var failureCallbacks = 0
            var rollbacks = 0
            XCTAssertEqual(coordinator(context: context, event: preserved).delete(
                event: preserved, completed: &failedComplete,
                persistChanges: {
                    failureAttempts += 1
                    throw InjectedFailure.save
                }, rollback: {
                    rollbacks += 1
                    context.rollback()
                }, onSuccess: { failureCallbacks += 1 }
            ), .failed)
            XCTAssertEqual(failureAttempts, 1)
            XCTAssertEqual(rollbacks, 1)
            XCTAssertEqual(failureCallbacks, 0)
            XCTAssertFalse(failedComplete)
            let fresh = ModelContext(container)
            XCTAssertEqual(
                Set(try fresh.fetch(FetchDescriptor<PlannerEvent>()).map(\.id)),
                [preservedID]
            )
            XCTAssertEqual(try fresh.fetch(FetchDescriptor<EventAllocation>()).count, 1)
            XCTAssertTrue(try fresh.fetch(FetchDescriptor<ExpenseOccurrenceStatus>()).isEmpty)
        }

        let reopened = try makeContainer(at: url)
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<PlannerEvent>())
        XCTAssertEqual(Set(rows.map(\.id)), [preservedID])
        XCTAssertEqual(rows.first?.amount, 900)
        let reopenedContext = ModelContext(reopened)
        XCTAssertEqual(
            try reopenedContext.fetch(FetchDescriptor<EventAllocation>()).map(\.sourceEventID),
            [preservedID]
        )
        XCTAssertTrue(
            try reopenedContext.fetch(FetchDescriptor<ExpenseOccurrenceStatus>()).isEmpty
        )
    }

    func testOwnerSwitchGenerationChangeAndReadFailureRejectWithoutSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let eventA = income(owner: "owner-a")
        let eventB = income(owner: "owner-b")
        context.insert(eventA)
        context.insert(eventB)
        try context.save()

        var completed = false
        var saves = 0
        var callbacks = 0
        let save: () throws -> Void = { saves += 1; try context.save() }
        let callback = { callbacks += 1 }

        XCTAssertEqual(coordinator(
            context: context, event: eventA, currentOwner: "owner-b"
        ).edit(
            event: eventA, name: "Retargeted", amount: 1,
            date: updatedDate, frequency: .once, completed: &completed,
            persistChanges: save, rollback: { context.rollback() },
            onSuccess: callback
        ), .rejected)
        XCTAssertEqual(coordinator(
            context: context, event: eventA, currentGeneration: 2
        ).delete(
            event: eventA, completed: &completed,
            persistChanges: save, rollback: { context.rollback() },
            onSuccess: callback
        ), .rejected)
        XCTAssertEqual(coordinator(
            context: context, event: eventA,
            readEvents: { _, _ in throw InjectedFailure.read }
        ).edit(
            event: eventA, name: "Unreadable", amount: 1,
            date: updatedDate, frequency: .once, completed: &completed,
            persistChanges: save, rollback: { context.rollback() },
            onSuccess: callback
        ), .rejected)
        XCTAssertEqual(coordinator(
            context: context, event: eventA
        ).delete(
            event: eventB, completed: &completed,
            persistChanges: save, rollback: { context.rollback() },
            onSuccess: callback
        ), .rejected)
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(callbacks, 0)
        let fresh = ModelContext(container)
        let rows = try fresh.fetch(FetchDescriptor<PlannerEvent>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.name == "Paycheck" && $0.amount == 900 })
    }

    private func income(
        id: UUID = UUID(), owner: String
    ) -> PlannerEvent {
        PlannerEvent(
            id: id, ownerScopeID: owner, name: "Paycheck", amount: 900,
            date: originalDate, frequency: .monthly, type: .income
        )
    }

    private func coordinator(
        context: ModelContext,
        event: PlannerEvent,
        currentOwner: String = "owner-a",
        currentGeneration: UInt64 = 1,
        readEvents: ((ModelContext, UUID) throws -> [PlannerEvent])? = nil
    ) -> LegacyIncomeEventPersistenceCoordinator {
        LegacyIncomeEventPersistenceCoordinator(
            modelContext: context, preparedEventID: event.id,
            preparedOwnerScopeID: "owner-a",
            currentOwnerScopeID: currentOwner, preparedGeneration: 1,
            currentGeneration: currentGeneration, availability: .available,
            readEvents: readEvents
        )
    }

    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([
            PlannerEvent.self, EventAllocation.self, ExpenseOccurrenceStatus.self
        ])
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                "LegacyIncomePersistence", schema: schema, url: url,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
