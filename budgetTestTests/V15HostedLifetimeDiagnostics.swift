import Foundation
import ObjectiveC
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Caldera_Money

// These witnesses never own the object they observe. All persisted identities
// are captured before a diagnostic transition, never from deinit or a failure.
nonisolated final class V15HostedSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    private var seen: Set<String> = []
    private var waiters: [String: XCTestExpectation] = [:]
    private var survivalProbes: [String: V15WeakObjectProbe] = [:]
    private var destructionSurvival: [String: [String: Bool]] = [:]
    let label: String

    init(label: String) {
        self.label = "\(label) pid=\(ProcessInfo.processInfo.processIdentifier) run=\(UUID().uuidString)"
    }

    func record(_ event: String) {
        lock.lock()
        let survival = event.hasPrefix("destroyed:")
            ? survivalProbes.mapValues { $0.isAlive } : [:]
        if !survival.isEmpty { destructionSurvival[event] = survival }
        let suffix = survival.isEmpty ? "" : " survival[" + survival.keys.sorted()
            .map { "\($0)=\(survival[$0]!)" }.joined(separator: ",") + "]"
        let rendered = event + suffix
        events.append(rendered)
        let isNew = seen.insert(event).inserted
        let waiter = isNew ? waiters.removeValue(forKey: event) : nil
        lock.unlock()
        print("V15-HOST \(label) \(rendered)")
        fflush(stdout)
        waiter?.fulfill()
    }

    func installWeakSurvivalProbes(_ objects: [String: AnyObject]) {
        lock.lock()
        survivalProbes = objects.mapValues(V15WeakObjectProbe.init)
        lock.unlock()
    }

    func survival(at event: String) -> [String: Bool]? {
        lock.lock()
        defer { lock.unlock() }
        return destructionSurvival[event]
    }

    func expectation(for event: String) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "V15 \(event)")
        lock.lock()
        let occurred = seen.contains(event)
        if !occurred { waiters[event] = expectation }
        lock.unlock()
        if occurred { expectation.fulfill() }
        return expectation
    }

    var trace: String {
        lock.lock()
        defer { lock.unlock() }
        return events.joined(separator: "\n")
    }
}

// Weak loads answer object survival only. They never inspect a model getter,
// context property, or SwiftData relationship after storage release.
nonisolated private final class V15WeakObjectProbe: @unchecked Sendable {
    private weak var object: AnyObject?
    init(_ object: AnyObject) { self.object = object }
    var isAlive: Bool { object != nil }
}

nonisolated private final class V15ObjectLifetimeWitness {
    let signals: V15HostedSignals
    let label: String
    init(label: String, signals: V15HostedSignals) {
        self.label = label
        self.signals = signals
    }
    deinit { signals.record("destroyed:\(label)") }
}

@MainActor
enum V15ObserveLifetime {
    private static var associationKey: UInt8 = 0

