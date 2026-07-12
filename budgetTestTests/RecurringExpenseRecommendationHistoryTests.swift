import XCTest
@testable import Caldera_Money

final class RecurringExpenseRecommendationHistoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        suiteName = "RecurringExpenseRecommendationHistoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        calendar = nil
        super.tearDown()
    }

    func testHistoryIsIsolatedByUserAndRestoresForSameUser() {
        let store = makeStore()
        let suggestion = makeSuggestion()

        store.record(
            suggestion,
            status: .dismissed,
            plannerEventID: nil,
            for: "user-a"
        )

        XCTAssertEqual(store.records(for: "user-a").count, 1)
        XCTAssertTrue(store.records(for: "user-b").isEmpty)
        XCTAssertTrue(store.records(for: nil).isEmpty)

        let restoredStore = makeStore()
        XCTAssertEqual(
            restoredStore.records(for: "user-a")[suggestion.historyID]?.status,
            .dismissed
        )
    }

    func testAccountDeletionClearsOnlyThatUsersHistory() {
        let store = makeStore()
        store.record(
            makeSuggestion(merchantName: "Alpha Mobile"),
            status: .dismissed,
            plannerEventID: nil,
            for: "user-a"
        )
        store.record(
            makeSuggestion(
                merchantName: "Beta Mobile",
                normalizedName: "beta mobile",
                accountID: "account-b"
            ),
            status: .dismissed,
            plannerEventID: nil,
            for: "user-b"
        )

        store.clearHistory(for: "user-a")

        XCTAssertTrue(store.records(for: "user-a").isEmpty)
        XCTAssertEqual(store.records(for: "user-b").count, 1)
    }

    func testNotNowSurvivesSourceWindowExpiration() {
        let store = makeStore()
        let suggestion = makeSuggestion()
        store.record(
            suggestion,
            status: .dismissed,
            plannerEventID: nil,
            for: "user-a"
        )

        let groups = RecurringExpenseRecommendationGroups(
            suggestions: [],
            history: store.records(for: "user-a"),
            existingExpenseIDs: []
        )

        XCTAssertEqual(groups.dismissed.count, 1)
        XCTAssertEqual(groups.dismissed.first?.displayName, suggestion.merchantName)
        XCTAssertEqual(groups.dismissed.first?.hasCurrentEvidence, false)
        XCTAssertTrue(groups.needsReview.isEmpty)
    }

    func testMinorAmountAndDueDayChangesRetainFamilyDecision() {
        let original = makeSuggestion(
            amount: 80,
            dayOfMonth: 15
        )
        let changed = makeSuggestion(
            amount: 84,
            dayOfMonth: 17
        )
        let store = makeStore()
        store.record(
            original,
            status: .dismissed,
            plannerEventID: nil,
            for: "user-a"
        )

        let groups = RecurringExpenseRecommendationGroups(
            suggestions: [changed],
            history: store.records(for: "user-a"),
            existingExpenseIDs: []
        )

        XCTAssertEqual(original.historyID, changed.historyID)
        XCTAssertNotEqual(original.id, changed.id)
        XCTAssertEqual(groups.dismissed.count, 1)
        XCTAssertTrue(groups.needsReview.isEmpty)
    }

    func testSameMerchantOnDifferentAccountsHasDistinctFamilies() {
        let first = RecurringExpenseRecommendationIdentity.familyID(
            normalizedName: "streaming service",
            accountID: "card-a"
        )
        let second = RecurringExpenseRecommendationIdentity.familyID(
            normalizedName: "streaming service",
            accountID: "card-b"
        )

        XCTAssertNotEqual(first, second)
    }

    func testEngineKeepsReliableAccountFamiliesSeparate() {
        let transactions = [
            transaction("a-1", amount: 12, date: "2026-04-15", accountID: "card-a"),
            transaction("a-2", amount: 12, date: "2026-05-15", accountID: "card-a"),
            transaction("a-3", amount: 12, date: "2026-06-15", accountID: "card-a"),
            transaction("b-1", amount: 24, date: "2026-04-16", accountID: "card-b"),
            transaction("b-2", amount: 24, date: "2026-05-16", accountID: "card-b"),
            transaction("b-3", amount: 24, date: "2026-06-16", accountID: "card-b")
        ]
        let metadata = TransactionSnapshotMetadata(
            windowStart: "2026-04-02",
            windowEnd: "2026-07-01",
            lookbackDays: 90,
            totalTransactions: transactions.count,
            returnedTransactions: transactions.count,
            complete: true,
            partialFailure: false
        )

        let suggestions = RecurringExpenseSuggestionEngine.suggestions(
            transactions: transactions,
            existingEvents: [],
            snapshotMetadata: metadata,
            automationIsEligible: true,
            now: date(2026, 7, 1),
            calendar: calendar
        )

        XCTAssertEqual(suggestions.count, 2)
        XCTAssertEqual(Set(suggestions.map(\.historyID)).count, 2)
    }

    func testAddedHistorySurvivesSourceChangesAndReconcilesDeletion() {
        let store = makeStore()
        let suggestion = makeSuggestion()
        let eventID = UUID()
        store.record(
            suggestion,
            status: .added,
            plannerEventID: eventID,
            for: "user-a"
        )
        let history = store.records(for: "user-a")

        let represented = RecurringExpenseRecommendationGroups(
            suggestions: [],
            history: history,
            existingExpenseIDs: [eventID]
        )
        let deleted = RecurringExpenseRecommendationGroups(
            suggestions: [],
            history: history,
            existingExpenseIDs: []
        )

        XCTAssertEqual(represented.added.count, 1)
        XCTAssertTrue(represented.noLongerInPlan.isEmpty)
        XCTAssertTrue(deleted.added.isEmpty)
        XCTAssertEqual(deleted.noLongerInPlan.count, 1)
        XCTAssertEqual(
            deleted.noLongerInPlan.first?.hasCurrentEvidence,
            false
        )
    }

    func testDeletedEventCanOnlyBeReviewedWithCurrentEvidence() {
        let store = makeStore()
        let suggestion = makeSuggestion()
        store.record(
            suggestion,
            status: .added,
            plannerEventID: UUID(),
            for: "user-a"
        )

        let groups = RecurringExpenseRecommendationGroups(
            suggestions: [suggestion],
            history: store.records(for: "user-a"),
            existingExpenseIDs: []
        )

        XCTAssertEqual(groups.noLongerInPlan.count, 1)
        XCTAssertEqual(
            groups.noLongerInPlan.first?.hasCurrentEvidence,
            true
        )
    }

    func testReviewAgainRestoresPendingOnlyWithCurrentEvidence() {
        let store = makeStore()
        let suggestion = makeSuggestion()
        store.record(
            suggestion,
            status: .dismissed,
            plannerEventID: nil,
            for: "user-a"
        )

        store.removeDecision(
            stableID: suggestion.historyID,
            for: "user-a"
        )

        let withEvidence = RecurringExpenseRecommendationGroups(
            suggestions: [suggestion],
            history: store.records(for: "user-a"),
            existingExpenseIDs: []
        )
        let withoutEvidence = RecurringExpenseRecommendationGroups(
            suggestions: [],
            history: store.records(for: "user-a"),
            existingExpenseIDs: []
        )

        XCTAssertEqual(withEvidence.needsReview.count, 1)
        XCTAssertEqual(withoutEvidence.totalCount, 0)
    }

    func testSuccessfulPersistenceRecordsCreatedPlannerEventID() throws {
        let store = makeStore()
        let suggestion = makeSuggestion()
        let eventID = UUID()
        var didPersist = false

        try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: eventID,
            persist: {
                didPersist = true
            },
            onPersisted: { persistedEventID in
                XCTAssertTrue(didPersist)
                store.record(
                    suggestion,
                    status: .added,
                    plannerEventID: persistedEventID,
                    for: "user-a"
                )
            }
        )

        XCTAssertEqual(
            store.records(for: "user-a")[suggestion.historyID]?.plannerEventID,
            eventID
        )
    }

    func testPersistenceFailureDoesNotMarkAdded() {
        let store = makeStore()
        let suggestion = makeSuggestion()
        var didRecord = false

        XCTAssertThrowsError(
            try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
                eventID: UUID(),
                persist: {
                    throw TestError.persistenceFailed
                },
                onPersisted: { _ in
                    didRecord = true
                    store.record(
                        suggestion,
                        status: .added,
                        plannerEventID: UUID(),
                        for: "user-a"
                    )
                }
            )
        )

        XCTAssertFalse(didRecord)
        XCTAssertTrue(store.records(for: "user-a").isEmpty)
    }

    func testLegacyGlobalStatusIsRemovedWithoutMigration() throws {
        defaults.set(
            try JSONEncoder().encode(["unowned": "dismissed"]),
            forKey: RecurringExpenseRecommendationHistoryStore
                .legacyGlobalStatusKey
        )

        _ = makeStore()

        XCTAssertNil(
            defaults.object(
                forKey: RecurringExpenseRecommendationHistoryStore
                    .legacyGlobalStatusKey
            )
        )
        XCTAssertTrue(makeStore().records(for: "user-a").isEmpty)
    }

    func testStorageKeysContainOnlyHashedUserScope() {
        let store = makeStore()
        store.record(
            makeSuggestion(
                merchantName: "Private Merchant Name",
                amount: 82.37,
                dayOfMonth: 19
            ),
            status: .dismissed,
            plannerEventID: nil,
            for: "private-user-id"
        )

        let keys = defaults.dictionaryRepresentation().keys
        XCTAssertFalse(keys.contains { $0.contains("Private Merchant") })
        XCTAssertFalse(keys.contains { $0.contains("private-user-id") })
        XCTAssertFalse(keys.contains { $0.contains("82.37") })
    }

    private func makeStore() -> RecurringExpenseRecommendationHistoryStore {
        RecurringExpenseRecommendationHistoryStore(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_750_000_000) }
        )
    }

    private func makeSuggestion(
        merchantName: String = "Example Wireless",
        normalizedName: String = "example wireless",
        accountID: String? = "card-a",
        amount: Double = 82,
        dayOfMonth: Int = 15
    ) -> RecurringExpenseSuggestion {
        let historyID = RecurringExpenseRecommendationIdentity.familyID(
            normalizedName: normalizedName,
            accountID: accountID
        )

        return RecurringExpenseSuggestion(
            id: RecurringExpenseRecommendationIdentity.suggestionID(
                familyID: historyID,
                amount: amount,
                dayOfMonth: dayOfMonth
            ),
            historyID: historyID,
            merchantName: merchantName,
            normalizedName: normalizedName,
            amount: amount,
            nextDueDate: date(2026, 7, dayOfMonth),
            dayOfMonth: dayOfMonth,
            occurrenceCount: 3,
            isAlreadyInPlan: false
        )
    }

    private func transaction(
        _ id: String,
        amount: Double,
        date: String,
        accountID: String
    ) -> PlaidTransaction {
        PlaidTransaction(
            transaction_id: id,
            name: "STREAMING SERVICE",
            amount: amount,
            date: date,
            pending: false,
            account_id: accountID
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day
            )
        )!
    }

    private enum TestError: Error {
        case persistenceFailed
    }
}
