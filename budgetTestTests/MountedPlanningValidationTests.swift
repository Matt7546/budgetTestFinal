import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Caldera_Money

@MainActor
final class MountedPlanningValidationTests: ContainedNetworkTestCase {
    private var activePaymentPlanFixture: PaymentPlanFixtureLifetime?

    func testMountedUnavailableAccountControlRetainsExcludedPreference() async throws {
        let ownerID = "mounted-account-owner"
        let accountID = "mounted-excluded-checking"
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(
            ReserveSettings(
                ownerScopeID: try XCTUnwrap(
                    PlanningOwnerScope.authenticated(ownerID)
                ),
                balance: 0
            )
        )
        context.insert(
            AvailableToSpendAccountPreference(
                userID: ownerID,
                plaidAccountID: accountID,
                isIncluded: false
            )
        )
        try context.save()

        var shouldFailPreferenceRead = true
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "MountedAccountControl.\(UUID().uuidString)")
        )
        let service = PlaidService(
            sessionTokenProvider: { "mounted-account-session" },
            authenticatedUserIDProvider: { ownerID },
            urlSession: makeInterceptedSession(),
            bankCacheDefaults: defaults,
            shouldFailPersistenceRead: { domain in
                shouldFailPreferenceRead &&
                    domain == .availableToSpendPreferences
            }
        )
        let account = PlaidAccount(
            account_id: accountID,
            name: "Rendered Checking",
            official_name: nil,
            type: "depository",
            subtype: "checking",
            mask: "4242",
            balances: PlaidBalance(
                available: 1_000,
                current: 1_000
            )
        )
        apply(account: account, to: service)
        service.configurePersistence(modelContext: context)

        let view = ScrollView {
            DetailedAccountCard(
                account: account,
                lastSyncedText: "Last updated just now"
            )
            .padding()
        }
        .environmentObject(service)
        let mounted = mount(view)
        defer { mounted.window.isHidden = true }
        try await settleMountedView()

        XCTAssertEqual(
            service.availableToSpendAccountInclusionState(account),
            .unavailable
        )
        XCTAssertFalse(service.canManageAvailableToSpendAccountScope)
        XCTAssertTrue(service.financialSummaryAccounts.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(
                try context.fetch(
                    FetchDescriptor<AvailableToSpendAccountPreference>()
                ).first
            ).isIncluded,
            false
        )
        attachScreenshot(
            of: mounted.window,
            named: "Rendered unavailable account inclusion control"
        )

        shouldFailPreferenceRead = false
        XCTAssertTrue(
            service.retryPlanningSnapshot(authenticatedUserID: ownerID)
        )
        try await settleMountedView()
        XCTAssertEqual(
            service.availableToSpendAccountInclusionState(account),
            .excluded
        )
        XCTAssertTrue(service.canManageAvailableToSpendAccountScope)
        XCTAssertTrue(service.financialSummaryAccounts.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(
                try context.fetch(
                    FetchDescriptor<AvailableToSpendAccountPreference>()
                ).first
            ).isIncluded,
            false
        )
        attachScreenshot(
            of: mounted.window,
            named: "Rendered restored excluded account selection"
        )
        XCTAssertTrue(transport.observations.isEmpty)
    }

    func testSavingsGoalsRequiredQueryAdapterPreservesRecordsAndAddsFailures() throws {
        let ownerScopeID = try XCTUnwrap(
            PlanningOwnerScope.authenticated("adapter-owner")
        )
        let event = PlannerEvent(
            ownerScopeID: ownerScopeID,
            name: "Adapter Bill",
            amount: 125,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            frequency: .once,
            type: .expense
        )
        let reserve = ReserveSettings(
            ownerScopeID: ownerScopeID,
            balance: 450
        )

        let result = SavingsGoalsRequiredQueryResultAdapter.resolve(
            events: [event],
            eventsFetchFailed: true,
            allocations: [],
            allocationsFetchFailed: false,
            occurrenceStatuses: [],
            occurrenceStatusesFetchFailed: false,
            debtPayoffBuckets: [],
            debtPayoffBucketsFetchFailed: false,
            paymentPlanCycles: [],
            paymentPlanCyclesFetchFailed: false,
            reserveSettings: [reserve],
            reserveSettingsFetchFailed: false,
            additionalControlledFailures: [.paymentPlanCycles]
        )

        XCTAssertEqual(result.events.map(\.id), [event.id])
        XCTAssertEqual(result.reserveSettings.map(\.id), [reserve.id])
        XCTAssertEqual(
            result.failedRequiredReads,
            [.plannerEvents, .paymentPlanCycles]
        )
    }

    func testMountedQueryFailureInvalidatesOldHoldAcrossRecoveryAndFreshHoldPersists() async throws {
        try await withPaymentPlanHarness { harness, fixture in
        let mounted = fixture.mount(harness.view, control: harness.validationControl)

        let initialAvailability = try await waitForTrace(
            in: harness.validationControl,
            after: 0
        ) { $0 == .viewAvailabilityUpdated(.available) }
        harness.navigation.openSavingsEditDebtPayoff(
            harness.bucketID,
            cycleID: harness.cycleID
        )
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: initialAvailability.sequence
        ) { $0 == .holdControlMounted }

        let firstQueueStart = harness.validationControl.trace.last?.sequence ?? 0
        harness.validationControl.requestMountedHoldCallback()
        let firstQueued = try await waitForTrace(
            in: harness.validationControl,
            after: firstQueueStart
        ) {
            if case .callbackQueued = $0 { return true }
            return false
        }
        let firstCallbackID = try XCTUnwrap(firstQueued.callbackID)

        let failureStart = firstQueued.sequence
        harness.validationControl.supplyRequiredQueryFailure(
            .paymentPlanCycles
        )
        let unavailable = try await waitForTrace(
            in: harness.validationControl,
            after: failureStart
        ) {
            $0 == .viewAvailabilityUpdated(.unavailable)
        }
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: unavailable.sequence
        ) {
            if case .mutationGenerationInvalidated = $0 {
                return true
            }
            return false
        }
        // Availability/generation does not establish cancellation. Wait on
        // the actual Hold control's Task.cancel() observation before release.
        _ = try await waitForTrace(
            in: harness.validationControl, after: firstQueued.sequence
        ) { $0 == .callbackCancellationRequested(firstCallbackID) }
        let recoveryStart =
            harness.validationControl.trace.last?.sequence ?? 0
        harness.validationControl.recoverRequiredQueries()
        let available = try await waitForTrace(
            in: harness.validationControl,
            after: recoveryStart
        ) {
            $0 == .viewAvailabilityUpdated(.available)
        }
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: available.sequence
        ) {
            if case .mutationGenerationInvalidated = $0 {
                return true
            }
            return false
        }

        let oldReleaseStart =
            harness.validationControl.trace.last?.sequence ?? 0
        XCTAssertTrue(
            harness.validationControl.releaseDeferredCallback(
                firstCallbackID
            )
        )
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: oldReleaseStart
        ) {
            if case .callbackEntry(firstCallbackID, _) = $0 {
                return true
            }
            return false
        }
        let oldTaskSettled = await harness.validationControl.awaitCallbackTaskSettlement(firstCallbackID)
        XCTAssertTrue(oldTaskSettled)
        XCTAssertTrue(harness.validationControl.trace.contains {
            $0.event == .callbackEntry(firstCallbackID, wasCancelled: true)
        })
        XCTAssertFalse(harness.validationControl.trace.contains {
            $0.event == .persistenceAttempt(firstCallbackID)
        })
        XCTAssertEqual(
            try storedProtectedAmount(in: harness),
            275,
            accuracy: 0.001
        )

        await fixture.closeMount(mounted, test: self)
        let freshNavigation = AppNavigation()
        let freshValidationControl = PlanningViewValidationControl(
            isTestEnabled: true,
            blocksDeferredCallbacks: true
        )
        let freshView = paymentPlanView(
            harness: harness,
            navigation: freshNavigation,
            validationControl: freshValidationControl
        )
        _ = fixture.mount(freshView, control: freshValidationControl,
                          additionalDependencies: [freshNavigation])
        let freshAvailability = try await waitForTrace(
            in: freshValidationControl,
            after: 0
        ) { $0 == .viewAvailabilityUpdated(.available) }
        freshNavigation.openSavingsEditDebtPayoff(
            harness.bucketID,
            cycleID: harness.cycleID
        )
        _ = try await waitForTrace(
            in: freshValidationControl,
            after: freshAvailability.sequence
        ) { $0 == .holdControlMounted }

        let freshQueueStart =
            freshValidationControl.trace.last?.sequence ?? 0
        freshValidationControl.requestMountedHoldCallback()
        let freshQueued = try await waitForTrace(
            in: freshValidationControl,
            after: freshQueueStart
        ) {
            if case .callbackQueued = $0 { return true }
            return false
        }
        let freshCallbackID = try XCTUnwrap(freshQueued.callbackID)
        XCTAssertTrue(
            freshValidationControl.releaseDeferredCallback(
                freshCallbackID
            )
        )
        let authorized = try await waitForTrace(
            in: freshValidationControl,
            after: freshQueued.sequence
        ) {
            $0 == .finalAuthorization(
                freshCallbackID,
                allowed: true
            )
        }
        XCTAssertNotNil(
            freshValidationControl.trace.first {
                $0.sequence < authorized.sequence &&
                    $0.event == .persistenceAttempt(freshCallbackID)
            }
        )
        XCTAssertEqual(
            freshValidationControl.trace.filter {
                $0.event == .persistenceAttempt(freshCallbackID)
            }.count,
            1
        )
        XCTAssertEqual(
            try storedProtectedAmount(in: harness),
            900,
            accuracy: 0.001
        )
        attachTrace(
            harness.validationControl.trace,
            named: "Query failure, recovery, and old callback"
        )
        attachTrace(
            freshValidationControl.trace,
            named: "Fresh callback after query recovery"
        )
        XCTAssertTrue(transport.observations.isEmpty)
        }
    }

    func testMountedLegacyEditorHealthyHoldSavesExactlyOnce() async throws {
        try await withPaymentPlanHarness(debtKind: .autoLoan) { harness, fixture in
        _ = fixture.mount(harness.view, control: harness.validationControl)
        let available = try await waitForTrace(
            in: harness.validationControl,
            after: 0
        ) { $0 == .viewAvailabilityUpdated(.available) }
        harness.navigation.openSavingsEditDebtPayoff(
            harness.bucketID,
            cycleID: harness.cycleID
        )
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: available.sequence
        ) { $0 == .holdControlMounted }

        let queueStart = harness.validationControl.trace.last?.sequence ?? 0
        harness.validationControl.requestMountedHoldCallback()
        let queued = try await waitForTrace(
            in: harness.validationControl,
            after: queueStart
        ) {
            if case .callbackQueued = $0 { return true }
            return false
        }
        let callbackID = try XCTUnwrap(queued.callbackID)
        XCTAssertTrue(
            harness.validationControl.releaseDeferredCallback(callbackID)
        )
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: queued.sequence
        ) {
            $0 == .finalAuthorization(callbackID, allowed: true)
        }
        XCTAssertEqual(
            harness.validationControl.trace.filter {
                $0.event == .persistenceAttempt(callbackID)
            }.count,
            1
        )
        XCTAssertEqual(
            try storedProtectedAmount(in: harness),
            900,
            accuracy: 0.001
        )
        attachTrace(
            harness.validationControl.trace,
            named: "Healthy legacy editor hold"
        )
        XCTAssertTrue(transport.observations.isEmpty)
        }
    }

    func testMountedQueryFailureSuppliedBeforeQueuedCallbackCannotPersistWithoutForcedOnChangeOrdering() async throws {
        try await withPaymentPlanHarness { harness, fixture in
        _ = fixture.mount(harness.view, control: harness.validationControl)
        let initialAvailability = try await waitForTrace(
            in: harness.validationControl,
            after: 0
        ) { $0 == .viewAvailabilityUpdated(.available) }
        harness.navigation.openSavingsEditDebtPayoff(
            harness.bucketID,
            cycleID: harness.cycleID
        )
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: initialAvailability.sequence
        ) { $0 == .holdControlMounted }

        let queueStart = harness.validationControl.trace.last?.sequence ?? 0
        harness.validationControl.requestMountedHoldCallback()
        let queued = try await waitForTrace(
            in: harness.validationControl,
            after: queueStart
        ) {
            if case .callbackQueued = $0 { return true }
            return false
        }
        let callbackID = try XCTUnwrap(queued.callbackID)

        // Deliberately do not wait for the parent view's onChange before
        // releasing the already-queued production callback.
        harness.validationControl.supplyRequiredQueryFailure(
            .paymentPlanCycles
        )
        XCTAssertTrue(
            harness.validationControl.releaseDeferredCallback(callbackID)
        )

        _ = try await waitForTrace(
            in: harness.validationControl,
            after: queued.sequence
        ) {
            if case .callbackEntry(callbackID, _) = $0 { return true }
            return false
        }
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: queued.sequence
        ) {
            if case .mutationGenerationInvalidated = $0 {
                return true
            }
            return false
        }

        attachTrace(
            harness.validationControl.trace,
            named: "Failure supplied before callback release"
        )
        XCTAssertEqual(
            try storedProtectedAmount(in: harness),
            275,
            accuracy: 0.001,
            "A callback released after failed query input must not persist, even when the test does not pre-run the view's onChange."
        )
        XCTAssertTrue(transport.observations.isEmpty)
        }
    }

    func testMountedQueryFailureRejectsCallbackBeforeAvailabilityObserver() async throws {
        try await assertCallbackBeforeObserverIsRejected(
            debtKind: .linkedCreditCard
        )
    }

    func testMountedLegacyEditorRejectsCallbackBeforeAvailabilityObserver() async throws {
        try await assertCallbackBeforeObserverIsRejected(
            debtKind: .autoLoan
        )
    }

    func testViewOnlyFailureWithVerifiedCommandInputsCanCommitBeforeObserver() async throws {
        try await withPaymentPlanHarness(
            controlledFailuresAlsoFailCommandReads: false
        ) { harness, fixture in
        _ = fixture.mount(harness.view, control: harness.validationControl)
        let available = try await waitForTrace(
            in: harness.validationControl,
            after: 0
        ) { $0 == .viewAvailabilityUpdated(.available) }
        harness.navigation.openSavingsEditDebtPayoff(
            harness.bucketID,
            cycleID: harness.cycleID
        )
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: available.sequence
        ) { $0 == .holdControlMounted }

        let queueStart = harness.validationControl.trace.last?.sequence ?? 0
        harness.validationControl.requestMountedHoldCallback()
        let queued = try await waitForTrace(
            in: harness.validationControl,
            after: queueStart
        ) {
            if case .callbackQueued = $0 { return true }
            return false
        }
        let callbackID = try XCTUnwrap(queued.callbackID)
        harness.validationControl.supplyRequiredQueryFailure(
            .paymentPlanCycles
        )
        XCTAssertEqual(
            harness.service.planningSnapshotAvailability(
                authenticatedUserID: harness.auth.user?.id
            ),
            .available
        )
        XCTAssertTrue(
            harness.validationControl.executeQueuedCallbackBeforeObserver(
                callbackID
            )
        )
        let trace = harness.validationControl.trace
        let failed = try XCTUnwrap(trace.first {
            if case .failedInput = $0.event { return true }
            return false
        })
        let callback = try XCTUnwrap(trace.first {
            if case .callbackEntry(callbackID, _) = $0.event {
                return true
            }
            return false
        })
        XCTAssertLessThan(failed.sequence, callback.sequence)
        XCTAssertFalse(trace.contains {
            $0.sequence > failed.sequence &&
                $0.sequence < callback.sequence &&
                $0.event == .viewAvailabilityUpdated(.unavailable)
        })
        XCTAssertTrue(trace.contains {
            $0.event == .finalAuthorization(callbackID, allowed: true)
        })
        XCTAssertEqual(trace.filter {
            $0.event == .persistenceAttempt(callbackID)
        }.count, 1)
        XCTAssertEqual(
            try storedProtectedAmount(in: harness),
            900,
            accuracy: 0.001
        )
        attachTrace(trace, named: "View-only failure, verified command read")
        XCTAssertTrue(transport.observations.isEmpty)
        }
    }

    func testEveryRequiredCommandReadFailureRejectsCallbackBeforeObserver() async throws {
        for domain in [
            PlanningPersistenceReadDomain.plannerEvents,
            .eventAllocations,
            .occurrenceStatuses,
            .debtPayoffBuckets,
            .paymentPlanCycles,
            .reserveSettings
        ] {
            try await assertCallbackBeforeObserverIsRejected(
                debtKind: .linkedCreditCard,
                failingDomain: domain
            )
        }
    }

    private enum FixtureBodyError: Error { case intentional }

    func testV15CleanupPreservesFailedAssertionAndReleasesFixture() async throws {
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        options.issueMatcher = { $0.compactDescription.contains("V15 intentional financial assertion failure") }
        XCTExpectFailure("The original assertion must remain visible while teardown completes", options: options)
        try await withPaymentPlanHarness(debtKind: .autoLoan) { harness, fixture in
            try await mountReadyEditor(harness, fixture: fixture)
            XCTAssertEqual(try storedProtectedAmount(in: harness), 999,
                           "V15 intentional financial assertion failure")
        }
        XCTAssertNil(activePaymentPlanFixture)
    }

    func testV15CleanupAfterThrownErrorSettlesQueuedHold() async throws {
        do {
            try await withPaymentPlanHarness(debtKind: .autoLoan) { harness, fixture in
                try await mountReadyEditor(harness, fixture: fixture)
                let start = harness.validationControl.trace.last?.sequence ?? 0
                harness.validationControl.requestMountedHoldCallback()
                _ = try await waitForTrace(in: harness.validationControl, after: start) {
                    if case .callbackQueued = $0 { return true }
                    return false
                }
                XCTAssertEqual(try storedProtectedAmount(in: harness), 275)
                throw FixtureBodyError.intentional
            }
            XCTFail("Original fixture error must be rethrown after cleanup")
        } catch FixtureBodyError.intentional { }
        XCTAssertNil(activePaymentPlanFixture)
    }

    func testV15CleanupAfterBodyTimeout() async throws {
        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        options.issueMatcher = { $0.compactDescription.contains("V15 intentional body timeout") }
        XCTExpectFailure("The body timeout must remain visible while teardown completes", options: options)
        do {
            try await withPaymentPlanHarness { harness, fixture in
                try await mountReadyEditor(harness, fixture: fixture)
                let missing = expectation(description: "V15 intentional body timeout")
                await fulfillment(of: [missing], timeout: 0.1)
                throw FixtureBodyError.intentional
            }
            XCTFail("Timed-out body must rethrow its error after cleanup")
        } catch FixtureBodyError.intentional { }
        XCTAssertNil(activePaymentPlanFixture)
    }

    func testV15CleanupAfterCancellation() async throws {
        let task = Task { @MainActor in
            try await self.withPaymentPlanHarness { harness, fixture in
                try await self.mountReadyEditor(harness, fixture: fixture)
                try Task.checkCancellation()
                XCTFail("Cancelled body must throw before success")
            }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Cancellation must remain observable after cleanup")
        } catch is CancellationError { }
        XCTAssertNil(activePaymentPlanFixture)
    }

    private func mountReadyEditor(_ harness: PaymentPlanHarness,
                                 fixture: PaymentPlanFixtureLifetime) async throws {
        _ = fixture.mount(harness.view, control: harness.validationControl)
        let available = try await waitForTrace(in: harness.validationControl, after: 0) {
            $0 == .viewAvailabilityUpdated(.available)
        }
        harness.navigation.openSavingsEditDebtPayoff(harness.bucketID, cycleID: harness.cycleID)
        _ = try await waitForTrace(in: harness.validationControl, after: available.sequence) {
            $0 == .holdControlMounted
        }
    }

    private func assertCallbackBeforeObserverIsRejected(
        debtKind: DebtPayoffKind,
        failingDomain: PlanningPersistenceReadDomain = .paymentPlanCycles
    ) async throws {
        try await withPaymentPlanHarness(debtKind: debtKind) { harness, fixture in
        _ = fixture.mount(harness.view, control: harness.validationControl)
        let available = try await waitForTrace(
            in: harness.validationControl,
            after: 0
        ) { $0 == .viewAvailabilityUpdated(.available) }
        harness.navigation.openSavingsEditDebtPayoff(
            harness.bucketID,
            cycleID: harness.cycleID
        )
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: available.sequence
        ) { $0 == .holdControlMounted }

        let queueStart = harness.validationControl.trace.last?.sequence ?? 0
        harness.validationControl.requestMountedHoldCallback()
        let queued = try await waitForTrace(
            in: harness.validationControl,
            after: queueStart
        ) {
            if case .callbackQueued = $0 { return true }
            return false
        }
        let callbackID = try XCTUnwrap(queued.callbackID)

        harness.validationControl.supplyRequiredQueryFailure(
            failingDomain
        )
        XCTAssertEqual(
            harness.service.planningSnapshotAvailability(
                authenticatedUserID: harness.auth.user?.id
            ),
            .available,
            "The test must not pre-clear service readiness."
        )
        XCTAssertTrue(
            harness.validationControl.executeQueuedCallbackBeforeObserver(
                callbackID
            )
        )

        let trace = harness.validationControl.trace
        let failed = try XCTUnwrap(trace.first {
            if case .failedInput = $0.event { return true }
            return false
        })
        let callback = try XCTUnwrap(trace.first {
            if case .callbackEntry(callbackID, _) = $0.event {
                return true
            }
            return false
        })
        XCTAssertLessThan(failed.sequence, callback.sequence)
        XCTAssertFalse(trace.contains {
            $0.sequence > failed.sequence &&
                $0.sequence < callback.sequence &&
                $0.event == .viewAvailabilityUpdated(.unavailable)
        })

        XCTAssertTrue(trace.contains {
            $0.event == .finalAuthorization(
                callbackID,
                allowed: false
            )
        })
        XCTAssertFalse(trace.contains {
            $0.event == .persistenceAttempt(callbackID)
        })
        XCTAssertEqual(
            try storedProtectedAmount(in: harness),
            275,
            accuracy: 0.001
        )

        let observer = try await waitForTrace(
            in: harness.validationControl,
            after: callback.sequence
        ) { $0 == .viewAvailabilityUpdated(.unavailable) }
        let invalidation = try await waitForTrace(
            in: harness.validationControl,
            after: observer.sequence
        ) {
            if case .mutationGenerationInvalidated = $0 { return true }
            return false
        }
        XCTAssertLessThan(callback.sequence, observer.sequence)
        XCTAssertLessThan(observer.sequence, invalidation.sequence)
        attachTrace(
            harness.validationControl.trace,
            named: "Failure, callback, then observer and invalidation"
        )
        XCTAssertTrue(transport.observations.isEmpty)
        }
    }

    private func makeInterceptedSession() -> URLSession {
        transport.session
    }

    /// The body frame (and its local editor/view references) finishes before
    /// cleanup begins. One owner retains storage throughout every exit path.
    private func withPaymentPlanHarness(
        debtKind: DebtPayoffKind = .linkedCreditCard,
        controlledFailuresAlsoFailCommandReads: Bool = true,
        body: (PaymentPlanHarness, PaymentPlanFixtureLifetime) async throws -> Void
    ) async throws {
        let fixture = PaymentPlanFixtureLifetime(harness: try makePaymentPlanHarness(
            debtKind: debtKind,
            controlledFailuresAlsoFailCommandReads: controlledFailuresAlsoFailCommandReads
        ))
        activePaymentPlanFixture = fixture
        defer { activePaymentPlanFixture = nil }
        do {
            try await fixture.runBody(body)
        } catch {
            fixture.signals.record("body-threw:\(String(describing: type(of: error))):cleanup-before-rethrow")
            await fixture.cleanup(test: self)
            throw error
        }
        await fixture.cleanup(test: self)
    }

    @MainActor
    private final class PaymentPlanFixtureLifetime {
        private final class WeakReference {
            weak var object: AnyObject?
            init(_ object: AnyObject) { self.object = object }
        }

        final class Mount {
            var window: UIWindow?
            var host: UIHostingController<AnyView>?
            let control: PlanningViewValidationControl
            let identity: String
            var closed = false
            var observedSheet = false
            init(window: UIWindow, host: UIHostingController<AnyView>,
                 control: PlanningViewValidationControl, identity: String) {
                self.window = window
                self.host = host
                self.control = control
                self.identity = identity
            }
        }

        let signals: V15HostedSignals
        private var harness: PaymentPlanHarness?
        private var container: ModelContainer?
        private var context: ModelContext?
        private var auth: AuthManager?
        private var service: PlaidService?
        private var dependencies: [AnyObject] = []
        private var mounts: [Mount] = []
        private var weakReferences: [String: WeakReference] = [:]
        private var cleanupFinished = false

        init(harness: PaymentPlanHarness) {
            self.harness = harness
            signals = harness.diagnostics
            container = harness.container
            context = harness.container.mainContext
            auth = harness.auth
            service = harness.service
            dependencies = [harness.navigation, harness.validationControl, harness.sessionStore]
            observe(harness.container, name: "fixture-container")
            observe(harness.container.mainContext, name: "fixture-context")
            observe(harness.auth, name: "fixture-auth")
            observe(harness.service, name: "fixture-service")
            observe(harness.navigation, name: "fixture-navigation")
            observe(harness.validationControl, name: "fixture-control")
            observe(harness.sessionStore, name: "fixture-session-store")
        }

        func runBody(_ body: (PaymentPlanHarness, PaymentPlanFixtureLifetime) async throws -> Void) async throws {
            try await body(harness!, self)
        }

        @discardableResult
        func mount(_ view: AnyView, control: PlanningViewValidationControl,
                   additionalDependencies: [AnyObject] = []) -> Mount {
            let identity = "mounted-fixture-\(mounts.count + 1)"
            let observedView = AnyView(view
                .background(V15GraphObserver(identity: identity, snapshot: identity, signals: signals))
                .onAppear { [signals] in signals.record("graph-appeared:\(identity)") }
                .onDisappear { [signals] in signals.record("graph-disappeared:\(identity)") })
            let host = UIHostingController(rootView: observedView)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
            let mount = Mount(window: window, host: host, control: control, identity: identity)
            mounts.append(mount)
            for object in [control] + additionalDependencies {
                let name = "additional-\(identity)-\(ObjectIdentifier(object))"
                dependencies.append(object)
                observe(object, name: name)
            }
            observe(host, name: "host:\(identity)")
            observe(window, name: "window:\(identity)")
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            signals.record("mount-created:\(identity):storage-retained")
            return mount
        }

        /// Called only at the original, successful editor-mount observation,
        /// before a query failure or teardown can invalidate access.
        func observePresentedRecords() throws {
            guard let harness, let context else { return }
            for mount in mounts where !mount.closed && !mount.observedSheet {
                guard let sheet = mount.host?.presentedViewController else { continue }
                mount.observedSheet = true
                observe(sheet, name: "sheet:\(mount.identity)")
                let bucket = try XCTUnwrap(context.fetch(FetchDescriptor<DebtPayoffBucket>())
                    .first { $0.id == harness.bucketID })
                let cycle = try XCTUnwrap(context.fetch(FetchDescriptor<PaymentPlanCycle>())
                    .first { $0.id == harness.cycleID })
                V15ObserveLifetime.capture(bucket: bucket, cycle: cycle, context: context, signals: signals)
                observe(bucket, name: "editor-bucket:\(mount.identity)")
                observe(cycle, name: "editor-cycle:\(mount.identity)")
                signals.record("presented-editor-observed:\(mount.identity)")
            }
        }

        func closeMount(_ mount: Mount, test: XCTestCase) async {
            guard !mount.closed else { return }
            signals.record("cleanup-begin:\(mount.identity):storage-retained")
            await dismissAndSettleCallbacks(mount, test: test)
            detach(mount)
            await require(["graph-disappeared:\(mount.identity)",
                           "graph-dismantled:\(mount.identity)",
                           "graph-destroyed:\(mount.identity)",
                           "destroyed:host:\(mount.identity)"], test: test)
            requireReleased("host:\(mount.identity)")
            if mount.observedSheet {
                await require(["destroyed:sheet:\(mount.identity)"], test: test)
                requireReleased("sheet:\(mount.identity)")
            }
            XCTAssertNotNil(container)
            XCTAssertNotNil(context)
            mount.window = nil
            await require(["destroyed:window:\(mount.identity)"], test: test)
            requireReleased("window:\(mount.identity)")
            mount.closed = true
            signals.record("host-graph-destroyed-before-storage:\(mount.identity)")
        }

        private func dismissAndSettleCallbacks(_ mount: Mount, test: XCTestCase) async {
            guard let host = mount.host else {
                fatalError("V15 fixture lost its host before cleanup")
            }
            if let sheet = host.presentedViewController {
                if !mount.observedSheet {
                    mount.observedSheet = true
                    observe(sheet, name: "sheet:\(mount.identity)")
                }
                let dismissed = "sheet-dismissal-completed:\(mount.identity)"
                host.dismiss(animated: false) { [signals] in signals.record(dismissed) }
                await require([dismissed], test: test)
                XCTAssertNil(host.presentedViewController, "Actual sheet dismissal must finish")
            }

            // Dismissal's disappearance cancels the real Hold task. Release
            // its controlled wait only after that lifecycle event, then await
            // exact callback tasks so they cannot survive storage cleanup.
            let control = mount.control
            let unreleasedCallbackIDs = control.trace.compactMap(\.callbackID).filter { id in
                !control.trace.contains { $0.event == .callbackReleased(id) }
            }
            let mountedCount = control.trace.filter { $0.event == .holdControlMounted }.count
            if mountedCount > 0 {
                let disappeared = "editor-disappeared:\(mount.identity)"
                control.traceObserver = { [signals] entry in
                    if entry.event == .holdControlDisappeared { signals.record(disappeared) }
                    if case .callbackSettled(let id) = entry.event {
                        signals.record("callback-settled:\(mount.identity):\(id)")
                    }
                }
                let disappearedCount = control.trace.filter { $0.event == .holdControlDisappeared }.count
                if disappearedCount >= mountedCount { signals.record(disappeared) }
                await require([disappeared], test: test)
            }
            let callbackIDs = control.trace.compactMap(\.callbackID)
            for entry in control.trace {
                if case .callbackSettled(let id) = entry.event {
                    signals.record("callback-settled:\(mount.identity):\(id)")
                }
            }
            control.releaseAllDeferredCallbacks()
            await require(callbackIDs.map { "callback-settled:\(mount.identity):\($0)" }, test: test)
            for id in callbackIDs { _ = await control.awaitCallbackTaskSettlement(id) }
            for id in unreleasedCallbackIDs {
                XCTAssertFalse(control.trace.contains { $0.event == .persistenceAttempt(id) },
                               "Cleanup must cancel an unreleased Hold before funding")
            }
            control.traceObserver = nil
        }

        // A separate synchronous frame ensures the strong host reference used
        // to request dismissal cannot extend through the weak-release wait.
        private func detach(_ mount: Mount) {
            mount.window?.isHidden = true
            mount.window?.rootViewController = nil
            mount.host = nil
        }

        func cleanup(test: XCTestCase) async {
            guard !cleanupFinished else { return }
            for mount in mounts.reversed() { await closeMount(mount, test: test) }
            signals.record("all-editor-host-graphs-destroyed")
            harness?.defaults.removePersistentDomain(forName: harness!.defaultsSuiteName)
            harness = nil
            mounts.removeAll()
            signals.record("editor-and-view-references-released")
            service = nil
            auth = nil
            dependencies.removeAll()
            signals.record("services-and-navigation-released")
            context = nil
            signals.record("test-context-reference-released")
            container = nil
            await require(["destroyed:fixture-container", "destroyed:fixture-context",
                           "destroyed:fixture-auth", "destroyed:fixture-service",
                           "destroyed:fixture-navigation", "destroyed:fixture-control",
                           "destroyed:fixture-session-store"], test: test)
            for name in weakReferences.keys { requireReleased(name) }
            cleanupFinished = true
            signals.record("fixture-cleanup-completed:all-weak-references-clear")
            let attachment = XCTAttachment(string: signals.trace)
            attachment.name = "V15 corrected fixture teardown"
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }

        private func observe(_ object: AnyObject, name: String) {
            weakReferences[name] = WeakReference(object)
            V15ObserveLifetime.attach(object, label: name, signals: signals)
        }

        private func requireReleased(_ name: String) {
            // Never stringify a possibly invalid SwiftData object on failure.
            XCTAssertTrue(weakReferences[name]?.object == nil, "Fixture retained \(name)")
        }

        private func require(_ events: [String], test: XCTestCase) async {
            guard !events.isEmpty else { return }
            let result = await XCTWaiter.fulfillment(
                of: events.map { signals.expectation(for: $0) }, timeout: 10
            )
            guard result == .completed else {
                XCTFail("V15 fixture destruction did not complete: \(events)")
                // This isolated test process must fail while its storage is
                // still retained, rather than release live storage or leak it.
                fatalError("V15 cleanup lifecycle precondition failed; original body evidence precedes this failure")
            }
        }
    }

    private struct PaymentPlanHarness {
        let container: ModelContainer
        let view: AnyView
        let navigation: AppNavigation
        let validationControl: PlanningViewValidationControl
        let auth: AuthManager
        let sessionStore: SentinelAuthSessionStore
        let service: PlaidService
        let bucketID: UUID
        let cycleID: UUID
        let defaults: UserDefaults
        let defaultsSuiteName: String
        let diagnostics: V15HostedSignals
    }

    private func makePaymentPlanHarness(
        debtKind: DebtPayoffKind = .linkedCreditCard,
        controlledFailuresAlsoFailCommandReads: Bool = true
    ) throws -> PaymentPlanHarness {
        let ownerID = "mounted-query-owner"
        let ownerScopeID = try XCTUnwrap(
            PlanningOwnerScope.authenticated(ownerID)
        )
        let container = try makeContainer()
        let context = container.mainContext
        let diagnostics = V15HostedSignals(label: "historical-mounted-\(debtKind)")
        V15ObserveLifetime.attach(container, label: "historical-container", signals: diagnostics)
        V15ObserveLifetime.attach(context, label: "historical-main-context", signals: diagnostics)
        let dueDate = Calendar.current.date(
            byAdding: .day,
            value: 21,
            to: Date()
        ) ?? Date().addingTimeInterval(21 * 86_400)
        let bucket = DebtPayoffBucket(
            ownerScopeID: ownerScopeID,
            plaidAccountID: debtKind == .linkedCreditCard
                ? "mounted-card"
                : "",
            accountName: debtKind == .linkedCreditCard
                ? "Mounted Card"
                : "Mounted Loan",
            dueDate: dueDate,
            paymentTargetAmount: 900,
            protectedAmount: 275,
            debtKind: debtKind,
            manualCurrentBalance:
                debtKind.isManualInstallmentDebt ? 0 : nil
        )
        let cycle = PaymentPlanCycle(
            ownerScopeID: ownerScopeID,
            paymentPlanID: bucket.id,
            dueDate: dueDate,
            frozenTargetAmount: 900
        )
        context.insert(bucket)
        context.insert(cycle)
        context.insert(
            ReserveSettings(
                ownerScopeID: ownerScopeID,
                balance: 0
            )
        )
        try context.save()

        V15ObserveLifetime.capture(bucket: bucket, cycle: cycle, context: context, signals: diagnostics)
        V15ObserveLifetime.attach(bucket, label: "historical-bucket", signals: diagnostics)
        V15ObserveLifetime.attach(cycle, label: "historical-cycle", signals: diagnostics)
        diagnostics.record("initial-fixture-save-completed")

        let defaultsSuiteName = "MountedQuery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: defaultsSuiteName)
        )
        let session = makeInterceptedSession()
        let sessionStore = SentinelAuthSessionStore()
        let auth = AuthManager(
            urlSession: session,
            pendingDeletionDefaults: defaults,
            localStoreKind: .development,
            restoreSavedSession: false,
            initialSessionToken: "mounted-query-session",
            initialUser: AuthUserSummary(
                id: ownerID,
                email: "mounted@example.invalid",
                fullName: "Mounted Owner"
            ),
            sessionStore: sessionStore,
            localDevelopmentSignInAllowed: { false }
        )
        let validationControl = PlanningViewValidationControl(
            isTestEnabled: true,
            blocksDeferredCallbacks: true
        )
        let service = PlaidService(
            sessionTokenProvider: { auth.backendSessionToken },
            authenticatedUserIDProvider: { auth.user?.id },
            urlSession: session,
            bankCacheDefaults: defaults,
            localStoreKind: .development,
            shouldFailPersistenceRead: { domain in
                controlledFailuresAlsoFailCommandReads &&
                    validationControl.additionalFailedRequiredReads
                        .contains(domain)
            }
        )
        service.configurePersistence(modelContext: context)
        service.handlePlanningOwnerScopeChanged(
            authenticatedUserID: ownerID
        )
        XCTAssertEqual(
            service.planningSnapshotAvailability(
                authenticatedUserID: ownerID
            ),
            .available
        )

        let navigation = AppNavigation()
        let view = AnyView(
            SavingsGoalsView(
                initialPagerSection: .paymentPlans,
                validationControl: validationControl
            )
            .environmentObject(auth)
            .environmentObject(service)
            .environmentObject(navigation)
            .modelContainer(container)
            .defaultAppStorage(defaults)
        )

        return PaymentPlanHarness(
            container: container,
            view: view,
            navigation: navigation,
            validationControl: validationControl,
            auth: auth,
            sessionStore: sessionStore,
            service: service,
            bucketID: bucket.id,
            cycleID: cycle.id,
            defaults: defaults,
            defaultsSuiteName: defaultsSuiteName,
            diagnostics: diagnostics
        )
    }

    private func paymentPlanView(
        harness: PaymentPlanHarness,
        navigation: AppNavigation,
        validationControl: PlanningViewValidationControl
    ) -> AnyView {
        AnyView(
            SavingsGoalsView(
                initialPagerSection: .paymentPlans,
                validationControl: validationControl
            )
            .environmentObject(harness.auth)
            .environmentObject(harness.service)
            .environmentObject(navigation)
            .modelContainer(harness.container)
            .defaultAppStorage(harness.defaults)
        )
    }

    private func storedProtectedAmount(
        in harness: PaymentPlanHarness
    ) throws -> Double {
        harness.diagnostics.record("begin-original-fresh-context-protected-amount-assertion")
        let freshContext = ModelContext(harness.container)
        V15ObserveLifetime.attach(freshContext, label: "historical-assertion-context-\(ObjectIdentifier(freshContext))", signals: harness.diagnostics)
        return try XCTUnwrap(
            try freshContext.fetch(FetchDescriptor<DebtPayoffBucket>())
                .first { $0.id == harness.bucketID }
        ).protectedAmount
    }

    private func waitForTrace(
        in control: PlanningViewValidationControl,
        after sequence: UInt64,
        matching predicate:
            @escaping (PlanningViewValidationControl.TraceEvent) -> Bool
    ) async throws -> PlanningViewValidationControl.TraceEntry {
        if let existing = control.trace.first(where: {
            $0.sequence > sequence && predicate($0.event)
        }) {
            if existing.event == .holdControlMounted {
                try activePaymentPlanFixture?.observePresentedRecords()
            }
            print("V15-HISTORY control=\(ObjectIdentifier(control)) existing-trace=\(existing.sequence):\(existing.event)")
            fflush(stdout)
            return existing
        }

        let eventExpectation = expectation(
            description: "Planning validation trace event"
        )
        let diagnosticControlIdentity = ObjectIdentifier(control)
        var matchedEntry: PlanningViewValidationControl.TraceEntry?
        control.traceObserver = { entry in
            print("V15-HISTORY control=\(diagnosticControlIdentity) observed-trace=\(entry.sequence):\(entry.event)")
            fflush(stdout)
            guard entry.sequence > sequence,
                  predicate(entry.event),
                  matchedEntry == nil else {
                return
            }
            matchedEntry = entry
            eventExpectation.fulfill()
        }
        await fulfillment(of: [eventExpectation], timeout: 3)
        control.traceObserver = nil
        if matchedEntry == nil {
            XCTFail(
                "Observed planning trace: \(control.trace.map { String(describing: $0.event) })"
            )
        }
        let entry = try XCTUnwrap(matchedEntry)
        if entry.event == .holdControlMounted {
            try activePaymentPlanFixture?.observePresentedRecords()
        }
        return entry
    }

    private func attachTrace(
        _ trace: [PlanningViewValidationControl.TraceEntry],
        named name: String
    ) {
        let body = trace.map {
            "\($0.sequence): \(String(describing: $0.event))"
        }
        .joined(separator: "\n")
        let attachment = XCTAttachment(
            data: Data(body.utf8),
            uniformTypeIdentifier: "public.plain-text"
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            TransactionMatchedExpenseResolution.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self,
            IncomeSchedule.self,
            PlanningOwnershipMigrationState.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            ]
        )
    }

    private func apply(
        account: PlaidAccount,
        to service: PlaidService
    ) {
        let scope = service.beginBankSyncRefreshRequest()
        let body = """
        {
          "accounts": [{
            "account_id": "\(account.account_id)",
            "name": "\(account.name)",
            "official_name": null,
            "type": "depository",
            "subtype": "checking",
            "mask": "4242",
            "item_id": "mounted-item",
            "balances": {"available": 1000, "current": 1000}
          }],
          "partial_failure": false,
          "refreshed_item_ids": ["mounted-item"],
          "evaluated_item_ids": ["mounted-item"]
        }
        """
        service.handleAccountsResponse(
            requestScope: scope,
            data: Data(body.utf8),
            response: HTTPURLResponse(
                url: URL(string: "https://mounted.invalid/api/plaid/accounts")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ),
            error: nil,
            reason: .debugTool,
            completion: { _ in }
        )
    }

    private func mount<Content: View>(
        _ view: Content,
        diagnostics: V15HostedSignals? = nil
    ) -> (window: UIWindow, host: UIHostingController<Content>) {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 430, height: 932)
        )
        if let diagnostics {
            V15ObserveLifetime.attach(host, label: "historical-host-\(ObjectIdentifier(host))", signals: diagnostics)
            V15ObserveLifetime.attach(window, label: "historical-window-\(ObjectIdentifier(window))", signals: diagnostics)
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return (window, host)
    }

    private func flushMountedUpdates() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func settleMountedView() async throws {
        for _ in 0..<5 {
            await flushMountedUpdates()
        }
        try await Task.sleep(for: .milliseconds(250))
        await flushMountedUpdates()
    }

    private func attachScreenshot(
        of view: UIView,
        named name: String
    ) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension PlanningViewValidationControl.TraceEntry {
    var callbackID: UInt64? {
        guard case .callbackQueued(let callbackID) = event else {
            return nil
        }
        return callbackID
    }
}
