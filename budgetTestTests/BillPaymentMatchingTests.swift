import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class BillPaymentMatchingTests: XCTestCase {
    private let userA = "bill-match-user-a"
    private let userB = "bill-match-user-b"
    private let refreshDate = Date(timeIntervalSince1970: 1_789_603_200)

    func testStrongMatchRequiresPostedAccountProvenanceAmountAndCompleteWindow() throws {
        let fixture = makeFixture()
        let match = try XCTUnwrap(matches(fixture).first)
        XCTAssertEqual(matches(fixture).count, 1)
        XCTAssertEqual(match.occurrenceID, fixture.forecast.occurrenceID)
        XCTAssertEqual(match.transactionID, "txn-1")
        XCTAssertEqual(match.accountID, "checking-1")
        XCTAssertEqual(match.amountCents, 10_000)
    }

    func testPendingAndIncompleteHistoryNeverSuggest() {
        var fixture = makeFixture()
        fixture.transactions[0].pending = true
        XCTAssertTrue(matches(fixture).isEmpty)

        fixture = makeFixture()
        fixture.metadata = metadata(
            count: 1, complete: false
        )
        XCTAssertTrue(matches(fixture).isEmpty)
        fixture = makeFixture()
        fixture.metadata = TransactionSnapshotMetadata(
            windowStart: "2026-09-13", windowEnd: "2026-09-17",
            lookbackDays: 4, totalTransactions: 2,
            returnedTransactions: 1, complete: true,
            partialFailure: false
        )
        XCTAssertTrue(matches(fixture).isEmpty)
        fixture = makeFixture()
        XCTAssertTrue(matches(fixture, automationIsEligible: false).isEmpty)
        XCTAssertTrue(matches(fixture, snapshotRefreshDate: nil).isEmpty)
        fixture = makeFixture()
        XCTAssertTrue(matches(fixture, balancesAreCurrent: false).isEmpty)
    }

    func testCrossUserAndCrossAccountFailClosed() {
        var fixture = makeFixture()
        XCTAssertTrue(matches(fixture, snapshotOwnerUserID: userB).isEmpty)
        XCTAssertTrue(matches(fixture, ownerUserID: userB).isEmpty)

        fixture.transactions[0].account_id = "checking-2"
        fixture.accounts.append(account("checking-2"))
        XCTAssertTrue(matches(fixture).isEmpty)
    }

    func testStaleSnapshotAndItemMismatchDoNotSuggest() {
        var fixture = makeFixture()
        fixture.transactions[0].item_id = "different-item"
        XCTAssertTrue(matches(fixture).isEmpty)

        fixture = makeFixture()
        XCTAssertTrue(BillPaymentMatcher.suggestions(
            ownerUserID: userA,
            snapshotOwnerUserID: userA,
            snapshotGeneration: 1,
            snapshotRefreshDate: refreshDate,
            forecasts: fixture.forecasts,
            statuses: [],
            decisions: [],
            history: fixture.history,
            accounts: fixture.accounts,
            transactions: fixture.transactions,
            metadata: fixture.metadata,
            balancesAreCurrent: true,
            automationIsEligible: true,
            now: refreshDate.addingTimeInterval(25 * 60 * 60)
        ).isEmpty)
    }

    func testMerchantAmountDateAndCardPaymentExclusions() {
        var fixture = makeFixture()
        fixture.transactions[0] = transaction(name: "Other Merchant")
        XCTAssertTrue(matches(fixture).isEmpty)

        fixture = makeFixture()
        fixture.transactions[0] = transaction(amount: 105)
        XCTAssertTrue(matches(fixture).isEmpty)

        fixture = makeFixture()
        fixture.transactions[0] = transaction(date: "2026-09-12")
        XCTAssertTrue(matches(fixture).isEmpty)

        fixture = makeFixture()
        fixture.transactions[0] = transaction(name: "Electric Utility Card Payment")
        XCTAssertTrue(matches(fixture).isEmpty)
    }

    func testTwoPlausibleTransactionsOrTwoCompetingOccurrencesDoNotSuggest() {
        var fixture = makeFixture()
        fixture.transactions.append(
            transaction(id: "txn-2", date: "2026-09-16")
        )
        fixture.metadata = metadata(count: 2)
        XCTAssertTrue(matches(fixture).isEmpty)

        fixture = makeFixture()
        let competingForecast = ForecastEvent(
            event: fixture.event,
            occurrenceDate: date("2026-09-16")
        )
        fixture.forecasts.append(competingForecast)
        fixture.metadata = metadata(count: 1, end: "2026-09-18")
        XCTAssertTrue(matches(fixture).isEmpty)
    }

    func testConfirmResolvesOnlyExactOccurrenceUsingExistingFundingLogic() throws {
        let fixture = makeFixture()
        let match = try XCTUnwrap(matches(fixture).first)
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(fixture.event)
        context.insert(EventAllocation(
            ownerScopeID: fixture.event.ownerScopeID,
            occurrenceID: fixture.forecast.occurrenceID,
            sourceEventID: fixture.event.id,
            occurrenceDate: fixture.forecast.normalizedOccurrenceDate,
            allocatedAmount: 40
        ))
        try context.save()

        XCTAssertEqual(
            try funding(in: context, for: userA).totalSetAside, 40,
            accuracy: 0.001
        )
        XCTAssertEqual(decide(.released, match: match, fixture: fixture, in: context), .saved)
        XCTAssertEqual(
            try funding(in: context, for: userA).totalSetAside, 0,
            accuracy: 0.001
        )
        let statuses = try context.fetch(FetchDescriptor<ExpenseOccurrenceStatus>())
        let status = try XCTUnwrap(statuses.first)
        XCTAssertEqual(status.occurrenceID, match.occurrenceID)
        XCTAssertEqual(status.status, .postedFromChecking)
        XCTAssertEqual(statuses.count, 1)
        let decisions = try context.fetch(
            FetchDescriptor<TransactionMatchedExpenseResolution>()
        )
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions[0].outcome, .released)
        XCTAssertEqual(decisions[0].appliedSetAsideAmountCents, 4_000)
        XCTAssertEqual(decide(.released, match: match, fixture: fixture, in: context), .stale)
    }

    func testDismissSuppressesOnlyExactMatchAndKeepsFutureOccurrence() throws {
        var fixture = makeFixture()
        let future = ForecastEvent(
            event: fixture.event,
            occurrenceDate: date("2026-10-15")
        )
        fixture.forecasts.append(future)
        fixture.transactions.append(transaction(id: "txn-2", date: "2026-10-15"))
        fixture.metadata = metadata(count: 2, end: "2026-10-17")
        let initial = matches(fixture)
        XCTAssertEqual(initial.count, 2)
        let september = try XCTUnwrap(initial.first {
            $0.occurrenceID == fixture.forecast.occurrenceID
        })
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(fixture.event)
        try context.save()

        XCTAssertEqual(decide(.ignored, match: september, fixture: fixture, in: context), .saved)
        let decisions = try context.fetch(
            FetchDescriptor<TransactionMatchedExpenseResolution>()
        )
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions[0].outcome, .ignored)
        XCTAssertTrue(try context.fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        ).isEmpty)
        let remaining = matches(fixture, decisions: decisions)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].occurrenceID, future.occurrenceID)
    }

    func testStaleOwnerStatusTransactionEvidenceAndGenerationCannotConfirm() throws {
        let fixture = makeFixture()
        let match = try XCTUnwrap(matches(fixture).first)

        let context = ModelContext(try makeContainer())
        context.insert(fixture.event)
        try context.save()
        XCTAssertEqual(
            decide(.released, match: match, fixture: fixture, in: context,
                   userID: userB), .stale
        )
        assertNoDecision(in: context)

        let status = ExpenseOccurrenceStatus(
            ownerScopeID: fixture.event.ownerScopeID,
            occurrenceID: match.occurrenceID,
            sourceEventID: fixture.event.id,
            occurrenceDate: fixture.forecast.normalizedOccurrenceDate,
            status: .paid
        )
        context.insert(status)
        try context.save()
        XCTAssertEqual(decide(.released, match: match, fixture: fixture, in: context), .stale)
        assertNoDecision(in: context)
        context.delete(status)
        try context.save()

        var changed = fixture
        changed.transactions[0].pending = true
        XCTAssertEqual(decide(.released, match: match, fixture: changed,
                              in: context), .stale)
        changed = fixture
        changed.transactions[0] = transaction(amount: 101)
        XCTAssertEqual(decide(.released, match: match, fixture: changed,
                              in: context), .stale)
        XCTAssertEqual(decide(.released, match: match, fixture: fixture,
                              in: context, generation: 2), .stale)
        XCTAssertEqual(decide(.released, match: match, fixture: fixture,
                              in: context, planningAvailable: false), .stale)
        fixture.event.name = "Different Bill"
        XCTAssertEqual(decide(.released, match: match, fixture: fixture,
                              in: context), .stale)
        assertNoDecision(in: context)
    }

    func testRecoveryRequiresFreshProposalAndThenConfirms() throws {
        let fixture = makeFixture()
        let old = try XCTUnwrap(matches(fixture).first)
        let context = ModelContext(try makeContainer())
        context.insert(fixture.event)
        try context.save()
        XCTAssertEqual(decide(.released, match: old, fixture: fixture,
                              in: context, generation: 2), .stale)
        let fresh = try XCTUnwrap(matches(fixture, generation: 2).first)
        XCTAssertEqual(decide(.released, match: fresh, fixture: fixture,
                              in: context, generation: 2), .saved)
    }

    func testDecisionsPersistAcrossReopenAndRemainOwnerScoped() throws {
        let fixture = makeFixture()
        let match = try XCTUnwrap(matches(fixture).first)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("BillPayment.store")
        do {
            let context = ModelContext(try makeContainer(url: storeURL))
            context.insert(fixture.event)
            try context.save()
            XCTAssertEqual(decide(.ignored, match: match, fixture: fixture,
                                  in: context), .saved)
        }
        let reopened = ModelContext(try makeContainer(url: storeURL))
        let decisions = try reopened.fetch(
            FetchDescriptor<TransactionMatchedExpenseResolution>()
        )
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions[0].ownerScopeID, match.ownerScopeID)
        XCTAssertTrue(matches(fixture, decisions: decisions).isEmpty)
        XCTAssertTrue(matches(fixture, ownerUserID: userB,
                              decisions: decisions).isEmpty)
    }

    func testConfirmedPaymentSurvivesReopenWithoutCrossOwnerFunding() throws {
        let fixture = makeFixture()
        let match = try XCTUnwrap(matches(fixture).first)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Confirmed.store")
        do {
            let context = ModelContext(try makeContainer(url: storeURL))
            context.insert(fixture.event)
            context.insert(EventAllocation(
                ownerScopeID: fixture.event.ownerScopeID,
                occurrenceID: match.occurrenceID,
                sourceEventID: fixture.event.id,
                occurrenceDate: fixture.forecast.normalizedOccurrenceDate,
                allocatedAmount: 40
            ))
            try context.save()
            XCTAssertEqual(decide(.released, match: match, fixture: fixture,
                                  in: context), .saved)
        }
        let reopened = ModelContext(try makeContainer(url: storeURL))
        let statuses = try reopened.fetch(
            FetchDescriptor<ExpenseOccurrenceStatus>()
        )
        let decisions = try reopened.fetch(
            FetchDescriptor<TransactionMatchedExpenseResolution>()
        )
        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses[0].status, .postedFromChecking)
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions[0].outcome, .released)
        XCTAssertEqual(try funding(in: reopened, for: userA).totalSetAside, 0)
        XCTAssertEqual(try funding(in: reopened, for: userB).totalSetAside, 0)
        XCTAssertTrue(matches(fixture, decisions: decisions).isEmpty)
    }

    private struct Fixture {
        var event: PlannerEvent
        var forecast: ForecastEvent
        var forecasts: [ForecastEvent]
        var accounts: [PlaidAccount]
        var transactions: [PlaidTransaction]
        var metadata: TransactionSnapshotMetadata
        var history: [String: RecurringExpenseRecommendationHistoryRecord]
    }

    private func makeFixture() -> Fixture {
        let event = PlannerEvent(
            ownerScopeID: PlanningOwnerScope.authenticated(userA),
            name: "Electric Utility",
            amount: 100,
            date: date("2026-09-15"),
            frequency: .monthly,
            type: .expense
        )
        let forecast = ForecastEvent(event: event, occurrenceDate: event.date)
        let familyID = RecurringExpenseRecommendationIdentity.familyID(
            normalizedName: "electric utility", accountID: "checking-1"
        )
        let record = RecurringExpenseRecommendationHistoryRecord(
            stableID: familyID,
            userScope: RecurringExpenseRecommendationIdentity.userScope(userID: userA),
            displayName: "Electric Utility",
            representativeAmount: 100,
            cadence: "monthly",
            dayOfMonth: 15,
            status: .added,
            createdAt: refreshDate,
            updatedAt: refreshDate,
            plannerEventID: event.id
        )
        return Fixture(
            event: event,
            forecast: forecast,
            forecasts: [forecast],
            accounts: [account("checking-1")],
            transactions: [transaction()],
            metadata: metadata(count: 1),
            history: [familyID: record]
        )
    }

    private func matches(
        _ fixture: Fixture,
        ownerUserID: String? = nil,
        snapshotOwnerUserID: String? = nil,
        generation: UInt64 = 1,
        snapshotRefreshDate: Date? = Date(timeIntervalSince1970: 1_789_603_200),
        balancesAreCurrent: Bool = true,
        automationIsEligible: Bool = true,
        decisions: [TransactionMatchedExpenseResolution] = []
    ) -> [BillPaymentMatch] {
        BillPaymentMatcher.suggestions(
            ownerUserID: ownerUserID ?? userA,
            snapshotOwnerUserID: snapshotOwnerUserID ?? userA,
            snapshotGeneration: generation,
            snapshotRefreshDate: snapshotRefreshDate,
            forecasts: fixture.forecasts,
            statuses: [],
            decisions: decisions,
            history: fixture.history,
            accounts: fixture.accounts,
            transactions: fixture.transactions,
            metadata: fixture.metadata,
            balancesAreCurrent: balancesAreCurrent,
            automationIsEligible: automationIsEligible,
            now: refreshDate
        )
    }

    private func decide(
        _ outcome: TransactionMatchedExpenseResolutionOutcome,
        match: BillPaymentMatch,
        fixture: Fixture,
        in context: ModelContext,
        userID: String? = nil,
        generation: UInt64 = 1,
        planningAvailable: Bool = true
    ) -> BillPaymentDecisionResult {
        BillPaymentDecisionCoordinator.decide(
            outcome,
            expected: match,
            userID: userID ?? userA,
            snapshotOwnerUserID: userID ?? userA,
            snapshotGeneration: generation,
            snapshotRefreshDate: refreshDate,
            planningAvailable: planningAvailable,
            automationIsEligible: true,
            history: fixture.history,
            accounts: fixture.accounts,
            transactions: fixture.transactions,
            metadata: fixture.metadata,
            balancesAreCurrent: true,
            modelContext: context,
            now: refreshDate
        )
    }

    private func assertNoDecision(in context: ModelContext) {
        XCTAssertTrue((try? context.fetch(
            FetchDescriptor<TransactionMatchedExpenseResolution>()
        ))?.isEmpty == true)
    }

    private func funding(in context: ModelContext, for userID: String)
        throws -> UpcomingExpenseFundingSnapshot {
        let owner = PlanningOwnerScope.authenticated(userID)!
        return UpcomingExpenseFundingSnapshot(
            events: try context.fetch(FetchDescriptor<PlannerEvent>()).owned(by: owner),
            allocations: try context.fetch(FetchDescriptor<EventAllocation>()).owned(by: owner),
            occurrenceStatuses: try context.fetch(
                FetchDescriptor<ExpenseOccurrenceStatus>()
            ).owned(by: owner)
        )
    }

    private func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            TransactionMatchedExpenseResolution.self
        ])
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(
                schema: schema, url: url, cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func account(_ id: String) -> PlaidAccount {
        var result = PlaidAccount(
            account_id: id, name: "Checking", official_name: nil,
            type: "depository", subtype: "checking", mask: nil,
            balances: PlaidBalance(available: 1_000, current: 1_000)
        )
        result.item_id = "bank-item-1"
        return result
    }

    private func transaction(
        id: String = "txn-1",
        name: String = "Electric Utility",
        amount: Double = 100,
        date: String = "2026-09-15"
    ) -> PlaidTransaction {
        var result = PlaidTransaction(
            transaction_id: id, name: name, amount: amount, date: date,
            pending: false, account_id: "checking-1"
        )
        result.item_id = "bank-item-1"
        return result
    }

    private func metadata(
        count: Int,
        complete: Bool = true,
        end: String = "2026-09-17"
    ) -> TransactionSnapshotMetadata {
        TransactionSnapshotMetadata(
            windowStart: "2026-09-13", windowEnd: end,
            lookbackDays: 35, totalTransactions: count,
            returnedTransactions: count, complete: complete,
            partialFailure: false
        )
    }

    private func date(_ key: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        // Preserve the intended civil day in western simulator timezones.
        return formatter.date(from: key)!.addingTimeInterval(12 * 60 * 60)
    }
}
