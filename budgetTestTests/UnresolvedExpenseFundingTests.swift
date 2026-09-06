import SwiftData
import XCTest

@testable import Caldera_Money

@MainActor
final class UnresolvedExpenseFundingTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testJulyFundingRemainsDeductedAcrossAugustBoundary() {
        let expense = PlannerEvent(
            name: "Monthly expense",
            amount: 400,
            date: date(2026, 7, 1),
            frequency: .monthly,
            type: .expense
        )
        let july = ForecastEvent(event: expense, occurrenceDate: date(2026, 7, 1))
        let allocation = EventAllocation(
            occurrenceID: july.occurrenceID,
            sourceEventID: expense.id,
            occurrenceDate: july.occurrenceDate,
            allocatedAmount: 400
        )

        for now in [date(2026, 8, 1), date(2026, 8, 2)] {
            let calculator = PlannerForecastCalculator(
                events: [expense],
                totalAvailable: 2_000,
                totalGoalAllocated: 0,
                includeFutureIncome: false,
                protectGoals: true,
                now: now,
                calendar: calendar
            )
            let deduction = FinancialSummaryCalculator.activeUpcomingExpensesSetAside(
                allocations: [allocation],
                events: [expense],
                occurrenceStatuses: []
            )
            let summary = FinancialSummary(
                cash: 2_000,
                checking: 2_000,
                savings: 0,
                debt: 0,
                netWorth: 2_000,
                savingsGoalsSetAside: 0,
                reserve: 0,
                upcomingExpensesSetAside: deduction,
                debtPaymentsSetAside: 0
            )

            XCTAssertEqual(deduction, 400, accuracy: 0.001, "Funding lost at \(now)")
            XCTAssertEqual(
                summary.safeToSpend, 1_600, accuracy: 0.001, "Available to Spend changed at \(now)")
            XCTAssertEqual(allocation.occurrenceID, july.occurrenceID)
            XCTAssertEqual(allocation.allocatedAmount, 400)
            let funding = snapshot(events: [expense], allocations: [allocation])
            XCTAssertTrue(
                funding.mergingFundedOccurrences(with: calculator.forecastEvents)
                    .contains { $0.occurrenceID == july.occurrenceID })
            XCTAssertTrue(
                funding.reviewableExpenses(
                    in: calculator.forecastEvents, now: now, calendar: calendar
                )
                .contains { $0.occurrenceID == july.occurrenceID })
        }
    }

    func testIndependentlyFundedMissedOccurrencesRemainDistinctAcrossLaterMonths() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let august = forecast(expense, on: date(2026, 8, 1))
        let allocations = [allocation(july, amount: 400), allocation(august, amount: 100)]
        let originalIDs = allocations.map(\.occurrenceID)

        for now in [date(2026, 9, 2), date(2027, 1, 2), date(2030, 9, 2)] {
            let funding = snapshot(events: [expense], allocations: allocations)
            let merged = funding.mergingFundedOccurrences(with: forecasts([expense], now: now))
            let reviewable = funding.reviewableExpenses(in: merged, now: now, calendar: calendar)

            XCTAssertEqual(funding.totalSetAside, 500, accuracy: 0.001)
            XCTAssertEqual(summary(funding).safeToSpend, 1_500, accuracy: 0.001)
            XCTAssertEqual(funding.allocatedAmount(for: july), 400)
            XCTAssertEqual(funding.allocatedAmount(for: august), 100)
            for id in originalIDs {
                XCTAssertEqual(merged.filter { $0.occurrenceID == id }.count, 1)
                XCTAssertEqual(reviewable.filter { $0.occurrenceID == id }.count, 1)
            }
            XCTAssertEqual(allocations.map(\.occurrenceID), originalIDs)
            XCTAssertEqual(allocations.map(\.allocatedAmount), [400, 100])
        }
    }

    func testPaidAndSkipReleaseOnlySelectedOldOccurrenceAndRepeatDoesNotReleaseAgain() throws {
        for resolution in [ExpenseOccurrenceResolution.paid, .skipped] {
            let container = try makeContainer()
            let context = ModelContext(container)
            let expense = monthlyExpense()
            let july = forecast(expense, on: date(2026, 7, 1))
            let august = forecast(expense, on: date(2026, 8, 1))
            let allocations = [allocation(july, amount: 400), allocation(august, amount: 100)]
            context.insert(expense)
            allocations.forEach { context.insert($0) }
            try context.save()

            XCTAssertEqual(snapshot(events: [expense], allocations: allocations).totalSetAside, 500)
            for _ in 0..<2 {
                let statuses = try context.fetch(FetchDescriptor<ExpenseOccurrenceStatus>())
                let result = UpcomingExpenseActionPersistenceCoordinator.resolve(
                    resolution,
                    forecast: july,
                    existingStatus: statuses.first { $0.occurrenceID == july.occurrenceID },
                    modelContext: context,
                    persistChanges: { try context.save() },
                    rollback: { context.rollback() }
                )
                guard case .saved = result else {
                    return XCTFail("Expected manual resolution to save")
                }
                let savedStatuses = try context.fetch(FetchDescriptor<ExpenseOccurrenceStatus>())
                let funding = snapshot(
                    events: [expense], allocations: allocations, statuses: savedStatuses)
                XCTAssertEqual(savedStatuses.count, 1)
                XCTAssertEqual(savedStatuses.first?.status, resolution)
                XCTAssertEqual(funding.totalSetAside, 100)
                XCTAssertEqual(summary(funding).safeToSpend, 1_900)
                XCTAssertEqual(funding.fundedOccurrences.map(\.occurrenceID), [august.occurrenceID])
                XCTAssertEqual(allocations.map(\.allocatedAmount), [400, 100])
            }
        }
    }

    func testWeeklyFundingSurvivesSeveralMissedDatesWithoutFundingOtherOccurrences() {
        let expense = PlannerEvent(
            name: "Weekly expense", amount: 400, date: date(2026, 7, 1), frequency: .weekly,
            type: .expense)
        let first = forecast(expense, on: date(2026, 7, 1))
        let second = forecast(expense, on: date(2026, 7, 8))
        let allocations = [allocation(first, amount: 400), allocation(second, amount: 100)]

        for now in [date(2026, 7, 16), date(2026, 10, 1), date(2028, 10, 1)] {
            let funding = snapshot(events: [expense], allocations: allocations)
            let merged = funding.mergingFundedOccurrences(with: forecasts([expense], now: now))
            XCTAssertEqual(funding.totalSetAside, 500)
            XCTAssertEqual(funding.fundedOccurrences.count, 2)
            XCTAssertEqual(summary(funding).safeToSpend, 1_500)
            XCTAssertEqual(Set(merged.map(\.occurrenceID)).count, merged.count)
            for occurrence in merged
            where !allocations.contains(where: { $0.occurrenceID == occurrence.occurrenceID }) {
                XCTAssertEqual(funding.allocatedAmount(for: occurrence), 0)
            }
            let pastDue = ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
                from: merged, statuses: [], now: now, calendar: calendar
            )
            XCTAssertTrue(pastDue.contains { $0.occurrenceID == first.occurrenceID })
            XCTAssertTrue(pastDue.contains { $0.occurrenceID == second.occurrenceID })
        }
    }

    func testDeductionDoesNotDependOnDisplayHorizonOrPage() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let august = forecast(expense, on: date(2026, 8, 1))
        let allocations = [allocation(july, amount: 400), allocation(august, amount: 100)]
        let now = date(2027, 3, 2)
        let generated = forecasts([expense], now: now)
        let funding = snapshot(events: [expense], allocations: allocations)
        let pages: [[ForecastEvent]] = [
            [], Array(generated.prefix(1)), Array(generated.prefix(3)),
            Array(generated.dropFirst(3)), generated,
        ]

        for page in pages {
            let reviewable = funding.reviewableExpenses(in: page, now: now, calendar: calendar)
            XCTAssertEqual(funding.totalSetAside, 500)
            XCTAssertEqual(summary(funding).safeToSpend, 1_500)
            XCTAssertEqual(reviewable.filter { $0.occurrenceID == july.occurrenceID }.count, 1)
            XCTAssertEqual(reviewable.filter { $0.occurrenceID == august.occurrenceID }.count, 1)
            XCTAssertEqual(Set(reviewable.map(\.occurrenceID)).count, reviewable.count)
        }
    }

    func testFileBackedRelaunchPreservesOldFundingIdentityTotalsAndReviewVisibility() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("UnresolvedExpenseFunding.store")
        let saved = try seedFileBackedStore(at: storeURL)

        try autoreleasepool {
            let container = try makeContainer(at: storeURL)
            let context = ModelContext(container)
            let events = try context.fetch(FetchDescriptor<PlannerEvent>())
            let allocations = try context.fetch(FetchDescriptor<EventAllocation>())
            let statuses = try context.fetch(FetchDescriptor<ExpenseOccurrenceStatus>())
            let now = date(2028, 11, 2)
            let funding = snapshot(events: events, allocations: allocations, statuses: statuses)
            let reviewable = funding.reviewableExpenses(
                in: forecasts(events, now: now), now: now, calendar: calendar)
            let pastDue = ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
                from: reviewable, statuses: statuses, now: now, calendar: calendar
            )

            XCTAssertEqual(events.map(\.id), [saved.eventID])
            XCTAssertEqual(Set(allocations.map(\.id)), Set(saved.allocations.map(\.id)))
            XCTAssertEqual(
                Set(allocations.map(\.occurrenceID)), Set(saved.allocations.map(\.occurrenceID)))
            for original in saved.allocations {
                let reopened = try XCTUnwrap(allocations.first { $0.id == original.id })
                XCTAssertEqual(reopened.sourceEventID, saved.eventID)
                XCTAssertEqual(reopened.occurrenceDate, original.date)
                XCTAssertEqual(reopened.allocatedAmount, original.amount)
                XCTAssertEqual(reopened.createdAt, original.createdAt)
                XCTAssertEqual(reopened.updatedAt, original.updatedAt)
                XCTAssertTrue(reviewable.contains { $0.occurrenceID == original.occurrenceID })
                XCTAssertTrue(pastDue.contains { $0.occurrenceID == original.occurrenceID })
            }
            XCTAssertTrue(statuses.isEmpty)
            XCTAssertEqual(funding.totalSetAside, 500)
            XCTAssertEqual(summary(funding).safeToSpend, 1_500)
            let pager = pagerSnapshot(events: events, allocations: allocations, now: now)
            XCTAssertEqual(pager.upcomingExpenses.totalActiveSetAside, funding.totalSetAside)
            for original in saved.allocations {
                let row = try XCTUnwrap(
                    pager.upcomingExpenses.rows.first { $0.occurrenceID == original.occurrenceID })
                XCTAssertEqual(row.eventID, saved.eventID)
                XCTAssertEqual(row.setAsideAmount, original.amount)
            }
        }
    }

    func testUnknownStatusStaysUnresolvedAndDormantStatusesKeepExistingMeaning() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let allocation = allocation(july, amount: 400)
        let unknown = status(july, resolution: .skipped)
        unknown.statusRawValue = "future-unrecognized-status"
        let funding = snapshot(events: [expense], allocations: [allocation], statuses: [unknown])
        XCTAssertNil(unknown.status)
        XCTAssertEqual(funding.totalSetAside, 400)
        XCTAssertEqual(funding.fundedOccurrences.map(\.occurrenceID), [july.occurrenceID])

        for resolution in [ExpenseOccurrenceResolution.chargedToCard, .postedFromChecking] {
            let record = status(july, resolution: resolution)
            XCTAssertNotEqual(record.status, .paid)
            XCTAssertNotEqual(record.status, .skipped)
            XCTAssertFalse(resolution.isManualResolution)
            XCTAssertEqual(
                snapshot(events: [expense], allocations: [allocation], statuses: [record])
                    .totalSetAside, 0)
            XCTAssertEqual(record.status, resolution)
            XCTAssertEqual(allocation.allocatedAmount, 400)
        }
    }

    func testNoAllocationDoesNotInventFundingAndCoverRequiresExplicitAction() throws {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let context = ModelContext(try makeContainer())
        context.insert(expense)
        try context.save()
        XCTAssertEqual(snapshot(events: [expense], allocations: []).totalSetAside, 0)
        XCTAssertTrue(snapshot(events: [expense], allocations: []).fundedOccurrences.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<EventAllocation>()).isEmpty)

        let result = UpcomingExpenseActionPersistenceCoordinator.coverInFull(
            forecast: july,
            existingAllocation: nil,
            insertAllocation: { context.insert($0) },
            persistChanges: { try context.save() },
            rollback: { context.rollback() }
        )
        XCTAssertTrue(result.didSave)
        let allocations = try context.fetch(FetchDescriptor<EventAllocation>())
        XCTAssertEqual(allocations.count, 1)
        XCTAssertEqual(allocations.first?.occurrenceID, july.occurrenceID)
        XCTAssertEqual(snapshot(events: [expense], allocations: allocations).totalSetAside, 400)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExpenseOccurrenceStatus>()).isEmpty)
    }

    func testExplicitResetAndEventDeletionReleaseOnlyTheirExistingFunding() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let expense = monthlyExpense()
        let july = allocation(forecast(expense, on: date(2026, 7, 1)), amount: 400)
        let august = allocation(forecast(expense, on: date(2026, 8, 1)), amount: 100)
        context.insert(expense)
        context.insert(july)
        context.insert(august)
        try context.save()
        let result = UpcomingExpenseActionPersistenceCoordinator.resetSetAside(
            july,
            deleteAllocation: { context.delete($0) },
            persistChanges: { try context.save() },
            rollback: { context.rollback() }
        )
        XCTAssertTrue(result.didSave)
        let remaining = try context.fetch(FetchDescriptor<EventAllocation>())
        XCTAssertEqual(remaining.map(\.occurrenceID), [august.occurrenceID])
        XCTAssertEqual(snapshot(events: [expense], allocations: remaining).totalSetAside, 100)
        context.delete(expense)
        try context.save()
        XCTAssertEqual(
            snapshot(
                events: try context.fetch(FetchDescriptor<PlannerEvent>()), allocations: remaining
            ).totalSetAside, 0)
    }

    func testDuplicateInputsCountAnExactOccurrenceOnlyOnce() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let allocation = allocation(july, amount: 400)
        let funding = snapshot(events: [expense, expense], allocations: [allocation, allocation])
        let merged = funding.mergingFundedOccurrences(with: [july, july])
        XCTAssertEqual(funding.totalSetAside, 400)
        XCTAssertEqual(funding.fundedOccurrences.count, 1)
        XCTAssertEqual(merged.map(\.occurrenceID), [july.occurrenceID])
    }

    func testLatestDuplicateReductionWinsWithoutDependingOnInputOrder() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let older = allocation(july, amount: 400)
        let reduced = allocation(july, amount: 100)
        reduced.updatedAt = date(2026, 8, 2)
        for records in [[older, reduced], [reduced, older]] {
            XCTAssertEqual(snapshot(events: [expense], allocations: records).totalSetAside, 100)
        }
        reduced.allocatedAmount = 0
        for records in [[older, reduced], [reduced, older]] {
            let funding = snapshot(events: [expense], allocations: records)
            XCTAssertEqual(funding.totalSetAside, 0)
            XCTAssertTrue(funding.fundedOccurrences.isEmpty)
        }
        XCTAssertEqual(older.allocatedAmount, 400)
    }

    func testMalformedOrOrphanedAllocationCannotAttachToAnotherEventAndIsNotMutated() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let missingEvent = monthlyExpense()
        let orphan = allocation(forecast(missingEvent, on: date(2026, 7, 1)), amount: 50)
        let malformed = allocation(july, amount: 70)
        malformed.occurrenceID = "not-an-occurrence-key"
        let invalidDate = allocation(july, amount: 80)
        invalidDate.occurrenceID = "\(expense.id.uuidString)_2026-02-31"
        let records = [orphan, malformed, invalidDate]
        let ids = records.map(\.occurrenceID)
        let amounts = records.map(\.allocatedAmount)
        let funding = snapshot(events: [expense], allocations: records)
        XCTAssertEqual(funding.totalSetAside, 0)
        XCTAssertTrue(funding.fundedOccurrences.isEmpty)
        XCTAssertEqual(records.map(\.occurrenceID), ids)
        XCTAssertEqual(records.map(\.allocatedAmount), amounts)
    }

    func testLegacySourceConflictDoesNotReleaseOrReassignPreviouslyCountedFunding() {
        let expense = monthlyExpense()
        let otherExpense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let record = allocation(july, amount: 60)
        record.sourceEventID = otherExpense.id
        let originalSource = record.sourceEventID
        let previousDeduction = EventAllocationTotals.activeTotal(
            allocations: [record], forecastEvents: [july])
        XCTAssertEqual(previousDeduction, 60)

        for events in [[expense], [expense, otherExpense]] {
            let funding = snapshot(events: events, allocations: [record])
            XCTAssertEqual(funding.totalSetAside, previousDeduction)
            XCTAssertEqual(funding.sourceMismatchOccurrenceIDs, [july.occurrenceID])
            XCTAssertEqual(funding.fundedOccurrences.first?.event.id, expense.id)
            XCTAssertEqual(record.sourceEventID, originalSource)
            XCTAssertEqual(record.occurrenceID, july.occurrenceID)
            XCTAssertEqual(record.allocatedAmount, 60)
        }
    }

    func testRecurrenceEditDoesNotReassignExistingCanonicalFundedOccurrence() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let allocation = allocation(july, amount: 400)
        expense.date = date(2026, 9, 15)
        expense.frequency = .weekly
        let funding = snapshot(events: [expense], allocations: [allocation])
        XCTAssertEqual(funding.totalSetAside, 400)
        XCTAssertEqual(funding.fundedOccurrences.map(\.occurrenceID), [july.occurrenceID])
        XCTAssertEqual(funding.fundedOccurrences.first?.event.id, expense.id)
        XCTAssertEqual(allocation.occurrenceDate, date(2026, 7, 1))
        XCTAssertEqual(allocation.allocatedAmount, 400)
    }

    func testStoredOccurrenceKeyRemainsAuthoritativeWhenAbsoluteDateNoLongerMatchesLocalDay() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let allocation = allocation(july, amount: 400)
        allocation.occurrenceDate = date(2026, 6, 30)
        let originalDate = allocation.occurrenceDate
        let funding = snapshot(events: [expense], allocations: [allocation])
        XCTAssertEqual(funding.totalSetAside, 400)
        XCTAssertEqual(funding.fundedOccurrences.map(\.occurrenceID), [july.occurrenceID])
        XCTAssertEqual(allocation.occurrenceID, july.occurrenceID)
        XCTAssertEqual(allocation.occurrenceDate, originalDate)
    }

    func testOtherSetAsideCategoriesAndExpectedIncomeRemainUnchanged() throws {
        let expense = monthlyExpense()
        let july = allocation(forecast(expense, on: date(2026, 7, 1)), amount: 400)
        let income = PlannerEvent(
            name: "Legacy expected income", amount: 5_000, date: date(2026, 10, 1),
            frequency: .monthly, type: .income)
        let incomeAllocation = allocation(forecast(income, on: date(2026, 10, 1)), amount: 5_000)
        let funding = snapshot(events: [expense, income], allocations: [july, incomeAllocation])
        let checking = PlaidAccount(
            account_id: "fixture-checking", name: "Fixture", official_name: nil, type: "depository",
            subtype: "checking", mask: nil, balances: PlaidBalance(available: 2_000, current: 2_000)
        )
        let goal = SavingsGoal(name: "Fixture goal", targetAmount: 1_000, currentAmount: 100)
        let calculate = {
            FinancialSummaryCalculator.calculate(
                accounts: [checking], goals: [goal], reserveBalance: 200,
                upcomingExpensesSetAside: funding.totalSetAside, debtPaymentsSetAside: 300)
        }
        let before = calculate()
        let schedule = IncomeSchedule(
            ownerScopeID: "synthetic-owner", takeHomeAmountCents: 500_000, frequency: .monthly,
            lastPaydayDateKey: "2026-09-01", nextExpectedPaydayDateKey: "2026-10-01",
            dateBasis: .explicit)
        let incomeContainer = try ModelContainer(
            for: IncomeSchedule.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let incomeContext = ModelContext(incomeContainer)
        incomeContext.insert(schedule)
        try incomeContext.save()
        let after = calculate()
        XCTAssertEqual(try incomeContext.fetch(FetchDescriptor<IncomeSchedule>()).count, 1)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.cash, 2_000)
        XCTAssertEqual(after.savingsGoalsSetAside, 100)
        XCTAssertEqual(after.reserve, 200)
        XCTAssertEqual(after.debtPaymentsSetAside, 300)
        XCTAssertEqual(after.upcomingExpensesSetAside, 400)
        XCTAssertEqual(after.safeToSpend, 1_000)
        XCTAssertEqual(incomeAllocation.allocatedAmount, 5_000)
    }

    func testManagementKeepsCurrentEntryAsWellAsEveryOlderFundedOccurrence() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let august = forecast(expense, on: date(2026, 8, 1))
        let funding = snapshot(events: [expense], allocations: [
            allocation(july, amount: 400), allocation(august, amount: 100)
        ])
        let bounded = forecasts([expense], now: date(2027, 1, 2))
        let management = funding.managementExpenses(in: bounded)
        XCTAssertEqual(management.count, 3)
        XCTAssertTrue(management.contains { $0.occurrenceID == bounded.first?.occurrenceID })
        XCTAssertTrue(management.contains { $0.occurrenceID == july.occurrenceID })
        XCTAssertTrue(management.contains { $0.occurrenceID == august.occurrenceID })
    }

    func testMergingCannotReintroduceKnownResolvedOccurrences() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let allocation = allocation(july, amount: 400)
        let funding = snapshot(events: [expense], allocations: [allocation], statuses: [
            status(july, resolution: .paid)
        ])
        XCTAssertTrue(funding.mergingFundedOccurrences(with: [july]).isEmpty)

        let calculator = PlannerForecastCalculator(
            events: [expense], totalAvailable: 2_000, totalGoalAllocated: 0,
            includeFutureIncome: false, protectGoals: true,
            now: date(2027, 1, 2), calendar: calendar,
            inactiveOccurrenceIDs: [july.occurrenceID],
            fundingSnapshot: snapshot(events: [expense], allocations: [allocation])
        )
        XCTAssertFalse(calculator.forecastEvents.contains { $0.occurrenceID == july.occurrenceID })
    }

    func testCanonicalKeyPreservesFundingDespiteAmbiguousLegacyTimestamp() {
        let expense = monthlyExpense()
        let july = forecast(expense, on: date(2026, 7, 1))
        let record = allocation(july, amount: 400)
        record.occurrenceDate = date(2020, 1, 1)
        let funding = snapshot(events: [expense], allocations: [record])
        XCTAssertEqual(funding.totalSetAside, 400)
        XCTAssertEqual(funding.fundedOccurrences.map(\.occurrenceID), [july.occurrenceID])
        XCTAssertEqual(record.occurrenceDate, date(2020, 1, 1))
        XCTAssertEqual(record.occurrenceID, july.occurrenceID)
        XCTAssertEqual(record.allocatedAmount, 400)
    }

    func testSetAsidePagerAndSharedFinancialSummaryAgreeBeyondPreviewLimit() {
        let expense = monthlyExpense()
        expense.date = date(2026, 1, 1)
        let allocations = (1...5).map {
            allocation(forecast(expense, on: date(2026, $0, 1)), amount: 100)
        }
        let funding = snapshot(events: [expense], allocations: allocations)
        let pager = pagerSnapshot(
            events: [expense], allocations: allocations, now: date(2027, 1, 2))
        let sharedTotal = FinancialSummaryCalculator.activeUpcomingExpensesSetAside(
            allocations: allocations, events: [expense], occurrenceStatuses: [])
        XCTAssertEqual(sharedTotal, 500)
        XCTAssertEqual(pager.upcomingExpenses.totalActiveSetAside, sharedTotal)
        XCTAssertEqual(summary(funding).upcomingExpensesSetAside, sharedTotal)
        XCTAssertEqual(
            pager.upcomingExpenses.rows.count, SetAsidePagerUpcomingSnapshot.summaryLimit)
        XCTAssertTrue(pager.upcomingExpenses.hasAdditionalItems)
        XCTAssertEqual(pager.upcomingExpenses.rows.reduce(0) { $0 + $1.setAsideAmount }, 300)

        let planAhead = PlannerForecastCalculator(
            events: [expense],
            totalAvailable: 2_000,
            totalGoalAllocated: 0,
            protectedEventAllocations: sharedTotal,
            includeFutureIncome: false,
            protectGoals: true,
            now: date(2027, 1, 2),
            calendar: calendar,
            allocatedAmountProvider: { funding.allocatedAmount(for: $0) },
            fundingSnapshot: funding
        )
        XCTAssertEqual(planAhead.safeToSpend, summary(funding).safeToSpend)
        let management = funding.managementExpenses(in: planAhead.forecastEvents)
        for allocation in allocations {
            XCTAssertEqual(
                planAhead.forecastEvents.filter { $0.occurrenceID == allocation.occurrenceID }
                    .count, 1)
            XCTAssertEqual(
                management.filter { $0.occurrenceID == allocation.occurrenceID }.count, 1)
        }
    }

    private func snapshot(
        events: [PlannerEvent], allocations: [EventAllocation],
        statuses: [ExpenseOccurrenceStatus] = []
    ) -> UpcomingExpenseFundingSnapshot {
        UpcomingExpenseFundingSnapshot(
            events: events, allocations: allocations, occurrenceStatuses: statuses)
    }

    private func monthlyExpense() -> PlannerEvent {
        PlannerEvent(
            name: "Monthly expense", amount: 400, date: date(2026, 7, 1), frequency: .monthly,
            type: .expense)
    }

    private func forecast(_ event: PlannerEvent, on date: Date) -> ForecastEvent {
        ForecastEvent(event: event, occurrenceDate: date)
    }

    private func allocation(_ forecast: ForecastEvent, amount: Double) -> EventAllocation {
        EventAllocation(
            occurrenceID: forecast.occurrenceID, sourceEventID: forecast.event.id,
            occurrenceDate: forecast.occurrenceDate, allocatedAmount: amount,
            createdAt: date(2026, 7, 1), updatedAt: date(2026, 8, 1))
    }

    private func status(_ forecast: ForecastEvent, resolution: ExpenseOccurrenceResolution)
        -> ExpenseOccurrenceStatus
    {
        ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID, sourceEventID: forecast.event.id,
            occurrenceDate: forecast.occurrenceDate, status: resolution)
    }

    private func forecasts(_ events: [PlannerEvent], now: Date) -> [ForecastEvent] {
        PlannerForecastCalculator(
            events: events, totalAvailable: 2_000, totalGoalAllocated: 0, includeFutureIncome: true,
            protectGoals: true, now: now, calendar: calendar
        ).forecastEvents
    }

    private func summary(_ funding: UpcomingExpenseFundingSnapshot) -> FinancialSummary {
        FinancialSummary(
            cash: 2_000, checking: 2_000, savings: 0, debt: 0, netWorth: 2_000,
            savingsGoalsSetAside: 0, reserve: 0, upcomingExpensesSetAside: funding.totalSetAside,
            debtPaymentsSetAside: 0)
    }

    private func pagerSnapshot(events: [PlannerEvent], allocations: [EventAllocation], now: Date)
        -> SetAsidePagerSnapshot
    {
        SetAsidePagerSnapshotBuilder.build(
            from: .init(
                reserveBalance: 0, savingsGoals: [], events: events, allocations: allocations,
                occurrenceStatuses: [], paymentPlans: [], paymentPlanCycles: [], debtAccounts: [],
                now: now, calendar: calendar))
    }

    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([PlannerEvent.self, EventAllocation.self, ExpenseOccurrenceStatus.self])
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                "UnresolvedExpenseFunding", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private struct SavedAllocation {
        let id: UUID
        let occurrenceID: String
        let date: Date
        let amount: Double
        let createdAt: Date
        let updatedAt: Date
    }

    private struct SavedFixture {
        let eventID: UUID
        let allocations: [SavedAllocation]
    }

    private func seedFileBackedStore(at url: URL) throws -> SavedFixture {
        try autoreleasepool {
            let container = try makeContainer(at: url)
            let context = ModelContext(container)
            let expense = monthlyExpense()
            let allocations = [
                allocation(forecast(expense, on: date(2026, 7, 1)), amount: 400),
                allocation(forecast(expense, on: date(2026, 8, 1)), amount: 100),
            ]
            context.insert(expense)
            allocations.forEach { context.insert($0) }
            try context.save()
            XCTAssertEqual(snapshot(events: [expense], allocations: allocations).totalSetAside, 500)
            return SavedFixture(
                eventID: expense.id,
                allocations: allocations.map {
                    SavedAllocation(
                        id: $0.id, occurrenceID: $0.occurrenceID, date: $0.occurrenceDate,
                        amount: $0.allocatedAmount, createdAt: $0.createdAt, updatedAt: $0.updatedAt
                    )
                })
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        // Noon UTC avoids a date-key boundary in the test host's local zone.
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
