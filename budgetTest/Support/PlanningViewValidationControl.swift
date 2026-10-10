import Foundation
import Observation

/// A source-level validation seam for mounted planning-view tests.
///
/// Absent in ordinary production construction. An injected instance can only
/// add required query failures; it cannot hide a production `@Query.fetchError` or make an
/// unavailable planning snapshot authoritative. There is intentionally no
/// launch argument, defaults key, or environment-variable activation path.
@MainActor
@Observable
final class PlanningViewValidationControl {

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

    private(set) var additionalFailedRequiredReads:
        Set<PlanningPersistenceReadDomain> = []
    private(set) var mountedHoldActivationGeneration: UInt64 = 0

    @ObservationIgnored private(set) var trace: [TraceEntry] = []
    @ObservationIgnored var traceObserver: ((TraceEntry) -> Void)?

    private let isTestEnabled: Bool
    private let blocksDeferredCallbacks: Bool
    @ObservationIgnored private var nextTraceSequence: UInt64 = 0
    @ObservationIgnored private var nextCallbackID: UInt64 = 0
    @ObservationIgnored private var deferredCallbackContinuations:
        [UInt64: CheckedContinuation<Void, Never>] = [:]
    @ObservationIgnored private var queuedCallbackIDs: Set<UInt64> = []
    @ObservationIgnored private var releasedBeforeWaitingCallbackIDs: Set<UInt64> = []
    #if DEBUG
    @ObservationIgnored private var callbacksExecutedBeforeTaskResume: Set<UInt64> = []
    @ObservationIgnored private var queuedCallbackExecutors: [UInt64: () -> Void] = [:]
    @ObservationIgnored private var callbackTasks: [UInt64: Task<Void, Never>] = [:]
    private(set) static var constructedInstanceCount = 0
    #endif
    @ObservationIgnored private(set) var executingCallbackID: UInt64?

    init(
        isTestEnabled: Bool = false,
        blocksDeferredCallbacks: Bool = false
    ) {
        self.isTestEnabled = isTestEnabled
        self.blocksDeferredCallbacks = blocksDeferredCallbacks
        #if DEBUG
        Self.constructedInstanceCount += 1
        #endif
    }

    func supplyRequiredQueryFailure(
        _ domain: PlanningPersistenceReadDomain
    ) {
        guard isTestEnabled else { return }
        additionalFailedRequiredReads.insert(domain)
        record(.failedInput(additionalFailedRequiredReads))
    }

    func recoverRequiredQueries() {
        guard isTestEnabled else { return }
        additionalFailedRequiredReads.removeAll()
        record(.recoveredInput)
    }

    /// Mounted-method activation for unit-hosted SwiftUI validation only.
    /// Physical control interaction is intentionally left to XCUIAutomation.
    func requestMountedHoldCallback() {
        guard isTestEnabled else { return }
        mountedHoldActivationGeneration &+= 1
    }

    func recordViewAvailability(
        _ availability: PlanningSnapshotAvailability
    ) {
        record(.viewAvailabilityUpdated(availability))
    }

    func recordMutationGenerationInvalidated(_ generation: UInt64) {
        record(.mutationGenerationInvalidated(generation))
    }

    func recordHoldControlMounted() {
        record(.holdControlMounted)
    }

    func queueDeferredCallback() -> UInt64? {
        guard isTestEnabled else { return nil }
        nextCallbackID &+= 1
        let callbackID = nextCallbackID
        queuedCallbackIDs.insert(callbackID)
        record(.callbackQueued(callbackID))
        return callbackID
    }

    #if DEBUG
    func registerCallbackTask(_ callbackID: UInt64?, task: Task<Void, Never>) {
        guard isTestEnabled, let callbackID else { return }
        callbackTasks[callbackID] = task
    }

    /// Wait on the actual production commit Task, not a SwiftUI observer or
    /// a trace emitted just before that Task returns.
    @discardableResult
    func awaitCallbackTaskSettlement(_ callbackID: UInt64) async -> Bool {
        guard let task = callbackTasks[callbackID] else { return false }
        await task.value
        callbackTasks.removeValue(forKey: callbackID)
        return true
    }

    func registerQueuedCallbackExecutor(
        _ callbackID: UInt64?,
        execute: @escaping () -> Void
    ) {
        guard isTestEnabled,
              let callbackID,
              queuedCallbackIDs.contains(callbackID) else {
            return
        }
        queuedCallbackExecutors[callbackID] = execute
    }

