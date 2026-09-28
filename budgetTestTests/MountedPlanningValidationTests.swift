import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Caldera_Money

private final class MountedValidationURLProtocol: URLProtocol {
    static var attemptedURLs: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let url = request.url {
            Self.attemptedURLs.append(url)
        }
        client?.urlProtocol(
            self,
            didFailWithError: URLError(.notConnectedToInternet)
        )
    }

    override func stopLoading() {}
}

@MainActor
final class MountedPlanningValidationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MountedValidationURLProtocol.attemptedURLs = []
    }

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
        XCTAssertTrue(MountedValidationURLProtocol.attemptedURLs.isEmpty)
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
        let harness = try makePaymentPlanHarness()
        defer {
            harness.validationControl.releaseAllDeferredCallbacks()
            harness.defaults.removePersistentDomain(
                forName: harness.defaultsSuiteName
            )
        }

        let mounted = mount(harness.view)
        defer { mounted.window.isHidden = true }

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
        _ = try await waitForTrace(
            in: harness.validationControl,
            after: oldReleaseStart
        ) {
            $0 == .finalAuthorization(
                firstCallbackID,
                allowed: false
            )
        }
        XCTAssertEqual(
            try storedProtectedAmount(in: harness),
            275,
            accuracy: 0.001
        )

        mounted.window.isHidden = true
        let freshNavigation = AppNavigation()
        let freshValidationControl = PlanningViewValidationControl(
            isTestEnabled: true,
            blocksDeferredCallbacks: true
        )
        defer {
            freshValidationControl.releaseAllDeferredCallbacks()
        }
        let freshView = paymentPlanView(
            harness: harness,
            navigation: freshNavigation,
            validationControl: freshValidationControl
        )
        let freshMounted = mount(freshView)
        defer { freshMounted.window.isHidden = true }
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
        XCTAssertTrue(MountedValidationURLProtocol.attemptedURLs.isEmpty)
    }

    func testMountedLegacyEditorHealthyHoldSavesExactlyOnce() async throws {
        let harness = try makePaymentPlanHarness(debtKind: .autoLoan)
        defer {
            harness.validationControl.releaseAllDeferredCallbacks()
            harness.defaults.removePersistentDomain(
                forName: harness.defaultsSuiteName
            )
        }

        let mounted = mount(harness.view)
        defer { mounted.window.isHidden = true }
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
        XCTAssertTrue(MountedValidationURLProtocol.attemptedURLs.isEmpty)
    }

    func testMountedQueryFailureSuppliedBeforeQueuedCallbackCannotPersistWithoutForcedOnChangeOrdering() async throws {
        let harness = try makePaymentPlanHarness()
        defer {
            harness.validationControl.releaseAllDeferredCallbacks()
            harness.defaults.removePersistentDomain(
                forName: harness.defaultsSuiteName
            )
        }

        let mounted = mount(harness.view)
        defer { mounted.window.isHidden = true }
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
        XCTAssertTrue(MountedValidationURLProtocol.attemptedURLs.isEmpty)
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
        let harness = try makePaymentPlanHarness(
            controlledFailuresAlsoFailCommandReads: false
        )
        defer {
            harness.validationControl.releaseAllDeferredCallbacks()
            harness.defaults.removePersistentDomain(
                forName: harness.defaultsSuiteName
            )
        }

        let mounted = mount(harness.view)
        defer { mounted.window.isHidden = true }
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
        XCTAssertTrue(MountedValidationURLProtocol.attemptedURLs.isEmpty)
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

    private func assertCallbackBeforeObserverIsRejected(
        debtKind: DebtPayoffKind,
        failingDomain: PlanningPersistenceReadDomain = .paymentPlanCycles
    ) async throws {
        let harness = try makePaymentPlanHarness(debtKind: debtKind)
        defer {
            harness.validationControl.releaseAllDeferredCallbacks()
            harness.defaults.removePersistentDomain(
                forName: harness.defaultsSuiteName
            )
        }

        let mounted = mount(harness.view)
        defer { mounted.window.isHidden = true }
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
        XCTAssertTrue(MountedValidationURLProtocol.attemptedURLs.isEmpty)
    }

    private func makeInterceptedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MountedValidationURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private struct PaymentPlanHarness {
        let container: ModelContainer
        let view: AnyView
        let navigation: AppNavigation
        let validationControl: PlanningViewValidationControl
        let auth: AuthManager
        let service: PlaidService
        let bucketID: UUID
        let cycleID: UUID
        let defaults: UserDefaults
        let defaultsSuiteName: String
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

        let defaultsSuiteName = "MountedQuery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: defaultsSuiteName)
        )
        let session = makeInterceptedSession()
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
            sessionTokenSaver: { _ in },
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
            service: service,
            bucketID: bucket.id,
            cycleID: cycle.id,
            defaults: defaults,
            defaultsSuiteName: defaultsSuiteName
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
        let freshContext = ModelContext(harness.container)
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
            return existing
        }

        let eventExpectation = expectation(
            description: "Planning validation trace event"
        )
        var matchedEntry: PlanningViewValidationControl.TraceEntry?
        control.traceObserver = { entry in
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
        return try XCTUnwrap(matchedEntry)
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
        _ view: Content
    ) -> (window: UIWindow, host: UIHostingController<Content>) {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 430, height: 932)
        )
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
