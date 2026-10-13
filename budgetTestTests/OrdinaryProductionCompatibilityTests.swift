import Combine
import Foundation
import ObjectiveC
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import Caldera_Money

// Passive witnesses are deliberately nonisolated, own no app resources, and
// signal actual destruction. They neither schedule nor delay SwiftUI cleanup.
nonisolated private final class ProductionLifecycleSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: Set<String> = []
    private var waiters: [String: XCTestExpectation] = [:]
    private var recorded: [String] = []
    let prefix: String

    init(prefix: String) { self.prefix = prefix }

    func record(_ event: String) {
        lock.lock()
        recorded.append(event)
        let first = seen.insert(event).inserted
        let waiter = first ? waiters.removeValue(forKey: event) : nil
        lock.unlock()
        print("V14 \(prefix) \(event)")
        fflush(stdout)
        waiter?.fulfill()
    }

    func expectation(for event: String) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: event)
        lock.lock()
        let alreadySeen = seen.contains(event)
        if !alreadySeen { waiters[event] = expectation }
        lock.unlock()
        if alreadySeen { expectation.fulfill() }
        return expectation
    }

    var trace: String {
        lock.lock()
        defer { lock.unlock() }
        return recorded.joined(separator: "\n")
    }
}

nonisolated private final class ProductionGraphWitness {
    let identity: String
    let signals: ProductionLifecycleSignals
    init(identity: String, signals: ProductionLifecycleSignals) {
        self.identity = identity
        self.signals = signals
        signals.record("created:\(identity)")
    }
    deinit { signals.record("destroyed:\(identity)") }
}

private struct ProductionGraphObserver: UIViewRepresentable {
    let identity: String
    let snapshot: String
    let signals: ProductionLifecycleSignals

    func makeCoordinator() -> ProductionGraphWitness {
        ProductionGraphWitness(identity: identity, signals: signals)
    }
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ view: UIView, context: Context) {
        signals.record("observed:\(snapshot)")
    }
    static func dismantleUIView(_ view: UIView, coordinator: ProductionGraphWitness) {
        coordinator.signals.record("dismantled:\(coordinator.identity)")
    }
}

// This thin host applies AppRootView's existing owner:generation identity and
// owner-change handler to REAL ContentView. It bypasses onboarding, not the
// production TabView/SavingsGoalsView object graph. No validation injection.
private struct OrdinaryProductionRoot: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var plaid: PlaidService
    @EnvironmentObject var navigation: AppNavigation
    let signals: ProductionLifecycleSignals

    private var owner: String { auth.user?.id ?? "signed-out" }
    private var identity: String {
        "\(PlanningOwnerScope.current(authenticatedUserID: auth.user?.id)):\(plaid.planningQueryReloadGeneration)"
    }
    private var label: String { "\(owner):\(plaid.planningQueryReloadGeneration)" }

    var body: some View {
        let currentLabel = label
        ContentView()
            .background(ProductionGraphObserver(
                identity: currentLabel,
                snapshot: "\(currentLabel):\(plaid.planningSnapshotAvailability(authenticatedUserID: auth.user?.id)):tab\(navigation.selectedTab)",
                signals: signals
            ))
            .onAppear { signals.record("appeared:\(currentLabel)") }
            .onDisappear { signals.record("disappeared:\(currentLabel)") }
            .id(identity)
            .onChange(of: owner) { _, _ in
                // Same synchronous production handler used by AppRootView.
                plaid.handlePlanningOwnerScopeChanged(authenticatedUserID: auth.user?.id)
            }
    }
}

nonisolated private final class ProductionHostWitness {
    let signals: ProductionLifecycleSignals
    init(signals: ProductionLifecycleSignals) { self.signals = signals }
    deinit { signals.record("host-destroyed") }
}