    static func attach(_ object: AnyObject, label: String, signals: V15HostedSignals) {
        signals.record("created:\(label):object=\(ObjectIdentifier(object))")
        // More than one diagnostic phase may observe the same registered
        // model instance. Append witnesses so relabeling never destroys an old
        // witness and falsely reports that its still-live object was released.
        var witnesses = objc_getAssociatedObject(object, &associationKey)
            as? [V15ObjectLifetimeWitness] ?? []
        witnesses.append(V15ObjectLifetimeWitness(label: label, signals: signals))
        objc_setAssociatedObject(object, &associationKey, witnesses,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func capture(bucket: DebtPayoffBucket, cycle: PaymentPlanCycle,
                        context: ModelContext, signals: V15HostedSignals) {
        signals.record("captured-before-transition:bucket=\(bucket.id):persistent=\(bucket.persistentModelID):owner=\(bucket.ownerScopeID ?? "nil"):object=\(ObjectIdentifier(bucket)):context=\(ObjectIdentifier(context))")
        signals.record("captured-before-transition:cycle=\(cycle.id):persistent=\(cycle.persistentModelID):owner=\(cycle.ownerScopeID ?? "nil"):plan=\(cycle.paymentPlanID):object=\(ObjectIdentifier(cycle))")
    }
}

nonisolated final class V15GraphWitness {
    let identity: String
    let signals: V15HostedSignals
    init(identity: String, signals: V15HostedSignals) {
        self.identity = identity
        self.signals = signals
        signals.record("graph-created:\(identity)")
    }
    deinit { signals.record("graph-destroyed:\(identity)") }
}

struct V15GraphObserver: UIViewRepresentable {
    let identity: String
    let snapshot: String
    let signals: V15HostedSignals
    func makeCoordinator() -> V15GraphWitness { V15GraphWitness(identity: identity, signals: signals) }
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ view: UIView, context: Context) { signals.record("observed:\(snapshot)") }
    static func dismantleUIView(_ view: UIView, coordinator: V15GraphWitness) {
        coordinator.signals.record("graph-dismantled:\(coordinator.identity)")
    }
}

nonisolated private final class V15ReadFault: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    func set(_ value: Bool) { lock.lock(); enabled = value; lock.unlock() }
    func fails(_ domain: PlanningPersistenceReadDomain) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled && domain == .reserveSettings
    }
}

private struct V15SavingsRoot: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var plaid: PlaidService
    let control: PlanningViewValidationControl
    let signals: V15HostedSignals
    private var owner: String { auth.user?.id ?? "signed-out" }
    private var identity: String {
        "\(PlanningOwnerScope.current(authenticatedUserID: auth.user?.id)):\(plaid.planningQueryReloadGeneration)"
    }
    var body: some View {
        let label = "\(owner):\(plaid.planningQueryReloadGeneration)"
        SavingsGoalsView(initialPagerSection: .paymentPlans, validationControl: control)
            .background(V15GraphObserver(identity: label,
                snapshot: "\(label):\(plaid.planningSnapshotAvailability(authenticatedUserID: auth.user?.id))",
                signals: signals))
            .onAppear { signals.record("graph-appeared:\(label)") }
            .onDisappear { signals.record("graph-disappeared:\(label)") }
            .id(identity)
            .onChange(of: owner) { _, _ in
                plaid.handlePlanningOwnerScopeChanged(authenticatedUserID: auth.user?.id)
            }
    }
}

/// Diagnostic selections: run individually in fresh processes. A fatal child
/// outcome is evidence to classify; it is never counted as release validation.
@MainActor
final class V15HostedLifetimeDiagnosticTests: ContainedNetworkTestCase {
    private struct Dependencies {
        let container: ModelContainer
        let context: ModelContext
        let auth: AuthManager
        let store: SentinelAuthSessionStore
        let service: PlaidService
        let navigation: AppNavigation
        let control: PlanningViewValidationControl
        let fault: V15ReadFault
        let defaults: UserDefaults
        let suite: String
        let bucketID: UUID
        let cycleID: UUID
    }

    private enum Scenario: String {
        case retainedLegacy, retainedModern, ownerBeforeDismiss, dismissBeforeOwner
        case queryFailureRecovery, saveFailureRollback, deleteOrderProbe, shortHiddenOnly
        case ownerBeforeDismissModern, queryFailureRecoveryModern, shortHiddenOnlyModern

        var usesModernEditor: Bool {
            switch self {
            case .retainedModern, .ownerBeforeDismissModern, .queryFailureRecoveryModern, .shortHiddenOnlyModern:
                return true
            default: return false
            }
        }
    }

