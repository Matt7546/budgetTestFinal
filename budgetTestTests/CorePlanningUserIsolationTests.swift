import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
private final class BankSessionTestHarness {
    var userID: String?
    var sessionToken: String?
    var authManager: AuthManager?
    private(set) var expiryCallbackCount = 0

    init(
        userID: String?,
        sessionToken: String?,
        authManager: AuthManager? = nil
    ) {
        self.userID = userID
        self.sessionToken = sessionToken
        self.authManager = authManager
    }

    func handleAuthoritativeSessionExpiration(
        _ scope: BankDataRequestScope
    ) {
        expiryCallbackCount += 1
        authManager?.invalidateSessionIfCurrent(scope)
    }
}

@MainActor
private final class ProductionPlanningActionBarrier {
    private var actions: [() -> Bool] = []

    func enqueue(_ action: @escaping () -> Bool) {
        actions.append(action)
    }

    func releaseNext() -> Bool {
        guard !actions.isEmpty else {
            XCTFail("Expected a captured production planning action.")
            return false
        }

        return actions.removeFirst()()
    }
}

private enum PaymentPlanTestPersistenceError: Error {
    case injected
}

@MainActor
final class CorePlanningUserIsolationTests: XCTestCase {

    private let userAID = "isolation-user-a"
    private let userBID = "isolation-user-b"

    private var userAScope: String {
        PlanningOwnerScope.authenticated(userAID)!
    }

    private var userBScope: String {
        PlanningOwnerScope.authenticated(userBID)!
    }

    func testDebugAndLabStoresAreSeparatedFromReleaseCandidate() {
        let directory = URL(fileURLWithPath: "/tmp/caldera-store-policy")
        let debugURL = CalderaSwiftDataStore.url(
            applicationSupportDirectory: directory,
            kind: .development
        )
        let labURL = CalderaSwiftDataStore.url(
            applicationSupportDirectory: directory,
            kind: .lab
        )
        let releaseURL = CalderaSwiftDataStore.url(
            applicationSupportDirectory: directory,
            kind: .production
        )

        XCTAssertNotEqual(debugURL, releaseURL)
        XCTAssertNotEqual(labURL, releaseURL)
        XCTAssertNotEqual(debugURL, labURL)
        XCTAssertEqual(releaseURL.lastPathComponent, "default.store")
        XCTAssertEqual(
            CalderaSwiftDataStore.kind(
                isDebugBuild: false,
                isLabEnabled: true
            ),
            .production
        )
    }

    func testReleaseCandidateCannotSeeDevelopmentFixture() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema([PlannerEvent.self])
        let developmentContainer = try container(
            schema: schema,
            url: CalderaSwiftDataStore.url(
                applicationSupportDirectory: directory,
                kind: .development
            )
        )
        let developmentContext = ModelContext(developmentContainer)
        developmentContext.insert(
            PlannerEvent(
                ownerScopeID: userAScope,
                name: "Debug QA fixture",
                amount: 9_999,
                date: Date(),
                type: .expense
            )
        )
        try developmentContext.save()

        let releaseContainer = try container(
            schema: schema,
            url: CalderaSwiftDataStore.url(
                applicationSupportDirectory: directory,
                kind: .production
            )
        )
        let releaseContext = ModelContext(releaseContainer)