nonisolated private final class ProductionReadFault: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    func set(_ value: Bool) { lock.lock(); enabled = value; lock.unlock() }
    func fails(_ domain: PlanningPersistenceReadDomain) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled && domain == .reserveSettings
    }
}

@MainActor
final class OrdinaryProductionCompatibilityTests: ContainedNetworkTestCase {
    private struct AppDependencies {
        let container: ModelContainer
        let context: ModelContext
        let auth: AuthManager
        let sessionStore: SentinelAuthSessionStore
        let plaid: PlaidService
        let summary: SummaryViewModel
        let navigation: AppNavigation
        let defaults: UserDefaults
        let suite: String
        let fault: ProductionReadFault
    }

    private static var associationKey: UInt8 = 0

    func testOrdinaryProductionGraphOneIteration() async throws {
        try await Task { @MainActor in try await runIteration(1) }.value
    }

    func testOrdinaryProductionGraphFiveSameProcessIterations() async throws {
        try await Task { @MainActor in
            for iteration in 1...5 { try await runIteration(iteration) }
        }.value
    }

    private func runIteration(_ iteration: Int) async throws {
        XCTAssertNotNil(withUnsafeCurrentTask { $0 }, "Release must run in an actual MainActor task")
        let signals = ProductionLifecycleSignals(
            prefix: "run=\(UUID().uuidString) pid=\(ProcessInfo.processInfo.processIdentifier) iteration=\(iteration)"
        )
        defer {
            let attachment = XCTAttachment(string: signals.trace)
            attachment.name = "V14 ordinary production lifecycle iteration \(iteration)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        signals.record("construct-app-dependencies")
        XCTAssertEqual(PlanningValidationDriver.constructedInstanceCount, 0)
        var dependencies: AppDependencies? = try makeDependencies()
        weak var weakAuth = dependencies?.auth
        weak var weakStore = dependencies?.sessionStore
        weak var weakPlaid = dependencies?.plaid
        weak var weakSummary = dependencies?.summary
        weak var weakNavigation = dependencies?.navigation
        weak var weakContainer = dependencies?.container
        weak var weakContext = dependencies?.context

        var host: UIHostingController<AnyView>? = UIHostingController(rootView: makeRoot(
            dependencies: dependencies!, signals: signals
        ))
        weak var weakHost = host
        objc_setAssociatedObject(host!, &Self.associationKey,
                                 ProductionHostWitness(signals: signals), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        await observe(["appeared:v14-owner-A:0", "observed:v14-owner-A:0:available:tab1"], signals)
        checkControls("initial host construction", signals)
        XCTAssertEqual(dependencies!.plaid.reserveBalance(authenticatedUserID: "v14-owner-A"), 125)

        // Ordinary TabView navigation causes real body reevaluation; no editor.
        dependencies!.navigation.selectedTab = 0
        await observe(["observed:v14-owner-A:0:available:tab0"], signals)
        dependencies!.navigation.openSavings()
        await observe(["observed:v14-owner-A:0:available:tab1"], signals)
        checkControls("normal body recomputation", signals)

        signals.record("begin-real-auth-owner-replacement")
        let consumed = expectation(description: "synthetic sign-in intercepted")
        transport.expect(method: "POST", path: "/api/auth/apple", body: Data(
            #"{"session_token":"v14-sentinel-B","user":{"id":"v14-owner-B"},"expires_at":"2030-01-01"}"#.utf8
        ), consumed: consumed)
        await dependencies!.auth.signInWithAppleToken("v14-synthetic-identity", nonce: nil, fullName: nil, email: nil)
        await fulfillment(of: [consumed], timeout: 5)
        XCTAssertEqual(dependencies!.auth.user?.id, "v14-owner-B")
        await observe([
            "disappeared:v14-owner-A:0", "dismantled:v14-owner-A:0",
            "appeared:v14-owner-B:0", "observed:v14-owner-B:0:available:tab1"
        ], signals)
        checkControls("owner replacement", signals)
        XCTAssertEqual(dependencies!.plaid.reserveBalance(authenticatedUserID: "v14-owner-B"), 250)

        // Existing service read-fault seam, not a validation control or scheduler.
        // A real retry increments the production query generation and reloads.
        signals.record("begin-real-query-failure-replacement")
        dependencies!.fault.set(true)
        XCTAssertFalse(dependencies!.plaid.retryPlanningSnapshot(authenticatedUserID: "v14-owner-B"))
        XCTAssertEqual(dependencies!.plaid.planningSnapshotAvailability(authenticatedUserID: "v14-owner-B"), .unavailable)
        await observe([
            "disappeared:v14-owner-B:0", "dismantled:v14-owner-B:0",
            "appeared:v14-owner-B:1", "observed:v14-owner-B:1:unavailable:tab1"
        ], signals)
        checkControls("failed query-generation replacement", signals)

        signals.record("begin-real-query-recovery-replacement")
        dependencies!.fault.set(false)
        XCTAssertTrue(dependencies!.plaid.retryPlanningSnapshot(authenticatedUserID: "v14-owner-B"))
        await observe([
            "disappeared:v14-owner-B:1", "dismantled:v14-owner-B:1",
            "appeared:v14-owner-B:2", "observed:v14-owner-B:2:available:tab1"
        ], signals)
        XCTAssertEqual(dependencies!.plaid.reserveBalance(authenticatedUserID: "v14-owner-B"), 250)
        checkControls("recovered query-generation replacement", signals)

        signals.record("detach-host-on-MainActor-task")
        XCTAssertNotNil(withUnsafeCurrentTask { $0 })
        window.isHidden = true
        window.rootViewController = nil
        host = nil
        // Services and persistence are still owned by dependencies, not delayed
        // by queue turns. Await actual disappearance/dismantling/destruction.
        await observe([
            "disappeared:v14-owner-B:2", "dismantled:v14-owner-B:2",
            "destroyed:v14-owner-A:0", "destroyed:v14-owner-B:0",
            "destroyed:v14-owner-B:1", "destroyed:v14-owner-B:2", "host-destroyed"
        ], signals)
        XCTAssertNil(weakHost)
        XCTAssertNotNil(weakContainer)
        XCTAssertNotNil(weakContext)
        XCTAssertNotNil(weakAuth)
        XCTAssertNotNil(weakPlaid)
        checkControls("host detachment", signals)
        try checkPersistedData(dependencies!.container)
        XCTAssertEqual(transport.observations.count, iteration)
        XCTAssertTrue(transport.observations.allSatisfy(\.matched))
        transport.assertSatisfied()
        XCTAssertEqual(UIValidationURLProtocol.unexpectedRequestCount, 0)

        signals.record("release-app-resources-on-MainActor-task")
        XCTAssertNotNil(withUnsafeCurrentTask { $0 })
        dependencies!.defaults.removePersistentDomain(forName: dependencies!.suite)
        dependencies = nil
        XCTAssertNil(weakPlaid)
        XCTAssertNil(weakAuth)
        XCTAssertNil(weakStore)
        XCTAssertNil(weakSummary)
        XCTAssertNil(weakNavigation)
        XCTAssertNil(weakContext)
        XCTAssertNil(weakContainer)
        signals.record("iteration-completed")
    }

    private func observe(_ events: [String], _ signals: ProductionLifecycleSignals) async {
        await fulfillment(of: events.map { signals.expectation(for: $0) }, timeout: 10)
    }

    private func checkControls(_ phase: String, _ signals: ProductionLifecycleSignals) {
        XCTAssertEqual(PlanningValidationDriver.constructedInstanceCount, 0, phase)
        signals.record("zero-validation-controls:\(phase)")
        XCTAssertNotNil(_typeByName(String(reflecting: AuthManager.self)),
                        "Compiled app type lookup must resolve the current module")
        XCTAssertNil(_typeByName("Caldera_Money.DashboardAmbientBlobActivity"), phase)
        signals.record("no-dashboard-ambient-activity:\(phase)")
    }

    private func makeRoot(dependencies: AppDependencies, signals: ProductionLifecycleSignals) -> AnyView {
        AnyView(OrdinaryProductionRoot(signals: signals)
            .environmentObject(dependencies.auth)
            .environmentObject(dependencies.plaid)
            .environmentObject(dependencies.summary)
            .environmentObject(dependencies.navigation)
            .modelContainer(dependencies.container)
            .defaultAppStorage(dependencies.defaults))
    }

    private func makeDependencies() throws -> AppDependencies {
        let schema = Schema([
            PlannerEvent.self, EventAllocation.self, ExpenseOccurrenceStatus.self,
            TransactionMatchedExpenseResolution.self, SavingsGoalRecord.self, ReserveSettings.self,
            DebtPayoffBucket.self, PaymentPlanCycle.self, AvailableToSpendAccountPreference.self,
            IncomeSchedule.self, PlanningOwnershipMigrationState.self
        ])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = container.mainContext
        context.insert(ReserveSettings(ownerScopeID: PlanningOwnerScope.authenticated("v14-owner-A"), balance: 125))
        context.insert(ReserveSettings(ownerScopeID: PlanningOwnerScope.authenticated("v14-owner-B"), balance: 250))
        try context.save()
        let suite = "V14OrdinaryProduction.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SentinelAuthSessionStore()
        let auth = AuthManager(
            urlSession: transport.session, pendingDeletionDefaults: defaults, localStoreKind: .development,
            restoreSavedSession: false, initialSessionToken: "v14-sentinel-A",
            initialUser: AuthUserSummary(id: "v14-owner-A", email: nil, fullName: nil),
            sessionStore: store, localDevelopmentSignInAllowed: { false }
        )
        let fault = ProductionReadFault()
        let plaid = PlaidService(
            sessionTokenProvider: { auth.backendSessionToken }, authenticatedUserIDProvider: { auth.user?.id },
            urlSession: transport.session, bankCacheDefaults: defaults, localStoreKind: .development,
            shouldFailPersistenceRead: { fault.fails($0) }
        )
        plaid.configurePersistence(modelContext: context)
        plaid.handlePlanningOwnerScopeChanged(authenticatedUserID: auth.user?.id)
        XCTAssertEqual(plaid.planningSnapshotAvailability(authenticatedUserID: auth.user?.id), .available)
        let summary = SummaryViewModel(
            accountsPublisher: plaid.$financialSummaryAccounts.eraseToAnyPublisher(),
            goalsPublisher: plaid.$savingsGoals.eraseToAnyPublisher(),
            reservePublisher: plaid.$reserveBalance.eraseToAnyPublisher()
        )
        let navigation = AppNavigation()
        navigation.openSavings()
        return AppDependencies(container: container, context: context, auth: auth, sessionStore: store,
                               plaid: plaid, summary: summary, navigation: navigation,
                               defaults: defaults, suite: suite, fault: fault)
    }

    private func checkPersistedData(_ container: ModelContainer) throws {
        let freshContext = ModelContext(container)
        let reserves = try freshContext.fetch(FetchDescriptor<ReserveSettings>())
        XCTAssertEqual(reserves.count, 2)
        XCTAssertEqual(reserves.first { $0.ownerScopeID == PlanningOwnerScope.authenticated("v14-owner-A") }?.balance, 125)
        XCTAssertEqual(reserves.first { $0.ownerScopeID == PlanningOwnerScope.authenticated("v14-owner-B") }?.balance, 250)
        XCTAssertTrue(try freshContext.fetch(FetchDescriptor<DebtPayoffBucket>()).isEmpty)
        XCTAssertTrue(try freshContext.fetch(FetchDescriptor<PaymentPlanCycle>()).isEmpty)
    }
}
