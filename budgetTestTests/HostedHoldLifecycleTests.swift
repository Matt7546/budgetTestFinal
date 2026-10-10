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
    private final class CurrentOwner { var id = "hold-owner" }
    private final class SaveCounter { var attempts = 0 }

    private struct Fixture {
        let container: ModelContainer
        let service: PlaidService
        let control: PlanningViewValidationControl
        let owner: CurrentOwner
        let bucket: DebtPayoffBucket
        let cycle: PaymentPlanCycle
        let saves: SaveCounter
        let defaults: UserDefaults
        let suite: String
    }

    func testCancelFirstObservesCancellationBeforeReleaseAndActualSettlement() async throws {
        for _ in 0..<3 {
            let fixture = try makeFixture()
            defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
            let action = try preparedAction(fixture)
            var host: UIHostingController<AnyView>? = UIHostingController(rootView: hold(fixture, action: action))
            let window = mount(host!)
            _ = try await event(fixture.control) { $0 == .holdControlMounted }
            fixture.control.requestMountedHoldCallback()
            let queued = try await event(fixture.control) {
                if case .callbackQueued = $0 { return true }; return false
            }
            let id = try callbackID(queued)
            _ = try await event(fixture.control) { $0 == .callbackTaskStarted(id) }
            host!.rootView = AnyView(Text("Removed hold"))
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
            detach(window, host: &host)
            attach(fixture.control)
        }
    }

    func testCallbackFirstReadFailureRejectsWithoutWaitingForLaterCancellation() async throws {
        for _ in 0..<3 {
            let fixture = try makeFixture()
            defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
            var host: UIHostingController<AnyView>? = UIHostingController(rootView: hold(fixture, action: try preparedAction(fixture)))
            let window = mount(host!)
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
            detach(window, host: &host)
            attach(fixture.control)
        }
    }

    func testRecoveryDoesNotReviveOldActionAndFreshActionSavesOnce() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let old = try preparedAction(fixture)
        var host: UIHostingController<AnyView>? = UIHostingController(rootView: hold(fixture, action: old))
        let window = mount(host!)
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
        host!.rootView = hold(fixture, action: try preparedAction(fixture), identity: "fresh")
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
        detach(window, host: &host)
        attach(fixture.control)
    }

    func testOrdinaryConstructionDoesNotInstantiateValidationControl() {
        let count = PlanningViewValidationControl.constructedInstanceCount
        for _ in 0..<100 {
            let view = SavingsGoalsView()
            XCTAssertFalse(view.hasInjectedValidationControl)
            _ = HoldToCoverInFullButton(color: .blue, isCovered: false, isEnabled: true,
                isSaving: false, accessibilityConfirmationMessage: "Confirm", onConfirmed: {})
        }
        XCTAssertEqual(PlanningViewValidationControl.constructedInstanceCount, count)
    }

    private func makeFixture() throws -> Fixture {
        let schema = Schema([PlannerEvent.self, EventAllocation.self, ExpenseOccurrenceStatus.self,
            TransactionMatchedExpenseResolution.self, SavingsGoalRecord.self, ReserveSettings.self,
            DebtPayoffBucket.self, PaymentPlanCycle.self, AvailableToSpendAccountPreference.self,
            IncomeSchedule.self, PlanningOwnershipMigrationState.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let owner = CurrentOwner()
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
        let control = PlanningViewValidationControl(isTestEnabled: true, blocksDeferredCallbacks: true)
        let suite = "HostedHold.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let service = PlaidService(authenticatedUserIDProvider: { owner.id }, urlSession: transport.session,
            bankCacheDefaults: defaults, shouldFailPersistenceRead: {
                control.additionalFailedRequiredReads.contains($0)
            })
        service.configurePersistence(modelContext: container.mainContext)
        XCTAssertEqual(service.planningSnapshotAvailability(authenticatedUserID: owner.id), .available)
        return Fixture(container: container, service: service, control: control, owner: owner,
                       bucket: bucket, cycle: cycle, saves: SaveCounter(), defaults: defaults, suite: suite)
    }

    private func preparedAction(_ fixture: Fixture) throws -> () -> Bool {
        let token = try XCTUnwrap(fixture.service.paymentPlanMutationAuthorizationToken(
            authenticatedUserID: fixture.owner.id, recordID: fixture.bucket.id, cycleID: fixture.cycle.id))
        return PaymentPlanEditorMutationActionFactory.make(service: fixture.service, token: token,
            authenticatedUserID: { fixture.owner.id }, record: fixture.bucket,
            cycle: { fixture.cycle }, cycles: { [fixture.cycle] }) {
                fixture.saves.attempts += 1
                fixture.bucket.protectedAmount = 900
                do { try fixture.container.mainContext.save() }
                catch { XCTFail("Authorized fixture save failed") }
            }
    }

    private func hold(_ fixture: Fixture, action: @escaping () -> Bool,
                      identity: String = "initial") -> AnyView {
        AnyView(HoldToCoverInFullButton(color: .blue, isCovered: false, isEnabled: true,
            isSaving: false, accessibilityConfirmationMessage: "Confirm", onConfirmed: {
                fixture.control.recordFinalAuthorization(action())
            }, validationControl: fixture.control).id(identity).padding())
    }

    private func storedAmount(_ fixture: Fixture) throws -> Double {
        try XCTUnwrap(ModelContext(fixture.container).fetch(FetchDescriptor<DebtPayoffBucket>())
            .first { $0.id == fixture.bucket.id }).protectedAmount
    }

    private func mount(_ host: UIHostingController<AnyView>) -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        return window
    }

    private func detach(_ window: UIWindow, host: inout UIHostingController<AnyView>?) {
        window.isHidden = true
        window.rootViewController = nil
        host = nil
        XCTAssertTrue(transport.observations.isEmpty)
    }

    private func callbackID(_ entry: PlanningViewValidationControl.TraceEntry) throws -> UInt64 {
        guard case .callbackQueued(let id) = entry.event else { throw URLError(.unknown) }
        return id
    }

    private func event(_ control: PlanningViewValidationControl, after sequence: UInt64 = 0,
                       matches: @escaping (PlanningViewValidationControl.TraceEvent) -> Bool
    ) async throws -> PlanningViewValidationControl.TraceEntry {
        if let entry = control.trace.first(where: { $0.sequence > sequence && matches($0.event) }) { return entry }
        let observed = expectation(description: "Explicit hold lifecycle signal")
        var result: PlanningViewValidationControl.TraceEntry?
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

    private func attach(_ control: PlanningViewValidationControl) {
        let attachment = XCTAttachment(string: control.trace.map {
            "\($0.sequence): \($0.event)"
        }.joined(separator: "\n"))
        attachment.name = "Deterministic production Hold trace"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
