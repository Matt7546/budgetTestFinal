import Foundation

/// Optional value-only validation plumbing. Ordinary production supplies nil.
/// The test target owns scheduling and lifetime; these callbacks never own it.
struct PlanningViewValidationHooks {
    enum TraceEvent: Equatable {
        case failedInput(Set<PlanningPersistenceReadDomain>)
        case recoveredInput
        case viewAvailabilityUpdated(PlanningSnapshotAvailability)
        case mutationGenerationInvalidated(UInt64)
        case holdControlMounted
        case callbackQueued(UInt64)
        case callbackTaskStarted(UInt64)
        case callbackCancellationRequested(UInt64)
        case callbackReleased(UInt64)
        case callbackSettled(UInt64)
        case holdControlDisappeared
        case callbackEntry(UInt64, wasCancelled: Bool)
        case finalAuthorization(UInt64?, allowed: Bool)
        case persistenceAttempt(UInt64?)
    }

    struct TraceEntry: Equatable {
        let sequence: UInt64
        let event: TraceEvent
    }

    let currentReadFailures: @MainActor () -> Set<PlanningPersistenceReadDomain>
    let observe: @MainActor (TraceEvent) -> Void
    let queueDeferredCallback: @MainActor () -> UInt64?
    let awaitDeferredCallbackRelease: @MainActor (UInt64?) async -> Bool
    let beginCallbackExecution: @MainActor (UInt64?) -> Bool
    let endCallbackExecution: @MainActor (UInt64?) -> Void
    let recordFinalAuthorization: @MainActor (Bool) -> Void
    let recordPersistenceAttempt: @MainActor () -> Void
    #if DEBUG
    let registerCallbackTask: @MainActor (UInt64?, Task<Void, Never>) -> Void
    let registerQueuedCallbackExecutor: @MainActor (UInt64?, @escaping @MainActor () -> Void) -> Void
    #endif

    func recordViewAvailability(_ availability: PlanningSnapshotAvailability) {
        observe(.viewAvailabilityUpdated(availability))
    }
    func recordMutationGenerationInvalidated(_ generation: UInt64) {
        observe(.mutationGenerationInvalidated(generation))
    }
    func recordHoldControlMounted() { observe(.holdControlMounted) }
    func recordHoldControlDisappeared() { observe(.holdControlDisappeared) }
    func recordCallbackTaskStarted(_ id: UInt64?) {
        if let id { observe(.callbackTaskStarted(id)) }
    }
    func recordCallbackCancellationRequested(_ id: UInt64?) {
        if let id { observe(.callbackCancellationRequested(id)) }
    }
    func recordCallbackSettled(_ id: UInt64?) {
        if let id { observe(.callbackSettled(id)) }
    }
    func recordCallbackEntry(_ id: UInt64?, wasCancelled: Bool) {
        if let id { observe(.callbackEntry(id, wasCancelled: wasCancelled)) }
    }
}

/// Values that explicitly invalidate the test host's SwiftUI body. Command-time
/// reads use currentReadFailures, so authorization does not wait for observation.
struct PlanningViewValidationInputs: Equatable {
    var additionalFailedRequiredReads: Set<PlanningPersistenceReadDomain> = []
    var mountedHoldActivationGeneration: UInt64 = 0
}
