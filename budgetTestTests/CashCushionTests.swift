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
}