    func testV15RetainedContainerLegacyRoute() async throws { try await run(.retainedLegacy) }
    func testV15RetainedContainerModernRoute() async throws { try await run(.retainedModern) }
    func testV15OwnerReplacementBeforeSheetDismissal() async throws { try await run(.ownerBeforeDismiss) }
    func testV15SheetDismissalBeforeOwnerReplacement() async throws { try await run(.dismissBeforeOwner) }
    func testV15RequiredReadRollbackWithPresentedRouteAndRecovery() async throws { try await run(.queryFailureRecovery) }
    func testV15SaveFailureRollbackWithPresentedRoute() async throws { try await run(.saveFailureRollback) }
    func testV15ExactPlanDeleteWithPresentedRouteOrderProbe() async throws { try await run(.deleteOrderProbe) }
    func testV15ShortFixtureHiddenOnlyTeardown() async throws { try await run(.shortHiddenOnly) }
    func testV15ModernOwnerReplacementBeforeSheetDismissal() async throws { try await run(.ownerBeforeDismissModern) }
    func testV15ModernRequiredReadRollbackWithPresentedRouteAndRecovery() async throws { try await run(.queryFailureRecoveryModern) }
    func testV15ModernShortFixtureHiddenOnlyTeardown() async throws { try await run(.shortHiddenOnlyModern) }

    private func run(_ scenario: Scenario) async throws {
        try await Task { @MainActor in try await runOnMainActor(scenario) }.value
    }