        XCTAssertTrue(
            try releaseContext.fetch(
                FetchDescriptor<PlannerEvent>()
            ).isEmpty
        )
    }

    func testEveryCorePlanningModelIsHiddenFromAnotherOwner() {
        let graph = planningGraph(ownerScopeID: userAScope)

        XCTAssertEqual([graph.event].owned(by: userAScope).count, 1)
        XCTAssertTrue([graph.event].owned(by: userBScope).isEmpty)
        XCTAssertEqual([graph.allocation].owned(by: userAScope).count, 1)
        XCTAssertTrue([graph.allocation].owned(by: userBScope).isEmpty)
        XCTAssertEqual([graph.status].owned(by: userAScope).count, 1)
        XCTAssertTrue([graph.status].owned(by: userBScope).isEmpty)
        XCTAssertEqual([graph.paymentPlan].owned(by: userAScope).count, 1)
        XCTAssertTrue([graph.paymentPlan].owned(by: userBScope).isEmpty)
        XCTAssertEqual([graph.cycle].owned(by: userAScope).count, 1)
        XCTAssertTrue([graph.cycle].owned(by: userBScope).isEmpty)
        XCTAssertEqual([graph.goal].owned(by: userAScope).count, 1)
        XCTAssertTrue([graph.goal].owned(by: userBScope).isEmpty)
        XCTAssertEqual([graph.reserve].owned(by: userAScope).count, 1)
        XCTAssertTrue([graph.reserve].owned(by: userBScope).isEmpty)
    }

    func testAutomatedChildCreationInheritsAuthoritativeParentOwner() throws {
        let container = try planningContainer()
        let context = ModelContext(container)
        let event = PlannerEvent(
            ownerScopeID: userAScope,
            name: "Owned bill",
            amount: 500,
            date: Date(timeIntervalSince1970: 1_800_000_000),
            type: .expense
        )
        let forecast = ForecastEvent(
            event: event,
            occurrenceDate: event.date
        )
        context.insert(event)

        XCTAssertTrue(
            UpcomingExpenseActionPersistenceCoordinator.addSetAside(
                100,
                to: forecast,
                existingAllocation: nil,
                insertAllocation: context.insert,
                persistChanges: context.save,
                rollback: context.rollback
            ).didSave
        )
        _ = ExpenseOccurrenceResolutionMutation.apply(
            .paid,
            to: forecast,
            existingStatus: nil,
            in: context
        )
        let plan = DebtPayoffBucket(
            ownerScopeID: userAScope,
            plaidAccountID: "",
            accountName: "Owned loan",
            dueDate: event.date,
            paymentTargetAmount: 200,
            debtKind: .other
        )
        let cycle = try XCTUnwrap(
            PaymentPlanCycleStore.makeActiveCycle(
                for: plan,
                dueDate: plan.dueDate,
                targetAmount: plan.paymentTargetAmount,
                existingCycles: []
            )
        )

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<EventAllocation>())
                .first?.ownerScopeID,
            userAScope
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ExpenseOccurrenceStatus>())
                .first?.ownerScopeID,
            userAScope
        )
        XCTAssertEqual(cycle.ownerScopeID, userAScope)
    }

    func testSilentAuthLossAndUserSwitchNeverExposePriorOwner() {
        let userA = planningGraph(ownerScopeID: userAScope)
        let userB = planningGraph(
            ownerScopeID: userBScope,
            name: "User B bill",
            allocationAmount: 40,
            paymentPlanProtectedAmount: 25,
            goalAmount: 15,
            reserveAmount: 10
        )
        let events = [userA.event, userB.event]
        let allocations = [userA.allocation, userB.allocation]
        let statuses = [userA.status, userB.status]
        let plans = [userA.paymentPlan, userB.paymentPlan]
        let cycles = [userA.cycle, userB.cycle]
        let goals = [userA.goal, userB.goal]
        let reserves = [userA.reserve, userB.reserve]

        assertVisibleCounts(
            ownerScopeID: userAScope,
            events: events,
            allocations: allocations,
            statuses: statuses,
            plans: plans,
            cycles: cycles,
            goals: goals,
            reserves: reserves,
            expectedEventName: "User A bill"
        )
        assertNoVisibleRecords(
            ownerScopeID: PlanningOwnerScope.local,
            events: events,
            allocations: allocations,
            statuses: statuses,
            plans: plans,
            cycles: cycles,
            goals: goals,
            reserves: reserves
        )
        assertVisibleCounts(
            ownerScopeID: userBScope,
            events: events,
            allocations: allocations,
            statuses: statuses,
            plans: plans,
            cycles: cycles,
            goals: goals,
            reserves: reserves,
            expectedEventName: "User B bill"
        )
        assertVisibleCounts(
            ownerScopeID: userAScope,
            events: events,
            allocations: allocations,
            statuses: statuses,
            plans: plans,
            cycles: cycles,
            goals: goals,
            reserves: reserves,
            expectedEventName: "User A bill"
        )
    }

    func testUserBAvailableToSpendIgnoresEveryUserAPlanningInput() {
        let userA = planningGraph(
            ownerScopeID: userAScope,
            allocationAmount: 300,
            paymentPlanProtectedAmount: 200,
            goalAmount: 150,
            reserveAmount: 100
        )
        let userB = planningGraph(
            ownerScopeID: userBScope,
            name: "User B bill",
            allocationAmount: 50,
            paymentPlanProtectedAmount: 40,
            goalAmount: 20,
            reserveAmount: 30
        )
        let summary = financialSummary(
            ownerScopeID: userBScope,
            graphs: [userA, userB]
        )

        XCTAssertEqual(summary.upcomingExpensesSetAside, 50, accuracy: 0.001)
        XCTAssertEqual(summary.debtPaymentsSetAside, 40, accuracy: 0.001)
        XCTAssertEqual(summary.savingsGoalsSetAside, 20, accuracy: 0.001)
        XCTAssertEqual(summary.reserve, 30, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpend, 860, accuracy: 0.001)
    }

    func testSingleUserFinancialResultIsUnchangedAfterOwnershipAssignment() {
        let graph = planningGraph(
            ownerScopeID: nil,
            allocationAmount: 125,
            paymentPlanProtectedAmount: 75,
            goalAmount: 60,
            reserveAmount: 40
        )
        let before = financialSummary(
            events: [graph.event],
            allocations: [graph.allocation],
            statuses: [graph.status],
            plans: [graph.paymentPlan],
            goals: [graph.goal],
            reserves: [graph.reserve]
        )

        graph.event.ownerScopeID = userAScope
        graph.allocation.ownerScopeID = userAScope
        graph.status.ownerScopeID = userAScope
        graph.paymentPlan.ownerScopeID = userAScope
        graph.cycle.ownerScopeID = userAScope
        graph.goal.ownerScopeID = userAScope
        graph.reserve.ownerScopeID = userAScope

        let after = financialSummary(
            ownerScopeID: userAScope,
            graphs: [graph]
        )

        XCTAssertEqual(after, before)
        XCTAssertEqual(after.safeToSpend, 700, accuracy: 0.001)
    }

    func testScopeRecalculationCannotRetainPriorUsersTotals() {
        let userA = planningGraph(
            ownerScopeID: userAScope,
            allocationAmount: 400,
            paymentPlanProtectedAmount: 100,
            goalAmount: 100,
            reserveAmount: 100
        )
        let userB = planningGraph(
            ownerScopeID: userBScope,
            name: "User B bill",
            allocationAmount: 10,
            paymentPlanProtectedAmount: 20,
            goalAmount: 30,
            reserveAmount: 40
        )
        let graphs = [userA, userB]

        XCTAssertEqual(
            financialSummary(
                ownerScopeID: userAScope,
                graphs: graphs
            ).safeToSpend,
            300,
            accuracy: 0.001
        )
        XCTAssertEqual(
            financialSummary(
                ownerScopeID: userBScope,
                graphs: graphs
            ).safeToSpend,
            900,
            accuracy: 0.001
        )
        XCTAssertEqual(
            financialSummary(
                ownerScopeID: userAScope,
                graphs: graphs
            ).safeToSpend,
            300,
            accuracy: 0.001
        )
    }

    func testInMemoryGoalAndCushionSnapshotFailsClosedDuringOwnerSwitch() throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        context.insert(
            SavingsGoalRecord(
                ownerScopeID: userAScope,
                name: "A goal",
                targetAmount: 1_000,
                currentAmount: 400
            )
        )
        context.insert(
            SavingsGoalRecord(
                ownerScopeID: userBScope,
                name: "B goal",
                targetAmount: 500,
                currentAmount: 50
            )
        )
        context.insert(
            ReserveSettings(
                ownerScopeID: userAScope,
                balance: 300
            )
        )
        context.insert(
            ReserveSettings(
                ownerScopeID: userBScope,
                balance: 25
            )
        )
        try context.save()

        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID }
        )
        service.configurePersistence(modelContext: context)

        XCTAssertEqual(
            service.savingsGoals(
                authenticatedUserID: userAID
            ).map(\.name),
            ["A goal"]
        )
        XCTAssertEqual(
            service.reserveBalance(authenticatedUserID: userAID),
            300,
            accuracy: 0.001
        )
        XCTAssertTrue(
            service.savingsGoals(
                authenticatedUserID: userBID
            ).isEmpty
        )
        XCTAssertEqual(
            service.reserveBalance(authenticatedUserID: userBID),
            0,
            accuracy: 0.001
        )

        service.handlePlanningOwnerScopeChanged(
            authenticatedUserID: userBID
        )

        XCTAssertEqual(
            service.savingsGoals(
                authenticatedUserID: userBID
            ).map(\.name),
            ["B goal"]
        )
        XCTAssertEqual(
            service.reserveBalance(authenticatedUserID: userBID),
            25,
            accuracy: 0.001
        )
        XCTAssertTrue(
            service.savingsGoals(
                authenticatedUserID: userAID
            ).isEmpty
        )

        service.handlePlanningOwnerScopeChanged(
            authenticatedUserID: userAID
        )
        XCTAssertEqual(
            service.savingsGoals(
                authenticatedUserID: userAID
            ).map(\.name),
            ["A goal"]
        )
    }

    func testLegacyAdoptionIsExplicitCoherentAndSingleOwner() throws {
        let container = try planningContainer()
        let context = ModelContext(container)
        let graph = planningGraph(ownerScopeID: nil)
        let orphan = EventAllocation(
            ownerScopeID: nil,
            occurrenceID: "orphan",
            sourceEventID: UUID(),
            occurrenceDate: Date(),
            allocatedAmount: 25
        )
        insert(graph, into: context)
        context.insert(orphan)
        try context.save()

        XCTAssertTrue(
            LegacyPlanningDataAdoptionCoordinator
                .hasAdoptableLegacyData(in: context)
        )
        XCTAssertEqual(
            LegacyPlanningDataAdoptionCoordinator.adoptLegacyData(
                to: userAScope,
                in: context
            ),
            .adopted(recordCount: 7)
        )
        XCTAssertEqual(graph.event.ownerScopeID, userAScope)
        XCTAssertEqual(graph.allocation.ownerScopeID, userAScope)
        XCTAssertEqual(graph.status.ownerScopeID, userAScope)
        XCTAssertEqual(graph.paymentPlan.ownerScopeID, userAScope)
        XCTAssertEqual(graph.cycle.ownerScopeID, userAScope)
        XCTAssertEqual(graph.goal.ownerScopeID, userAScope)
        XCTAssertEqual(graph.reserve.ownerScopeID, userAScope)
        XCTAssertNil(orphan.ownerScopeID)
        XCTAssertEqual(
            LegacyPlanningDataAdoptionCoordinator.adoptLegacyData(
                to: userBScope,
                in: context
            ),
            .alreadyHandled
        )
        XCTAssertFalse(
            LegacyPlanningDataAdoptionCoordinator
                .hasAdoptableLegacyData(in: context)
        )
    }

    func testLegacyAdoptionMarkerSurvivesReopenAndRetry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("LegacyAdoption.store")

        do {
            let container = try planningContainer(url: storeURL)
            let context = ModelContext(container)
            let graph = planningGraph(ownerScopeID: nil)
            insert(graph, into: context)
            try context.save()
            XCTAssertEqual(
                LegacyPlanningDataAdoptionCoordinator.adoptLegacyData(
                    to: userAScope,
                    in: context
                ),
                .adopted(recordCount: 7)
            )
        }

        let reopened = try planningContainer(url: storeURL)
        let reopenedContext = ModelContext(reopened)
        XCTAssertEqual(
            LegacyPlanningDataAdoptionCoordinator.adoptLegacyData(
                to: userBScope,
                in: reopenedContext
            ),
            .alreadyHandled
        )
        let events = try reopenedContext.fetch(
            FetchDescriptor<PlannerEvent>()
        )
        XCTAssertEqual(events.map(\.ownerScopeID), [userAScope])
        let marker = try XCTUnwrap(
            reopenedContext.fetch(
                FetchDescriptor<PlanningOwnershipMigrationState>()
            ).first
        )
        XCTAssertEqual(marker.adoptedOwnerScopeID, userAScope)
        XCTAssertNotNil(marker.completedAt)
    }

    func testServiceAdoptionReconcilesOwnerZeroWithLegacyNonzeroCushion() throws {
        let defaults = try isolatedDefaults()
        defaults.set(275.0, forKey: "reserve_balance")
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID },
            bankCacheDefaults: defaults
        )

        service.configurePersistence(modelContext: context)

        var reserves = try context.fetch(FetchDescriptor<ReserveSettings>())
        XCTAssertEqual(reserves.count, 2)
        XCTAssertEqual(
            reserves.first { $0.ownerScopeID == userAScope }?.balance,
            0
        )
        XCTAssertEqual(
            service.adoptLegacyPlanningDataForCurrentUser(),
            .adopted(recordCount: 1)
        )

        reserves = try context.fetch(FetchDescriptor<ReserveSettings>())
        XCTAssertEqual(reserves.count, 1)
        XCTAssertEqual(reserves[0].ownerScopeID, userAScope)
        XCTAssertEqual(reserves[0].balance, 275, accuracy: 0.001)
        XCTAssertEqual(
            service.reserveBalance(authenticatedUserID: userAID),
            275,
            accuracy: 0.001
        )

        let relaunched = PlaidService(
            authenticatedUserIDProvider: { self.userAID },
            bankCacheDefaults: defaults
        )
        relaunched.configurePersistence(modelContext: context)
        XCTAssertEqual(
            relaunched.reserveBalance(authenticatedUserID: userAID),
            275,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ReserveSettings>()).count,
            1
        )
    }

    func testAdoptionUsesLargerNonzeroCushionWithoutSumming() throws {
        let container = try planningContainer()
        let context = ModelContext(container)
        context.insert(
            ReserveSettings(ownerScopeID: userAScope, balance: 125)
        )
        context.insert(
            ReserveSettings(ownerScopeID: nil, balance: 300)
        )
        try context.save()

        XCTAssertEqual(
            LegacyPlanningDataAdoptionCoordinator.adoptLegacyData(
                to: userAScope,
                in: context
            ),
            .adopted(recordCount: 1)
        )

        let reserves = try context.fetch(FetchDescriptor<ReserveSettings>())
        XCTAssertEqual(reserves.count, 1)
        XCTAssertEqual(reserves[0].ownerScopeID, userAScope)
        XCTAssertEqual(reserves[0].balance, 300, accuracy: 0.001)
        XCTAssertNotEqual(reserves[0].balance, 425)
    }

    func testLegacyGoalMigrationSaveFailureFailsClosedAndRetries() throws {
        let defaults = try isolatedDefaults()
        let legacyGoal = SavingsGoal(
            name: "Legacy emergency fund",
            targetAmount: 2_000,
            currentAmount: 650
        )
        defaults.set(
            try JSONEncoder().encode([legacyGoal]),
            forKey: "savings_goals"
        )
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        var shouldFailSave = true
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID },
            bankCacheDefaults: defaults,
            shouldFailPersistenceSave: { shouldFailSave }
        )

        service.configurePersistence(modelContext: context)

        XCTAssertTrue(service.savingsGoals.isEmpty)
        XCTAssertNil(service.loadedPlanningOwnerScopeID)
        XCTAssertTrue(
            service.savingsGoals(authenticatedUserID: userAID).isEmpty
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SavingsGoalRecord>()).isEmpty
        )

        shouldFailSave = false
        service.handlePlanningOwnerScopeChanged(
            authenticatedUserID: userAID
        )
        XCTAssertEqual(service.loadedPlanningOwnerScopeID, userAScope)
        XCTAssertTrue(service.savingsGoals.isEmpty)
        XCTAssertTrue(service.legacyPlanningDataRecoveryAvailable)

        XCTAssertEqual(
            service.adoptLegacyPlanningDataForCurrentUser(),
            .adopted(recordCount: 1)
        )
        XCTAssertEqual(
            service.savingsGoals(authenticatedUserID: userAID).map(\.name),
            ["Legacy emergency fund"]
        )
    }

    func testOwnerSwitchSaveFailurePublishesNoPriorOwnerSnapshotAndRetries() throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        context.insert(
            SavingsGoalRecord(
                ownerScopeID: userAScope,
                name: "A private goal",
                targetAmount: 1_000,
                currentAmount: 400
            )
        )
        context.insert(
            ReserveSettings(ownerScopeID: userAScope, balance: 90)
        )
        context.insert(
            SavingsGoalRecord(
                ownerScopeID: userBScope,
                name: "B goal",
                targetAmount: 500,
                currentAmount: 50
            )
        )
        try context.save()
        var shouldFailSave = false
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID },
            shouldFailPersistenceSave: { shouldFailSave }
        )
        service.configurePersistence(modelContext: context)
        XCTAssertEqual(service.savingsGoals.map(\.name), ["A private goal"])

        shouldFailSave = true
        service.handlePlanningOwnerScopeChanged(authenticatedUserID: userBID)

        XCTAssertTrue(service.savingsGoals.isEmpty)
        XCTAssertNil(service.loadedPlanningOwnerScopeID)
        XCTAssertFalse(service.savingsGoals.map(\.name).contains("A private goal"))
        XCTAssertEqual(
            service.reserveBalance(authenticatedUserID: userBID),
            0,
            accuracy: 0.001
        )

        shouldFailSave = false
        service.handlePlanningOwnerScopeChanged(authenticatedUserID: userBID)
        XCTAssertEqual(service.loadedPlanningOwnerScopeID, userBScope)
        XCTAssertEqual(service.savingsGoals.map(\.name), ["B goal"])
        XCTAssertFalse(service.savingsGoals.map(\.name).contains("A private goal"))
    }

    func testUnavailablePlanningSnapshotBlocksFalseZeroMutationUntilRetry() throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        context.insert(
            SavingsGoalRecord(
                ownerScopeID: userAScope,
                name: "A private goal",
                targetAmount: 1_000,
                currentAmount: 400
            )
        )
        context.insert(
            SavingsGoalRecord(
                ownerScopeID: userBScope,
                name: "B emergency fund",
                targetAmount: 2_000,
                currentAmount: 750
            )
        )
        context.insert(
            ReserveSettings(
                ownerScopeID: userBScope,
                balance: 500
            )
        )
        try context.save()

        var shouldFailRead = true
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userBID },
            shouldFailPersistenceRead: { domain in
                shouldFailRead && domain == .reserveSettings
            }
        )

        service.configurePersistence(modelContext: context)

        XCTAssertEqual(
            service.planningSnapshotAvailability(
                authenticatedUserID: userBID
            ),
            .unavailable
        )
        XCTAssertNil(service.loadedPlanningOwnerScopeID)
        XCTAssertTrue(
            service.savingsGoals(
                authenticatedUserID: userBID
            ).isEmpty
        )
        XCTAssertFalse(
            service.savingsGoals.map(\.name).contains("A private goal")
        )
        XCTAssertEqual(
            DashboardAvailableToSpendPresentation.make(
                canShowBankData: true,
                planningSnapshotAvailability: .unavailable,
                safeToSpend: 1_000
            ),
            .planningUnavailable(isLoading: false)
        )

        XCTAssertFalse(service.addToReserve(100))
        XCTAssertFalse(
            service.addGoal(
                SavingsGoal(
                    name: "Must not be inserted",
                    targetAmount: 100,
                    currentAmount: 0
                )
            )
        )
        let persistedBeforeRetry = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ReserveSettings>())
                .first { $0.ownerScopeID == userBScope }
        )
        XCTAssertEqual(persistedBeforeRetry.balance, 500, accuracy: 0.001)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SavingsGoalRecord>())
                .filter { $0.ownerScopeID == userBScope }
                .map(\.name),
            ["B emergency fund"]
        )

        shouldFailRead = false
        XCTAssertTrue(
            service.retryPlanningSnapshot(
                authenticatedUserID: userBID
            )
        )
        XCTAssertEqual(
            service.planningSnapshotAvailability(
                authenticatedUserID: userBID
            ),
            .available
        )
        XCTAssertEqual(
            service.reserveBalance(authenticatedUserID: userBID),
            500,
            accuracy: 0.001
        )
        XCTAssertEqual(
            service.savingsGoals(authenticatedUserID: userBID).map(\.name),
            ["B emergency fund"]
        )

        XCTAssertTrue(service.addToReserve(100))
        XCTAssertEqual(
            service.reserveBalance(authenticatedUserID: userBID),
            600,
            accuracy: 0.001
        )
        let persistedAfterMutation = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ReserveSettings>())
                .first { $0.ownerScopeID == userBScope }
        )
        XCTAssertEqual(persistedAfterMutation.balance, 600, accuracy: 0.001)
    }

    func testAdoptionReadFailureDoesNotWriteCompletionMarker() throws {
        let container = try planningContainer()
        let context = ModelContext(container)
        let graph = planningGraph(ownerScopeID: nil)
        insert(graph, into: context)
        try context.save()

        XCTAssertEqual(
            LegacyPlanningDataAdoptionCoordinator.adoptLegacyData(
                to: userAScope,
                in: context,
                shouldFailRead: { $0 == .eventAllocations }
            ),
            .failed
        )
        XCTAssertNil(graph.event.ownerScopeID)
        XCTAssertTrue(
            try context.fetch(
                FetchDescriptor<PlanningOwnershipMigrationState>()
            ).isEmpty
        )

        XCTAssertEqual(
            LegacyPlanningDataAdoptionCoordinator.adoptLegacyData(
                to: userAScope,
                in: context
            ),
            .adopted(recordCount: 7)
        )
        XCTAssertEqual(graph.event.ownerScopeID, userAScope)
    }

    func testDeletionReadFailureKeepsExactJobPendingUntilRetry() throws {
        let defaults = try isolatedDefaults()
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let userA = planningGraph(ownerScopeID: userAScope)
        let userB = planningGraph(
            ownerScopeID: userBScope,
            name: "User B bill"
        )
        insert(userA, into: context)
        insert(userB, into: context)
        try context.save()
        let pendingStore = PendingLocalAccountDeletionStore(defaults: defaults)
        let intent = try XCTUnwrap(
            pendingStore.beginDeletionIntent(
                userID: userAID,
                sessionToken: "session-a",
                storeKind: .production
            )
        )
        XCTAssertNotNil(
            pendingStore.markServerDeletionConfirmed(matching: intent)
        )
        var shouldFailRead = true
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userBID },
            bankCacheDefaults: defaults,
            shouldFailPersistenceRead: {
                shouldFailRead && $0 == .eventAllocations
            }
        )

        service.configurePersistence(modelContext: context)

        assertPreserved(ownerScopeID: userAScope, in: context)
        assertPreserved(ownerScopeID: userBScope, in: context)
        XCTAssertEqual(pendingStore.readPendingDeletions().jobs?.count, 1)

        shouldFailRead = false
        service.resumePendingDeletedUserCleanup()

        assertDeleted(ownerScopeID: userAScope, in: context)
        assertPreserved(ownerScopeID: userBScope, in: context)
        XCTAssertTrue(pendingStore.readPendingDeletions().jobs?.isEmpty == true)
    }

    func testDeletionSaveFailureKeepsConfirmedJobForNextLaunchCleanup() throws {
        let defaults = try isolatedDefaults()
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let userA = planningGraph(ownerScopeID: userAScope)
        let userB = planningGraph(
            ownerScopeID: userBScope,
            name: "User B bill"
        )
        insert(userA, into: context)
        insert(userB, into: context)
        try context.save()

        let pendingStore = PendingLocalAccountDeletionStore(defaults: defaults)
        let intent = try XCTUnwrap(
            pendingStore.beginDeletionIntent(
                userID: userAID,
                sessionToken: "session-a",
                storeKind: .production
            )
        )
        let confirmed = try XCTUnwrap(
            pendingStore.markServerDeletionConfirmed(matching: intent)
        )
        var shouldFailSave = true
        let firstLaunch = PlaidService(
            authenticatedUserIDProvider: { self.userBID },
            bankCacheDefaults: defaults,
            pendingDeletionStore: pendingStore,
            shouldFailPersistenceSave: { shouldFailSave }
        )

        firstLaunch.configurePersistence(modelContext: context)

        assertPreserved(ownerScopeID: userAScope, in: context)
        assertPreserved(ownerScopeID: userBScope, in: context)
        XCTAssertEqual(
            pendingStore.readPendingDeletions().jobs,
            [confirmed]
        )

        shouldFailSave = false
        let nextLaunch = PlaidService(
            authenticatedUserIDProvider: { self.userBID },
            bankCacheDefaults: defaults,
            pendingDeletionStore: pendingStore
        )
        nextLaunch.configurePersistence(modelContext: context)

        assertDeleted(ownerScopeID: userAScope, in: context)
        assertPreserved(ownerScopeID: userBScope, in: context)
        XCTAssertTrue(
            pendingStore.readPendingDeletions().jobs?.isEmpty == true
        )
    }

    func testPendingDeletionStoreKeepsMultipleOwnersAndAcknowledgesExactJob() throws {
        let defaults = try isolatedDefaults()
        let store = PendingLocalAccountDeletionStore(defaults: defaults)
        let userAJob = try XCTUnwrap(
            store.beginDeletionIntent(
                userID: userAID,
                sessionToken: "session-a",
                storeKind: .production
            )
        )
        let userBJob = try XCTUnwrap(
            store.beginDeletionIntent(
                userID: userBID,
                sessionToken: "session-b",
                storeKind: .production
            )
        )

        let relaunchedStore = PendingLocalAccountDeletionStore(
            defaults: defaults
        )
        XCTAssertEqual(relaunchedStore.readPendingDeletions().jobs?.count, 2)
        XCTAssertNotNil(
            relaunchedStore.markServerDeletionConfirmed(matching: userAJob)
        )
        XCTAssertTrue(relaunchedStore.remove(matching: userAJob))
        XCTAssertEqual(relaunchedStore.readPendingDeletions().jobs, [userBJob])
    }

    func testPendingDeletionRunsOnlyInOriginatingStore() throws {
        let defaults = try isolatedDefaults()
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let userA = planningGraph(ownerScopeID: userAScope)
        let userB = planningGraph(
            ownerScopeID: userBScope,
            name: "User B bill"
        )
        insert(userA, into: context)
        insert(userB, into: context)
        try context.save()
        let store = PendingLocalAccountDeletionStore(defaults: defaults)
        let job = try XCTUnwrap(
            store.beginDeletionIntent(
                userID: userAID,
                sessionToken: "session-a",
                storeKind: .production
            )
        )
        XCTAssertNotNil(store.markServerDeletionConfirmed(matching: job))

        let developmentService = PlaidService(
            authenticatedUserIDProvider: { self.userBID },
            bankCacheDefaults: defaults,
            localStoreKind: .development
        )
        developmentService.configurePersistence(modelContext: context)

        assertPreserved(ownerScopeID: userAScope, in: context)
        XCTAssertEqual(store.readPendingDeletions().jobs?.count, 1)

        let productionService = PlaidService(
            authenticatedUserIDProvider: { self.userBID },
            bankCacheDefaults: defaults,
            localStoreKind: .production
        )
        productionService.configurePersistence(modelContext: context)

        assertDeleted(ownerScopeID: userAScope, in: context)
        assertPreserved(ownerScopeID: userBScope, in: context)
        XCTAssertTrue(store.readPendingDeletions().jobs?.isEmpty == true)
    }

    func testCurrentBackendSessionExpiryInvalidatesAuthAndPlanningScope() async throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        context.insert(
            SavingsGoalRecord(
                ownerScopeID: userAScope,
                name: "A private goal",
                targetAmount: 1_000,
                currentAmount: 400
            )
        )
        context.insert(
            ReserveSettings(ownerScopeID: userAScope, balance: 200)
        )
        context.insert(
            SavingsGoalRecord(
                ownerScopeID: userBScope,
                name: "B goal",
                targetAmount: 500,
                currentAmount: 50
            )
        )
        context.insert(
            ReserveSettings(ownerScopeID: userBScope, balance: 25)
        )
        try context.save()
        let authDefaults = try isolatedDefaults()
        let authA = AuthManager(
            pendingDeletionDefaults: authDefaults,
            restoreSavedSession: false,
            initialSessionToken: "session-a",
            initialUser: AuthUserSummary(
                id: userAID,
                email: nil,
                fullName: nil
            )
        )
        let session = BankSessionTestHarness(
            userID: userAID,
            sessionToken: "session-a",
            authManager: authA
        )
        let service = PlaidService(
            sessionTokenProvider: { session.sessionToken },
            authenticatedUserIDProvider: { session.userID },
            authoritativeSessionExpirationHandler: { scope in
                session.handleAuthoritativeSessionExpiration(scope)
                session.userID = session.authManager?.user?.id
                session.sessionToken = session.authManager?.backendSessionToken
            }
        )
        service.configurePersistence(modelContext: context)
        XCTAssertEqual(service.savingsGoals.map(\.name), ["A private goal"])
        let requestScope = service.beginBankSyncRefreshRequest()

        service.handleAccountsResponse(
            requestScope: requestScope,
            data: Data(#"{"error":"unauthorized"}"#.utf8),
            response: httpResponse(statusCode: 401),
            error: nil,
            reason: .manualSettingsTap,
            completion: { _ in }
        )

        XCTAssertFalse(authA.isSignedIn)
        XCTAssertNil(authA.user)
        XCTAssertTrue(service.savingsGoals.isEmpty)
        XCTAssertTrue(
            service.savingsGoals(authenticatedUserID: userAID).isEmpty
        )

        let authB = AuthManager(
            pendingDeletionDefaults: authDefaults,
            restoreSavedSession: false,
            initialSessionToken: "session-b",
            initialUser: AuthUserSummary(
                id: userBID,
                email: nil,
                fullName: nil
            )
        )
        session.authManager = authB
        session.userID = authB.user?.id
        session.sessionToken = authB.backendSessionToken
        service.handlePlanningOwnerScopeChanged(
            authenticatedUserID: authB.user?.id
        )
        XCTAssertEqual(service.savingsGoals.map(\.name), ["B goal"])
        XCTAssertFalse(service.savingsGoals.map(\.name).contains("A private goal"))
    }

    func testStaleBackendSessionExpiryCannotInvalidateNewerUser() async throws {
        let authDefaults = try isolatedDefaults()
        let authB = AuthManager(
            pendingDeletionDefaults: authDefaults,
            restoreSavedSession: false,
            initialSessionToken: "session-b",
            initialUser: AuthUserSummary(
                id: userBID,
                email: nil,
                fullName: nil
            )
        )
        let session = BankSessionTestHarness(
            userID: userAID,
            sessionToken: "session-a",
            authManager: authB
        )
        let service = PlaidService(
            sessionTokenProvider: { session.sessionToken },
            authenticatedUserIDProvider: { session.userID },
            authoritativeSessionExpirationHandler: { scope in
                session.handleAuthoritativeSessionExpiration(scope)
            }
        )
        let staleRequest = service.beginBankSyncRefreshRequest()

        session.userID = userBID
        session.sessionToken = "session-b"
        service.handleAccountsResponse(
            requestScope: staleRequest,
            data: Data(#"{"error":"unauthorized"}"#.utf8),
            response: httpResponse(statusCode: 401),
            error: nil,
            reason: .manualSettingsTap,
            completion: { _ in }
        )

        XCTAssertEqual(session.expiryCallbackCount, 0)
        XCTAssertTrue(authB.isSignedIn)
        XCTAssertEqual(authB.user?.id, userBID)
    }

    func testPendingAccountDeletionResumesAndDeletesOnlyExactOwner() throws {
        let suiteName = "CorePlanningUserIsolationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let userA = planningGraph(ownerScopeID: userAScope)
        let userB = planningGraph(
            ownerScopeID: userBScope,
            name: "User B bill"
        )
        insert(userA, into: context)
        insert(userB, into: context)
        context.insert(incomeSchedule(ownerScopeID: userAScope))
        context.insert(incomeSchedule(ownerScopeID: userBScope))
        context.insert(transactionResolution(userID: userAID))
        context.insert(transactionResolution(userID: userBID))
        context.insert(
            AvailableToSpendAccountPreference(
                userID: userAID,
                plaidAccountID: "checking-a",
                isIncluded: true
            )
        )
        context.insert(
            AvailableToSpendAccountPreference(
                userID: userBID,
                plaidAccountID: "checking-b",
                isIncluded: true
            )
        )
        try context.save()

        let personalization = AppPersonalizationStore(defaults: defaults)
        personalization.set(
            "Alice",
            for: AppPersonalizationKeys.preferredName,
            ownerScopeID: userAScope
        )
        personalization.set(
            "Bob",
            for: AppPersonalizationKeys.preferredName,
            ownerScopeID: userBScope
        )
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: [checkingAccount(id: "checking-b")],
                lastSuccessfulRefresh: Date(),
                ownerUserID: userBID,
                defaults: defaults
            )
        )
        let pendingStore = PendingLocalAccountDeletionStore(
            defaults: defaults
        )
        let intent = try XCTUnwrap(
            pendingStore.beginDeletionIntent(
                userID: userAID,
                sessionToken: "session-a",
                storeKind: .production
            )
        )
        XCTAssertNotNil(
            pendingStore.markServerDeletionConfirmed(matching: intent)
        )

        let service = PlaidService(
            sessionTokenProvider: { "session-b" },
            authenticatedUserIDProvider: { self.userBID },
            bankCacheDefaults: defaults
        )
        service.configurePersistence(modelContext: context)

        assertDeleted(ownerScopeID: userAScope, in: context)
        assertPreserved(ownerScopeID: userBScope, in: context)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<IncomeSchedule>())
                .map(\.ownerScopeID),
            [userBScope]
        )
        XCTAssertEqual(
            try context.fetch(
                FetchDescriptor<TransactionMatchedExpenseResolution>()
            ).map(\.ownerScopeID),
            [
                TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                    authenticatedUserID: userBID
                )!
            ]
        )
        XCTAssertEqual(
            try context.fetch(
                FetchDescriptor<AvailableToSpendAccountPreference>()
            ).map(\.userID),
            [userBID]
        )
        XCTAssertTrue(pendingStore.readPendingDeletions().jobs?.isEmpty == true)
        XCTAssertEqual(
            personalization.string(
                for: AppPersonalizationKeys.preferredName,
                ownerScopeID: userAScope
            ),
            ""
        )
        XCTAssertEqual(
            personalization.string(
                for: AppPersonalizationKeys.preferredName,
                ownerScopeID: userBScope
            ),
            "Bob"
        )
        XCTAssertEqual(
            PlaidLocalCache.loadAccountSnapshot(
                for: userBID,
                defaults: defaults
            )?.accounts.map(\.account_id),
            ["checking-b"]
        )

        service.clearLocalFinancialDataForDeletedUser(userID: userAID)
        service.clearLocalFinancialDataForDeletedUser(userID: userAID)

        assertDeleted(ownerScopeID: userAScope, in: context)
        assertPreserved(ownerScopeID: userBScope, in: context)
        XCTAssertTrue(pendingStore.readPendingDeletions().jobs?.isEmpty == true)
    }

    func testUserSpecificPersonalizationIsScopedAndLegacyValuesAreQuarantined() throws {
        let suiteName = "PersonalizationScopeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            "Legacy name",
            forKey: AppPersonalizationKeys.preferredName
        )
        let store = AppPersonalizationStore(defaults: defaults)

        XCTAssertEqual(
            store.string(
                for: AppPersonalizationKeys.preferredName,
                ownerScopeID: userAScope
            ),
            ""
        )
        XCTAssertEqual(
            store.string(
                for: AppPersonalizationKeys.preferredName,
                ownerScopeID: PlanningOwnerScope.local
            ),
            "Legacy name"
        )
        XCTAssertNil(
            defaults.object(
                forKey: AppPersonalizationKeys.preferredName
            )
        )

        store.set(
            "Alice",
            for: AppPersonalizationKeys.preferredName,
            ownerScopeID: userAScope
        )
        store.set(
            "Bob",
            for: AppPersonalizationKeys.preferredName,
            ownerScopeID: userBScope
        )
        XCTAssertEqual(
            store.string(
                for: AppPersonalizationKeys.preferredName,
                ownerScopeID: userAScope
            ),
            "Alice"
        )
        XCTAssertEqual(
            store.string(
                for: AppPersonalizationKeys.preferredName,
                ownerScopeID: userBScope
            ),
            "Bob"
        )
    }

    func testPlanningReadinessFailsClosedForEveryRequiredInput() {
        XCTAssertEqual(
            PlanningSnapshotAvailability.resolving(
                base: .available,
                failedRequiredReads: []
            ),
            .available
        )
        XCTAssertEqual(
            PlanningSnapshotAvailability.resolving(
                base: .loading,
                failedRequiredReads: [.eventAllocations]
            ),
            .unavailable
        )
        XCTAssertEqual(
            PlanningSnapshotAvailability.resolving(
                base: .unavailable,
                failedRequiredReads: []
            ),
            .unavailable
        )

        for domain in PlanningPersistenceReadDomain.allCases {
            let availability = PlanningSnapshotAvailability.resolving(
                base: .available,
                failedRequiredReads: [domain]
            )
            XCTAssertEqual(availability, .unavailable, "Failed domain: \(domain)")
            XCTAssertFalse(
                PlanningMutationAuthorization.isAllowed(
                    recordOwnerScopeID: userAScope,
                    currentOwnerScopeID: userAScope,
                    availability: availability
                ),
                "Mutation remained enabled for failed domain: \(domain)"
            )
        }
    }

    func testAccountPreferenceReadFailureDoesNotReincludeExcludedAccountAndRetryIsExact() throws {
        let defaults = try isolatedDefaults()
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        context.insert(ReserveSettings(ownerScopeID: userBScope, balance: 0))
        context.insert(
            AvailableToSpendAccountPreference(
                userID: userBID,
                plaidAccountID: "checking-b",
                isIncluded: false
            )
        )
        try context.save()
        var shouldFailPreferenceRead = true
        let service = PlaidService(
            sessionTokenProvider: { "session-b" },
            authenticatedUserIDProvider: { self.userBID },
            bankCacheDefaults: defaults,
            shouldFailPersistenceRead: { domain in
                shouldFailPreferenceRead &&
                    domain == .availableToSpendPreferences
            }
        )
        applyAccount(
            id: "checking-b",
            to: service
        )

        service.configurePersistence(modelContext: context)

        XCTAssertEqual(
            service.planningSnapshotAvailability(
                authenticatedUserID: userBID
            ),
            .unavailable
        )
        applyAccount(
            id: "checking-b",
            to: service
        )
        XCTAssertTrue(service.financialSummaryAccounts.isEmpty)
        XCTAssertEqual(
            service.availableToSpendAccountInclusionState(
                checkingAccount(id: "checking-b")
            ),
            .unavailable
        )
        XCTAssertFalse(service.canManageAvailableToSpendAccountScope)
        XCTAssertEqual(
            AvailableToSpendAccountControlPresentation.make(
                state: service.availableToSpendAccountInclusionState(
                    checkingAccount(id: "checking-b")
                )
            ),
            AvailableToSpendAccountControlPresentation(
                title: "Account setting unavailable",
                message: "Your saved choice is unchanged. Try loading your plan again before updating this account.",
                showsProgress: false,
                allowsEditing: false
            )
        )
        XCTAssertFalse(
            service.setAccountIncludedInAvailableToSpend(
                accountID: "checking-b",
                isIncluded: true
            )
        )
        XCTAssertEqual(
            try context.fetch(
                FetchDescriptor<AvailableToSpendAccountPreference>()
            ).first?.isIncluded,
            false
        )

        shouldFailPreferenceRead = false
        XCTAssertTrue(
            service.retryPlanningSnapshot(
                authenticatedUserID: userBID
            )
        )
        XCTAssertEqual(
            service.planningSnapshotAvailability(
                authenticatedUserID: userBID
            ),
            .available
        )
        XCTAssertTrue(service.financialSummaryAccounts.isEmpty)
        XCTAssertFalse(
            service.isAccountIncludedInAvailableToSpend(
                checkingAccount(id: "checking-b")
            )
        )
        XCTAssertEqual(
            service.availableToSpendAccountInclusionState(
                checkingAccount(id: "checking-b")
            ),
            .excluded
        )
        XCTAssertTrue(service.canManageAvailableToSpendAccountScope)

        XCTAssertTrue(
            service.setAccountIncludedInAvailableToSpend(
                accountID: "checking-b",
                isIncluded: true
            )
        )
        XCTAssertEqual(
            service.financialSummaryAccounts.map(\.account_id),
            ["checking-b"]
        )
    }

    func testSuccessfulMissingAccountPreferenceKeepsDefaultInclusion() throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        context.insert(ReserveSettings(ownerScopeID: userAScope, balance: 0))
        try context.save()
        let service = PlaidService(
            sessionTokenProvider: { "session-a" },
            authenticatedUserIDProvider: { self.userAID }
        )
        applyAccount(id: "checking-a", to: service)

        service.configurePersistence(modelContext: context)

        XCTAssertEqual(
            service.planningSnapshotAvailability(
                authenticatedUserID: userAID
            ),
            .available
        )
        XCTAssertEqual(
            service.financialSummaryAccounts.map(\.account_id),
            ["checking-a"]
        )
    }

    func testDeferredMutationIsRejectedImmediatelyAfterOwnerIdentityChanges() throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let goalID = UUID()
        context.insert(
            SavingsGoalRecord(
                id: goalID,
                ownerScopeID: userAScope,
                name: "A private goal",
                targetAmount: 1_000,
                currentAmount: 200
            )
        )
        context.insert(ReserveSettings(ownerScopeID: userAScope, balance: 0))
        context.insert(ReserveSettings(ownerScopeID: userBScope, balance: 0))
        try context.save()
        var currentUserID = userAID
        let service = PlaidService(
            authenticatedUserIDProvider: { currentUserID }
        )
        service.configurePersistence(modelContext: context)

        currentUserID = userBID
        XCTAssertFalse(
            service.updateGoal(
                SavingsGoal(
                    id: goalID,
                    name: "Stale callback overwrite",
                    targetAmount: 1_000,
                    currentAmount: 1_000
                )
            )
        )

        let persistedGoal = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SavingsGoalRecord>())
                .first { $0.id == goalID }
        )
        XCTAssertEqual(persistedGoal.name, "A private goal")
        XCTAssertEqual(persistedGoal.currentAmount, 200, accuracy: 0.001)
    }

    func testProductionDeferredPaymentPlanActionRejectsOldReadinessGenerationOwnerAndQueryBridge() throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let bucket = DebtPayoffBucket(
            ownerScopeID: userAScope,
            plaidAccountID: "card-a",
            accountName: "Card A",
            dueDate: Date(timeIntervalSince1970: 1_788_739_200),
            paymentTargetAmount: 900,
            protectedAmount: 275,
            debtKind: .linkedCreditCard
        )
        let cycle = PaymentPlanCycle(
            ownerScopeID: userAScope,
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: 900
        )
        context.insert(bucket)
        context.insert(cycle)
        context.insert(ReserveSettings(ownerScopeID: userAScope, balance: 0))
        context.insert(ReserveSettings(ownerScopeID: userBScope, balance: 0))
        try context.save()
        var currentUserID = userAID
        var failReserveRead = false
        var failedCommandReadDomain: PlanningPersistenceReadDomain?
        let service = PlaidService(
            authenticatedUserIDProvider: { currentUserID },
            shouldFailPersistenceRead: { domain in
                (failReserveRead && domain == .reserveSettings) ||
                    failedCommandReadDomain == domain
            }
        )
        service.configurePersistence(modelContext: context)
        var mutationCount = 0
        let barrier = ProductionPlanningActionBarrier()

        func captureAction() throws -> () -> Bool {
            let token = try XCTUnwrap(
                service.paymentPlanMutationAuthorizationToken(
                    authenticatedUserID: currentUserID,
                    recordID: bucket.id,
                    cycleID: cycle.id
                )
            )
            return PaymentPlanEditorMutationActionFactory.make(
                service: service,
                token: token,
                authenticatedUserID: { currentUserID },
                record: bucket,
                cycle: { cycle },
                cycles: { [cycle] }
            ) {
                bucket.accountName = "Authorized mutation \(mutationCount + 1)"
                bucket.updatedAt = Date()
                try? context.save()
                mutationCount += 1
            }
        }

        for domain in [
            PlanningPersistenceReadDomain.plannerEvents,
            .eventAllocations,
            .occurrenceStatuses,
            .debtPayoffBuckets,
            .paymentPlanCycles,
            .reserveSettings
        ] {
            let action = try captureAction()
            failedCommandReadDomain = domain
            XCTAssertEqual(
                service.planningSnapshotAvailability(
                    authenticatedUserID: currentUserID
                ),
                .available
            )
            XCTAssertFalse(action(), "Failed command read: \(domain)")
            XCTAssertEqual(mutationCount, 0)
            XCTAssertEqual(
                service.planningSnapshotAvailability(
                    authenticatedUserID: currentUserID
                ),
                .unavailable
            )
            failedCommandReadDomain = nil
            XCTAssertTrue(
                service.retryPlanningSnapshot(
                    authenticatedUserID: currentUserID
                )
            )
            XCTAssertFalse(action(), "Old action revived after \(domain) recovery")
            XCTAssertEqual(mutationCount, 0)
        }

        let oldLoadAction = try captureAction()
        barrier.enqueue(oldLoadAction)
        failReserveRead = true
        XCTAssertFalse(
            service.retryPlanningSnapshot(
                authenticatedUserID: userAID
            )
        )
        XCTAssertFalse(barrier.releaseNext())
        failReserveRead = false
        XCTAssertTrue(
            service.retryPlanningSnapshot(
                authenticatedUserID: userAID
            )
        )
        XCTAssertFalse(oldLoadAction())

        barrier.enqueue(try captureAction())
        service.invalidatePlanningMutationAuthorization()
        XCTAssertFalse(barrier.releaseNext())

        barrier.enqueue(try captureAction())
        currentUserID = userBID
        XCTAssertFalse(barrier.releaseNext())

        currentUserID = userAID
        let queryInvalidatedAction = try captureAction()
        barrier.enqueue(queryInvalidatedAction)
        XCTAssertTrue(
            PlanningQueryAvailabilityMutationBridge
                .shouldDismissPlanningEditors(
                    availability: .unavailable,
                    invalidateMutationAuthorization:
                        service.invalidatePlanningMutationAuthorization
                )
        )
        XCTAssertFalse(barrier.releaseNext())
        XCTAssertFalse(queryInvalidatedAction())

        XCTAssertFalse(
            PlanningQueryAvailabilityMutationBridge
                .shouldDismissPlanningEditors(
                    availability: .available,
                    invalidateMutationAuthorization:
                        service.invalidatePlanningMutationAuthorization
                )
        )
        XCTAssertFalse(queryInvalidatedAction())

        barrier.enqueue(try captureAction())
        XCTAssertTrue(barrier.releaseNext())
        XCTAssertEqual(mutationCount, 1)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<DebtPayoffBucket>())
                .first { $0.id == bucket.id }?.accountName,
            "Authorized mutation 1"
        )

        let staleEditorCycle = PaymentPlanCycle(
            id: cycle.id,
            ownerScopeID: userAScope,
            paymentPlanID: bucket.id,
            dueDate: cycle.dueDate,
            frozenTargetAmount: 700
        )
        let currentToken = try XCTUnwrap(
            service.paymentPlanMutationAuthorizationToken(
                authenticatedUserID: currentUserID,
                recordID: bucket.id,
                cycleID: cycle.id
            )
        )
        let staleEditorAction = PaymentPlanEditorMutationActionFactory.make(
            service: service,
            token: currentToken,
            authenticatedUserID: { currentUserID },
            record: bucket,
            cycle: { staleEditorCycle },
            cycles: { [staleEditorCycle] }
        ) {
            mutationCount += 1
        }
        XCTAssertFalse(staleEditorAction())
        XCTAssertEqual(mutationCount, 1)
        let freshContext = ModelContext(container)
        XCTAssertEqual(
            try freshContext.fetch(FetchDescriptor<DebtPayoffBucket>())
                .first { $0.id == bucket.id }?.protectedAmount,
            275
        )
    }

    func testProductionDeferredPaymentPlanActionRejectsChangedCyclelessInputsWithoutTimestampChange() throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let bucket = DebtPayoffBucket(
            ownerScopeID: userAScope,
            plaidAccountID: "",
            accountName: "Auto loan",
            dueDate: Date(timeIntervalSince1970: 1_788_739_200),
            paymentTargetAmount: 0,
            protectedAmount: 275,
            debtKind: .autoLoan,
            monthlyPayment: 900,
            hasPaymentDueDate: true
        )
        context.insert(bucket)
        try context.save()
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID }
        )
        service.configurePersistence(modelContext: context)
        var mutationCount = 0

        func captureAction() throws -> () -> Bool {
            let token = try XCTUnwrap(
                service.paymentPlanMutationAuthorizationToken(
                    authenticatedUserID: userAID,
                    recordID: bucket.id,
                    cycleID: nil
                )
            )
            return PaymentPlanEditorMutationActionFactory.make(
                service: service,
                token: token,
                authenticatedUserID: { self.userAID },
                record: bucket,
                cycle: { nil },
                cycles: { [] }
            ) {
                mutationCount += 1
                bucket.protectedAmount = 900
                try? context.save()
            }
        }

        let capturedUpdatedAt = bucket.updatedAt
        let monthlyPaymentAction = try captureAction()
        bucket.monthlyPayment = 1_000
        XCTAssertFalse(monthlyPaymentAction())
        XCTAssertEqual(mutationCount, 0)
        XCTAssertEqual(bucket.updatedAt, capturedUpdatedAt)

        bucket.monthlyPayment = 900
        let debtKindAction = try captureAction()
        bucket.debtKind = .linkedCreditCard
        XCTAssertFalse(debtKindAction())
        XCTAssertEqual(mutationCount, 0)
        XCTAssertEqual(bucket.updatedAt, capturedUpdatedAt)

        bucket.debtKind = .autoLoan
        let dueDateVisibilityAction = try captureAction()
        bucket.shouldDisplayDueDate = false
        XCTAssertFalse(dueDateVisibilityAction())
        XCTAssertEqual(mutationCount, 0)
        XCTAssertEqual(bucket.updatedAt, capturedUpdatedAt)
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<DebtPayoffBucket>())
                .first { $0.id == bucket.id }?.protectedAmount,
            275
        )

        bucket.shouldDisplayDueDate = true
        XCTAssertTrue(try captureAction()())
        XCTAssertEqual(mutationCount, 1)
        XCTAssertEqual(
            try ModelContext(container).fetch(FetchDescriptor<DebtPayoffBucket>())
                .first { $0.id == bucket.id }?.protectedAmount,
            900
        )
    }

    func testProductionDeferredPaymentPlanActionRejectsReplacedRecordAndChangedCycle() throws {
        let recordContainer = try fullPersistenceContainer()
        let recordContext = ModelContext(recordContainer)
        let originalBucket = DebtPayoffBucket(
            id: UUID(),
            ownerScopeID: userAScope,
            plaidAccountID: "card-record",
            accountName: "Original",
            dueDate: Date(timeIntervalSince1970: 1_788_739_200),
            paymentTargetAmount: 600,
            protectedAmount: 125,
            debtKind: .linkedCreditCard
        )
        let originalCycle = PaymentPlanCycle(
            ownerScopeID: userAScope,
            paymentPlanID: originalBucket.id,
            dueDate: originalBucket.dueDate,
            frozenTargetAmount: 600
        )
        recordContext.insert(originalBucket)
        recordContext.insert(originalCycle)
        recordContext.insert(ReserveSettings(ownerScopeID: userAScope, balance: 0))
        try recordContext.save()
        let recordService = PlaidService(
            authenticatedUserIDProvider: { self.userAID }
        )
        recordService.configurePersistence(modelContext: recordContext)
        let recordToken = try XCTUnwrap(
            recordService.paymentPlanMutationAuthorizationToken(
                authenticatedUserID: userAID,
                recordID: originalBucket.id,
                cycleID: originalCycle.id
            )
        )
        let replacedRecordID = originalBucket.id
        let replacedRecordDueDate = originalBucket.dueDate
        var recordMutationCount = 0
        let replacedRecordAction = PaymentPlanEditorMutationActionFactory.make(
            service: recordService,
            token: recordToken,
            authenticatedUserID: { self.userAID },
            record: originalBucket,
            cycle: { originalCycle },
            cycles: { [originalCycle] }
        ) {
            recordMutationCount += 1
        }
        recordContext.delete(originalBucket)
        try recordContext.save()
        let replacementBucket = DebtPayoffBucket(
            id: replacedRecordID,
            ownerScopeID: userAScope,
            plaidAccountID: "card-record",
            accountName: "Replacement",
            dueDate: replacedRecordDueDate,
            paymentTargetAmount: 600,
            protectedAmount: 125,
            debtKind: .linkedCreditCard
        )
        recordContext.insert(replacementBucket)
        try recordContext.save()
        XCTAssertFalse(replacedRecordAction())
        XCTAssertEqual(recordMutationCount, 0)

        let replacementToken = try XCTUnwrap(
            recordService.paymentPlanMutationAuthorizationToken(
                authenticatedUserID: userAID,
                recordID: replacementBucket.id,
                cycleID: originalCycle.id
            )
        )
        let deletedRecordAction = PaymentPlanEditorMutationActionFactory.make(
            service: recordService,
            token: replacementToken,
            authenticatedUserID: { self.userAID },
            record: replacementBucket,
            cycle: { originalCycle },
            cycles: { [originalCycle] }
        ) {
            recordMutationCount += 1
        }
        recordContext.delete(replacementBucket)
        try recordContext.save()
        XCTAssertFalse(deletedRecordAction())
        XCTAssertEqual(recordMutationCount, 0)

        let cycleContainer = try fullPersistenceContainer()
        let cycleContext = ModelContext(cycleContainer)
        let cycleBucket = DebtPayoffBucket(
            ownerScopeID: userAScope,
            plaidAccountID: "card-cycle",
            accountName: "Cycle",
            dueDate: Date(timeIntervalSince1970: 1_788_739_200),
            paymentTargetAmount: 700,
            protectedAmount: 150,
            debtKind: .linkedCreditCard
        )
        let changedCycle = PaymentPlanCycle(
            ownerScopeID: userAScope,
            paymentPlanID: cycleBucket.id,
            dueDate: cycleBucket.dueDate,
            frozenTargetAmount: 700
        )
        cycleContext.insert(cycleBucket)
        cycleContext.insert(changedCycle)
        cycleContext.insert(ReserveSettings(ownerScopeID: userAScope, balance: 0))
        try cycleContext.save()
        let cycleService = PlaidService(
            authenticatedUserIDProvider: { self.userAID }
        )
        cycleService.configurePersistence(modelContext: cycleContext)
        let cycleToken = try XCTUnwrap(
            cycleService.paymentPlanMutationAuthorizationToken(
                authenticatedUserID: userAID,
                recordID: cycleBucket.id,
                cycleID: changedCycle.id
            )
        )
        var cycleMutationCount = 0
        let changedCycleAction = PaymentPlanEditorMutationActionFactory.make(
            service: cycleService,
            token: cycleToken,
            authenticatedUserID: { self.userAID },
            record: cycleBucket,
            cycle: { changedCycle },
            cycles: { [changedCycle] }
        ) {
            cycleMutationCount += 1
        }
        changedCycle.frozenTargetAmount = 750
        changedCycle.updatedAt = Date()
        try cycleContext.save()
        XCTAssertFalse(changedCycleAction())
        XCTAssertEqual(cycleMutationCount, 0)
    }

    func testCapturedHandledCycleUndoCannotOverwriteSupersedingCycleSave() throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let firstDueDate = Date(timeIntervalSince1970: 1_788_739_200)
        let secondDueDate = Date(timeIntervalSince1970: 1_791_417_600)
        let bucket = DebtPayoffBucket(
            ownerScopeID: userAScope,
            plaidAccountID: "card-a",
            accountName: "Card A",
            dueDate: firstDueDate,
            paymentTargetAmount: 900,
            protectedAmount: 275,
            debtKind: .linkedCreditCard
        )
        let firstCycle = PaymentPlanCycle(
            ownerScopeID: userAScope,
            paymentPlanID: bucket.id,
            dueDate: firstDueDate,
            frozenTargetAmount: 900
        )
        context.insert(bucket)
        context.insert(firstCycle)
        context.insert(ReserveSettings(ownerScopeID: userAScope, balance: 0))
        try context.save()

        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID }
        )
        service.configurePersistence(modelContext: context)
        let handleToken = try XCTUnwrap(
            service.paymentPlanMutationAuthorizationToken(
                authenticatedUserID: userAID,
                recordID: bucket.id,
                cycleID: firstCycle.id
            )
        )
        var handlingResult: PaymentPlanCycleHandlingResult?
        let handleAction = PaymentPlanEditorMutationActionFactory.make(
            service: service,
            token: handleToken,
            authenticatedUserID: { self.userAID },
            record: bucket,
            cycle: { firstCycle },
            cycles: { [firstCycle] }
        ) {
            handlingResult = PaymentPlanCycleHandlingCoordinator
                .handleCurrentPayment(
                    for: bucket,
                    cycles: [firstCycle],
                    handledAt: Date(timeIntervalSince1970: 1_788_825_600),
                    insertCycle: context.insert,
                    persistChanges: context.save,
                    rollback: context.rollback
                )
        }
        XCTAssertTrue(handleAction())
        guard case .handled(let handlingSuccess) = handlingResult else {
            return XCTFail("Expected the first cycle to be handled.")
        }

        let undoToken = try XCTUnwrap(
            service.paymentPlanMutationAuthorizationToken(
                authenticatedUserID: userAID,
                recordID: bucket.id,
                cycleID: firstCycle.id
            )
        )
        var undoSaveCount = 0
        let oldUndoAction = PaymentPlanEditorMutationActionFactory.make(
            service: service,
            token: undoToken,
            authenticatedUserID: { self.userAID },
            record: bucket,
            cycle: { firstCycle },
            cycles: { [firstCycle] }
        ) {
            handlingSuccess.undo.restore(deleteCreatedCycle: context.delete)
            try? context.save()
            undoSaveCount += 1
        }

        var input = EditPaymentPlanInput(bucket: bucket)
        input.dueDate = secondDueDate
        input.cycleDueDayAnchor = 14
        input.paymentTargetAmountText = "1200"
        input.setAsideChangeMode = .add
        input.setAsideAmountText = "425"
        input.shouldCreateActiveCycle = true
        let draft = try XCTUnwrap(input.draft(for: bucket))
        let saveResult = PaymentPlanUpdatePersistenceCoordinator.persist(
            draft: draft,
            bucket: bucket,
            activeCycle: nil,
            existingCycles: [firstCycle],
            insertCycle: context.insert,
            persistChanges: context.save,
            rollback: context.rollback
        )
        XCTAssertTrue(saveResult.startsSuccessFlow)

        XCTAssertFalse(oldUndoAction())
        XCTAssertEqual(undoSaveCount, 0)
        XCTAssertEqual(firstCycle.status, .handled)
        XCTAssertEqual(bucket.paymentTargetAmount, 1_200, accuracy: 0.001)
        XCTAssertEqual(bucket.protectedAmount, 425, accuracy: 0.001)
        let storedCycles = try context.fetch(FetchDescriptor<PaymentPlanCycle>())
            .filter { $0.ownerScopeID == userAScope && $0.paymentPlanID == bucket.id }
        XCTAssertEqual(storedCycles.filter(\.isActive).count, 1)
        XCTAssertEqual(storedCycles.first(where: \.isActive)?.frozenTargetAmount, 1_200)

        let reopenedContext = ModelContext(container)
        let reopenedBucket = try XCTUnwrap(
            try reopenedContext.fetch(FetchDescriptor<DebtPayoffBucket>())
                .first { $0.id == bucket.id }
        )
        let reopenedCycles = try reopenedContext
            .fetch(FetchDescriptor<PaymentPlanCycle>())
            .filter {
                $0.ownerScopeID == userAScope &&
                    $0.paymentPlanID == bucket.id
            }
        let reopenedActiveCycle = try XCTUnwrap(
            reopenedCycles.first(where: \.isActive)
        )
        let reopenedFirstCycle = try XCTUnwrap(
            reopenedCycles.first { $0.id == firstCycle.id }
        )
        XCTAssertEqual(reopenedCycles.filter(\.isActive).count, 1)
        XCTAssertEqual(reopenedFirstCycle.status, .handled)
        XCTAssertEqual(reopenedActiveCycle.dueDate, secondDueDate)
        XCTAssertEqual(reopenedActiveCycle.frozenTargetAmount, 1_200, accuracy: 0.001)
        XCTAssertEqual(reopenedBucket.paymentTargetAmount, 1_200, accuracy: 0.001)
        XCTAssertEqual(reopenedBucket.protectedAmount, 425, accuracy: 0.001)
    }

    func testCapturedHandledCycleUndoRestoresOnceWhenNotSuperseded() throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let bucket = DebtPayoffBucket(
            ownerScopeID: userAScope,
            plaidAccountID: "card-valid-undo",
            accountName: "Valid Undo",
            dueDate: Date(timeIntervalSince1970: 1_788_739_200),
            paymentTargetAmount: 800,
            protectedAmount: 240,
            debtKind: .linkedCreditCard
        )
        let cycle = PaymentPlanCycle(
            ownerScopeID: userAScope,
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: 800
        )
        context.insert(bucket)
        context.insert(cycle)
        context.insert(ReserveSettings(ownerScopeID: userAScope, balance: 0))
        try context.save()
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID }
        )
        service.configurePersistence(modelContext: context)

        var handlingResult: PaymentPlanCycleHandlingResult?
        let handleAction = PaymentPlanEditorMutationActionFactory.make(
            service: service,
            token: try XCTUnwrap(
                service.paymentPlanMutationAuthorizationToken(
                    authenticatedUserID: userAID,
                    recordID: bucket.id,
                    cycleID: cycle.id
                )
            ),
            authenticatedUserID: { self.userAID },
            record: bucket,
            cycle: { cycle },
            cycles: { [cycle] }
        ) {
            handlingResult = PaymentPlanCycleHandlingCoordinator
                .handleCurrentPayment(
                    for: bucket,
                    cycles: [cycle],
                    handledAt: Date(timeIntervalSince1970: 1_788_825_600),
                    insertCycle: context.insert,
                    persistChanges: context.save,
                    rollback: context.rollback
                )
        }
        XCTAssertTrue(handleAction())
        guard case .handled(let handlingSuccess) = handlingResult else {
            return XCTFail("Expected a handled cycle.")
        }

        var undoSaveCount = 0
        let undoAction = PaymentPlanEditorMutationActionFactory.make(
            service: service,
            token: try XCTUnwrap(
                service.paymentPlanMutationAuthorizationToken(
                    authenticatedUserID: userAID,
                    recordID: bucket.id,
                    cycleID: cycle.id
                )
            ),
            authenticatedUserID: { self.userAID },
            record: bucket,
            cycle: { cycle },
            cycles: { [cycle] }
        ) {
            handlingSuccess.undo.restore(deleteCreatedCycle: context.delete)
            try? context.save()
            undoSaveCount += 1
        }

        XCTAssertTrue(undoAction())
        XCTAssertFalse(undoAction())
        XCTAssertEqual(undoSaveCount, 1)

        let reopenedContext = ModelContext(container)
        let reopenedBucket = try XCTUnwrap(
            try reopenedContext.fetch(FetchDescriptor<DebtPayoffBucket>())
                .first { $0.id == bucket.id }
        )
        let reopenedCycles = try reopenedContext
            .fetch(FetchDescriptor<PaymentPlanCycle>())
            .filter { $0.ownerScopeID == userAScope && $0.paymentPlanID == bucket.id }
        XCTAssertEqual(reopenedCycles.filter(\.isActive).count, 1)
        XCTAssertEqual(reopenedCycles.first?.status, .active)
        XCTAssertEqual(reopenedBucket.protectedAmount, 240, accuracy: 0.001)
    }

    func testFailedSupersedingSaveRollsBackAndLeavesValidUndoUsable() throws {
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let bucket = DebtPayoffBucket(
            ownerScopeID: userAScope,
            plaidAccountID: "card-failed-save",
            accountName: "Failed Save",
            dueDate: Date(timeIntervalSince1970: 1_788_739_200),
            paymentTargetAmount: 700,
            protectedAmount: 210,
            debtKind: .linkedCreditCard
        )
        let cycle = PaymentPlanCycle(
            ownerScopeID: userAScope,
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: 700
        )
        context.insert(bucket)
        context.insert(cycle)
        context.insert(ReserveSettings(ownerScopeID: userAScope, balance: 0))
        try context.save()
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID }
        )
        service.configurePersistence(modelContext: context)

        var handlingResult: PaymentPlanCycleHandlingResult?
        let handleAction = PaymentPlanEditorMutationActionFactory.make(
            service: service,
            token: try XCTUnwrap(
                service.paymentPlanMutationAuthorizationToken(
                    authenticatedUserID: userAID,
                    recordID: bucket.id,
                    cycleID: cycle.id
                )
            ),
            authenticatedUserID: { self.userAID },
            record: bucket,
            cycle: { cycle },
            cycles: { [cycle] }
        ) {
            handlingResult = PaymentPlanCycleHandlingCoordinator
                .handleCurrentPayment(
                    for: bucket,
                    cycles: [cycle],
                    handledAt: Date(timeIntervalSince1970: 1_788_825_600),
                    insertCycle: context.insert,
                    persistChanges: context.save,
                    rollback: context.rollback
                )
        }
        XCTAssertTrue(handleAction())
        guard case .handled(let handlingSuccess) = handlingResult else {
            return XCTFail("Expected a handled cycle.")
        }

        var undoSaveCount = 0
        let undoAction = PaymentPlanEditorMutationActionFactory.make(
            service: service,
            token: try XCTUnwrap(
                service.paymentPlanMutationAuthorizationToken(
                    authenticatedUserID: userAID,
                    recordID: bucket.id,
                    cycleID: cycle.id
                )
            ),
            authenticatedUserID: { self.userAID },
            record: bucket,
            cycle: { cycle },
            cycles: { [cycle] }
        ) {
            handlingSuccess.undo.restore(deleteCreatedCycle: context.delete)
            try? context.save()
            undoSaveCount += 1
        }

        var input = EditPaymentPlanInput(bucket: bucket)
        input.dueDate = Date(timeIntervalSince1970: 1_791_417_600)
        input.cycleDueDayAnchor = 14
        input.paymentTargetAmountText = "1100"
        input.setAsideChangeMode = .add
        input.setAsideAmountText = "360"
        input.shouldCreateActiveCycle = true
        let failedDraft = try XCTUnwrap(input.draft(for: bucket))
        let saveResult = PaymentPlanUpdatePersistenceCoordinator.persist(
            draft: failedDraft,
            bucket: bucket,
            activeCycle: nil,
            existingCycles: [cycle],
            insertCycle: context.insert,
            persistChanges: { throw PaymentPlanTestPersistenceError.injected },
            rollback: context.rollback
        )
        XCTAssertFalse(saveResult.startsSuccessFlow)
        let cyclesAfterFailure = try context
            .fetch(FetchDescriptor<PaymentPlanCycle>())
            .filter { $0.ownerScopeID == userAScope && $0.paymentPlanID == bucket.id }
        XCTAssertTrue(cyclesAfterFailure.allSatisfy { !$0.isActive })
        XCTAssertEqual(bucket.paymentTargetAmount, 700, accuracy: 0.001)
        XCTAssertEqual(bucket.protectedAmount, 0, accuracy: 0.001)

        XCTAssertTrue(undoAction())
        XCTAssertFalse(undoAction())
        XCTAssertEqual(undoSaveCount, 1)
        let reopenedContext = ModelContext(container)
        let reopenedBucket = try XCTUnwrap(
            try reopenedContext.fetch(FetchDescriptor<DebtPayoffBucket>())
                .first { $0.id == bucket.id }
        )
        let reopenedCycles = try reopenedContext
            .fetch(FetchDescriptor<PaymentPlanCycle>())
            .filter { $0.ownerScopeID == userAScope && $0.paymentPlanID == bucket.id }
        XCTAssertEqual(reopenedCycles.filter(\.isActive).count, 1)
        XCTAssertEqual(reopenedBucket.paymentTargetAmount, 700, accuracy: 0.001)
        XCTAssertEqual(reopenedBucket.protectedAmount, 210, accuracy: 0.001)
    }

    func testSettingsLocalClearDeletesOnlyCapturedOwnerAndPreservesQuarantine() throws {
        let defaults = try isolatedDefaults()
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        insert(planningGraph(ownerScopeID: userAScope), into: context)
        insert(
            planningGraph(ownerScopeID: userBScope, name: "User B bill"),
            into: context
        )
        insert(
            planningGraph(ownerScopeID: nil, name: "Quarantined bill"),
            into: context
        )
        context.insert(incomeSchedule(ownerScopeID: userAScope))
        context.insert(incomeSchedule(ownerScopeID: userBScope))
        context.insert(transactionResolution(userID: userAID))
        context.insert(transactionResolution(userID: userBID))
        context.insert(
            AvailableToSpendAccountPreference(
                userID: userAID,
                plaidAccountID: "checking-a",
                isIncluded: false
            )
        )
        context.insert(
            AvailableToSpendAccountPreference(
                userID: userBID,
                plaidAccountID: "checking-b",
                isIncluded: false
            )
        )
        try context.save()

        let personalization = AppPersonalizationStore(defaults: defaults)
        personalization.set(
            "Alice",
            for: AppPersonalizationKeys.preferredName,
            ownerScopeID: userAScope
        )
        personalization.set(
            "Bob",
            for: AppPersonalizationKeys.preferredName,
            ownerScopeID: userBScope
        )
        let history = RecurringExpenseRecommendationHistoryStore(
            defaults: defaults,
            storeKind: .production
        )
        let suggestion = recurringSuggestion()
        history.record(
            suggestion,
            status: .dismissed,
            plannerEventID: nil,
            for: userAID
        )
        history.record(
            suggestion,
            status: .dismissed,
            plannerEventID: nil,
            for: userBID
        )
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: [checkingAccount(id: "checking-b")],
                lastSuccessfulRefresh: Date(),
                ownerUserID: userBID,
                defaults: defaults
            )
        )
        let pendingStore = PendingLocalAccountDeletionStore(defaults: defaults)
        let recoveryJob = try XCTUnwrap(
            pendingStore.beginDeletionIntent(
                userID: userAID,
                sessionToken: "session-a",
                storeKind: .production
            )
        )
        let service = PlaidService(
            sessionTokenProvider: { "session-b" },
            authenticatedUserIDProvider: { self.userBID },
            bankCacheDefaults: defaults,
            pendingDeletionStore: pendingStore
        )
        service.configurePersistence(modelContext: context)

        XCTAssertEqual(
            service.clearLocalFinancialDataForSignOut(
                authenticatedUserID: userBID
            ),
            .cleared
        )

        assertDeleted(ownerScopeID: userBScope, in: context)
        assertPreserved(ownerScopeID: userAScope, in: context)
        assertPreserved(ownerScopeID: nil, in: context)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<IncomeSchedule>())
                .map(\.ownerScopeID),
            [userAScope]
        )
        XCTAssertEqual(
            try context.fetch(
                FetchDescriptor<TransactionMatchedExpenseResolution>()
            ).map(\.ownerScopeID),
            [
                TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                    authenticatedUserID: userAID
                )!
            ]
        )
        XCTAssertEqual(
            try context.fetch(
                FetchDescriptor<AvailableToSpendAccountPreference>()
            ).map(\.userID),
            [userAID]
        )
        XCTAssertEqual(history.records(for: userAID).count, 1)
        XCTAssertTrue(history.records(for: userBID).isEmpty)
        XCTAssertEqual(
            personalization.string(
                for: AppPersonalizationKeys.preferredName,
                ownerScopeID: userAScope
            ),
            "Alice"
        )
        XCTAssertEqual(
            personalization.string(
                for: AppPersonalizationKeys.preferredName,
                ownerScopeID: userBScope
            ),
            ""
        )
        XCTAssertNil(
            PlaidLocalCache.loadAccountSnapshot(
                for: userBID,
                defaults: defaults
            )
        )
        XCTAssertEqual(pendingStore.readPendingDeletions().jobs, [recoveryJob])
    }

    func testSettingsLocalClearFetchFailureRollsBackAndPreservesAncillaryData() throws {
        try assertLocalClearFailurePreservesEverything(
            failRead: .eventAllocations,
            failSave: false
        )
    }

    func testSettingsLocalClearSaveFailureRollsBackAndPreservesAncillaryData() throws {
        try assertLocalClearFailurePreservesEverything(
            failRead: nil,
            failSave: true
        )
    }

    func testSettingsLocalClearOwnerTransitionDoesNotClearNewOwnerSnapshot() throws {
        let defaults = try isolatedDefaults()
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        insert(planningGraph(ownerScopeID: userAScope), into: context)
        insert(
            planningGraph(ownerScopeID: userBScope, name: "User B bill"),
            into: context
        )
        try context.save()
        var currentUserID = userBID
        var service: PlaidService!
        service = PlaidService(
            authenticatedUserIDProvider: { currentUserID },
            bankCacheDefaults: defaults,
            localFinancialDataClearDidSave: {
                currentUserID = self.userAID
                service.handlePlanningOwnerScopeChanged(
                    authenticatedUserID: self.userAID
                )
            }
        )
        service.configurePersistence(modelContext: context)

        XCTAssertEqual(
            service.clearLocalFinancialDataForSignOut(
                authenticatedUserID: userBID
            ),
            .clearedAfterOwnerChanged
        )
        XCTAssertEqual(service.loadedPlanningOwnerScopeID, userAScope)
        XCTAssertEqual(
            service.savingsGoals(authenticatedUserID: userAID).count,
            1
        )
        assertDeleted(ownerScopeID: userBScope, in: context)
        assertPreserved(ownerScopeID: userAScope, in: context)
    }

    func testMalformedLegacyGoalsFailClosedAndPreserveOriginalBytes() throws {
        let defaults = try isolatedDefaults()
        let original = Data("{not-valid-json".utf8)
        defaults.set(original, forKey: "savings_goals")
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        context.insert(
            ReserveSettings(ownerScopeID: userAScope, balance: 125)
        )
        try context.save()
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID },
            bankCacheDefaults: defaults
        )

        service.configurePersistence(modelContext: context)

        XCTAssertEqual(
            service.planningSnapshotAvailability(
                authenticatedUserID: userAID
            ),
            .unavailable
        )
        XCTAssertEqual(defaults.data(forKey: "savings_goals"), original)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SavingsGoalRecord>()).isEmpty
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ReserveSettings>()).first?.balance,
            125
        )
    }

    func testWrongTypeAndNonfiniteLegacyCushionFailClosed() throws {
        let invalidValues: [Any] = [true, "275", Double.infinity]

        for invalidValue in invalidValues {
            let defaults = try isolatedDefaults()
            defaults.set(invalidValue, forKey: "reserve_balance")
            let container = try fullPersistenceContainer()
            let context = ModelContext(container)
            let service = PlaidService(
                authenticatedUserIDProvider: { self.userAID },
                bankCacheDefaults: defaults
            )

            service.configurePersistence(modelContext: context)

            XCTAssertEqual(
                service.planningSnapshotAvailability(
                    authenticatedUserID: userAID
                ),
                .unavailable
            )
            XCTAssertNotNil(defaults.object(forKey: "reserve_balance"))
            XCTAssertTrue(
                try context.fetch(FetchDescriptor<ReserveSettings>()).isEmpty
            )
        }
    }

    func testValidZeroAndAbsentLegacyCushionRemainDistinctSuccessfulStates() throws {
        do {
            let defaults = try isolatedDefaults()
            defaults.set(0.0, forKey: "reserve_balance")
            let container = try fullPersistenceContainer()
            let context = ModelContext(container)
            let service = PlaidService(
                authenticatedUserIDProvider: { self.userAID },
                bankCacheDefaults: defaults
            )

            service.configurePersistence(modelContext: context)

            XCTAssertNil(defaults.object(forKey: "reserve_balance"))
            let reserves = try context.fetch(FetchDescriptor<ReserveSettings>())
            XCTAssertTrue(
                reserves.contains { $0.ownerScopeID == nil && $0.balance == 0 }
            )
            XCTAssertTrue(
                reserves.contains {
                    $0.ownerScopeID == userAScope && $0.balance == 0
                }
            )
        }

        do {
            let defaults = try isolatedDefaults()
            let container = try fullPersistenceContainer()
            let context = ModelContext(container)
            let service = PlaidService(
                authenticatedUserIDProvider: { self.userAID },
                bankCacheDefaults: defaults
            )

            service.configurePersistence(modelContext: context)

            let reserves = try context.fetch(FetchDescriptor<ReserveSettings>())
            XCTAssertEqual(reserves.count, 1)
            XCTAssertEqual(reserves.first?.ownerScopeID, userAScope)
            XCTAssertEqual(reserves.first?.balance, 0)
        }
    }

    func testValidLegacyGoalImportPreservesValueAsOwnerlessRecovery() throws {
        let defaults = try isolatedDefaults()
        let legacyGoal = SavingsGoal(
            name: "Legacy home repair",
            targetAmount: 3_000,
            currentAmount: 450
        )
        defaults.set(
            try JSONEncoder().encode([legacyGoal]),
            forKey: "savings_goals"
        )
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID },
            bankCacheDefaults: defaults
        )

        service.configurePersistence(modelContext: context)

        XCTAssertNil(defaults.object(forKey: "savings_goals"))
        let imported = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SavingsGoalRecord>()).first
        )
        XCTAssertNil(imported.ownerScopeID)
        XCTAssertEqual(imported.name, legacyGoal.name)
        XCTAssertEqual(imported.targetAmount, 3_000, accuracy: 0.001)
        XCTAssertEqual(imported.currentAmount, 450, accuracy: 0.001)
        XCTAssertTrue(service.legacyPlanningDataRecoveryAvailable)
        XCTAssertTrue(
            service.savingsGoals(authenticatedUserID: userAID).isEmpty
        )
    }

    func testLegacyCushionImportSaveFailurePreservesSourceAndRetriesExactly() throws {
        let defaults = try isolatedDefaults()
        defaults.set(275.0, forKey: "reserve_balance")
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        var shouldFailSave = true
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userAID },
            bankCacheDefaults: defaults,
            shouldFailPersistenceSave: { shouldFailSave }
        )

        service.configurePersistence(modelContext: context)

        XCTAssertEqual(
            service.planningSnapshotAvailability(
                authenticatedUserID: userAID
            ),
            .unavailable
        )
        XCTAssertEqual(defaults.double(forKey: "reserve_balance"), 275)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ReserveSettings>()).isEmpty
        )

        shouldFailSave = false
        XCTAssertTrue(
            service.retryPlanningSnapshot(
                authenticatedUserID: userAID
            )
        )
        XCTAssertNil(defaults.object(forKey: "reserve_balance"))
        let reserves = try context.fetch(FetchDescriptor<ReserveSettings>())
        XCTAssertEqual(
            reserves.first { $0.ownerScopeID == nil }?.balance,
            275
        )
        XCTAssertEqual(
            reserves.first { $0.ownerScopeID == userAScope }?.balance,
            0
        )
    }

    func testSharedLegacyDefaultsRemainForProductionAcrossDevelopmentAndLab() throws {
        let defaults = try isolatedDefaults()
        let legacyGoal = SavingsGoal(
            name: "Historical emergency fund",
            targetAmount: 4_000,
            currentAmount: 725
        )
        let originalGoalData = try JSONEncoder().encode([legacyGoal])
        defaults.set(originalGoalData, forKey: "savings_goals")
        defaults.set(325.0, forKey: "reserve_balance")

        let developmentContext = ModelContext(try fullPersistenceContainer())
        let development = PlaidService(
            authenticatedUserIDProvider: { self.userAID },
            bankCacheDefaults: defaults,
            localStoreKind: .development
        )
        development.configurePersistence(modelContext: developmentContext)

        XCTAssertEqual(defaults.data(forKey: "savings_goals"), originalGoalData)
        XCTAssertEqual(defaults.double(forKey: "reserve_balance"), 325)
        XCTAssertTrue(
            try developmentContext.fetch(FetchDescriptor<SavingsGoalRecord>())
                .allSatisfy { $0.ownerScopeID != nil }
        )
        _ = development.debugResetLocalUserData()
        XCTAssertEqual(defaults.data(forKey: "savings_goals"), originalGoalData)
        XCTAssertEqual(defaults.double(forKey: "reserve_balance"), 325)

        let labContext = ModelContext(try fullPersistenceContainer())
        let lab = PlaidService(
            authenticatedUserIDProvider: { self.userAID },
            bankCacheDefaults: defaults,
            localStoreKind: .lab
        )
        lab.configurePersistence(modelContext: labContext)

        XCTAssertFalse(lab.debugResetLocalUserData())
        XCTAssertEqual(defaults.data(forKey: "savings_goals"), originalGoalData)
        XCTAssertEqual(defaults.double(forKey: "reserve_balance"), 325)
        XCTAssertTrue(
            try labContext.fetch(FetchDescriptor<SavingsGoalRecord>())
                .allSatisfy { $0.ownerScopeID != nil }
        )

        let productionContext = ModelContext(try fullPersistenceContainer())
        var shouldFailProductionSave = true
        let production = PlaidService(
            authenticatedUserIDProvider: { self.userAID },
            bankCacheDefaults: defaults,
            localStoreKind: .production,
            shouldFailPersistenceSave: { shouldFailProductionSave }
        )
        production.configurePersistence(modelContext: productionContext)

        XCTAssertEqual(
            production.planningSnapshotAvailability(
                authenticatedUserID: userAID
            ),
            .unavailable
        )
        XCTAssertEqual(defaults.data(forKey: "savings_goals"), originalGoalData)
        XCTAssertEqual(defaults.double(forKey: "reserve_balance"), 325)

        shouldFailProductionSave = false
        XCTAssertTrue(
            production.retryPlanningSnapshot(
                authenticatedUserID: userAID
            )
        )
        XCTAssertNil(defaults.object(forKey: "savings_goals"))
        XCTAssertNil(defaults.object(forKey: "reserve_balance"))
        XCTAssertTrue(production.legacyPlanningDataRecoveryAvailable)

        XCTAssertEqual(
            production.adoptLegacyPlanningDataForCurrentUser(),
            .adopted(recordCount: 2)
        )
        XCTAssertEqual(
            production.savingsGoals(authenticatedUserID: userAID).map(\.name),
            [legacyGoal.name]
        )
        XCTAssertEqual(
            production.reserveBalance(authenticatedUserID: userAID),
            325,
            accuracy: 0.001
        )
    }
}

