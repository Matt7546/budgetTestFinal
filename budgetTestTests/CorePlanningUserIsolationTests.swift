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
}

private extension CorePlanningUserIsolationTests {

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
        ownerScopeID: String,
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
        ownerScopeID: String,
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
