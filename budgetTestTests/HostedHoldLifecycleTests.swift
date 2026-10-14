import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Caldera_Money

/// Actual production Hold task and action factory, without an editor/model
/// rendered by SwiftUI. V15's editor routing/model lifetime is intentionally absent.
@MainActor
final class HostedHoldLifecycleTests: ContainedNetworkTestCase {
    /// Shared mutable value state, not an actor-isolated reference object.
    /// Copies of the closures see the same ID; there is no identity/deinit contract.
    @MainActor
    private struct CurrentOwner {
        let read: @MainActor () -> String
        let write: @MainActor (String) -> Void

        var id: String {
            get { read() }
            nonmutating set { write(newValue) }
        }
    }
    /// The same scalar-fixture policy as CurrentOwner. No reference identity or
    /// actor-isolated destructor is needed to observe exact save attempts.
    @MainActor
    private struct SaveCounter {
        let read: @MainActor () -> Int
        let increment: @MainActor () -> Void

        var attempts: Int { read() }
    }

    private struct Fixture {
        let container: ModelContainer
        let service: PlaidService
        let control: PlanningValidationDriver
        let owner: CurrentOwner
        let bucket: DebtPayoffBucket
        let cycle: PaymentPlanCycle
        let saves: SaveCounter
        let defaults: UserDefaults
        let suite: String
    }

    func testCancelFirstObservesCancellationBeforeReleaseAndActualSettlement() async throws {
        for _ in 0..<3 {
            try await withFixture { fixture, lifetime in
            let action = try preparedAction(fixture)
            lifetime.mount(hold(fixture, action: action))
            _ = try await event(fixture.control) { $0 == .holdControlMounted }
            fixture.control.requestMountedHoldCallback()
            let queued = try await event(fixture.control) {
                if case .callbackQueued = $0 { return true }; return false
            }
            let id = try callbackID(queued)
            _ = try await event(fixture.control) { $0 == .callbackTaskStarted(id) }
            lifetime.replaceRoot(AnyView(Text("Removed hold")), observed: false)
            let cancelled = try await event(fixture.control) { $0 == .callbackCancellationRequested(id) }
            _ = try await event(fixture.control) { $0 == .holdControlDisappeared }
            XCTAssertTrue(fixture.control.releaseDeferredCallback(id))
            let taskSettled = await fixture.control.awaitCallbackTaskSettlement(id)
            XCTAssertTrue(taskSettled)
            let released = try XCTUnwrap(fixture.control.trace.first { $0.event == .callbackReleased(id) })
            let settled = try XCTUnwrap(fixture.control.trace.first { $0.event == .callbackSettled(id) })
            XCTAssertLessThan(cancelled.sequence, released.sequence)
            XCTAssertLessThan(released.sequence, settled.sequence)
            XCTAssertTrue(fixture.control.trace.contains { $0.event == .callbackEntry(id, wasCancelled: true) })
            XCTAssertFalse(fixture.control.trace.contains { $0.event == .finalAuthorization(id, allowed: true) })
            XCTAssertEqual(fixture.saves.attempts, 0)
            XCTAssertEqual(try storedAmount(fixture), 275)
            await lifetime.closeHost(test: self)
            XCTAssertTrue(transport.observations.isEmpty)
            attach(fixture.control)
            }
        }
    }