private extension CorePlanningUserIsolationTests {

    func assertLocalClearFailurePreservesEverything(
        failRead: PlanningPersistenceReadDomain?,
        failSave: Bool
    ) throws {
        let defaults = try isolatedDefaults()
        let container = try fullPersistenceContainer()
        let context = ModelContext(container)
        insert(planningGraph(ownerScopeID: userAScope), into: context)
        insert(
            planningGraph(ownerScopeID: userBScope, name: "User B bill"),
            into: context
        )
        insert(
            planningGraph(ownerScopeID: nil, name: "Quarantined bill"),
            into: context
        )
        try context.save()
        let personalization = AppPersonalizationStore(defaults: defaults)
        personalization.set(
            "Bob",
            for: AppPersonalizationKeys.preferredName,
            ownerScopeID: userBScope
        )
        let history = RecurringExpenseRecommendationHistoryStore(
            defaults: defaults,
            storeKind: .production
        )
        history.record(
            recurringSuggestion(),
            status: .dismissed,
            plannerEventID: nil,
            for: userBID
        )
        XCTAssertTrue(
            PlaidLocalCache.saveAccountSnapshot(
                accounts: [checkingAccount(id: "checking-b")],
                lastSuccessfulRefresh: Date(),
                ownerUserID: userBID,
                defaults: defaults
            )
        )
        let service = PlaidService(
            authenticatedUserIDProvider: { self.userBID },
            bankCacheDefaults: defaults,
            shouldFailPersistenceRead: { $0 == failRead },
            shouldFailPersistenceSave: { failSave }
        )
        service.configurePersistence(modelContext: context)

        XCTAssertEqual(
            service.clearLocalFinancialDataForSignOut(
                authenticatedUserID: userBID
            ),
            .failed
        )
        assertPreserved(ownerScopeID: userAScope, in: context)
        assertPreserved(ownerScopeID: userBScope, in: context)
        assertPreserved(ownerScopeID: nil, in: context)
        XCTAssertEqual(history.records(for: userBID).count, 1)
        XCTAssertEqual(
            personalization.string(
                for: AppPersonalizationKeys.preferredName,
                ownerScopeID: userBScope
            ),
            "Bob"
        )
        XCTAssertEqual(
            PlaidLocalCache.loadAccountSnapshot(
                for: userBID,
                defaults: defaults
            )?.accounts.map(\.account_id),
            ["checking-b"]
        )
    }

