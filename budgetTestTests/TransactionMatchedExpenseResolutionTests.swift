import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class TransactionMatchedExpenseResolutionTests: XCTestCase {
    private let eventID = UUID(
        uuidString: "11111111-1111-1111-1111-111111111111"
    )!
    private let paymentPlanID = UUID(
        uuidString: "22222222-2222-2222-2222-222222222222"
    )!
    private let paymentPlanCycleID = UUID(
        uuidString: "33333333-3333-3333-3333-333333333333"
    )!

    func testAdditiveMigrationPreservesExistingPlanningRecordsAndStartsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("Caldera.store")
        try createLegacyStore(at: storeURL)

        let migratedSchema = Schema(
            legacyModelTypes + [
                TransactionMatchedExpenseResolution.self
            ]
        )
        let configuration = ModelConfiguration(
            "TransactionMatchedExpenseResolutionMigration",
            schema: migratedSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: migratedSchema,
            configurations: [configuration]
        )
        let context = ModelContext(container)

        let events = try context.fetch(FetchDescriptor<PlannerEvent>())
        let allocations = try context.fetch(FetchDescriptor<EventAllocation>())
        let statuses = try context.fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        )
        let goals = try context.fetch(FetchDescriptor<SavingsGoalRecord>())
        let cushions = try context.fetch(FetchDescriptor<ReserveSettings>())
        let plans = try context.fetch(FetchDescriptor<DebtPayoffBucket>())
        let cycles = try context.fetch(FetchDescriptor<PaymentPlanCycle>())
        let preferences = try context.fetch(
            FetchDescriptor<AvailableToSpendAccountPreference>()
        )
        let incomeSchedules = try context.fetch(
            FetchDescriptor<IncomeSchedule>()
        )
        let resolutions = try context.fetch(
            FetchDescriptor<TransactionMatchedExpenseResolution>()
        )

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.id, eventID)
        XCTAssertEqual(event.name, "Rent")
        XCTAssertEqual(event.amount, 1_500, accuracy: 0.001)
        XCTAssertEqual(event.date, date(2026, 9, 15))
        XCTAssertEqual(event.frequency, .monthly)
        XCTAssertEqual(event.type, .expense)

        let allocation = try XCTUnwrap(allocations.first)
        XCTAssertEqual(allocations.count, 1)
        XCTAssertEqual(allocation.occurrenceID, occurrenceID)
        XCTAssertEqual(allocation.sourceEventID, eventID)
        XCTAssertEqual(allocation.allocatedAmount, 750, accuracy: 0.001)

        let status = try XCTUnwrap(statuses.first)
        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(status.occurrenceID, occurrenceID)
        XCTAssertEqual(status.sourceEventID, eventID)
        XCTAssertEqual(status.status, .paid)

        let goal = try XCTUnwrap(goals.first)
        XCTAssertEqual(goals.count, 1)
        XCTAssertEqual(goal.name, "Emergency")
        XCTAssertEqual(goal.targetAmount, 3_000, accuracy: 0.001)
        XCTAssertEqual(goal.currentAmount, 600, accuracy: 0.001)

        XCTAssertEqual(cushions.count, 1)
        XCTAssertEqual(cushions[0].balance, 400, accuracy: 0.001)

        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plan.id, paymentPlanID)
        XCTAssertEqual(plan.plaidAccountID, "credit-account-1")
        XCTAssertEqual(plan.paymentTargetAmount, 900, accuracy: 0.001)
        XCTAssertEqual(plan.protectedAmount, 250, accuracy: 0.001)

        let cycle = try XCTUnwrap(cycles.first)
        XCTAssertEqual(cycles.count, 1)
        XCTAssertEqual(cycle.id, paymentPlanCycleID)
        XCTAssertEqual(cycle.paymentPlanID, paymentPlanID)
        XCTAssertEqual(cycle.frozenTargetAmount, 900, accuracy: 0.001)
        XCTAssertEqual(cycle.status, .active)

        XCTAssertEqual(preferences.count, 1)
        XCTAssertEqual(preferences[0].userID, "user-1")
        XCTAssertEqual(preferences[0].plaidAccountID, "checking-account-1")
        XCTAssertFalse(preferences[0].isIncluded)

        XCTAssertEqual(incomeSchedules.count, 1)
        XCTAssertEqual(incomeSchedules[0].takeHomeAmountCents, 250_000)
        XCTAssertEqual(incomeSchedules[0].frequency, .biweekly)
        XCTAssertTrue(resolutions.isEmpty)
    }

    func testDecisionStoresExactProvenanceWithoutDisplayNames() throws {
        let ownerScopeID = try XCTUnwrap(
            TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                authenticatedUserID: "user-1"
            )
        )
        let createdAt = date(2026, 9, 16)
        let decidedAt = createdAt.addingTimeInterval(30)
        let decisionID = UUID(
            uuidString: "44444444-4444-4444-4444-444444444444"
        )!
        let container = try decisionContainer()
        let context = ModelContext(container)

        context.insert(
            TransactionMatchedExpenseResolution(
                id: decisionID,
                hashedOwnerScopeID: ownerScopeID,
                transactionID: "transaction-123",
                accountID: "account-456",
                itemID: "item-789",
                transactionPostedDateKey: "2026-09-15",
                transactionAmountCents: 1_299,
                sourceEventID: eventID,
                occurrenceID: occurrenceID,
                occurrenceDateKey: "2026-09-15",
                outcome: .reassigned,
                appliedSetAsideAmountCents: 1_299,
                paymentPlanID: paymentPlanID,
                paymentPlanCycleID: paymentPlanCycleID,
                createdAt: createdAt,
                decidedAt: decidedAt
            )
        )
        try context.save()

        let saved = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<TransactionMatchedExpenseResolution>()
            ).first
        )

        XCTAssertEqual(saved.id, decisionID)
        XCTAssertTrue(saved.matchKey.hasPrefix("v1:"))
        XCTAssertEqual(saved.ownerScopeID, ownerScopeID)
        XCTAssertEqual(
            saved.matcherVersion,
            TransactionMatchedExpenseResolutionIdentity.matcherVersion
        )
        XCTAssertEqual(saved.transactionID, "transaction-123")
        XCTAssertEqual(saved.accountID, "account-456")
        XCTAssertEqual(saved.itemID, "item-789")
        XCTAssertEqual(saved.transactionPostedDateKey, "2026-09-15")
        XCTAssertEqual(saved.transactionAmountCents, 1_299)
        XCTAssertEqual(saved.sourceEventID, eventID)
        XCTAssertEqual(saved.occurrenceID, occurrenceID)
        XCTAssertEqual(saved.occurrenceDateKey, "2026-09-15")
        XCTAssertEqual(saved.outcome, .reassigned)
        XCTAssertEqual(saved.appliedSetAsideAmountCents, 1_299)
        XCTAssertEqual(saved.paymentPlanID, paymentPlanID)
        XCTAssertEqual(saved.paymentPlanCycleID, paymentPlanCycleID)
        XCTAssertEqual(saved.createdAt, createdAt)
        XCTAssertEqual(saved.decidedAt, decidedAt)
    }

    func testOwnerScopeAndMatchKeyAreHashedScopedAndStable() throws {
        XCTAssertNil(
            TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                authenticatedUserID: nil
            )
        )
        XCTAssertNil(
            TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                authenticatedUserID: "   "
            )
        )

        let ownerScopeID = try XCTUnwrap(
            TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                authenticatedUserID: " user-1 "
            )
        )
        let sameOwnerScopeID = try XCTUnwrap(
            TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                authenticatedUserID: "user-1"
            )
        )
        let otherOwnerScopeID = try XCTUnwrap(
            TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                authenticatedUserID: "user-2"
            )
        )

        XCTAssertEqual(ownerScopeID, sameOwnerScopeID)
        XCTAssertNotEqual(ownerScopeID, "user-1")
        XCTAssertNotEqual(ownerScopeID, otherOwnerScopeID)
        XCTAssertEqual(ownerScopeID.count, 64)

        let key = TransactionMatchedExpenseResolutionIdentity.matchKey(
            hashedOwnerScopeID: ownerScopeID,
            accountID: "account-1",
            transactionID: "transaction-1",
            occurrenceID: occurrenceID
        )
        let sameKey = TransactionMatchedExpenseResolutionIdentity.matchKey(
            hashedOwnerScopeID: ownerScopeID,
            accountID: "account-1",
            transactionID: "transaction-1",
            occurrenceID: occurrenceID
        )
        let otherAccountKey = TransactionMatchedExpenseResolutionIdentity.matchKey(
            hashedOwnerScopeID: ownerScopeID,
            accountID: "account-2",
            transactionID: "transaction-1",
            occurrenceID: occurrenceID
        )
        let otherOwnerKey = TransactionMatchedExpenseResolutionIdentity.matchKey(
            hashedOwnerScopeID: otherOwnerScopeID,
            accountID: "account-1",
            transactionID: "transaction-1",
            occurrenceID: occurrenceID
        )
        let otherTransactionKey = TransactionMatchedExpenseResolutionIdentity.matchKey(
            hashedOwnerScopeID: ownerScopeID,
            accountID: "account-1",
            transactionID: "transaction-2",
            occurrenceID: occurrenceID
        )
        let otherOccurrenceKey = TransactionMatchedExpenseResolutionIdentity.matchKey(
            hashedOwnerScopeID: ownerScopeID,
            accountID: "account-1",
            transactionID: "transaction-1",
            occurrenceID: "different-occurrence"
        )

        XCTAssertEqual(key, sameKey)
        XCTAssertNotEqual(key, otherAccountKey)
        XCTAssertNotEqual(key, otherOwnerKey)
        XCTAssertNotEqual(key, otherTransactionKey)
        XCTAssertNotEqual(key, otherOccurrenceKey)
        XCTAssertTrue(key.hasPrefix("v1:"))
    }

    func testUnknownOccurrenceStatusFailsClosedAsUnresolved() {
        let now = date(2026, 9, 16)
        let forecast = makeForecast(dueDate: date(2026, 9, 15))
        let status = makeStatus(for: forecast, resolution: .skipped)
        status.statusRawValue = "future-resolution"
        let allocation = EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            allocatedAmount: 400
        )

        let resolvedIDs = ExpenseOccurrenceLifecycleResolver
            .resolvedOccurrenceIDs(from: [status])
        let activeForecasts = [forecast].filter {
            !resolvedIDs.contains($0.occurrenceID)
        }

        XCTAssertNil(status.status)
        XCTAssertEqual(status.statusRawValue, "future-resolution")
        XCTAssertTrue(resolvedIDs.isEmpty)
        XCTAssertEqual(
            ExpenseOccurrenceLifecycleResolver.lifecycle(
                for: forecast,
                statuses: [status],
                now: now,
                calendar: utcCalendar
            ),
            .overdue
        )
        XCTAssertEqual(
            EventAllocationTotals.activeTotal(
                allocations: [allocation],
                forecastEvents: activeForecasts
            ),
            400,
            accuracy: 0.001
        )
    }

    func testChargedToCardIsDistinctFromPaid() {
        let forecast = makeForecast(dueDate: date(2026, 9, 15))
        let status = makeStatus(
            for: forecast,
            resolution: .chargedToCard
        )
        let lifecycle = ExpenseOccurrenceLifecycleResolver.lifecycle(
            for: forecast,
            statuses: [status],
            now: date(2026, 9, 16),
            calendar: utcCalendar
        )

        XCTAssertEqual(status.status, .chargedToCard)
        XCTAssertNotEqual(status.status, .paid)
        XCTAssertEqual(lifecycle, .chargedToCard)
        XCTAssertNotEqual(lifecycle, .paid)
        XCTAssertTrue(lifecycle.isResolved)
    }

    func testPostedFromCheckingIsDistinctFromSkipped() {
        let forecast = makeForecast(dueDate: date(2026, 9, 15))
        let status = makeStatus(
            for: forecast,
            resolution: .postedFromChecking
        )
        let lifecycle = ExpenseOccurrenceLifecycleResolver.lifecycle(
            for: forecast,
            statuses: [status],
            now: date(2026, 9, 16),
            calendar: utcCalendar
        )

        XCTAssertEqual(status.status, .postedFromChecking)
        XCTAssertNotEqual(status.status, .skipped)
        XCTAssertEqual(lifecycle, .postedFromChecking)
        XCTAssertNotEqual(lifecycle, .skipped)
        XCTAssertTrue(lifecycle.isResolved)
    }

    func testManualCoordinatorRejectsTransactionOnlyStatuses() throws {
        for resolution in [
            ExpenseOccurrenceResolution.chargedToCard,
            .postedFromChecking
        ] {
            let schema = Schema([ExpenseOccurrenceStatus.self])
            let container = try ModelContainer(
                for: schema,
                configurations: [
                    ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: true,
                        cloudKitDatabase: .none
                    )
                ]
            )
            let context = ModelContext(container)
            let forecast = makeForecast(dueDate: date(2026, 9, 15))
            var didPersist = false

            let result = UpcomingExpenseActionPersistenceCoordinator.resolve(
                resolution,
                forecast: forecast,
                existingStatus: nil,
                modelContext: context,
                persistChanges: { didPersist = true },
                rollback: {}
            )

            guard case .failed = result else {
                return XCTFail("Transaction-only status reached the manual save path")
            }

            XCTAssertFalse(didPersist)
            XCTAssertTrue(
                try context.fetch(
                    FetchDescriptor<ExpenseOccurrenceStatus>()
                ).isEmpty
            )
        }
    }

    func testDecisionRecordDoesNotChangeAvailableToSpendInputsOrFormula() throws {
        let accounts = [
            PlaidAccount(
                account_id: "checking-1",
                name: "Checking",
                official_name: nil,
                type: "depository",
                subtype: "checking",
                mask: nil,
                balances: PlaidBalance(
                    available: 2_000,
                    current: 2_000
                )
            )
        ]
        let goals = [
            SavingsGoal(
                name: "Emergency",
                targetAmount: 1_000,
                currentAmount: 300
            )
        ]
        let before = FinancialSummaryCalculator.calculate(
            accounts: accounts,
            goals: goals,
            reserveBalance: 200,
            upcomingExpensesSetAside: 400,
            debtPaymentsSetAside: 250
        )
        let container = try decisionContainer()
        let context = ModelContext(container)
        context.insert(try makeDecision(outcome: .released))
        try context.save()
        let after = FinancialSummaryCalculator.calculate(
            accounts: accounts,
            goals: goals,
            reserveBalance: 200,
            upcomingExpensesSetAside: 400,
            debtPaymentsSetAside: 250
        )

        XCTAssertEqual(before, after)
        XCTAssertEqual(after.safeToSpend, 850, accuracy: 0.001)
    }

    func testSignOutAndAccountDeletionCleanupRemoveDecisions() throws {
        let signOutFixture = try cleanupFixture()
        signOutFixture.service.clearLocalFinancialDataForSignOut()
        XCTAssertTrue(
            try signOutFixture.context.fetch(
                FetchDescriptor<TransactionMatchedExpenseResolution>()
            ).isEmpty
        )

        let deletionFixture = try cleanupFixture()
        deletionFixture.service.clearLocalFinancialDataForDeletedUser(
            userID: "user-1"
        )
        XCTAssertTrue(
            try deletionFixture.context.fetch(
                FetchDescriptor<TransactionMatchedExpenseResolution>()
            ).isEmpty
        )
    }

    #if DEBUG
    func testDeveloperResetRemovesDecisions() throws {
        let fixture = try cleanupFixture()
        fixture.service.debugResetLocalUserData()

        XCTAssertTrue(
            try fixture.context.fetch(
                FetchDescriptor<TransactionMatchedExpenseResolution>()
            ).isEmpty
        )
    }
    #endif

    private var occurrenceID: String {
        "\(eventID.uuidString.lowercased())|2026-09-15"
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var legacyModelTypes: [any PersistentModel.Type] {
        [
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self,
            IncomeSchedule.self
        ]
    }

    private func createLegacyStore(at url: URL) throws {
        let schema = Schema(legacyModelTypes)
        let configuration = ModelConfiguration(
            "TransactionMatchedExpenseResolutionMigration",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let occurrenceDate = date(2026, 9, 15)
        let event = PlannerEvent(
            id: eventID,
            name: "Rent",
            amount: 1_500,
            date: occurrenceDate,
            frequency: .monthly,
            type: .expense
        )
        let plan = DebtPayoffBucket(
            id: paymentPlanID,
            plaidAccountID: "credit-account-1",
            accountName: "Credit Card",
            dueDate: date(2026, 9, 28),
            paymentTargetAmount: 900,
            protectedAmount: 250
        )

        context.insert(event)
        context.insert(
            EventAllocation(
                occurrenceID: occurrenceID,
                sourceEventID: eventID,
                occurrenceDate: occurrenceDate,
                allocatedAmount: 750
            )
        )
        context.insert(
            ExpenseOccurrenceStatus(
                occurrenceID: occurrenceID,
                sourceEventID: eventID,
                occurrenceDate: occurrenceDate,
                status: .paid
            )
        )
        context.insert(
            SavingsGoalRecord(
                name: "Emergency",
                targetAmount: 3_000,
                currentAmount: 600
            )
        )
        context.insert(ReserveSettings(balance: 400))
        context.insert(plan)
        context.insert(
            PaymentPlanCycle(
                id: paymentPlanCycleID,
                paymentPlanID: paymentPlanID,
                dueDate: date(2026, 9, 28),
                frozenTargetAmount: 900,
                calendar: utcCalendar
            )
        )
        context.insert(
            AvailableToSpendAccountPreference(
                userID: "user-1",
                plaidAccountID: "checking-account-1",
                isIncluded: false,
                now: date(2026, 9, 1)
            )
        )
        context.insert(
            IncomeSchedule(
                ownerScopeID: "income-owner-scope",
                takeHomeAmountCents: 250_000,
                frequency: .biweekly,
                lastPaydayDateKey: "2026-09-04",
                nextExpectedPaydayDateKey: "2026-09-18",
                dateBasis: .calculated
            )
        )
        try context.save()
    }

    private func makeForecast(
        dueDate: Date
    ) -> ForecastEvent {
        let event = PlannerEvent(
            id: eventID,
            name: "Rent",
            amount: 800,
            date: dueDate,
            frequency: .once,
            type: .expense
        )
        return ForecastEvent(
            event: event,
            occurrenceDate: dueDate
        )
    }

    private func makeStatus(
        for forecast: ForecastEvent,
        resolution: ExpenseOccurrenceResolution
    ) -> ExpenseOccurrenceStatus {
        ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            status: resolution
        )
    }

    private func decisionContainer() throws -> ModelContainer {
        let schema = Schema([
            TransactionMatchedExpenseResolution.self
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

    private func cleanupFixture() throws -> (
        service: PlaidService,
        context: ModelContext,
        container: ModelContainer
    ) {
        let schema = Schema(
            legacyModelTypes + [
                TransactionMatchedExpenseResolution.self
            ]
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [
                ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            ]
        )
        let context = ModelContext(container)
        context.insert(try makeDecision(outcome: .ignored))
        try context.save()

        let service = PlaidService()
        service.configurePersistence(modelContext: context)
        return (service, context, container)
    }

    private func makeDecision(
        outcome: TransactionMatchedExpenseResolutionOutcome
    ) throws -> TransactionMatchedExpenseResolution {
        let ownerScopeID = try XCTUnwrap(
            TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                authenticatedUserID: "user-1"
            )
        )
        return TransactionMatchedExpenseResolution(
            hashedOwnerScopeID: ownerScopeID,
            transactionID: "transaction-123",
            accountID: "account-456",
            transactionPostedDateKey: "2026-09-15",
            transactionAmountCents: 1_299,
            sourceEventID: eventID,
            occurrenceID: occurrenceID,
            occurrenceDateKey: "2026-09-15",
            outcome: outcome,
            appliedSetAsideAmountCents: outcome == .ignored ? 0 : 1_299
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int
    ) -> Date {
        utcCalendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day
            )
        )!
    }
}