    private func runOnMainActor(_ scenario: Scenario) async throws {
        XCTAssertNotNil(withUnsafeCurrentTask { $0 })
        let signals = V15HostedSignals(label: scenario.rawValue)
        defer {
            let attachment = XCTAttachment(string: signals.trace)
            attachment.name = "V15 hosted \(scenario.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        var dependencies: Dependencies? = try makeDependencies(
            kind: scenario.usesModernEditor ? .linkedCreditCard : .autoLoan, signals: signals
        )
        weak var weakContainer = dependencies?.container
        weak var weakContext = dependencies?.context
        weak var weakAuth = dependencies?.auth
        weak var weakService = dependencies?.service
        weak var weakNavigation = dependencies?.navigation
        weak var weakStore = dependencies?.store
        var host: UIHostingController<AnyView>? = UIHostingController(rootView: makeRoot(dependencies!, signals))
        weak var weakHost = host
        V15ObserveLifetime.attach(host!, label: "host", signals: signals)
        var window: UIWindow? = UIWindow(frame: UIScreen.main.bounds)
        weak var weakWindow = window
        V15ObserveLifetime.attach(window!, label: "window", signals: signals)
        window!.rootViewController = host
        window!.makeKeyAndVisible()
        await observe(["graph-appeared:v15-owner-A:0", "observed:v15-owner-A:0:available"], signals)
        dependencies!.navigation.openSavingsEditDebtPayoff(dependencies!.bucketID, cycleID: dependencies!.cycleID)
        await observe(["hold-mounted:1"], signals)
        weak var weakSheet = host!.presentedViewController
        try attachPresentedLifetime(host!, signals)
        weak var weakBucket = try dependencies!.context.fetch(FetchDescriptor<DebtPayoffBucket>()).first {
            $0.id == dependencies!.bucketID
        }
        weak var weakCycle = try dependencies!.context.fetch(FetchDescriptor<PaymentPlanCycle>()).first {
            $0.id == dependencies!.cycleID
        }
        try capturePresentedRecords(bucket: XCTUnwrap(weakBucket), cycle: XCTUnwrap(weakCycle),
                                    context: dependencies!.context, signals: signals)
        signals.installWeakSurvivalProbes([
            "bucket": try XCTUnwrap(weakBucket), "sheet": try XCTUnwrap(weakSheet),
            "cycle": try XCTUnwrap(weakCycle),
            "host": host!, "window": window!, "container": dependencies!.container,
            "context": dependencies!.context
        ])
        signals.record("route-presented:captured-identities-valid-before-transition")

        var finalIdentity = "v15-owner-A:0"
        switch scenario {
        case .retainedLegacy, .retainedModern:
            signals.record("ordinary-context-save-with-route-presented")
            try dependencies!.context.save()
            // Deliberate named safe-read control, not diagnostic logging.
            try assertStoredPlan(dependencies!, expected: 275)
            await dismissSheet(host!, signals)
        case .dismissBeforeOwner:
            await dismissSheet(host!, signals)
            try await replaceOwner(dependencies!, signals)
            finalIdentity = "v15-owner-B:0"
        case .ownerBeforeDismiss, .ownerBeforeDismissModern:
            signals.record("owner-replacement-with-sheet-presented")
            try await replaceOwner(dependencies!, signals)
            finalIdentity = "v15-owner-B:0"
            await observe(["hold-disappeared:1"], signals)
        case .queryFailureRecovery, .queryFailureRecoveryModern:
            signals.record("begin-required-read-failure:service-will-rollback-main-context")
            dependencies!.fault.set(true)
            XCTAssertFalse(dependencies!.service.retryPlanningSnapshot(authenticatedUserID: "v15-owner-A"))
            signals.record("required-read-failure-returned")
            await observe(["observed:v15-owner-A:1:unavailable", "hold-disappeared:1"], signals)
            dependencies!.fault.set(false)
            signals.record("begin-required-read-recovery")
            XCTAssertTrue(dependencies!.service.retryPlanningSnapshot(authenticatedUserID: "v15-owner-A"))
            await observe(["observed:v15-owner-A:2:available"], signals)
            finalIdentity = "v15-owner-A:2"
            // A fresh fetch is intentionally authorized after successful load.
            try assertStoredPlan(dependencies!, expected: 275)
        case .saveFailureRollback:
            try exerciseProductionSaveFailure(dependencies!, signals)
            await dismissSheet(host!, signals)
        case .deleteOrderProbe:
            // These are the exact store operations used by SavingsGoalsView's
            // private delete callback, not a claim to have invoked its button.
            try deleteExactPlanOrderProbe(dependencies!, signals)
            await dismissSheet(host!, signals)
        case .shortHiddenOnly, .shortHiddenOnlyModern:
            signals.record("begin-historical-hidden-only-teardown:sheet-still-presented")
            window!.isHidden = true
            dependencies!.defaults.removePersistentDomain(forName: dependencies!.suite)
            dependencies!.control.releaseAllDeferredCallbacks()
            dependencies = nil
            host = nil
            window = nil
            signals.record("short-fixture-local-owners-released:container-alive=\(weakContainer != nil):context-alive=\(weakContext != nil):host-alive=\(weakHost != nil):window-alive=\(weakWindow != nil):sheet-alive=\(weakSheet != nil):bucket-alive=\(weakBucket != nil)")
            // The run loop remains active for genuine destruction evidence. A
            // retained storage owner is an unmet diagnostic precondition, not
            // evidence that early container destruction was harmless.
            await observe(["destroyed:container", "destroyed:context"], signals)
            let releaseOccurred = weakContainer == nil && weakContext == nil
            signals.record("short-fixture-storage-release-precondition=\(releaseOccurred)")
            XCTAssertNil(weakContainer, "Container release was not established")
            XCTAssertNil(weakContext, "Context release was not established")
            let containerSurvival = signals.survival(at: "destroyed:container")
            let retainedRouteAtContainerRelease = containerSurvival?["bucket"] == true &&
                containerSurvival?["sheet"] == true
            signals.record("short-fixture-hazardous-ordering-precondition=\(retainedRouteAtContainerRelease):bucket-alive-now=\(weakBucket != nil):sheet-alive-now=\(weakSheet != nil)")
            if !retainedRouteAtContainerRelease {
                signals.record("INCONCLUSIVE:storage-did-not-release-before-a-retained-sheet-and-model")
                XCTFail("Diagnostic precondition unmet: no retained model and editor at container destruction; this is not a safe-lifetime pass")
            }
            // End this diagnostic's UIKit graph if UIKit still holds it; these
            // are controller references, never invalid model-property reads.
            if let survivingHost = weakHost {
                signals.record("short-fixture-cleanup-surviving-host")
                if survivingHost.presentedViewController != nil {
                    await dismissSheet(survivingHost, signals)
                }
                weakWindow?.rootViewController = nil
            }
            XCTAssertTrue(transport.observations.isEmpty)
            signals.record("short-fixture-diagnostic-returning")
            return
        }

        signals.record("detach-host-with-container-retained")
        XCTAssertNotNil(weakContainer)
        XCTAssertNotNil(weakContext)
        window!.isHidden = true
        window!.rootViewController = nil
        host = nil
        await observe(["graph-disappeared:\(finalIdentity)", "graph-dismantled:\(finalIdentity)",
                       "graph-destroyed:\(finalIdentity)", "destroyed:host", "destroyed:sheet"], signals)
        XCTAssertNil(weakHost)
        XCTAssertNil(weakSheet)
        XCTAssertNotNil(weakContainer)
        XCTAssertNotNil(weakContext)
        window = nil
        await observe(["destroyed:window"], signals)
        dependencies!.defaults.removePersistentDomain(forName: dependencies!.suite)
        dependencies!.control.releaseAllDeferredCallbacks()
        signals.record("release-container-after-host-destruction")
        dependencies = nil
        XCTAssertNil(weakService)
        XCTAssertNil(weakAuth)
        XCTAssertNil(weakStore)
        XCTAssertNil(weakNavigation)
        XCTAssertNil(weakContext)
        XCTAssertNil(weakContainer)
        XCTAssertEqual(UIValidationURLProtocol.unexpectedRequestCount, 0)
        XCTAssertTrue(transport.observations.allSatisfy(\.matched))
        transport.assertSatisfied()
        signals.record("hosted-diagnostic-completed")
    }