    func recurringSuggestion() -> RecurringExpenseSuggestion {
        let familyID = RecurringExpenseRecommendationIdentity.familyID(
            normalizedName: "monthly service",
            accountID: "checking"
        )
        return RecurringExpenseSuggestion(
            id: RecurringExpenseRecommendationIdentity.suggestionID(
                familyID: familyID,
                amount: 25,
                dayOfMonth: 15
            ),
            historyID: familyID,
            merchantName: "Monthly Service",
            normalizedName: "monthly service",
            amount: 25,
            nextDueDate: Date(timeIntervalSince1970: 1_800_000_000),
            dayOfMonth: 15,
            occurrenceCount: 3,
            isAlreadyInPlan: false
        )
    }

    func applyAccount(
        id: String,
        to service: PlaidService
    ) {
        let requestScope = service.beginBankSyncRefreshRequest()
        service.handleAccountsResponse(
            requestScope: requestScope,
            data: Data(
                """
                {
                  "accounts": [{
                    "account_id": "\(id)",
                    "name": "Checking",
                    "official_name": null,
                    "type": "depository",
                    "subtype": "checking",
                    "mask": "0000",
                    "balances": {"available": 1000, "current": 1000}
                  }],
                  "partial_failure": false,
                  "refreshed_item_ids": ["item-1"],
                  "evaluated_item_ids": ["item-1"]
                }
                """.utf8
            ),
            response: httpResponse(statusCode: 200),
            error: nil,
            reason: .debugTool,
            completion: { _ in }
        )
    }

