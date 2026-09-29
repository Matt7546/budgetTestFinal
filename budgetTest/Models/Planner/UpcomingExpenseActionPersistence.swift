import Foundation
import SwiftData

enum UpcomingExpenseActionPersistenceResult {
    case saved
    case failed(message: String)

    var didSave: Bool {
        if case .saved = self {
            return true
        }

        return false
    }

    var errorMessage: String? {
        guard case let .failed(message) = self else {
            return nil
        }

        return message
    }
}

enum UpcomingExpenseResolutionPersistenceResult {
    case saved(undo: ExpenseOccurrenceResolutionUndo)
    case failed(message: String)

    var errorMessage: String? {
        guard case let .failed(message) = self else {
            return nil
        }

        return message
    }
}

struct UpcomingExpenseActionSaveGate {

    private(set) var isSaving = false

    mutating func begin() -> Bool {
        guard !isSaving else {
            return false
        }

        isSaving = true
        return true
    }

    mutating func finish() {
        isSaving = false
    }
}

/// A synchronous, final read at the contribution boundary. A failed read is
/// never interchangeable with the absence of a resolution record.
@MainActor
struct BillContributionAuthorization {
    let modelContext: ModelContext
    let currentOwnerScopeID: String
    let availability: PlanningSnapshotAvailability
    let preparedGeneration: UInt64?
    let currentGeneration: UInt64
    var readStatuses: ((ModelContext, String) throws -> [ExpenseOccurrenceStatus])? = nil
    var readAllocations: ((ModelContext, String) throws -> [EventAllocation])? = nil

    func permits(
        forecast: ForecastEvent,
        replacementOccurrenceID: String? = nil,
        existingAllocation: EventAllocation? = nil
    ) -> Bool {
        guard let preparedGeneration,
              preparedGeneration == currentGeneration,
              PlanningMutationAuthorization.isAllowed(
                recordOwnerScopeID: forecast.event.ownerScopeID,
                currentOwnerScopeID: currentOwnerScopeID,
                availability: availability
              ),
              forecast.event.type == .expense else {
            return false
        }

        do {
            let eventID = forecast.event.id
            let events = try modelContext.fetch(
                FetchDescriptor<PlannerEvent>(
                    predicate: #Predicate { $0.id == eventID }
                )
            )
            guard events.count == 1,
                  events[0].persistentModelID == forecast.event.persistentModelID,
                  events[0].ownerScopeID == currentOwnerScopeID,
                  events[0].type == .expense else {
                return false
            }

            func statuses(for occurrenceID: String) throws
                -> [ExpenseOccurrenceStatus] {
                if let readStatuses {
                    return try readStatuses(modelContext, occurrenceID)
                }
                return try modelContext.fetch(
                    FetchDescriptor<ExpenseOccurrenceStatus>(
                        predicate: #Predicate {
                            $0.occurrenceID == occurrenceID
                        }
                    )
                )
            }

            let currentStatuses = try statuses(for: forecast.occurrenceID)
            func allocations(for occurrenceID: String) throws -> [EventAllocation] {
                if let readAllocations {
                    return try readAllocations(modelContext, occurrenceID)
                }
                return try modelContext.fetch(
                    FetchDescriptor<EventAllocation>(
                        predicate: #Predicate { $0.occurrenceID == occurrenceID }
                    )
                )
            }
            let currentAllocations = try allocations(for: forecast.occurrenceID)
                .filter { $0.ownerScopeID == currentOwnerScopeID }
            guard currentAllocations.count <= 1,
                  currentAllocations.first?.persistentModelID ==
                    existingAllocation?.persistentModelID,
                  currentAllocations.allSatisfy({
                      $0.sourceEventID == forecast.event.id &&
                          $0.occurrenceDate == forecast.normalizedOccurrenceDate
                  }) else { return false }
            // Any record for the exact key, including an unknown or duplicate
            // status, is not proof that this occurrence is unresolved.
            guard let replacementOccurrenceID,
                  replacementOccurrenceID != forecast.occurrenceID else {
                return currentStatuses.isEmpty
            }

            // An explicit schedule reset may fund a genuinely new occurrence,
            // but changing only the repeat pattern cannot reopen the old key.
            return try statuses(for: replacementOccurrenceID).isEmpty &&
                allocations(for: replacementOccurrenceID).filter {
                    $0.ownerScopeID == currentOwnerScopeID
                }.isEmpty
        } catch {
            return false
        }
    }
}