    func testCallbackFirstReadFailureRejectsWithoutWaitingForLaterCancellation() async throws {
        for _ in 0..<3 {
            try await withFixture { fixture, lifetime in
            lifetime.mount(hold(fixture, action: try preparedAction(fixture)))
            _ = try await event(fixture.control) { $0 == .holdControlMounted }
            fixture.control.requestMountedHoldCallback()
            let queued = try await event(fixture.control) {
                if case .callbackQueued = $0 { return true }; return false
            }
            let id = try callbackID(queued)
            _ = try await event(fixture.control) { $0 == .callbackTaskStarted(id) }
            fixture.control.supplyRequiredQueryFailure(.paymentPlanCycles)
            XCTAssertEqual(fixture.service.planningSnapshotAvailability(authenticatedUserID: fixture.owner.id), .available)
            // Controlled scheduling: run the production callback before any
            // parent availability observer or disappearance can run.
            XCTAssertTrue(fixture.control.executeQueuedCallbackBeforeObserver(id))
            XCTAssertTrue(fixture.control.trace.contains { $0.event == .callbackEntry(id, wasCancelled: false) })
            XCTAssertTrue(fixture.control.trace.contains { $0.event == .finalAuthorization(id, allowed: false) })
            XCTAssertFalse(fixture.control.trace.contains { $0.event == .callbackCancellationRequested(id) })
            let taskSettled = await fixture.control.awaitCallbackTaskSettlement(id)
            XCTAssertTrue(taskSettled)
            XCTAssertEqual(fixture.saves.attempts, 0)
            XCTAssertEqual(try storedAmount(fixture), 275)
            await lifetime.closeHost(test: self)
            XCTAssertTrue(transport.observations.isEmpty)
            attach(fixture.control)
            }
        }
    }

    func testRecoveryDoesNotReviveOldActionAndFreshActionSavesOnce() async throws {
        try await withFixture { fixture, lifetime in
        let old = try preparedAction(fixture)
        lifetime.mount(hold(fixture, action: old))
        _ = try await event(fixture.control) { $0 == .holdControlMounted }
        fixture.control.requestMountedHoldCallback()
        let first = try await event(fixture.control) {
            if case .callbackQueued = $0 { return true }; return false
        }
        let firstID = try callbackID(first)
        _ = try await event(fixture.control) { $0 == .callbackTaskStarted(firstID) }
        fixture.control.supplyRequiredQueryFailure(.paymentPlanCycles)
        XCTAssertTrue(fixture.control.executeQueuedCallbackBeforeObserver(firstID))
        let oldTaskSettled = await fixture.control.awaitCallbackTaskSettlement(firstID)
        XCTAssertTrue(oldTaskSettled)
        fixture.control.recoverRequiredQueries()
        XCTAssertTrue(fixture.service.retryPlanningSnapshot(authenticatedUserID: fixture.owner.id))
        XCTAssertFalse(old())
        XCTAssertEqual(fixture.saves.attempts, 0)
        XCTAssertEqual(try storedAmount(fixture), 275)

        let after = fixture.control.trace.last!.sequence
        lifetime.replaceRoot(hold(fixture, action: try preparedAction(fixture), identity: "fresh"))
        _ = try await event(fixture.control, after: after) { $0 == .holdControlMounted }
        fixture.control.requestMountedHoldCallback()
        let fresh = try await event(fixture.control, after: after) {
            if case .callbackQueued = $0 { return true }; return false
        }
        let freshID = try callbackID(fresh)
        _ = try await event(fixture.control) { $0 == .callbackTaskStarted(freshID) }
        XCTAssertTrue(fixture.control.releaseDeferredCallback(freshID))
        let freshTaskSettled = await fixture.control.awaitCallbackTaskSettlement(freshID)
        XCTAssertTrue(freshTaskSettled)
        XCTAssertEqual(fixture.saves.attempts, 1)
        XCTAssertEqual(try storedAmount(fixture), 900)
        XCTAssertTrue(fixture.control.trace.contains { $0.event == .finalAuthorization(freshID, allowed: true) })
        await lifetime.closeHost(test: self)
            XCTAssertTrue(transport.observations.isEmpty)
        attach(fixture.control)
        }
    }