    func isolatedDefaults() throws -> UserDefaults {
        let suiteName = "CorePlanningUserIsolationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func httpResponse(
        statusCode: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/api/accounts")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    struct PlanningGraph {
        let event: PlannerEvent
        let allocation: EventAllocation
        let status: ExpenseOccurrenceStatus
        let paymentPlan: DebtPayoffBucket
        let cycle: PaymentPlanCycle
        let goal: SavingsGoalRecord
        let reserve: ReserveSettings
    }

    func planningGraph(
        ownerScopeID: String?,
        name: String = "User A bill",
        allocationAmount: Double = 100,
        paymentPlanProtectedAmount: Double = 80,
        goalAmount: Double = 70,
        reserveAmount: Double = 50
    ) -> PlanningGraph {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let event = PlannerEvent(
            ownerScopeID: ownerScopeID,
            name: name,
            amount: 500,
            date: date,
            type: .expense
        )
        let forecast = ForecastEvent(
            event: event,
            occurrenceDate: date
        )
        let allocation = EventAllocation(
            ownerScopeID: ownerScopeID,
            occurrenceID: forecast.occurrenceID,
            sourceEventID: event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: allocationAmount
        )
        let status = ExpenseOccurrenceStatus(
            ownerScopeID: ownerScopeID,
            occurrenceID: "historical-\(event.id.uuidString)",
            sourceEventID: event.id,
            occurrenceDate: date.addingTimeInterval(-86_400),
            status: .paid
        )
        let paymentPlan = DebtPayoffBucket(
            ownerScopeID: ownerScopeID,
            plaidAccountID: "",
            accountName: "Loan for \(name)",
            dueDate: date,
            paymentTargetAmount: 250,
            protectedAmount: paymentPlanProtectedAmount,
            debtKind: .other
        )
        let cycle = PaymentPlanCycle(
            ownerScopeID: ownerScopeID,
            paymentPlanID: paymentPlan.id,
            dueDate: date,
            frozenTargetAmount: 250
        )
        let goal = SavingsGoalRecord(
            ownerScopeID: ownerScopeID,
            name: "Goal for \(name)",
            targetAmount: 1_000,
            currentAmount: goalAmount
        )
        let reserve = ReserveSettings(
            ownerScopeID: ownerScopeID,
            balance: reserveAmount
        )

        return PlanningGraph(
            event: event,
            allocation: allocation,
            status: status,
            paymentPlan: paymentPlan,
            cycle: cycle,
            goal: goal,
            reserve: reserve
        )
    }