@MainActor
enum BillOccurrenceMutationIntegrity {
    static func permitsMutation(
        in modelContext: ModelContext,
        ownerScopeID: String?,
        occurrenceIDs: Set<String>
    ) -> Bool {
        do {
            let allAllocations = try modelContext.fetch(
                FetchDescriptor<EventAllocation>()
            ).filter { $0.ownerScopeID == ownerScopeID }
            let allStatuses = try modelContext.fetch(
                FetchDescriptor<ExpenseOccurrenceStatus>()
            ).filter { $0.ownerScopeID == ownerScopeID }
            guard !BillOccurrenceRecordIntegrity.hasConflict(
                allocations: allAllocations, statuses: allStatuses
            ) else { return false }
            let allocations = allAllocations.filter {
                occurrenceIDs.contains($0.occurrenceID)
            }
            let statuses = allStatuses.filter {
                occurrenceIDs.contains($0.occurrenceID)
            }
            return !BillOccurrenceRecordIntegrity.hasConflict(
                allocations: allocations, statuses: statuses
            ) && !BillOccurrenceRecordIntegrity.hasDuplicateRows(
                allocations: allocations, statuses: statuses
            )
        } catch {
            return false
        }
    }

    static func matchesAllocation(
        in modelContext: ModelContext,
        ownerScopeID: String?,
        occurrenceID: String,
        expected: EventAllocation?
    ) -> Bool {
        guard let rows = try? modelContext.fetch(
            FetchDescriptor<EventAllocation>()
        ) else { return false }
        let current = rows.filter {
            $0.ownerScopeID == ownerScopeID && $0.occurrenceID == occurrenceID
        }
        return current.map(\.persistentModelID) ==
            (expected.map { [$0.persistentModelID] } ?? [])
    }

    static func matchesRelatedRecords(
        in modelContext: ModelContext,
        ownerScopeID: String?,
        sourceEventID: UUID,
        allocations: [EventAllocation],
        statuses: [ExpenseOccurrenceStatus]
    ) -> Bool {
        guard let currentAllocations = try? modelContext.fetch(
            FetchDescriptor<EventAllocation>()
        ), let currentStatuses = try? modelContext.fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        ) else { return false }
        return Set(currentAllocations.filter {
            $0.ownerScopeID == ownerScopeID && $0.sourceEventID == sourceEventID
        }.map(\.persistentModelID)) == Set(allocations.map(\.persistentModelID)) &&
            Set(currentStatuses.filter {
                $0.ownerScopeID == ownerScopeID && $0.sourceEventID == sourceEventID
            }.map(\.persistentModelID)) == Set(statuses.map(\.persistentModelID))
    }
}

@MainActor
enum UpcomingExpenseActionPersistenceCoordinator {

    static let failureMessage =
        "This update wasn’t saved. Please try again."