    private func observe(_ events: [String], _ signals: V15HostedSignals) async {
        await fulfillment(of: events.map { signals.expectation(for: $0) }, timeout: 10)
    }

    private func attachPresentedLifetime(_ host: UIViewController, _ signals: V15HostedSignals) throws {
        let presented = try XCTUnwrap(host.presentedViewController, "Production route must present a real sheet")
        V15ObserveLifetime.attach(presented, label: "sheet", signals: signals)
    }

    private func capturePresentedRecords(bucket: DebtPayoffBucket, cycle: PaymentPlanCycle,
                                         context: ModelContext, signals: V15HostedSignals) {
        // Same main-context refetch as the mounted @Query. The initializer's
        // objects may already have been released and refaulted; these are the
        // currently registered objects after the real editor mounted. Locals
        // are owned only for this synchronous capture, before any transition.
        signals.record("capture-route-presented-main-context-records")
        V15ObserveLifetime.capture(bucket: bucket, cycle: cycle, context: context, signals: signals)
        V15ObserveLifetime.attach(bucket, label: "route-bucket", signals: signals)
        V15ObserveLifetime.attach(cycle, label: "route-cycle", signals: signals)
    }

    private func dismissSheet(_ host: UIViewController, _ signals: V15HostedSignals) async {
        signals.record("begin-UIKit-sheet-dismissal")
        await withCheckedContinuation { continuation in
            host.dismiss(animated: false) {
                signals.record("UIKit-sheet-dismissal-completed")
                continuation.resume()
            }
        }
        await observe(["hold-disappeared:1"], signals)
    }

    private func replaceOwner(_ dependencies: Dependencies, _ signals: V15HostedSignals) async throws {
        let consumed = expectation(description: "V15 synthetic owner replacement intercepted")
        transport.expect(method: "POST", path: "/api/auth/apple", body: Data(
            #"{"session_token":"v15-sentinel-B","user":{"id":"v15-owner-B"},"expires_at":"2030-01-01"}"#.utf8
        ), consumed: consumed)
        await dependencies.auth.signInWithAppleToken("v15-synthetic-identity", nonce: nil, fullName: nil, email: nil)
        await fulfillment(of: [consumed], timeout: 5)
        XCTAssertEqual(dependencies.auth.user?.id, "v15-owner-B")
        await observe(["graph-disappeared:v15-owner-A:0", "graph-dismantled:v15-owner-A:0",
                       "observed:v15-owner-B:0:available"], signals)
        XCTAssertEqual(dependencies.service.reserveBalance(authenticatedUserID: "v15-owner-B"), 250)
    }