    func financialSummary(
        ownerScopeID: String,
        graphs: [PlanningGraph]
    ) -> FinancialSummary {
        financialSummary(
            events: graphs.map(\.event).owned(by: ownerScopeID),
            allocations: graphs.map(\.allocation).owned(by: ownerScopeID),
            statuses: graphs.map(\.status).owned(by: ownerScopeID),
            plans: graphs.map(\.paymentPlan).owned(by: ownerScopeID),
            goals: graphs.map(\.goal).owned(by: ownerScopeID),
            reserves: graphs.map(\.reserve).owned(by: ownerScopeID)
        )
    }

    func financialSummary(
        events: [PlannerEvent],
        allocations: [EventAllocation],
        statuses: [ExpenseOccurrenceStatus],
        plans: [DebtPayoffBucket],
        goals: [SavingsGoalRecord],
        reserves: [ReserveSettings]
    ) -> FinancialSummary {
        UpcomingExpenseFundingComposition(
            events: events,
            allocations: allocations,
            occurrenceStatuses: statuses
        )
        .dashboardFinancialSummary(
            accounts: [checkingAccount(id: "checking")],
            goals: goals.map(\.savingsGoal),
            reserveBalance: reserves.first?.balance ?? 0,
            debtPaymentsSetAside: plans.totalProtectedAmount
        )
    }

