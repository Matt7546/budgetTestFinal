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

@MainActor
enum UpcomingExpenseActionPersistenceCoordinator {

    static let failureMessage =
        "This update wasn’t saved. Please try again."

    static func addSetAside(
        _ requestedAmount: Double,
        to forecast: ForecastEvent,
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

        guard requestedAmount.isFinite,
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
        deleteAllocation: (EventAllocation) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> UpcomingExpenseActionPersistenceResult {
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

    static func resolve(
        _ resolution: ExpenseOccurrenceResolution,
        forecast: ForecastEvent,
        existingStatus: ExpenseOccurrenceStatus?,
        modelContext: ModelContext,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> UpcomingExpenseResolutionPersistenceResult {
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
