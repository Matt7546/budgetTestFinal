import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class CashCushionTests: XCTestCase {

    func testBalancePolicyNormalizesInvalidStoredValues() {
        XCTAssertEqual(CashCushionBalancePolicy.normalized(-25), 0)
        XCTAssertEqual(CashCushionBalancePolicy.normalized(.infinity), 0)
        XCTAssertEqual(CashCushionBalancePolicy.normalized(-.infinity), 0)
        XCTAssertEqual(CashCushionBalancePolicy.normalized(.nan), 0)
        XCTAssertEqual(CashCushionBalancePolicy.normalized(125.50), 125.50)
    }

    func testBalancePolicyAddsAndUsesMoneyWithoutGoingNegative() {
        XCTAssertEqual(
            CashCushionBalancePolicy.adding(25, to: 100),
            125
        )
        XCTAssertEqual(
            CashCushionBalancePolicy.using(40, from: 100),
            60
        )
        XCTAssertEqual(
            CashCushionBalancePolicy.using(125, from: 100),
            0
        )
        XCTAssertEqual(
            CashCushionBalancePolicy.adding(.infinity, to: 100),
            100
        )
        XCTAssertEqual(
            CashCushionBalancePolicy.using(.nan, from: 100),
            100
        )
    }

    func testAdjustmentModesUseDestinationAccurateCopy() {
        XCTAssertEqual(CashCushionAdjustmentMode.add.title, "Add money")
        XCTAssertEqual(CashCushionAdjustmentMode.use.title, "Use money")
        XCTAssertEqual(
            CashCushionAdjustmentMode.use.amountSubtitle,
            "Amount to return to Available to Spend."
        )
    }

    func testAddPersistsBeforeReportingSuccess() throws {
        let fixture = try coordinatorFixture(balance: 100)
        var presentedBalance = 100.0
        var didPersist = false

        let result = CashCushionPersistenceCoordinator.add(
            25,
            to: presentedBalance,
            settings: fixture.settings,
            applyBalance: { presentedBalance = $0 },
            insertSettings: fixture.context.insert,
            persistChanges: {
                XCTAssertEqual(presentedBalance, 125, accuracy: 0.001)
                XCTAssertEqual(
                    fixture.settings.balance,
                    125,
                    accuracy: 0.001
                )
                try fixture.context.save()
                didPersist = true
            },
            rollback: fixture.context.rollback
        )

        XCTAssertTrue(didPersist)
        XCTAssertEqual(result, .saved(balance: 125))
        XCTAssertEqual(presentedBalance, 125, accuracy: 0.001)
        XCTAssertEqual(
            try persistedReserveBalance(in: fixture.context),
            125,
            accuracy: 0.001
        )
    }

    func testUsePersistsBeforeReportingSuccess() throws {
        let fixture = try coordinatorFixture(balance: 100)
        var presentedBalance = 100.0
        var didPersist = false

        let result = CashCushionPersistenceCoordinator.use(
            40,
            from: presentedBalance,
            settings: fixture.settings,
            applyBalance: { presentedBalance = $0 },
            insertSettings: fixture.context.insert,
            persistChanges: {
                XCTAssertEqual(presentedBalance, 60, accuracy: 0.001)
                XCTAssertEqual(
                    fixture.settings.balance,
                    60,
                    accuracy: 0.001
                )
                try fixture.context.save()
                didPersist = true
            },
            rollback: fixture.context.rollback
        )

        XCTAssertTrue(didPersist)
        XCTAssertEqual(result, .saved(balance: 60))
        XCTAssertEqual(presentedBalance, 60, accuracy: 0.001)
        XCTAssertEqual(
            try persistedReserveBalance(in: fixture.context),
            60,
            accuracy: 0.001
        )
    }

    func testFailedAddRestoresPreviousBalance() throws {
        let fixture = try coordinatorFixture(balance: 100)
        var presentedBalance = 100.0
        var didRollback = false

        let result = CashCushionPersistenceCoordinator.add(
            25,
            to: presentedBalance,
            settings: fixture.settings,
            applyBalance: { presentedBalance = $0 },
            insertSettings: fixture.context.insert,
            persistChanges: {
                throw CashCushionTestError.saveFailed
            },
            rollback: {
                didRollback = true
                fixture.context.rollback()
            }
        )

        XCTAssertEqual(
            result,
            .failed(
                message: CashCushionPersistenceCoordinator.failureMessage
            )
        )
        XCTAssertTrue(didRollback)
        XCTAssertEqual(presentedBalance, 100, accuracy: 0.001)
        XCTAssertEqual(fixture.settings.balance, 100, accuracy: 0.001)
        XCTAssertEqual(
            try persistedReserveBalance(in: fixture.context),
            100,
            accuracy: 0.001
        )
    }

    func testFailedUseRestoresPreviousBalance() throws {
        let fixture = try coordinatorFixture(balance: 100)
        var presentedBalance = 100.0

        let result = CashCushionPersistenceCoordinator.use(
            40,
            from: presentedBalance,
            settings: fixture.settings,
            applyBalance: { presentedBalance = $0 },
            insertSettings: fixture.context.insert,
            persistChanges: {
                throw CashCushionTestError.saveFailed
            },
            rollback: fixture.context.rollback
        )

        XCTAssertEqual(
            result,
            .failed(
                message: CashCushionPersistenceCoordinator.failureMessage
            )
        )
        XCTAssertEqual(presentedBalance, 100, accuracy: 0.001)
        XCTAssertEqual(fixture.settings.balance, 100, accuracy: 0.001)
        XCTAssertEqual(
            try persistedReserveBalance(in: fixture.context),
            100,
            accuracy: 0.001
        )
    }

    func testUseCannotExceedCurrentBalance() throws {
        let fixture = try coordinatorFixture(balance: 100)
        var presentedBalance = 100.0
        var didMutate = false
        var didPersist = false

        let result = CashCushionPersistenceCoordinator.use(
            100.01,
            from: presentedBalance,
            settings: fixture.settings,
            applyBalance: {
                didMutate = true
                presentedBalance = $0
            },
            insertSettings: fixture.context.insert,
            persistChanges: {
                didPersist = true
                try fixture.context.save()
            },
            rollback: fixture.context.rollback
        )

        XCTAssertFalse(didMutate)
        XCTAssertFalse(didPersist)
        XCTAssertFalse(result.didSave)
        XCTAssertEqual(presentedBalance, 100, accuracy: 0.001)
        XCTAssertEqual(fixture.settings.balance, 100, accuracy: 0.001)
    }

    func testZeroBalanceCannotBeUsed() throws {
        let fixture = try coordinatorFixture(balance: 0)
        var didMutate = false
        var didPersist = false

        let result = CashCushionPersistenceCoordinator.use(
            1,
            from: 0,
            settings: fixture.settings,
            applyBalance: { _ in didMutate = true },
            insertSettings: fixture.context.insert,
            persistChanges: {
                didPersist = true
                try fixture.context.save()
            },
            rollback: fixture.context.rollback
        )

        XCTAssertFalse(didMutate)
        XCTAssertFalse(didPersist)
        XCTAssertFalse(result.didSave)
        XCTAssertEqual(fixture.settings.balance, 0, accuracy: 0.001)
    }

    func testSaveGatePreventsDuplicateSubmissions() {
        var gate = CashCushionSaveGate()

        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())
        XCTAssertTrue(gate.isSaving)

        gate.finish()

        XCTAssertFalse(gate.isSaving)
        XCTAssertTrue(gate.begin())
    }

    func testPersistedBalanceLoadsAndAdjustmentsReuseSingleRecord() throws {
        let fixture = try persistenceFixture(balance: 100)

        XCTAssertEqual(fixture.service.reserveBalance, 100, accuracy: 0.001)

        fixture.service.addToReserve(25)
        XCTAssertEqual(fixture.service.reserveBalance, 125, accuracy: 0.001)

        fixture.service.subtractFromReserve(50)
        XCTAssertEqual(fixture.service.reserveBalance, 75, accuracy: 0.001)

        let records = try fixture.context.fetch(
            FetchDescriptor<ReserveSettings>()
        )
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].balance, 75, accuracy: 0.001)
    }

    func testInvalidPersistedBalanceCannotIncreaseAvailableToSpend() throws {
        let fixture = try persistenceFixture(balance: -100)

        XCTAssertEqual(fixture.service.reserveBalance, 0, accuracy: 0.001)

        fixture.service.addToReserve(25)

        let record = try XCTUnwrap(
            fixture.context.fetch(FetchDescriptor<ReserveSettings>()).first
        )
        XCTAssertEqual(fixture.service.reserveBalance, 25, accuracy: 0.001)
        XCTAssertEqual(record.balance, 25, accuracy: 0.001)
    }

    func testUsingMoreThanBalancePersistsZero() throws {
        let fixture = try persistenceFixture(balance: 60)

        fixture.service.subtractFromReserve(75)

        let record = try XCTUnwrap(
            fixture.context.fetch(FetchDescriptor<ReserveSettings>()).first
        )
        XCTAssertEqual(fixture.service.reserveBalance, 0, accuracy: 0.001)
        XCTAssertEqual(record.balance, 0, accuracy: 0.001)
    }

    func testSignOutRemovesCashCushionData() throws {
        let fixture = try persistenceFixture(balance: 80)

        fixture.service.clearLocalFinancialDataForSignOut()

        XCTAssertEqual(fixture.service.reserveBalance, 0, accuracy: 0.001)
        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<ReserveSettings>()).isEmpty
        )
    }

    func testAccountDeletionRemovesCashCushionData() throws {
        let fixture = try persistenceFixture(balance: 80)

        fixture.service.clearLocalFinancialDataForDeletedUser(
            userID: "user-a"
        )

        XCTAssertEqual(fixture.service.reserveBalance, 0, accuracy: 0.001)
        XCTAssertTrue(
            try fixture.context.fetch(FetchDescriptor<ReserveSettings>()).isEmpty
        )
    }

    private func persistenceFixture(
        balance: Double
    ) throws -> (
        service: PlaidService,
        context: ModelContext
    ) {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self,
            IncomeSchedule.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.insert(ReserveSettings(balance: balance))
        try context.save()

        let service = PlaidService()
        service.configurePersistence(modelContext: context)

        return (service, context)
    }

    private func coordinatorFixture(
        balance: Double
    ) throws -> (
        context: ModelContext,
        settings: ReserveSettings
    ) {
        let schema = Schema([ReserveSettings.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let settings = ReserveSettings(balance: balance)
        context.insert(settings)
        try context.save()

        return (context, settings)
    }

    private func persistedReserveBalance(
        in context: ModelContext
    ) throws -> Double {
        try XCTUnwrap(
            context.fetch(FetchDescriptor<ReserveSettings>()).first
        ).balance
    }
}

private enum CashCushionTestError: Error {
    case saveFailed
}