    func checkingAccount(id: String) -> PlaidAccount {
        PlaidAccount(
            account_id: id,
            name: "Checking",
            official_name: nil,
            type: "depository",
            subtype: "checking",
            mask: "0000",
            balances: PlaidBalance(
                available: 1_000,
                current: 1_000
            )
        )
    }

    func assertVisibleCounts(
        ownerScopeID: String,
        events: [PlannerEvent],
        allocations: [EventAllocation],
        statuses: [ExpenseOccurrenceStatus],
        plans: [DebtPayoffBucket],
        cycles: [PaymentPlanCycle],
        goals: [SavingsGoalRecord],
        reserves: [ReserveSettings],
        expectedEventName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            events.owned(by: ownerScopeID).map(\.name),
            [expectedEventName],
            file: file,
            line: line
        )
        XCTAssertEqual(allocations.owned(by: ownerScopeID).count, 1)
        XCTAssertEqual(statuses.owned(by: ownerScopeID).count, 1)
        XCTAssertEqual(plans.owned(by: ownerScopeID).count, 1)
        XCTAssertEqual(cycles.owned(by: ownerScopeID).count, 1)
        XCTAssertEqual(goals.owned(by: ownerScopeID).count, 1)
        XCTAssertEqual(reserves.owned(by: ownerScopeID).count, 1)
    }

    func assertNoVisibleRecords(
        ownerScopeID: String,
        events: [PlannerEvent],
        allocations: [EventAllocation],
        statuses: [ExpenseOccurrenceStatus],
        plans: [DebtPayoffBucket],
        cycles: [PaymentPlanCycle],
        goals: [SavingsGoalRecord],
        reserves: [ReserveSettings],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(events.owned(by: ownerScopeID).isEmpty, file: file, line: line)
        XCTAssertTrue(allocations.owned(by: ownerScopeID).isEmpty, file: file, line: line)
        XCTAssertTrue(statuses.owned(by: ownerScopeID).isEmpty, file: file, line: line)
        XCTAssertTrue(plans.owned(by: ownerScopeID).isEmpty, file: file, line: line)
        XCTAssertTrue(cycles.owned(by: ownerScopeID).isEmpty, file: file, line: line)
        XCTAssertTrue(goals.owned(by: ownerScopeID).isEmpty, file: file, line: line)
        XCTAssertTrue(reserves.owned(by: ownerScopeID).isEmpty, file: file, line: line)
    }

    func insert(
        _ graph: PlanningGraph,
        into context: ModelContext
    ) {
        context.insert(graph.event)
        context.insert(graph.allocation)
        context.insert(graph.status)
        context.insert(graph.paymentPlan)
        context.insert(graph.cycle)
        context.insert(graph.goal)
        context.insert(graph.reserve)
    }

    func assertDeleted(
        ownerScopeID: String,
        in context: ModelContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(hasRecord(ownerScopeID: ownerScopeID, type: PlannerEvent.self, in: context), file: file, line: line)
        XCTAssertFalse(hasRecord(ownerScopeID: ownerScopeID, type: EventAllocation.self, in: context), file: file, line: line)
        XCTAssertFalse(hasRecord(ownerScopeID: ownerScopeID, type: ExpenseOccurrenceStatus.self, in: context), file: file, line: line)
        XCTAssertFalse(hasRecord(ownerScopeID: ownerScopeID, type: DebtPayoffBucket.self, in: context), file: file, line: line)
        XCTAssertFalse(hasRecord(ownerScopeID: ownerScopeID, type: PaymentPlanCycle.self, in: context), file: file, line: line)
        XCTAssertFalse(hasRecord(ownerScopeID: ownerScopeID, type: SavingsGoalRecord.self, in: context), file: file, line: line)
        XCTAssertFalse(hasRecord(ownerScopeID: ownerScopeID, type: ReserveSettings.self, in: context), file: file, line: line)
    }

    func assertPreserved(
        ownerScopeID: String?,
        in context: ModelContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(hasRecord(ownerScopeID: ownerScopeID, type: PlannerEvent.self, in: context), file: file, line: line)
        XCTAssertTrue(hasRecord(ownerScopeID: ownerScopeID, type: EventAllocation.self, in: context), file: file, line: line)
        XCTAssertTrue(hasRecord(ownerScopeID: ownerScopeID, type: ExpenseOccurrenceStatus.self, in: context), file: file, line: line)
        XCTAssertTrue(hasRecord(ownerScopeID: ownerScopeID, type: DebtPayoffBucket.self, in: context), file: file, line: line)
        XCTAssertTrue(hasRecord(ownerScopeID: ownerScopeID, type: PaymentPlanCycle.self, in: context), file: file, line: line)
        XCTAssertTrue(hasRecord(ownerScopeID: ownerScopeID, type: SavingsGoalRecord.self, in: context), file: file, line: line)
        XCTAssertTrue(hasRecord(ownerScopeID: ownerScopeID, type: ReserveSettings.self, in: context), file: file, line: line)
    }

    func hasRecord<Model: PlanningOwnedRecord>(
        ownerScopeID: String?,
        type: Model.Type,
        in context: ModelContext
    ) -> Bool {
        let records = (try? context.fetch(FetchDescriptor<Model>())) ?? []
        return records.contains { $0.ownerScopeID == ownerScopeID }
    }

    func incomeSchedule(ownerScopeID: String) -> IncomeSchedule {
        IncomeSchedule(
            ownerScopeID: ownerScopeID,
            takeHomeAmountCents: 100_000,
            frequency: .monthly,
            lastPaydayDateKey: "2026-08-01",
            nextExpectedPaydayDateKey: "2026-09-01",
            dateBasis: .explicit
        )
    }

    func transactionResolution(
        userID: String
    ) -> TransactionMatchedExpenseResolution {
        TransactionMatchedExpenseResolution(
            hashedOwnerScopeID: TransactionMatchedExpenseResolutionIdentity
                .ownerScopeID(authenticatedUserID: userID)!,
            transactionID: UUID().uuidString,
            accountID: "checking-\(userID)",
            transactionPostedDateKey: "2026-08-01",
            transactionAmountCents: 2_500,
            sourceEventID: UUID(),
            occurrenceID: UUID().uuidString,
            occurrenceDateKey: "2026-08-01",
            outcome: .ignored,
            appliedSetAsideAmountCents: 0
        )
    }

    func planningContainer(
        url: URL? = nil
    ) throws -> ModelContainer {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            PlanningOwnershipMigrationState.self
        ])

        if let url {
            return try container(schema: schema, url: url)
        }

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

    func fullPersistenceContainer() throws -> ModelContainer {
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

    func container(
        schema: Schema,
        url: URL
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "CorePlanningUserIsolationTests",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
