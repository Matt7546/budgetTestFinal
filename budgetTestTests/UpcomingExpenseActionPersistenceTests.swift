import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class UpcomingExpenseActionPersistenceTests: XCTestCase {

    func testInvalidPersistedAllocationRejectsPreparedAddWithoutSavingOrRepairing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 100)
        let invalid = makeAllocation(for: forecast, amount: -5)
        context.insert(forecast.event)
        context.insert(invalid)
        try context.save()
        var saveCount = 0
        let result = UpcomingExpenseActionPersistenceCoordinator.addSetAside(
            20,
            to: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: invalid,
            insertAllocation: { context.insert($0) },
            persistChanges: { saveCount += 1; try context.save() },
            rollback: context.rollback
        )
        XCTAssertFalse(result.didSave)
        XCTAssertEqual(saveCount, 0)
        let rows = try ModelContext(container).fetch(FetchDescriptor<EventAllocation>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.allocatedAmount, -5)
        XCTAssertTrue(
            UpcomingExpenseFundingSnapshot(
                events: [forecast.event], allocations: rows, occurrenceStatuses: []
            ).totalSetAside.isNaN
        )
    }

    func testPreparedAddCannotMutateOneOfTwoEquivalentPersistedAllocations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 100)
        let first = makeAllocation(for: forecast, amount: 40)
        context.insert(forecast.event)
        context.insert(first)
        try context.save()
        let prepared = billContributionAuthorization(context: context)

        // A second physical row arrives after the action was prepared.
        context.insert(makeAllocation(for: forecast, amount: 40))
        try context.save()
        var saveCount = 0
        let result = UpcomingExpenseActionPersistenceCoordinator.addSetAside(
            20,
            to: forecast,
            authorization: prepared,
            existingAllocation: first,
            insertAllocation: { context.insert($0) },
            persistChanges: { saveCount += 1; try context.save() },
            rollback: { context.rollback() }
        )
        XCTAssertFalse(result.didSave)
        XCTAssertEqual(saveCount, 0)
        let reloaded = ModelContext(container)
        let rows = try reloaded.fetch(FetchDescriptor<EventAllocation>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.allocatedAmount), [40, 40])
        XCTAssertEqual(
            UpcomingExpenseFundingSnapshot(
                events: [forecast.event], allocations: rows, occurrenceStatuses: []
            ).totalSetAside, 40
        )
    }

    func testConflictingPersistedStatusesBlockResolutionWithoutDeletingRows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 100)
        context.insert(forecast.event)
        context.insert(ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            status: .paid
        ))
        context.insert(ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            status: .skipped
        ))
        try context.save()
        var saveCount = 0
        let result = UpcomingExpenseActionPersistenceCoordinator.resolve(
            .paid,
            forecast: forecast,
            existingStatus: nil,
            modelContext: context,
            persistChanges: { saveCount += 1; try context.save() },
            rollback: { context.rollback() }
        )
        XCTAssertNotNil(result.errorMessage)
        XCTAssertEqual(saveCount, 0)
        let rows = try ModelContext(container).fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap(\.status)), [.paid, .skipped])
        XCTAssertEqual(
            PlanningSnapshotAvailability.resolving(
                base: .available,
                failedRequiredReads: [],
                hasBillRecordConflict: BillOccurrenceRecordIntegrity.hasConflict(
                    allocations: [], statuses: rows
                )
            ), .unavailable
        )
    }

    func testAddSetAsidePersistsBeforeSuccessAndPreservesIdentity() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 800)
        context.insert(forecast.event)
        try context.save()

        var insertedAllocation: EventAllocation?
        var didPersist = false

        let result = UpcomingExpenseActionPersistenceCoordinator.addSetAside(
            125.50,
            to: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: nil,
            insertAllocation: {
                insertedAllocation = $0
                context.insert($0)
            },
            persistChanges: {
                XCTAssertEqual(
                    insertedAllocation?.allocatedAmount ?? -1,
                    125.50,
                    accuracy: 0.001
                )
                try context.save()
                didPersist = true
            },
            rollback: { context.rollback() }
        )

        XCTAssertTrue(result.didSave)
        XCTAssertTrue(didPersist)
        let saved = try XCTUnwrap(
            context.fetch(FetchDescriptor<EventAllocation>()).first
        )
        XCTAssertEqual(saved.occurrenceID, forecast.occurrenceID)
        XCTAssertEqual(saved.sourceEventID, forecast.event.id)
        XCTAssertEqual(
            saved.occurrenceDate,
            forecast.normalizedOccurrenceDate
        )
    }

    func testResolvedBillRejectsOrdinaryAddWithoutSavingOrChangingPersistedForty() throws {
        for resolution in [
            ExpenseOccurrenceResolution.paid,
            .skipped,
            .postedFromChecking
        ] {
            let container = try makeContainer()
            let context = ModelContext(container)
            let forecast = makeForecast(amount: 100)
            let allocation = makeAllocation(for: forecast, amount: 40)
            let status = ExpenseOccurrenceStatus(
                occurrenceID: forecast.occurrenceID,
                sourceEventID: forecast.event.id,
                occurrenceDate: forecast.normalizedOccurrenceDate,
                status: resolution
            )
            context.insert(forecast.event)
            context.insert(allocation)
            context.insert(status)
            try context.save()

            var saveCount = 0
            let amount = try XCTUnwrap(MoneyAmountParser.parse("20"))
            let result = UpcomingExpenseActionPersistenceCoordinator.addSetAside(
                amount,
                to: forecast,
                authorization: billContributionAuthorization(context: context),
                existingAllocation: allocation,
                insertAllocation: { context.insert($0) },
                persistChanges: {
                    saveCount += 1
                    try context.save()
                },
                rollback: { context.rollback() }
            )

            XCTAssertFalse(result.didSave, "\(resolution)")
            XCTAssertEqual(saveCount, 0)
            let reloaded = ModelContext(container)
            let persisted = try XCTUnwrap(
                reloaded.fetch(FetchDescriptor<EventAllocation>()).first
            )
            XCTAssertEqual(persisted.id, allocation.id)
            XCTAssertEqual(persisted.allocatedAmount, 40, accuracy: 0.001)
            XCTAssertEqual(
                try reloaded.fetch(FetchDescriptor<EventAllocation>()).count,
                1
            )
            XCTAssertEqual(
                activeSetAside(
                    allocation: persisted,
                    forecast: forecast,
                    statuses: try reloaded.fetch(
                        FetchDescriptor<ExpenseOccurrenceStatus>()
                    )
                ),
                0,
                accuracy: 0.001
            )
        }
    }

    func testPreparedUnresolvedAddCannotSaveAfterExactOccurrenceResolves() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 100)
        let allocation = makeAllocation(for: forecast, amount: 40)
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()

        let preparedAuthorization = billContributionAuthorization(context: context)
        let preparedAmount = try XCTUnwrap(
            UpcomingExpenseSetAsideInput(
                changeMode: .add,
                amountText: "20"
            ).changeAmount
        )
        context.insert(ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            status: .paid
        ))
        try context.save()

        var saveCount = 0
        let result = UpcomingExpenseActionPersistenceCoordinator.addSetAside(
            preparedAmount,
            to: forecast,
            authorization: preparedAuthorization,
            existingAllocation: allocation,
            insertAllocation: { context.insert($0) },
            persistChanges: {
                saveCount += 1
                try context.save()
            },
            rollback: { context.rollback() }
        )

        XCTAssertFalse(result.didSave)
        XCTAssertEqual(saveCount, 0)
        let persisted = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<EventAllocation>()).first
        )
        XCTAssertEqual(persisted.allocatedAmount, 40, accuracy: 0.001)
    }

    func testUnresolvedBillAddSavesExactlyOnceAndPersistsSixty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 100)
        let allocation = makeAllocation(for: forecast, amount: 40)
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()

        var saveCount = 0
        let result = UpcomingExpenseActionPersistenceCoordinator.addSetAside(
            20,
            to: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: allocation,
            insertAllocation: { context.insert($0) },
            persistChanges: {
                saveCount += 1
                try context.save()
            },
            rollback: { context.rollback() }
        )

        XCTAssertTrue(result.didSave)
        XCTAssertEqual(saveCount, 1)
        let persisted = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<EventAllocation>()).first
        )
        XCTAssertEqual(persisted.allocatedAmount, 60, accuracy: 0.001)
    }

    func testFailedRequiredStatusReadAndInvalidScopeDenyBeforeMutation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 100)
        let allocation = makeAllocation(for: forecast, amount: 40)
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()

        let authorizations = [
            billContributionAuthorization(
                context: context,
                readStatuses: { _, _ in throw PersistenceTestError.failed }
            ),
            billContributionAuthorization(
                context: context,
                ownerScopeID: "another-owner"
            ),
            billContributionAuthorization(
                context: context,
                availability: .unavailable
            ),
            billContributionAuthorization(
                context: context,
                preparedGeneration: 1,
                currentGeneration: 2
            )
        ]
        var saveCount = 0
        for authorization in authorizations {
            let result = UpcomingExpenseActionPersistenceCoordinator.addSetAside(
                20,
                to: forecast,
                authorization: authorization,
                existingAllocation: allocation,
                insertAllocation: { context.insert($0) },
                persistChanges: {
                    saveCount += 1
                    try context.save()
                },
                rollback: { context.rollback() }
            )
            XCTAssertFalse(result.didSave)
        }
        XCTAssertEqual(saveCount, 0)
        let persisted = try XCTUnwrap(
            ModelContext(container).fetch(FetchDescriptor<EventAllocation>()).first
        )
        XCTAssertEqual(persisted.allocatedAmount, 40, accuracy: 0.001)
    }

    func testCoverInFullPersistsExactRemainingAmountAndPreservesIdentity() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 1_000)
        let allocation = makeAllocation(for: forecast, amount: 275)
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()

        var didPersist = false
        let allocationID = allocation.id
        let occurrenceID = allocation.occurrenceID
        let sourceEventID = allocation.sourceEventID
        let occurrenceDate = allocation.occurrenceDate
        let result = UpcomingExpenseActionPersistenceCoordinator.coverInFull(
            forecast: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: allocation,
            insertAllocation: { context.insert($0) },
            persistChanges: {
                XCTAssertEqual(
                    allocation.allocatedAmount,
                    1_000,
                    accuracy: 0.001
                )
                try context.save()
                didPersist = true
            },
            rollback: { context.rollback() }
        )

        XCTAssertTrue(result.didSave)
        XCTAssertTrue(didPersist)
        XCTAssertEqual(allocation.allocatedAmount, 1_000, accuracy: 0.001)
        XCTAssertEqual(allocation.id, allocationID)
        XCTAssertEqual(allocation.occurrenceID, occurrenceID)
        XCTAssertEqual(allocation.sourceEventID, sourceEventID)
        XCTAssertEqual(allocation.occurrenceDate, occurrenceDate)
    }

    func testCoverInFullCreatesAllocationForExactOccurrence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 875)
        context.insert(forecast.event)
        try context.save()

        let result = UpcomingExpenseActionPersistenceCoordinator.coverInFull(
            forecast: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: nil,
            insertAllocation: { context.insert($0) },
            persistChanges: { try context.save() },
            rollback: { context.rollback() }
        )

        XCTAssertTrue(result.didSave)
        let saved = try XCTUnwrap(
            context.fetch(FetchDescriptor<EventAllocation>()).first
        )
        XCTAssertEqual(saved.allocatedAmount, 875, accuracy: 0.001)
        XCTAssertEqual(saved.occurrenceID, forecast.occurrenceID)
        XCTAssertEqual(saved.sourceEventID, forecast.event.id)
        XCTAssertEqual(
            saved.occurrenceDate,
            forecast.normalizedOccurrenceDate
        )
    }

    func testPastDueCoverInFullDoesNotResolveOccurrence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let forecast = makeForecast(
            amount: 700,
            dueDate: now.addingTimeInterval(-86_400)
        )
        context.insert(forecast.event)
        try context.save()

        let result = UpcomingExpenseActionPersistenceCoordinator.coverInFull(
            forecast: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: nil,
            insertAllocation: { context.insert($0) },
            persistChanges: { try context.save() },
            rollback: { context.rollback() }
        )

        XCTAssertTrue(result.didSave)
        let statuses = try context.fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        )
        XCTAssertTrue(statuses.isEmpty)

        switch ExpenseOccurrenceLifecycleResolver.lifecycle(
            for: forecast,
            statuses: statuses,
            now: now
        ) {
        case .overdue:
            break
        case .upcoming,
                .paid,
                .skipped,
                .chargedToCard,
                .postedFromChecking:
            XCTFail("Covering must leave the Past Due occurrence unresolved")
        }

        XCTAssertEqual(
            ExpenseOccurrenceLifecycleResolver
                .unresolvedPastDueForecasts(
                    from: [forecast],
                    statuses: statuses,
                    now: now
                )
                .map(\.occurrenceID),
            [forecast.occurrenceID]
        )
    }

    func testFailedCoverInFullRollsBackAllocation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 1_000)
        let allocation = makeAllocation(for: forecast, amount: 275)
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()
        let originalUpdatedAt = allocation.updatedAt

        let result = UpcomingExpenseActionPersistenceCoordinator.coverInFull(
            forecast: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: allocation,
            insertAllocation: { context.insert($0) },
            persistChanges: { throw PersistenceTestError.failed },
            rollback: { context.rollback() }
        )

        XCTAssertFalse(result.didSave)
        XCTAssertEqual(
            result.errorMessage,
            CoverInFullPolicy.failureMessage
        )
        XCTAssertEqual(allocation.allocatedAmount, 275, accuracy: 0.001)
        XCTAssertEqual(allocation.updatedAt, originalUpdatedAt)
    }

    func testCoverInFullCannotApplyTwice() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast(amount: 1_000)
        let allocation = makeAllocation(for: forecast, amount: 275)
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()
        var persistenceCount = 0

        let persist: () throws -> Void = {
            persistenceCount += 1
            try context.save()
        }
        let first = UpcomingExpenseActionPersistenceCoordinator.coverInFull(
            forecast: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: allocation,
            insertAllocation: { context.insert($0) },
            persistChanges: persist,
            rollback: { context.rollback() }
        )
        let second = UpcomingExpenseActionPersistenceCoordinator.coverInFull(
            forecast: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: allocation,
            insertAllocation: { context.insert($0) },
            persistChanges: persist,
            rollback: { context.rollback() }
        )

        XCTAssertTrue(first.didSave)
        XCTAssertFalse(second.didSave)
        XCTAssertEqual(persistenceCount, 1)
        XCTAssertEqual(allocation.allocatedAmount, 1_000, accuracy: 0.001)
    }

    func testResetSetAsidePersistsDeletionBeforeSuccess() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast()
        let allocation = makeAllocation(for: forecast, amount: 300)
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()

        var didPersist = false
        let result = UpcomingExpenseActionPersistenceCoordinator
            .resetSetAside(
                allocation,
                modelContext: context,
                deleteAllocation: { context.delete($0) },
                persistChanges: {
                    try context.save()
                    didPersist = true
                },
                rollback: { context.rollback() }
            )

        XCTAssertTrue(result.didSave)
        XCTAssertTrue(didPersist)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<EventAllocation>()).isEmpty
        )
    }

    func testMarkPaidPersistsBeforeLeavingPastDue() throws {
        try assertResolutionPersistsBeforeLeavingPastDue(.paid)
    }

    func testSkipPersistsBeforeLeavingPastDue() throws {
        try assertResolutionPersistsBeforeLeavingPastDue(.skipped)
    }

    func testFailedAddRollsBackAllocationAndKeepsTypedInput() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast()
        let allocation = makeAllocation(for: forecast, amount: 300)
        let originalUpdatedAt = allocation.updatedAt
        let amountText = "125.75"
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()

        let result = UpcomingExpenseActionPersistenceCoordinator.addSetAside(
            125.75,
            to: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: allocation,
            insertAllocation: { context.insert($0) },
            persistChanges: { throw PersistenceTestError.failed },
            rollback: { context.rollback() }
        )

        XCTAssertFalse(result.didSave)
        XCTAssertEqual(
            result.errorMessage,
            "This update wasn’t saved. Please try again."
        )
        XCTAssertEqual(allocation.allocatedAmount, 300, accuracy: 0.001)
        XCTAssertEqual(allocation.updatedAt, originalUpdatedAt)
        XCTAssertEqual(amountText, "125.75")
        XCTAssertEqual(
            try XCTUnwrap(ModelContext(container).fetch(
                FetchDescriptor<EventAllocation>()
            ).first).allocatedAmount,
            300,
            accuracy: 0.001
        )
    }

    func testFailedFirstAddRemovesUnpersistedAllocation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast()
        context.insert(forecast.event)
        try context.save()

        let result = UpcomingExpenseActionPersistenceCoordinator.addSetAside(
            125,
            to: forecast,
            authorization: billContributionAuthorization(context: context),
            existingAllocation: nil,
            insertAllocation: { context.insert($0) },
            persistChanges: { throw PersistenceTestError.failed },
            rollback: { context.rollback() }
        )

        XCTAssertFalse(result.didSave)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<EventAllocation>()).isEmpty
        )
    }

    func testFailedResetRestoresDeletedAllocation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast()
        let allocation = makeAllocation(for: forecast, amount: 300)
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()

        let result = UpcomingExpenseActionPersistenceCoordinator
            .resetSetAside(
                allocation,
                modelContext: context,
                deleteAllocation: { context.delete($0) },
                persistChanges: { throw PersistenceTestError.failed },
                rollback: { context.rollback() }
            )

        XCTAssertFalse(result.didSave)
        let restored = try XCTUnwrap(
            context.fetch(FetchDescriptor<EventAllocation>()).first
        )
        XCTAssertEqual(restored.occurrenceID, forecast.occurrenceID)
        XCTAssertEqual(restored.allocatedAmount, 300, accuracy: 0.001)
    }

    func testFailedResolutionRollsBackStatusAndKeepsPastDueActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let forecast = makeForecast(
            dueDate: now.addingTimeInterval(-86_400)
        )
        context.insert(forecast.event)
        try context.save()

        let result = UpcomingExpenseActionPersistenceCoordinator.resolve(
            .paid,
            forecast: forecast,
            existingStatus: nil,
            modelContext: context,
            persistChanges: { throw PersistenceTestError.failed },
            rollback: { context.rollback() }
        )

        guard case .failed(let message) = result else {
            return XCTFail("Expected persistence failure")
        }
        XCTAssertEqual(
            message,
            "This update wasn’t saved. Please try again."
        )
        let statuses = try context.fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        )
        XCTAssertTrue(statuses.isEmpty)
        XCTAssertEqual(
            ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
                from: [forecast],
                statuses: statuses,
                now: now
            ).map(\.occurrenceID),
            [forecast.occurrenceID]
        )
    }

    func testFailedUndoKeepsPersistedResolution() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast()
        context.insert(forecast.event)
        try context.save()

        let resolutionResult = UpcomingExpenseActionPersistenceCoordinator
            .resolve(
                .skipped,
                forecast: forecast,
                existingStatus: nil,
                modelContext: context,
                persistChanges: { try context.save() },
                rollback: { context.rollback() }
            )
        guard case let .saved(undo) = resolutionResult else {
            return XCTFail("Expected the resolution to save")
        }

        let undoResult = UpcomingExpenseActionPersistenceCoordinator
            .undoResolution(
                undo,
                modelContext: context,
                persistChanges: { throw PersistenceTestError.failed },
                rollback: { context.rollback() }
            )

        XCTAssertFalse(undoResult.didSave)
        let savedStatus = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<ExpenseOccurrenceStatus>()
            ).first
        )
        XCTAssertEqual(savedStatus.status, .skipped)
        XCTAssertEqual(savedStatus.occurrenceID, forecast.occurrenceID)
        XCTAssertEqual(savedStatus.sourceEventID, forecast.event.id)
    }

    func testPersistedUndoRestoresExactSetAsideEffect() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast()
        let allocation = makeAllocation(for: forecast, amount: 600)
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()

        let resolutionResult = UpcomingExpenseActionPersistenceCoordinator
            .resolve(
                .paid,
                forecast: forecast,
                existingStatus: nil,
                modelContext: context,
                persistChanges: { try context.save() },
                rollback: { context.rollback() }
            )
        guard case let .saved(undo) = resolutionResult else {
            return XCTFail("Expected the resolution to save")
        }

        XCTAssertEqual(
            activeSetAside(
                allocation: allocation,
                forecast: forecast,
                statuses: try context.fetch(
                    FetchDescriptor<ExpenseOccurrenceStatus>()
                )
            ),
            0,
            accuracy: 0.001
        )

        let undoResult = UpcomingExpenseActionPersistenceCoordinator
            .undoResolution(
                undo,
                modelContext: context,
                persistChanges: { try context.save() },
                rollback: { context.rollback() }
            )

        XCTAssertTrue(undoResult.didSave)
        let statuses = try context.fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        )
        XCTAssertTrue(statuses.isEmpty)
        XCTAssertEqual(
            activeSetAside(
                allocation: allocation,
                forecast: forecast,
                statuses: statuses
            ),
            600,
            accuracy: 0.001
        )
    }

    func testSaveGateRejectsDuplicateTapUntilPersistenceFinishes() {
        var gate = UpcomingExpenseActionSaveGate()

        XCTAssertTrue(gate.begin())
        XCTAssertTrue(gate.isSaving)
        XCTAssertFalse(gate.begin())

        gate.finish()

        XCTAssertFalse(gate.isSaving)
        XCTAssertTrue(gate.begin())
    }

    func testUseSetAsideFailureRestoresAllocationAndKeepsInput() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let forecast = makeForecast()
        let allocation = makeAllocation(for: forecast, amount: 600)
        context.insert(forecast.event)
        context.insert(allocation)
        try context.save()

        let details = UpcomingExpenseEditInput(event: forecast.event)
        let setAside = UpcomingExpenseSetAsideInput(
            changeMode: .use,
            amountText: "175.50"
        )
        let result = UpcomingExpenseUnifiedPersistenceCoordinator.persist(
            details: details,
            setAside: setAside,
            event: forecast.event,
            forecast: forecast,
            authorization: billContributionAuthorization(context: context),
            allocation: allocation,
            currentSetAside: 600,
            resetOccurrenceTracking: false,
            relatedAllocations: [allocation],
            relatedStatuses: [],
            insertAllocation: { context.insert($0) },
            deleteAllocation: { context.delete($0) },
            deleteStatus: { context.delete($0) },
            persistChanges: { throw PersistenceTestError.failed },
            rollback: { context.rollback() }
        )

        XCTAssertFalse(result.startsSuccessFlow)
        XCTAssertEqual(allocation.allocatedAmount, 600, accuracy: 0.001)
        XCTAssertEqual(setAside.amountText, "175.50")
    }

    private func assertResolutionPersistsBeforeLeavingPastDue(
        _ resolution: ExpenseOccurrenceResolution
    ) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let forecast = makeForecast(
            dueDate: now.addingTimeInterval(-86_400)
        )
        context.insert(forecast.event)
        try context.save()

        var didPersist = false
        let result = UpcomingExpenseActionPersistenceCoordinator.resolve(
            resolution,
            forecast: forecast,
            existingStatus: nil,
            modelContext: context,
            persistChanges: {
                try context.save()
                didPersist = true
            },
            rollback: { context.rollback() }
        )

        guard case .saved = result else {
            return XCTFail("Expected resolution to save")
        }
        XCTAssertTrue(didPersist)
        let statuses = try context.fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        )
        let status = try XCTUnwrap(statuses.first)
        XCTAssertEqual(status.status, resolution)
        XCTAssertEqual(status.occurrenceID, forecast.occurrenceID)
        XCTAssertEqual(status.sourceEventID, forecast.event.id)
        XCTAssertTrue(
            ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
                from: [forecast],
                statuses: statuses,
                now: now
            ).isEmpty
        )
    }

    private func activeSetAside(
        allocation: EventAllocation,
        forecast: ForecastEvent,
        statuses: [ExpenseOccurrenceStatus]
    ) -> Double {
        let resolvedIDs = ExpenseOccurrenceLifecycleResolver
            .resolvedOccurrenceIDs(from: statuses)
        let activeForecasts = [forecast].filter {
            !resolvedIDs.contains($0.occurrenceID)
        }

        return EventAllocationTotals.activeTotal(
            allocations: [allocation],
            forecastEvents: activeForecasts
        )
    }

    private func makeForecast(
        amount: Double = 1_000,
        dueDate: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> ForecastEvent {
        let event = PlannerEvent(
            name: "Rent",
            amount: amount,
            date: dueDate,
            frequency: .monthly,
            type: .expense
        )

        return ForecastEvent(event: event, occurrenceDate: dueDate)
    }

    private func makeAllocation(
        for forecast: ForecastEvent,
        amount: Double
    ) -> EventAllocation {
        EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: amount
        )
    }

    private func makeContainer() throws -> ModelContainer {
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

private enum PersistenceTestError: Error {
    case failed
}

@MainActor
func billContributionAuthorization(
    context: ModelContext,
    ownerScopeID: String = PlanningOwnerScope.local,
    availability: PlanningSnapshotAvailability = .available,
    preparedGeneration: UInt64? = 0,
    currentGeneration: UInt64 = 0,
    readStatuses: ((ModelContext, String) throws -> [ExpenseOccurrenceStatus])? = nil
) -> BillContributionAuthorization {
    BillContributionAuthorization(
        modelContext: context,
        currentOwnerScopeID: ownerScopeID,
        availability: availability,
        preparedGeneration: preparedGeneration,
        currentGeneration: currentGeneration,
        readStatuses: readStatuses
    )
}
