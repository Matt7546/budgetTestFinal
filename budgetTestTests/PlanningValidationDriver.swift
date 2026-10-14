import Foundation
import SwiftUI
import XCTest
@testable import Caldera_Money

/// Test-owned lifetime identity. Mutable work is compiler-isolated to MainActor;
/// the class and its synthesized destructor are deliberately nonisolated.
nonisolated final class PlanningValidationDriver {
    typealias TraceEvent = PlanningViewValidationHooks.TraceEvent
    typealias TraceEntry = PlanningViewValidationHooks.TraceEntry
    @MainActor private(set) var additionalFailedRequiredReads:
        Set<PlanningPersistenceReadDomain> = []
    @MainActor private(set) var mountedHoldActivationGeneration: UInt64 = 0

    @MainActor private(set) var trace: [TraceEntry] = []
    @MainActor var traceObserver: ((TraceEntry) -> Void)?

    @MainActor private let isTestEnabled: Bool
    @MainActor private let blocksDeferredCallbacks: Bool
    @MainActor private var nextTraceSequence: UInt64 = 0
    @MainActor private var nextCallbackID: UInt64 = 0
    @MainActor private var deferredCallbackContinuations:
        [UInt64: CheckedContinuation<Void, Never>] = [:]
    @MainActor private var queuedCallbackIDs: Set<UInt64> = []
    @MainActor private var releasedBeforeWaitingCallbackIDs: Set<UInt64> = []
    #if DEBUG
    @MainActor private var callbacksExecutedBeforeTaskResume: Set<UInt64> = []
    @MainActor private var queuedCallbackExecutors: [UInt64: @MainActor () -> Void] = [:]
    @MainActor private var callbackTasks: [UInt64: Task<Void, Never>] = [:]
    @MainActor private(set) static var constructedInstanceCount = 0
    #endif
    @MainActor private(set) var executingCallbackID: UInt64?

    @MainActor
    init(
        isTestEnabled: Bool = true,
        blocksDeferredCallbacks: Bool = false
    ) {
        self.isTestEnabled = isTestEnabled
        self.blocksDeferredCallbacks = blocksDeferredCallbacks
        #if DEBUG
        Self.constructedInstanceCount += 1
        #endif
    }

    @MainActor
    func supplyRequiredQueryFailure(
        _ domain: PlanningPersistenceReadDomain
    ) {
        guard isTestEnabled, ensureOpen() else { return }
        additionalFailedRequiredReads.insert(domain)
        record(.failedInput(additionalFailedRequiredReads))
        publishInputs()
    }

    @MainActor
    func recoverRequiredQueries() {
        guard isTestEnabled, ensureOpen() else { return }
        additionalFailedRequiredReads.removeAll()
        record(.recoveredInput)
        publishInputs()
    }

    /// Mounted-method activation for unit-hosted SwiftUI validation only.
    /// Physical control interaction is intentionally left to XCUIAutomation.
    @MainActor
    func requestMountedHoldCallback() {
        guard isTestEnabled, ensureOpen() else { return }
        mountedHoldActivationGeneration &+= 1
        publishInputs()
    }

    @MainActor
    func recordViewAvailability(
        _ availability: PlanningSnapshotAvailability
    ) {
        record(.viewAvailabilityUpdated(availability))
    }

    @MainActor
    func recordMutationGenerationInvalidated(_ generation: UInt64) {
        record(.mutationGenerationInvalidated(generation))
    }

    @MainActor
    func recordHoldControlMounted() {
        record(.holdControlMounted)
    }

    @MainActor
    func queueDeferredCallback() -> UInt64? {
        guard isTestEnabled, ensureOpen() else { return nil }
        nextCallbackID &+= 1
        let callbackID = nextCallbackID
        queuedCallbackIDs.insert(callbackID)
        record(.callbackQueued(callbackID))
        return callbackID
    }

    #if DEBUG
    @MainActor
    func registerCallbackTask(_ callbackID: UInt64?, task: Task<Void, Never>) {
        guard ensureOpen(), isTestEnabled, let callbackID else { return }
        callbackTasks[callbackID] = task
    }

    /// Wait on the actual production commit Task, not a SwiftUI observer or
    /// a trace emitted just before that Task returns.
    @discardableResult
    @MainActor
    func awaitCallbackTaskSettlement(_ callbackID: UInt64) async -> Bool {
        guard let task = callbackTasks[callbackID] else { return false }
        await task.value
        callbackTasks.removeValue(forKey: callbackID)
        return true
    }

    @MainActor
    func registerQueuedCallbackExecutor(
        _ callbackID: UInt64?,
        execute: @escaping @MainActor () -> Void
    ) {
        guard ensureOpen(), isTestEnabled,
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
    @MainActor
    func executeQueuedCallbackBeforeObserver(_ callbackID: UInt64) -> Bool {
        guard ensureOpen(), isTestEnabled,
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

    @MainActor
    func awaitDeferredCallbackRelease(_ callbackID: UInt64?) async -> Bool {
        guard ensureOpen() else { return false }
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
    @MainActor
    func releaseDeferredCallback(_ callbackID: UInt64) -> Bool {
        guard ensureOpen() else { return false }
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

    @MainActor
    func releaseAllDeferredCallbacks() {
        guard ensureOpen() else { return }
        let callbackIDs = queuedCallbackIDs
        for callbackID in callbackIDs {
            _ = releaseDeferredCallback(callbackID)
        }
    }

    @MainActor
    func recordCallbackTaskStarted(_ callbackID: UInt64?) {
        if let callbackID { record(.callbackTaskStarted(callbackID)) }
    }

    @MainActor
    func recordCallbackCancellationRequested(_ callbackID: UInt64?) {
        if let callbackID { record(.callbackCancellationRequested(callbackID)) }
    }

    @MainActor
    func recordCallbackSettled(_ callbackID: UInt64?) {
        if let callbackID { record(.callbackSettled(callbackID)) }
    }

    @MainActor
    func recordHoldControlDisappeared() { record(.holdControlDisappeared) }

    @MainActor
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

    @MainActor
    func beginCallbackExecution(_ callbackID: UInt64?) -> Bool {
        guard ensureOpen() else { return false }
        executingCallbackID = callbackID
        return true
    }

    @MainActor
    func endCallbackExecution(_ callbackID: UInt64?) {
        guard executingCallbackID == callbackID else { return }
        executingCallbackID = nil
        #if DEBUG
        if let callbackID {
            queuedCallbackExecutors.removeValue(forKey: callbackID)
        }
        #endif
    }

    @MainActor
    func recordFinalAuthorization(_ allowed: Bool) {
        record(
            .finalAuthorization(
                executingCallbackID,
                allowed: allowed
            )
        )
    }

    @MainActor
    func recordPersistenceAttempt() {
        record(.persistenceAttempt(executingCallbackID))
    }

    @MainActor
    private func record(_ event: TraceEvent) {
        guard isTestEnabled, !isClosed else {
            XCTFail("Validation hook invoked after driver close")
            return
        }
        nextTraceSequence &+= 1
        let entry = TraceEntry(
            sequence: nextTraceSequence,
            event: event
        )
        trace.append(entry)
        traceObserver?(entry)
    }

    @MainActor private(set) var isClosed = false
    @MainActor private var isClosing = false
    @MainActor private var inputSinks: [UUID: @MainActor (PlanningViewValidationInputs) -> Void] = [:]

    @MainActor var registeredCallbackIDs: [UInt64] { callbackTasks.keys.sorted() }

    @MainActor var inputs: PlanningViewValidationInputs {
        .init(additionalFailedRequiredReads: additionalFailedRequiredReads,
              mountedHoldActivationGeneration: mountedHoldActivationGeneration)
    }
    @MainActor var outstandingCollectionCount: Int {
        deferredCallbackContinuations.count + queuedCallbackIDs.count +
        releasedBeforeWaitingCallbackIDs.count + callbacksExecutedBeforeTaskResume.count +
        queuedCallbackExecutors.count + callbackTasks.count + inputSinks.count +
        (executingCallbackID == nil ? 0 : 1)
    }

    @MainActor private func ensureOpen() -> Bool {
        guard !isClosed, !isClosing else {
            XCTFail("Validation command invoked after driver close began")
            return false
        }
        return true
    }

    @MainActor private func publishInputs() {
        for sink in Array(inputSinks.values) { sink(inputs) }
    }

    @MainActor private func observe(_ event: TraceEvent) {
        if case .callbackEntry(let id, wasCancelled: true) = event {
            queuedCallbackExecutors.removeValue(forKey: id)
        }
        record(event)
    }

    @MainActor private func acquireForHook() -> Bool {
        guard !isClosed else { return false }
        return true
    }

    /// Every production-facing closure captures only a weak driver reference.
    @MainActor func makeHooks() -> PlanningViewValidationHooks {
        PlanningViewValidationHooks(
            currentReadFailures: { [weak self] in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed during required read")
                    return Set(PlanningPersistenceReadDomain.allCases)
                }
                return self.additionalFailedRequiredReads
            },
            observe: { [weak self] event in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed during lifecycle observation")
                    return
                }
                self.observe(event)
            },
            queueDeferredCallback: { [weak self] in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed during callback queue")
                    return nil
                }
                return self.queueDeferredCallback()
            },
            awaitDeferredCallbackRelease: { [weak self] id in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed during callback release")
                    return false
                }
                return await self.awaitDeferredCallbackRelease(id)
            },
            beginCallbackExecution: { [weak self] id in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed before callback execution")
                    return false
                }
                return self.beginCallbackExecution(id)
            },
            endCallbackExecution: { [weak self] id in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed after callback execution")
                    return
                }
                self.endCallbackExecution(id)
            },
            recordFinalAuthorization: { [weak self] allowed in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed during authorization observation")
                    return
                }
                self.recordFinalAuthorization(allowed)
            },
            recordPersistenceAttempt: { [weak self] in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed during persistence observation")
                    return
                }
                self.recordPersistenceAttempt()
            },
            registerCallbackTask: { [weak self] id, task in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed during task registration")
                    task.cancel()
                    return
                }
                self.registerCallbackTask(id, task: task)
            },
            registerQueuedCallbackExecutor: { [weak self] id, execute in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed during executor registration")
                    return
                }
                self.registerQueuedCallbackExecutor(id, execute: execute)
            })
    }

    /// SwiftUI owns only input values and weak bridge closures.
    @MainActor func hosted(_ content: @escaping @MainActor
        (PlanningViewValidationHooks, PlanningViewValidationInputs) -> AnyView) -> AnyView {
        let hooks = makeHooks()
        return AnyView(PlanningValidationInputHost(
            content: { inputs in content(hooks, inputs) },
            connect: { [weak self] sink in
                guard let self, self.ensureOpen() else {
                    XCTFail("Validation driver missing or closed during input registration")
                    return nil
                }
                let id = UUID()
                self.inputSinks[id] = sink
                sink(self.inputs)
                return id
            },
            disconnect: { [weak self] id in
                guard let self, self.acquireForHook() else {
                    XCTFail("Validation driver missing or closed during input disconnection")
                    return
                }
                self.inputSinks.removeValue(forKey: id)
            }))
    }

    /// Cleanup is explicit; destruction never schedules actor work.
    /// A caller that did not settle its task first fails, then safely cancels it.
    @MainActor func close() async {
        guard !isClosed else { return }
        isClosing = true
        for (id, task) in callbackTasks {
            if !trace.contains(where: { $0.event == .callbackSettled(id) }) {
                XCTFail("Driver close found unsettled production callback \(id)")
                task.cancel()
            }
        }
        let continuations = Array(deferredCallbackContinuations.values)
        deferredCallbackContinuations.removeAll()
        for continuation in continuations { continuation.resume() }
        for (id, task) in callbackTasks {
            await task.value
            XCTAssertTrue(trace.contains { $0.event == .callbackSettled(id) },
                          "Actual production Task returned without its settlement signal")
        }
        callbackTasks.removeAll()
        if !queuedCallbackExecutors.isEmpty {
            XCTFail("Driver close found unexecuted callback executors")
        }
        queuedCallbackExecutors.removeAll()
        queuedCallbackIDs.removeAll()
        releasedBeforeWaitingCallbackIDs.removeAll()
        callbacksExecutedBeforeTaskResume.removeAll()
        executingCallbackID = nil
        if !inputSinks.isEmpty {
            XCTFail("Driver close found a hosted input registration before disappearance")
        }
        inputSinks.removeAll()
        traceObserver = nil
        isClosed = true
        XCTAssertEqual(outstandingCollectionCount, 0)
    }
}

/// The hosted graph owns values and closures, never the driver reference.
private struct PlanningValidationInputHost: View {
    let content: @MainActor (PlanningViewValidationInputs) -> AnyView
    let connect: @MainActor (@escaping @MainActor (PlanningViewValidationInputs) -> Void) -> UUID?
    let disconnect: @MainActor (UUID) -> Void
    @State private var inputs = PlanningViewValidationInputs()
    @State private var registrationID: UUID?

    var body: some View {
        content(inputs)
            .onAppear {
                guard registrationID == nil else { return }
                registrationID = connect { inputs = $0 }
            }
            .onDisappear {
                if let registrationID { disconnect(registrationID) }
                registrationID = nil
            }
    }
}