    func testOrdinaryConstructionDoesNotInstantiateValidationControl() {
        let count = PlanningValidationDriver.constructedInstanceCount
        for _ in 0..<100 {
            let view = SavingsGoalsView()
            XCTAssertFalse(view.hasInjectedValidationHooks)
            _ = HoldToCoverInFullButton(color: .blue, isCovered: false, isEnabled: true,
                isSaving: false, accessibilityConfirmationMessage: "Confirm", onConfirmed: {})
        }
        XCTAssertEqual(PlanningValidationDriver.constructedInstanceCount, count)
    }

    private func makeFixture() throws -> Fixture {
        let schema = Schema([PlannerEvent.self, EventAllocation.self, ExpenseOccurrenceStatus.self,
            TransactionMatchedExpenseResolution.self, SavingsGoalRecord.self, ReserveSettings.self,
            DebtPayoffBucket.self, PaymentPlanCycle.self, AvailableToSpendAccountPreference.self,
            IncomeSchedule.self, PlanningOwnershipMigrationState.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        var ownerID = "hold-owner"
        let owner = CurrentOwner(read: { ownerID }, write: { ownerID = $0 })
        var saveAttempts = 0
        let saves = SaveCounter(read: { saveAttempts }, increment: { saveAttempts += 1 })
        let scope = try XCTUnwrap(PlanningOwnerScope.authenticated(owner.id))
        let bucket = DebtPayoffBucket(ownerScopeID: scope, plaidAccountID: "hold-card",
            accountName: "Hold card", dueDate: Date().addingTimeInterval(86400 * 21),
            paymentTargetAmount: 900, protectedAmount: 275, debtKind: .linkedCreditCard)
        let cycle = PaymentPlanCycle(ownerScopeID: scope, paymentPlanID: bucket.id,
                                    dueDate: bucket.dueDate, frozenTargetAmount: 900)
        container.mainContext.insert(bucket)
        container.mainContext.insert(cycle)
        container.mainContext.insert(ReserveSettings(ownerScopeID: scope, balance: 0))
        try container.mainContext.save()
        let control = PlanningValidationDriver(isTestEnabled: true, blocksDeferredCallbacks: true)
        let suite = "HostedHold.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        // These production closure interfaces are unannotated, not @Sendable.
        // Enforce the fixture's MainActor contract at each identity adapter.
        let readFailures = control.makeHooks().currentReadFailures
        let service = PlaidService(authenticatedUserIDProvider: {
            MainActor.assumeIsolated { owner.id }
        }, urlSession: transport.session,
            bankCacheDefaults: defaults, shouldFailPersistenceRead: {
                readFailures().contains($0)
            })
        service.configurePersistence(modelContext: container.mainContext)
        XCTAssertEqual(service.planningSnapshotAvailability(authenticatedUserID: owner.id), .available)
        return Fixture(container: container, service: service, control: control, owner: owner,
                       bucket: bucket, cycle: cycle, saves: saves, defaults: defaults, suite: suite)
    }

    private func preparedAction(_ fixture: Fixture) throws -> () -> Bool {
        let token = try XCTUnwrap(fixture.service.paymentPlanMutationAuthorizationToken(
            authenticatedUserID: fixture.owner.id, recordID: fixture.bucket.id, cycleID: fixture.cycle.id))
        let owner = fixture.owner
        let saves = fixture.saves
        let cycle = fixture.cycle
        let bucket = fixture.bucket
        let container = fixture.container
        return PaymentPlanEditorMutationActionFactory.make(service: fixture.service, token: token,
            authenticatedUserID: { MainActor.assumeIsolated { owner.id } }, record: bucket,
            cycle: { cycle }, cycles: { [cycle] }) {
                MainActor.assumeIsolated { saves.increment() }
                bucket.protectedAmount = 900
                do { try container.mainContext.save() }
                catch { XCTFail("Authorized fixture save failed") }
            }
    }

    private func hold(_ fixture: Fixture, action: @escaping () -> Bool,
                      identity: String = "initial") -> AnyView {
        fixture.control.hosted { hooks, inputs in
            AnyView(HoldToCoverInFullButton(color: .blue, isCovered: false, isEnabled: true,
                isSaving: false, accessibilityConfirmationMessage: "Confirm", onConfirmed: {
                    hooks.recordFinalAuthorization(action())
                }, validationHooks: hooks, validationInputs: inputs).id(identity).padding())
        }
    }

    private func storedAmount(_ fixture: Fixture) throws -> Double {
        try XCTUnwrap(ModelContext(fixture.container).fetch(FetchDescriptor<DebtPayoffBucket>())
            .first { $0.id == fixture.bucket.id }).protectedAmount
    }


    private func withFixture(
        body: (Fixture, FixtureLifetime) async throws -> Void
    ) async throws {
        let lifetime = FixtureLifetime(fixture: try makeFixture())
        do {
            try await lifetime.runBody(body)
        } catch {
            await lifetime.finish(test: self)
            throw error
        }
        await lifetime.finish(test: self)
    }

    /// A nonisolated lifetime identity, with all UI/storage work on MainActor.
    /// The body frame finishes before cleanup, so its copied fixture/actions die.
    nonisolated private final class FixtureLifetime {
        @MainActor private var fixture: Fixture?
        @MainActor private var host: UIHostingController<AnyView>?
        @MainActor private var window: UIWindow?
        @MainActor private var graphIDs: [String] = []
        @MainActor private weak var weakHost: UIHostingController<AnyView>?
        @MainActor private weak var weakWindow: UIWindow?
        // These two properties are weak; the fixture owns services/storage.
        @MainActor private weak var weakService: PlaidService?
        @MainActor private weak var weakContainer: ModelContainer?
        @MainActor private weak var weakDriver: PlanningValidationDriver?
        private let signals = V15HostedSignals(label: "hosted-hold-close")

        @MainActor init(fixture: Fixture) {
            self.fixture = fixture
            weakService = fixture.service
            weakContainer = fixture.container
            weakDriver = fixture.control
            V15ObserveLifetime.attach(fixture.service, label: "service", signals: signals)
            V15ObserveLifetime.attach(fixture.container, label: "container", signals: signals)
            V15ObserveLifetime.attach(fixture.control, label: "driver", signals: signals)
        }

        @MainActor func runBody(_ body: (Fixture, FixtureLifetime) async throws -> Void) async throws {
            try await body(fixture!, self)
        }

        @MainActor func mount(_ view: AnyView) {
            host = UIHostingController(rootView: observed(view))
            window = UIWindow(frame: UIScreen.main.bounds)
            weakHost = host
            weakWindow = window
            V15ObserveLifetime.attach(host!, label: "host", signals: signals)
            V15ObserveLifetime.attach(window!, label: "window", signals: signals)
            window!.rootViewController = host
            window!.makeKeyAndVisible()
        }

        @MainActor private func observed(_ view: AnyView) -> AnyView {
            let id = "hold-graph-\(graphIDs.count + 1)"
            graphIDs.append(id)
            let signals = signals
            return AnyView(view
                .background(V15GraphObserver(identity: id, snapshot: id, signals: signals))
                .onDisappear { signals.record("graph-disappeared:\(id)") }
                .id(id))
        }

        @MainActor func replaceRoot(_ view: AnyView, observed shouldObserve: Bool = true) {
            host!.rootView = shouldObserve ? observed(view) : view
        }

        @MainActor private func settleAndCloseDriver(test: XCTestCase) async {
            guard let driver = fixture?.control else { return }
            let disappeared = "all-holds-disappeared"
            driver.traceObserver = { [signals] entry in
                if entry.event == .holdControlDisappeared { signals.record(disappeared) }
            }
            let mounted = driver.trace.filter { $0.event == .holdControlMounted }.count
            let gone = driver.trace.filter { $0.event == .holdControlDisappeared }.count
            if gone >= mounted { signals.record(disappeared) }
            await require([disappeared], test: test)
            for id in driver.registeredCallbackIDs {
                if !driver.trace.contains(where: { $0.event == .callbackSettled(id) }) {
                    XCTAssertTrue(driver.trace.contains { $0.event == .callbackCancellationRequested(id) },
                                  "Cleanup requires observed actual Hold cancellation before release")
                }
            }
            driver.releaseAllDeferredCallbacks()
            for id in driver.registeredCallbackIDs {
                let settled = await driver.awaitCallbackTaskSettlement(id)
                XCTAssertTrue(settled)
            }
            await driver.close()
            XCTAssertTrue(driver.isClosed)
            XCTAssertEqual(driver.outstandingCollectionCount, 0)
            signals.record("driver-closed:collections-empty")
        }

        @MainActor func closeHost(test: XCTestCase) async {
            guard host != nil else { return }
            replaceRoot(AnyView(Text("Closed hosted Hold")), observed: false)
            await settleAndCloseDriver(test: test)
            window?.isHidden = true
            window?.rootViewController = nil
            host = nil
            await require(graphIDs.flatMap {
                ["graph-disappeared:\($0)", "graph-dismantled:\($0)", "graph-destroyed:\($0)"]
            } + ["destroyed:host"], test: test)
            XCTAssertTrue(weakHost == nil)
            XCTAssertNotNil(weakService)
            XCTAssertNotNil(weakContainer)
            window = nil
            await require(["destroyed:window"], test: test)
            XCTAssertTrue(weakWindow == nil)
            signals.record("host-destroyed-before-dependencies")
        }

        @MainActor func finish(test: XCTestCase) async {
            await closeHost(test: test)
            var driver = fixture?.control
            fixture?.defaults.removePersistentDomain(forName: fixture!.suite)
            fixture = nil
            await require(["destroyed:service", "destroyed:container"], test: test)
            XCTAssertTrue(weakService == nil)
            XCTAssertTrue(weakContainer == nil)
            XCTAssertNotNil(driver)
            driver = nil
            await require(["destroyed:driver"], test: test)
            XCTAssertTrue(weakDriver == nil)
            let attachment = XCTAttachment(string: signals.trace)
            attachment.name = "Hosted Hold explicit close and weak release"
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }

        @MainActor private func require(_ events: [String], test: XCTestCase) async {
            let result = await XCTWaiter.fulfillment(
                of: events.map { signals.expectation(for: $0) }, timeout: 10)
            guard result == .completed else {
                XCTFail("Hosted Hold destruction incomplete: \(events)")
                fatalError("Fixture cleanup failed while dependencies remain owned")
            }
        }
    }

    private func callbackID(_ entry: PlanningValidationDriver.TraceEntry) throws -> UInt64 {
        guard case .callbackQueued(let id) = entry.event else { throw URLError(.unknown) }
        return id
    }

    private func event(_ control: PlanningValidationDriver, after sequence: UInt64 = 0,
                       matches: @escaping (PlanningValidationDriver.TraceEvent) -> Bool
    ) async throws -> PlanningValidationDriver.TraceEntry {
        if let entry = control.trace.first(where: { $0.sequence > sequence && matches($0.event) }) { return entry }
        let observed = expectation(description: "Explicit hold lifecycle signal")
        var result: PlanningValidationDriver.TraceEntry?
        control.traceObserver = { entry in
            if entry.sequence > sequence && matches(entry.event) && result == nil {
                result = entry
                observed.fulfill()
            }
        }
        await fulfillment(of: [observed], timeout: 3)
        control.traceObserver = nil
        return try XCTUnwrap(result, "Trace: \(control.trace)")
    }

    private func attach(_ control: PlanningValidationDriver) {
        let attachment = XCTAttachment(string: control.trace.map {
            "\($0.sequence): \($0.event)"
        }.joined(separator: "\n"))
        attachment.name = "Deterministic production Hold trace"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
