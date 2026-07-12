import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class IncomeScheduleTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testWeeklyNextPaydayUsesSevenCalendarDays() throws {
        let next = try XCTUnwrap(
            IncomeScheduleCalendar.calculatedNextPayday(
                frequency: .weekly,
                lastPayday: date(2026, 7, 3),
                today: date(2026, 7, 4),
                calendar: utcCalendar
            )
        )

        XCTAssertEqual(dateKey(next), "2026-07-10")
    }

    func testBiweeklyNextPaydayUsesFourteenCalendarDays() throws {
        let next = try XCTUnwrap(
            IncomeScheduleCalendar.calculatedNextPayday(
                frequency: .biweekly,
                lastPayday: date(2026, 7, 3),
                today: date(2026, 7, 4),
                calendar: utcCalendar
            )
        )

        XCTAssertEqual(dateKey(next), "2026-07-17")
    }

    func testOldAnchorAdvancesToFirstOccurrenceOnOrAfterToday() throws {
        let next = try XCTUnwrap(
            IncomeScheduleCalendar.calculatedNextPayday(
                frequency: .weekly,
                lastPayday: date(2026, 6, 1),
                today: date(2026, 7, 12),
                calendar: utcCalendar
            )
        )

        XCTAssertEqual(dateKey(next), "2026-07-13")
    }

    func testWeeklyDateSurvivesDaylightSavingTransition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/New_York")
        )
        let next = try XCTUnwrap(
            IncomeScheduleCalendar.calculatedNextPayday(
                frequency: .weekly,
                lastPayday: date(
                    2026,
                    3,
                    7,
                    calendar: calendar
                ),
                today: date(
                    2026,
                    3,
                    8,
                    calendar: calendar
                ),
                calendar: calendar
            )
        )

        XCTAssertEqual(
            IncomeScheduleCalendar.dateKey(
                for: next,
                calendar: calendar
            ),
            "2026-03-14"
        )
    }

    func testLeapDayAndInvalidCalendarDates() throws {
        XCTAssertEqual(
            dateKey(
                try XCTUnwrap(
                    IncomeScheduleCalendar.date(
                        from: "2024-02-29",
                        calendar: utcCalendar
                    )
                )
            ),
            "2024-02-29"
        )
        XCTAssertNil(
            IncomeScheduleCalendar.date(
                from: "2025-02-29",
                calendar: utcCalendar
            )
        )
        XCTAssertNil(
            IncomeScheduleCalendar.date(
                from: "2026-13-01",
                calendar: utcCalendar
            )
        )
        XCTAssertNil(
            IncomeScheduleCalendar.date(
                from: "not-a-date",
                calendar: utcCalendar
            )
        )
    }

    func testWeeklyMonthEndAndYearBoundary() throws {
        let monthEnd = try XCTUnwrap(
            IncomeScheduleCalendar.calculatedNextPayday(
                frequency: .weekly,
                lastPayday: date(2026, 1, 31),
                today: date(2026, 2, 1),
                calendar: utcCalendar
            )
        )
        let yearEnd = try XCTUnwrap(
            IncomeScheduleCalendar.calculatedNextPayday(
                frequency: .weekly,
                lastPayday: date(2026, 12, 27),
                today: date(2026, 12, 28),
                calendar: utcCalendar
            )
        )

        XCTAssertEqual(dateKey(monthEnd), "2026-02-07")
        XCTAssertEqual(dateKey(yearEnd), "2027-01-03")
    }

    func testFutureLastPaydayAndIntervalInferenceAreRejected() {
        XCTAssertFalse(
            IncomeScheduleCalendar.isValidLastPayday(
                date(2026, 7, 13),
                today: date(2026, 7, 12),
                calendar: utcCalendar
            )
        )
        XCTAssertNil(
            IncomeScheduleCalendar.calculatedNextPayday(
                frequency: .monthly,
                lastPayday: date(2026, 7, 1),
                today: date(2026, 7, 12),
                calendar: utcCalendar
            )
        )
        XCTAssertNil(
            IncomeScheduleCalendar.calculatedNextPayday(
                frequency: .twiceMonthly,
                lastPayday: date(2026, 7, 1),
                today: date(2026, 7, 12),
                calendar: utcCalendar
            )
        )
    }

    func testDraftCreatesCorrectCalculatedConfirmationWithoutPersistence() throws {
        let container = try inMemoryIncomeContainer()
        let context = ModelContext(container)
        let draft = IncomeScheduleDraft(
            takeHomeAmountText: "$1,850.25",
            frequency: .biweekly,
            lastPayday: date(2026, 7, 3),
            explicitNextPayday: date(2026, 7, 4)
        )

        let confirmation = try XCTUnwrap(
            draft.confirmation(
                ownerScopeID: "scope-a",
                today: date(2026, 7, 12),
                calendar: utcCalendar
            )
        )

        XCTAssertTrue(
            try context.fetch(FetchDescriptor<IncomeSchedule>()).isEmpty
        )
        XCTAssertEqual(confirmation.takeHomeAmountCents, 185_025)
        XCTAssertEqual(confirmation.frequency, .biweekly)
        XCTAssertEqual(confirmation.lastPaydayDateKey, "2026-07-03")
        XCTAssertEqual(confirmation.nextExpectedPaydayDateKey, "2026-07-17")
        XCTAssertEqual(confirmation.dateBasis, .calculated)
    }

    func testSaveIsTheFirstPersistenceMutation() throws {
        let container = try inMemoryIncomeContainer()
        let context = ModelContext(container)
        let confirmation = try XCTUnwrap(
            IncomeScheduleDraft(
                takeHomeAmountText: "900.00",
                frequency: .weekly,
                lastPayday: date(2026, 7, 10),
                explicitNextPayday: date(2026, 7, 11)
            )
            .confirmation(
                ownerScopeID: "scope-a",
                today: date(2026, 7, 12),
                calendar: utcCalendar
            )
        )

        XCTAssertTrue(
            try context.fetch(FetchDescriptor<IncomeSchedule>()).isEmpty
        )

        try IncomeScheduleSaveCoordinator.save(
            confirmation,
            editing: nil,
            in: context,
            now: date(2026, 7, 12)
        )

        let saved = try context.fetch(FetchDescriptor<IncomeSchedule>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].takeHomeAmountCents, 90_000)
        XCTAssertEqual(saved[0].ownerScopeID, "scope-a")
    }

    func testDetachedEditDoesNotMutateUntilSave() throws {
        let container = try inMemoryIncomeContainer()
        let context = ModelContext(container)
        let schedule = incomeSchedule(
            ownerScopeID: "scope-a",
            cents: 100_000
        )
        context.insert(schedule)
        try context.save()

        var draft = IncomeScheduleDraft(
            schedule: schedule,
            today: date(2026, 7, 12),
            calendar: utcCalendar
        )
        draft.takeHomeAmountText = "1200.00"
        let confirmation = try XCTUnwrap(
            draft.confirmation(
                ownerScopeID: "scope-a",
                today: date(2026, 7, 12),
                calendar: utcCalendar
            )
        )

        XCTAssertEqual(schedule.takeHomeAmountCents, 100_000)

        try IncomeScheduleSaveCoordinator.save(
            confirmation,
            editing: schedule,
            in: context,
            now: date(2026, 7, 12)
        )

        XCTAssertEqual(schedule.takeHomeAmountCents, 120_000)
    }

    func testTwiceMonthlyAndMonthlyRequireExplicitNextPayday() throws {
        for frequency in [
            IncomeScheduleFrequency.twiceMonthly,
            .monthly
        ] {
            let valid = IncomeScheduleDraft(
                takeHomeAmountText: "1000",
                frequency: frequency,
                lastPayday: date(2026, 7, 1),
                explicitNextPayday: date(2026, 7, 15)
            )
            let invalid = IncomeScheduleDraft(
                takeHomeAmountText: "1000",
                frequency: frequency,
                lastPayday: date(2026, 7, 1),
                explicitNextPayday: date(2026, 7, 10)
            )

            XCTAssertEqual(
                valid.confirmation(
                    ownerScopeID: "scope-a",
                    today: date(2026, 7, 12),
                    calendar: utcCalendar
                )?.dateBasis,
                .explicit
            )
            XCTAssertNil(
                invalid.confirmation(
                    ownerScopeID: "scope-a",
                    today: date(2026, 7, 12),
                    calendar: utcCalendar
                )
            )
        }
    }

    func testPassedExplicitDateRequiresUpdateAndDoesNotRollForward() {
        let schedule = IncomeSchedule(
            ownerScopeID: "scope-a",
            takeHomeAmountCents: 100_000,
            frequency: .monthly,
            lastPaydayDateKey: "2026-06-15",
            nextExpectedPaydayDateKey: "2026-07-10",
            dateBasis: .explicit
        )

        XCTAssertTrue(
            IncomeScheduleCalendar.needsExplicitPaydayUpdate(
                schedule,
                today: date(2026, 7, 12),
                calendar: utcCalendar
            )
        )
        XCTAssertNil(
            IncomeScheduleCalendar.nextDisplayDate(
                for: schedule,
                today: date(2026, 7, 12),
                calendar: utcCalendar
            )
        )
    }

    func testPhaseOnePolicyShowsOnlyOneExactScopeSchedule() {
        let first = incomeSchedule(
            ownerScopeID: "scope-a",
            cents: 100_000,
            sortOrder: 0
        )
        let futureSource = incomeSchedule(
            ownerScopeID: "scope-a",
            cents: 200_000,
            sortOrder: 1
        )
        let otherUser = incomeSchedule(
            ownerScopeID: "scope-b",
            cents: 300_000,
            sortOrder: 0
        )

        XCTAssertEqual(
            IncomeSchedulePhaseOnePolicy.visibleSchedule(
                from: [futureSource, otherUser, first],
                ownerScopeID: "scope-a"
            )?.id,
            first.id
        )
        XCTAssertEqual(
            IncomeSchedulePhaseOnePolicy.visibleSchedule(
                from: [futureSource, otherUser, first],
                ownerScopeID: "scope-b"
            )?.id,
            otherUser.id
        )
        XCTAssertNil(
            IncomeSchedulePhaseOnePolicy.visibleSchedule(
                from: [futureSource, otherUser, first],
                ownerScopeID: "scope-c"
            )
        )
    }

    func testOwnerScopesAreStableAndIsolatedAcrossUsersAndSignedOutState() {
        let userA = IncomeScheduleOwnerScope.current(
            authenticatedUserID: "user-a"
        )
        let userAAgain = IncomeScheduleOwnerScope.current(
            authenticatedUserID: " user-a "
        )
        let userB = IncomeScheduleOwnerScope.current(
            authenticatedUserID: "user-b"
        )
        let signedOut = IncomeScheduleOwnerScope.current(
            authenticatedUserID: nil
        )

        XCTAssertEqual(userA, userAAgain)
        XCTAssertNotEqual(userA, userB)
        XCTAssertNotEqual(userA, signedOut)
        XCTAssertNotEqual(userB, signedOut)
    }

    func testSaveRejectsCrossScopeEditing() throws {
        let container = try inMemoryIncomeContainer()
        let context = ModelContext(container)
        let schedule = incomeSchedule(
            ownerScopeID: "scope-a",
            cents: 100_000
        )
        context.insert(schedule)
        try context.save()
        let confirmation = IncomeScheduleConfirmation(
            ownerScopeID: "scope-b",
            sourceLabel: "Paycheck",
            takeHomeAmountCents: 200_000,
            frequency: .weekly,
            lastPaydayDateKey: "2026-07-10",
            nextExpectedPaydayDateKey: "2026-07-17",
            dateBasis: .calculated,
            sortOrder: 0
        )

        XCTAssertThrowsError(
            try IncomeScheduleSaveCoordinator.save(
                confirmation,
                editing: schedule,
                in: context
            )
        )
        XCTAssertEqual(schedule.takeHomeAmountCents, 100_000)
    }

    func testSignOutCleanupRemovesIncomeSchedules() throws {
        let fixture = try persistenceFixture()
        fixture.service.clearLocalFinancialDataForSignOut()
        XCTAssertTrue(
            try fixture.context.fetch(
                FetchDescriptor<IncomeSchedule>()
            ).isEmpty
        )
    }

    func testAccountDeletionCleanupRemovesIncomeSchedules() throws {
        let fixture = try persistenceFixture()
        fixture.service.clearLocalFinancialDataForDeletedUser(
            userID: "user-a"
        )
        XCTAssertTrue(
            try fixture.context.fetch(
                FetchDescriptor<IncomeSchedule>()
            ).isEmpty
        )
    }

    #if DEBUG
    func testDebugResetRemovesIncomeSchedules() throws {
        let fixture = try persistenceFixture()
        fixture.service.debugResetLocalUserData()
        XCTAssertTrue(
            try fixture.context.fetch(
                FetchDescriptor<IncomeSchedule>()
            ).isEmpty
        )
    }
    #endif

    func testIncomeScheduleDoesNotChangeFinancialOrForecastBoundaries() {
        let checking = PlaidAccount(
            account_id: "checking",
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
        let expense = PlannerEvent(
            name: "Rent",
            amount: 1_000,
            date: date(2026, 7, 20),
            frequency: .once,
            type: .expense
        )
        let schedule = incomeSchedule(
            ownerScopeID: "scope-a",
            cents: 500_000
        )

        let summaryBefore = FinancialSummaryCalculator.calculate(
            accounts: [checking],
            goals: []
        )
        let forecastsBefore = PlannerForecastCalculator(
            events: [expense],
            totalAvailable: summaryBefore.safeToSpend,
            totalGoalAllocated: 0,
            includeFutureIncome: true,
            protectGoals: true,
            now: date(2026, 7, 12),
            calendar: utcCalendar
        )
        let nextActionBefore = DashboardNextActionPriority.resolve(
            hasBankRefreshWarning: false,
            needsAccountScope: false,
            pastDueExpense: nil,
            hasSuggestedUpdate: false,
            upcomingExpenseNeedingMoney: forecastsBefore.nextExpense,
            hasPaymentPlanNeedingMoney: false
        )
        let expenseForecast = forecastsBefore.forecastEvents[0]
        let allocation = EventAllocation(
            occurrenceID: expenseForecast.occurrenceID,
            sourceEventID: expense.id,
            occurrenceDate: expenseForecast.occurrenceDate,
            allocatedAmount: 400
        )
        let setAsideBefore = EventAllocationTotals.activeTotal(
            allocations: [allocation],
            forecastEvents: forecastsBefore.forecastEvents
        )

        XCTAssertEqual(schedule.takeHomeAmountCents, 500_000)
        XCTAssertEqual(summaryBefore.safeToSpend, 2_000, accuracy: 0.001)
        XCTAssertEqual(setAsideBefore, 400, accuracy: 0.001)
        XCTAssertEqual(forecastsBefore.forecastEvents.count, 1)
        XCTAssertEqual(forecastsBefore.forecastEvents[0].event.id, expense.id)

        guard case .upcomingNeedsMoney(let selected) = nextActionBefore else {
            return XCTFail("Expected the existing expense action")
        }

        XCTAssertEqual(selected.event.id, expense.id)
    }

    func testLegacyIncomeForecastBehaviorRemainsUnchanged() throws {
        let legacyIncome = PlannerEvent(
            name: "Legacy income",
            amount: 900,
            date: date(2026, 7, 20),
            frequency: .once,
            type: .income
        )
        let calculator = PlannerForecastCalculator(
            events: [legacyIncome],
            totalAvailable: 100,
            totalGoalAllocated: 0,
            includeFutureIncome: true,
            protectGoals: true,
            now: date(2026, 7, 1),
            calendar: utcCalendar
        )
        let forecast = try XCTUnwrap(calculator.forecastEvents.first)

        XCTAssertEqual(forecast.event.type, .income)
        XCTAssertEqual(
            calculator.projectedAvailable(after: forecast),
            1_000,
            accuracy: 0.001
        )
    }

    func testAdditiveMigrationPreservesExistingFinancialRecords() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent("Caldera.store")
        try createLegacyStore(at: storeURL)

        let newSchema = Schema(currentModelTypes + [IncomeSchedule.self])
        let newConfiguration = ModelConfiguration(
            "CalderaMigrationTest",
            schema: newSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let migratedContainer = try ModelContainer(
            for: newSchema,
            configurations: [newConfiguration]
        )
        let context = ModelContext(migratedContainer)

        let events = try context.fetch(FetchDescriptor<PlannerEvent>())
        let goals = try context.fetch(FetchDescriptor<SavingsGoalRecord>())
        let reserves = try context.fetch(FetchDescriptor<ReserveSettings>())
        let incomeSchedules = try context.fetch(
            FetchDescriptor<IncomeSchedule>()
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].name, "Rent")
        XCTAssertEqual(goals.count, 1)
        XCTAssertEqual(goals[0].name, "Emergency")
        XCTAssertEqual(reserves.count, 1)
        XCTAssertEqual(reserves[0].balance, 250, accuracy: 0.001)
        XCTAssertTrue(incomeSchedules.isEmpty)
    }

    private var currentModelTypes: [any PersistentModel.Type] {
        [
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self
        ]
    }

    private func createLegacyStore(at url: URL) throws {
        let oldSchema = Schema(currentModelTypes)
        let oldConfiguration = ModelConfiguration(
            "CalderaMigrationTest",
            schema: oldSchema,
            url: url,
            cloudKitDatabase: .none
        )
        let oldContainer = try ModelContainer(
            for: oldSchema,
            configurations: [oldConfiguration]
        )
        let context = ModelContext(oldContainer)
        context.insert(
            PlannerEvent(
                name: "Rent",
                amount: 1_500,
                date: date(2026, 8, 1),
                frequency: .monthly,
                type: .expense
            )
        )
        context.insert(
            SavingsGoalRecord(
                name: "Emergency",
                targetAmount: 2_000,
                currentAmount: 500
            )
        )
        context.insert(ReserveSettings(balance: 250))
        try context.save()
    }

    private func inMemoryIncomeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: IncomeSchedule.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true
            )
        )
    }

    private func persistenceFixture() throws -> (
        service: PlaidService,
        context: ModelContext
    ) {
        let schema = Schema(currentModelTypes + [IncomeSchedule.self])
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
        context.insert(
            incomeSchedule(
                ownerScopeID: "scope-a",
                cents: 100_000
            )
        )
        try context.save()

        let service = PlaidService()
        service.configurePersistence(modelContext: context)
        return (service, context)
    }

    private func incomeSchedule(
        ownerScopeID: String,
        cents: Int64,
        sortOrder: Int = 0
    ) -> IncomeSchedule {
        IncomeSchedule(
            ownerScopeID: ownerScopeID,
            takeHomeAmountCents: cents,
            frequency: .biweekly,
            lastPaydayDateKey: "2026-07-03",
            nextExpectedPaydayDateKey: "2026-07-17",
            dateBasis: .calculated,
            createdAt: date(2026, 7, 1),
            updatedAt: date(2026, 7, 1),
            sortOrder: sortOrder
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        calendar: Calendar? = nil
    ) -> Date {
        let calendar = calendar ?? utcCalendar
        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day
            )
        )!
    }

    private func dateKey(_ date: Date) -> String {
        IncomeScheduleCalendar.dateKey(
            for: date,
            calendar: utcCalendar
        )
    }
}