    private func exerciseProductionSaveFailure(_ dependencies: Dependencies, _ signals: V15HostedSignals) throws {
        let bucket = try XCTUnwrap(dependencies.context.fetch(FetchDescriptor<DebtPayoffBucket>()).first {
            $0.id == dependencies.bucketID
        })
        let cycles = try dependencies.context.fetch(FetchDescriptor<PaymentPlanCycle>())
        let cycle = try XCTUnwrap(cycles.first { $0.id == dependencies.cycleID })
        V15ObserveLifetime.capture(bucket: bucket, cycle: cycle, context: dependencies.context, signals: signals)
        let request = try XCTUnwrap(PaymentPlanCoverInFullCoordinator.request(for: bucket, activeCycle: cycle, cycles: cycles))
        let token = dependencies.service.paymentPlanMutationAuthorizationToken(
            authenticatedUserID: "v15-owner-A", recordID: dependencies.bucketID, cycleID: dependencies.cycleID)
        var result: PaymentPlanCoverInFullPersistenceResult?
        let action = PaymentPlanEditorMutationActionFactory.make(service: dependencies.service, token: token,
            authenticatedUserID: { "v15-owner-A" }, record: bucket, cycle: { cycle }, cycles: { cycles }) {
            result = PaymentPlanCoverInFullCoordinator.persist(request, bucket: bucket, activeCycle: cycle, cycles: cycles,
                persistChanges: {
                    signals.record("injected-save-failure-before-commit")
                    throw NSError(domain: "V15InjectedSaveFailure", code: 1)
                }, rollback: {
                    signals.record("before-production-coordinator-rollback")
                    dependencies.context.rollback()
                    signals.record("after-production-coordinator-rollback")
                })
        }
        signals.record("begin-production-coordinator-save-failure-with-mounted-route")
        XCTAssertTrue(action())
        XCTAssertEqual(result?.didSave, false)
        signals.record("production-coordinator-returned-after-rollback-and-restoration")
        // Fresh authoritative refetch is a named data verification, never an
        // attempt to interrogate a possibly invalid original reference.
        try assertStoredPlan(dependencies, expected: 275)
    }

    private func deleteExactPlanOrderProbe(_ dependencies: Dependencies, _ signals: V15HostedSignals) throws {
        let bucket = try XCTUnwrap(dependencies.context.fetch(FetchDescriptor<DebtPayoffBucket>()).first {
            $0.id == dependencies.bucketID
        })
        let cycles = try dependencies.context.fetch(FetchDescriptor<PaymentPlanCycle>()).filter {
            $0.paymentPlanID == dependencies.bucketID
        }
        signals.record("begin-delete-plus-save-order-probe:captured-bucket=\(dependencies.bucketID)")
        cycles.forEach { dependencies.context.delete($0) }
        dependencies.context.delete(bucket)
        try dependencies.context.save()
        signals.record("delete-plus-save-returned:no-original-model-read")
    }