    /// Executes the mounted control's own callback in this main-actor turn.
    /// Tests use this stronger scheduling intervention to model the callback
    /// winning a turn over SwiftUI's availability observer.
    @discardableResult
    func executeQueuedCallbackBeforeObserver(_ callbackID: UInt64) -> Bool {
        guard isTestEnabled,
              blocksDeferredCallbacks,
              queuedCallbackIDs.contains(callbackID),
              let execute = queuedCallbackExecutors.removeValue(
                forKey: callbackID
              ) else {
            return false
        }

        queuedCallbackIDs.remove(callbackID)
        record(.callbackReleased(callbackID))
        callbacksExecutedBeforeTaskResume.insert(callbackID)
        if let continuation = deferredCallbackContinuations.removeValue(
            forKey: callbackID
        ) {
            continuation.resume()
        }
        execute()
        return true
    }
    #endif

    func awaitDeferredCallbackRelease(_ callbackID: UInt64?) async -> Bool {
        guard isTestEnabled,
              blocksDeferredCallbacks,
              let callbackID else {
            return true
        }

        #if DEBUG
        if callbacksExecutedBeforeTaskResume.remove(callbackID) != nil {
            return false
        }
        #endif

        if releasedBeforeWaitingCallbackIDs.remove(callbackID) != nil {
            queuedCallbackIDs.remove(callbackID)
            return true
        }

        await withCheckedContinuation { continuation in
            deferredCallbackContinuations[callbackID] = continuation
        }
        #if DEBUG
        return callbacksExecutedBeforeTaskResume.remove(callbackID) == nil
        #else
        return true
        #endif
    }

    @discardableResult
    func releaseDeferredCallback(_ callbackID: UInt64) -> Bool {
        guard queuedCallbackIDs.contains(callbackID) else {
            return false
        }

        queuedCallbackIDs.remove(callbackID)
        record(.callbackReleased(callbackID))

        guard let continuation =
                deferredCallbackContinuations.removeValue(
                    forKey: callbackID
                ) else {
            releasedBeforeWaitingCallbackIDs.insert(callbackID)
            return true
        }

        continuation.resume()
        return true
    }

    func releaseAllDeferredCallbacks() {
        let callbackIDs = queuedCallbackIDs
        for callbackID in callbackIDs {
            _ = releaseDeferredCallback(callbackID)
        }
    }

    func recordCallbackTaskStarted(_ callbackID: UInt64?) {
        if let callbackID { record(.callbackTaskStarted(callbackID)) }
    }

    func recordCallbackCancellationRequested(_ callbackID: UInt64?) {
        if let callbackID { record(.callbackCancellationRequested(callbackID)) }
    }

    func recordCallbackSettled(_ callbackID: UInt64?) {
        if let callbackID { record(.callbackSettled(callbackID)) }
    }

    func recordHoldControlDisappeared() { record(.holdControlDisappeared) }

    func recordCallbackEntry(
        _ callbackID: UInt64?,
        wasCancelled: Bool
    ) {
        guard let callbackID else { return }
        #if DEBUG
        if wasCancelled {
            queuedCallbackExecutors.removeValue(forKey: callbackID)
        }
        #endif
        record(
            .callbackEntry(
                callbackID,
                wasCancelled: wasCancelled
            )
        )
    }

    func beginCallbackExecution(_ callbackID: UInt64?) {
        executingCallbackID = callbackID
    }

    func endCallbackExecution(_ callbackID: UInt64?) {
        guard executingCallbackID == callbackID else { return }
        executingCallbackID = nil
        #if DEBUG
        if let callbackID {
            queuedCallbackExecutors.removeValue(forKey: callbackID)
        }
        #endif
    }

    func recordFinalAuthorization(_ allowed: Bool) {
        record(
            .finalAuthorization(
                executingCallbackID,
                allowed: allowed
            )
        )
    }

    func recordPersistenceAttempt() {
        record(.persistenceAttempt(executingCallbackID))
    }

    private func record(_ event: TraceEvent) {
        guard isTestEnabled else { return }
        nextTraceSequence &+= 1
        let entry = TraceEntry(
            sequence: nextTraceSequence,
            event: event
        )
        trace.append(entry)
        traceObserver?(entry)
    }
}