    static func addSetAside(
        _ requestedAmount: Double,
        to forecast: ForecastEvent,
        authorization: BillContributionAuthorization,
        existingAllocation: EventAllocation?,
        insertAllocation: (EventAllocation) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> UpcomingExpenseActionPersistenceResult {
        let existingAmount = min(
            max(existingAllocation?.allocatedAmount ?? 0, 0),
            forecast.event.amount
        )
        let remainingAmount = max(
            forecast.event.amount - existingAmount,
            0
        )

        guard BillOccurrenceMutationIntegrity.permitsMutation(
            in: authorization.modelContext,
            ownerScopeID: authorization.currentOwnerScopeID,
            occurrenceIDs: [forecast.occurrenceID]
        ), authorization.permits(
            forecast: forecast, existingAllocation: existingAllocation
        ),
              requestedAmount.isFinite,
              requestedAmount > 0,
              remainingAmount > 0 else {
            return .failed(message: failureMessage)
        }

        let allocationSnapshot = existingAllocation.map(
            EventAllocationPersistenceSnapshot.init
        )
        let clampedAmount = min(requestedAmount, remainingAmount)

        if let existingAllocation {
            existingAllocation.apply(
                amount: clampedAmount,
                eventAmount: forecast.event.amount
            )
        } else {
            insertAllocation(
                EventAllocation(
                    ownerScopeID: forecast.event.ownerScopeID,
                    occurrenceID: forecast.occurrenceID,
                    sourceEventID: forecast.event.id,
                    occurrenceDate: forecast.normalizedOccurrenceDate,
                    allocatedAmount: clampedAmount
                )
            )
        }

        do {
            try persistChanges()
            return .saved
        } catch {
            rollback()

            if let existingAllocation,
               let allocationSnapshot {
                allocationSnapshot.restoreIfNeeded(existingAllocation)
            }

            return .failed(message: failureMessage)
        }
    }

    static func resetSetAside(
        _ allocation: EventAllocation,
        modelContext: ModelContext,
        deleteAllocation: (EventAllocation) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> UpcomingExpenseActionPersistenceResult {
        guard BillOccurrenceMutationIntegrity.permitsMutation(
            in: modelContext, ownerScopeID: allocation.ownerScopeID,
            occurrenceIDs: [allocation.occurrenceID]
        ), (try? modelContext.fetch(
            FetchDescriptor<EventAllocation>()
        ).filter({
            $0.occurrenceID == allocation.occurrenceID &&
                $0.ownerScopeID == allocation.ownerScopeID
        }))?
            .map(\.persistentModelID) == [allocation.persistentModelID] else {
            return .failed(message: failureMessage)
        }
        let allocationSnapshot = EventAllocationPersistenceSnapshot(
            allocation
        )
        deleteAllocation(allocation)

        do {
            try persistChanges()
            return .saved
        } catch {
            rollback()
            allocationSnapshot.restoreIfNeeded(allocation)
            return .failed(message: failureMessage)
        }
    }

    static func coverInFull(
        forecast: ForecastEvent,
        authorization: BillContributionAuthorization,
        existingAllocation: EventAllocation?,
        insertAllocation: (EventAllocation) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> UpcomingExpenseActionPersistenceResult {
        let remainingAmount = CoverInFullPolicy.remainingAmount(
            target: forecast.event.amount,
            current: existingAllocation?.allocatedAmount ?? 0
        )

        guard remainingAmount > 0 else {
            return .failed(message: failureMessage)
        }

        return addSetAside(
            remainingAmount,
            to: forecast,
            authorization: authorization,
            existingAllocation: existingAllocation,
            insertAllocation: insertAllocation,
            persistChanges: persistChanges,
            rollback: rollback
        )
    }

    static func resolve(
        _ resolution: ExpenseOccurrenceResolution,
        forecast: ForecastEvent,
        existingStatus: ExpenseOccurrenceStatus?,
        modelContext: ModelContext,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> UpcomingExpenseResolutionPersistenceResult {
        guard resolution.isManualResolution,
              BillOccurrenceMutationIntegrity.permitsMutation(
                  in: modelContext, ownerScopeID: forecast.event.ownerScopeID,
                  occurrenceIDs: [forecast.occurrenceID]
              ) else {
            return .failed(message: failureMessage)
        }
        guard (try? modelContext.fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        ).filter({
            $0.occurrenceID == forecast.occurrenceID &&
                $0.ownerScopeID == forecast.event.ownerScopeID
        }))?
            .map(\.persistentModelID) ==
            (existingStatus.map { [$0.persistentModelID] } ?? []) else {
            return .failed(message: failureMessage)
        }

        let undo = ExpenseOccurrenceResolutionMutation.apply(
            resolution,
            to: forecast,
            existingStatus: existingStatus,
            in: modelContext
        )

        do {
            try persistChanges()
            return .saved(undo: undo)
        } catch {
            undo.restore(in: modelContext)
            rollback()
            return .failed(message: failureMessage)
        }
    }

    static func undoResolution(
        _ undo: ExpenseOccurrenceResolutionUndo,
        modelContext: ModelContext,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> UpcomingExpenseActionPersistenceResult {
        guard BillOccurrenceMutationIntegrity.permitsMutation(
            in: modelContext, ownerScopeID: undo.statusRecord.ownerScopeID,
            occurrenceIDs: [undo.statusRecord.occurrenceID]
        ), (try? modelContext.fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        ).filter({
            $0.occurrenceID == undo.statusRecord.occurrenceID &&
                $0.ownerScopeID == undo.statusRecord.ownerScopeID
        }))?
            .map(\.persistentModelID) == [undo.statusRecord.persistentModelID] else {
            return .failed(message: failureMessage)
        }
        let resolvedSnapshot = ExpenseOccurrenceStatusPersistenceSnapshot(
            undo.statusRecord
        )
        undo.restore(in: modelContext)

        do {
            try persistChanges()
            return .saved
        } catch {
            rollback()
            resolvedSnapshot.restoreIfNeeded(undo.statusRecord)
            return .failed(message: failureMessage)
        }
    }
}

private struct EventAllocationPersistenceSnapshot {

    let allocatedAmount: Double
    let updatedAt: Date

    init(_ allocation: EventAllocation) {
        allocatedAmount = allocation.allocatedAmount
        updatedAt = allocation.updatedAt
    }

    func restoreIfNeeded(_ allocation: EventAllocation) {
        if allocation.allocatedAmount != allocatedAmount {
            allocation.allocatedAmount = allocatedAmount
        }

        if allocation.updatedAt != updatedAt {
            allocation.updatedAt = updatedAt
        }
    }
}

private struct ExpenseOccurrenceStatusPersistenceSnapshot {

    let statusRawValue: String
    let updatedAt: Date

    init(_ status: ExpenseOccurrenceStatus) {
        statusRawValue = status.statusRawValue
        updatedAt = status.updatedAt
    }

    func restoreIfNeeded(_ status: ExpenseOccurrenceStatus) {
        if status.statusRawValue != statusRawValue {
            status.statusRawValue = statusRawValue
        }

        if status.updatedAt != updatedAt {
            status.updatedAt = updatedAt
        }
    }
}