    private func assertStoredPlan(_ dependencies: Dependencies, expected: Double) throws {
        let context = ModelContext(dependencies.container)
        let records = try context.fetch(FetchDescriptor<DebtPayoffBucket>())
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.id, dependencies.bucketID)
        XCTAssertEqual(record.ownerScopeID, PlanningOwnerScope.authenticated("v15-owner-A"))
        XCTAssertEqual(record.protectedAmount, expected)
    }

    private func makeRoot(_ dependencies: Dependencies, _ signals: V15HostedSignals) -> AnyView {
        AnyView(V15SavingsRoot(control: dependencies.control, signals: signals)
            .environmentObject(dependencies.auth).environmentObject(dependencies.service)
            .environmentObject(dependencies.navigation).modelContainer(dependencies.container)
            .defaultAppStorage(dependencies.defaults))
    }

    private func makeDependencies(kind: DebtPayoffKind, signals: V15HostedSignals) throws -> Dependencies {
        let schema = Schema([PlannerEvent.self, EventAllocation.self, ExpenseOccurrenceStatus.self,
            TransactionMatchedExpenseResolution.self, SavingsGoalRecord.self, ReserveSettings.self,
            DebtPayoffBucket.self, PaymentPlanCycle.self, AvailableToSpendAccountPreference.self,
            IncomeSchedule.self, PlanningOwnershipMigrationState.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        V15ObserveLifetime.attach(container, label: "container", signals: signals)
        V15ObserveLifetime.attach(context, label: "context", signals: signals)
        let dueDate = Date().addingTimeInterval(21 * 86_400)
        let bucket = DebtPayoffBucket(ownerScopeID: PlanningOwnerScope.authenticated("v15-owner-A"),
            plaidAccountID: kind == .linkedCreditCard ? "v15-card" : "", accountName: "V15 Plan", dueDate: dueDate,
            paymentTargetAmount: 900, protectedAmount: 275, debtKind: kind,
            manualCurrentBalance: kind.isManualInstallmentDebt ? 0 : nil)
        let cycle = PaymentPlanCycle(ownerScopeID: bucket.ownerScopeID, paymentPlanID: bucket.id,
                                     dueDate: dueDate, frozenTargetAmount: 900)
        context.insert(bucket)
        context.insert(cycle)
        context.insert(ReserveSettings(ownerScopeID: PlanningOwnerScope.authenticated("v15-owner-A"), balance: 0))
        context.insert(ReserveSettings(ownerScopeID: PlanningOwnerScope.authenticated("v15-owner-B"), balance: 250))
        try context.save()
        V15ObserveLifetime.capture(bucket: bucket, cycle: cycle, context: context, signals: signals)
        V15ObserveLifetime.attach(bucket, label: "bucket", signals: signals)
        V15ObserveLifetime.attach(cycle, label: "cycle", signals: signals)
        let suite = "V15Hosted.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SentinelAuthSessionStore()
        let auth = AuthManager(urlSession: transport.session, pendingDeletionDefaults: defaults,
            localStoreKind: .development, restoreSavedSession: false, initialSessionToken: "v15-sentinel-A",
            initialUser: AuthUserSummary(id: "v15-owner-A", email: nil, fullName: nil),
            sessionStore: store, localDevelopmentSignInAllowed: { false })
        let fault = V15ReadFault()
        let service = PlaidService(sessionTokenProvider: { auth.backendSessionToken },
            authenticatedUserIDProvider: { auth.user?.id }, urlSession: transport.session,
            bankCacheDefaults: defaults, localStoreKind: .development,
            shouldFailPersistenceRead: { fault.fails($0) })
        service.configurePersistence(modelContext: context)
        service.handlePlanningOwnerScopeChanged(authenticatedUserID: "v15-owner-A")
        XCTAssertEqual(service.planningSnapshotAvailability(authenticatedUserID: "v15-owner-A"), .available)
        let control = PlanningViewValidationControl(isTestEnabled: true, blocksDeferredCallbacks: true)
        var mounted = 0
        var disappeared = 0
        control.traceObserver = { entry in
            signals.record("control:\(entry.sequence):\(entry.event)")
            if entry.event == .holdControlMounted { mounted += 1; signals.record("hold-mounted:\(mounted)") }
            if entry.event == .holdControlDisappeared { disappeared += 1; signals.record("hold-disappeared:\(disappeared)") }
        }
        let navigation = AppNavigation()
        navigation.openSavings(section: .paymentPlans)
        return Dependencies(container: container, context: context, auth: auth, store: store, service: service,
            navigation: navigation, control: control, fault: fault, defaults: defaults, suite: suite,
            bucketID: bucket.id, cycleID: cycle.id)
    }
}

