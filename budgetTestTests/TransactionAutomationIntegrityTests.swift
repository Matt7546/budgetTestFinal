import XCTest
@testable import Caldera_Money

final class TransactionAutomationIntegrityTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    override func setUp() {
        super.setUp()
        PlaidLocalCache.clear()
    }

    override func tearDown() {
        PlaidLocalCache.clear()
        super.tearDown()
    }

    func testCompleteMetadataDecodes() throws {
        let response = try decodeResponse(
            metadataJSON: """
            "window_start": "2026-05-01",
            "window_end": "2026-07-12",
            "lookback_days": 72,
            "total_transactions": 1,
            "returned_transactions": 1,
            "complete": true,
            "partial_failure": false
            """
        )

        XCTAssertEqual(response.snapshotMetadata.windowStart, "2026-05-01")
        XCTAssertEqual(response.snapshotMetadata.windowEnd, "2026-07-12")
        XCTAssertEqual(response.snapshotMetadata.lookbackDays, 72)
        XCTAssertEqual(response.snapshotMetadata.totalTransactions, 1)
        XCTAssertEqual(response.snapshotMetadata.returnedTransactions, 1)
        XCTAssertEqual(response.snapshotMetadata.complete, true)
        XCTAssertEqual(response.snapshotMetadata.partialFailure, false)
        XCTAssertTrue(
            response.snapshotMetadata.isExplicitlyComplete(
                transactionCount: response.transactions.count
            )
        )
    }

    func testLegacyNullAndMismatchedMetadataAreIneligible() throws {
        let legacy = try decodeResponse(metadataJSON: "")
        let nullMetadata = try decodeResponse(
            metadataJSON: """
            "window_start": null,
            "window_end": null,
            "lookback_days": null,
            "total_transactions": null,
            "returned_transactions": null,
            "complete": null,
            "partial_failure": null
            """
        )
        let mismatchedCount = try decodeResponse(
            metadataJSON: """
            "window_start": "2026-05-01",
            "window_end": "2026-07-12",
            "lookback_days": 72,
            "total_transactions": 2,
            "returned_transactions": 2,
            "complete": true,
            "partial_failure": false
            """
        )

        XCTAssertFalse(
            legacy.snapshotMetadata.isExplicitlyComplete(transactionCount: 1)
        )
        XCTAssertFalse(
            nullMetadata.snapshotMetadata.isExplicitlyComplete(transactionCount: 1)
        )
        XCTAssertFalse(
            mismatchedCount.snapshotMetadata.isExplicitlyComplete(transactionCount: 1)
        )
    }

    func testCompleteAndIncompleteCacheRoundTripsRemainAtomic() {
        let firstMetadata = completeMetadata(returnedTransactions: 1)
        let firstRefresh = date(2026, 7, 12)
        let firstSnapshot = CachedPlaidTransactionSnapshot(
            transactions: [transaction(id: "first", date: "2026-07-01")],
            metadata: firstMetadata,
            lastSuccessfulRefresh: firstRefresh,
            ownerUserID: "user-a"
        )

        PlaidLocalCache.saveTransactionSnapshot(firstSnapshot)

        let firstLoaded = PlaidLocalCache.loadTransactionSnapshot()
        XCTAssertEqual(firstLoaded.transactions.map(\.transaction_id), ["first"])
        XCTAssertEqual(firstLoaded.metadata, firstMetadata)
        XCTAssertEqual(firstLoaded.lastSuccessfulRefresh, firstRefresh)
        XCTAssertTrue(firstLoaded.canRestore(for: "user-a"))
        XCTAssertFalse(firstLoaded.canRestore(for: "user-b"))

        let incompleteMetadata = TransactionSnapshotMetadata(
            windowStart: "2026-06-12",
            windowEnd: "2026-07-12",
            lookbackDays: 30,
            totalTransactions: nil,
            returnedTransactions: 1,
            complete: false,
            partialFailure: true
        )
        PlaidLocalCache.saveTransactionSnapshot(
            CachedPlaidTransactionSnapshot(
                transactions: [transaction(id: "second", date: "2026-07-02")],
                metadata: incompleteMetadata,
                lastSuccessfulRefresh: nil,
                ownerUserID: "user-a"
            )
        )

        let secondLoaded = PlaidLocalCache.loadTransactionSnapshot()
        XCTAssertEqual(secondLoaded.transactions.map(\.transaction_id), ["second"])
        XCTAssertEqual(secondLoaded.metadata, incompleteMetadata)
        XCTAssertNil(secondLoaded.lastSuccessfulRefresh)

        PlaidLocalCache.clearTransactions()
        XCTAssertTrue(
            PlaidLocalCache.loadTransactionSnapshot().transactions.isEmpty
        )
        XCTAssertEqual(
            PlaidLocalCache.loadTransactionSnapshot().metadata,
            .unknown
        )
    }

    func testIncompleteRefreshDoesNotAdvanceFullSuccessTimestamp() {
        let previousRefresh = date(2026, 7, 1)
        let completedAt = date(2026, 7, 12)
        let previousState = BankSyncRefreshState(
            phase: .fullyUpdated,
            balances: .updated,
            transactions: .updated,
            lastSuccessfulBalanceRefresh: previousRefresh,
            lastSuccessfulTransactionRefresh: previousRefresh,
            hasUsableBalances: true,
            hasUsableTransactions: true,
            rateLimitMessage: nil
        )

        let nextState = BankSyncRefreshReducer.resolve(
            accountOutcome: .success,
            transactionOutcome: .partialSuccess,
            previousState: previousState,
            hasUsableBalances: true,
            hasUsableTransactions: true,
            completedAt: completedAt
        )

        XCTAssertEqual(nextState.phase, .partiallyUpdated)
        XCTAssertEqual(nextState.transactions, .partiallyUpdated)
        XCTAssertEqual(
            nextState.lastSuccessfulTransactionRefresh,
            previousRefresh
        )
    }

    func testSharedAutomationEligibilityRequiresCompleteCurrentManualSnapshot() {
        let refreshedAt = date(2026, 7, 12)
        let metadata = completeMetadata(returnedTransactions: 1)

        XCTAssertTrue(
            eligibility(
                metadata: metadata,
                refreshedAt: refreshedAt
            )
        )
        XCTAssertFalse(
            eligibility(
                metadata: .unknown,
                refreshedAt: refreshedAt
            )
        )
        XCTAssertFalse(
            eligibility(
                metadata: TransactionSnapshotMetadata(
                    windowStart: "2026-05-01",
                    windowEnd: "2026-07-12",
                    lookbackDays: 72,
                    totalTransactions: nil,
                    returnedTransactions: 1,
                    complete: false,
                    partialFailure: true
                ),
                refreshedAt: refreshedAt
            )
        )
        XCTAssertFalse(
            eligibility(
                metadata: metadata,
                refreshedAt: refreshedAt,
                transactionState: .showingEarlierData
            )
        )
        XCTAssertFalse(
            eligibility(
                metadata: metadata,
                refreshedAt: refreshedAt,
                hasMatchingManualRefresh: false
            )
        )
        XCTAssertFalse(
            eligibility(
                metadata: metadata,
                refreshedAt: refreshedAt,
                snapshotBelongsToCurrentSession: false
            )
        )
    }

    func testRecurringSuggestionsRejectPendingUnknownAndShortHistory() {
        let postedTransactions = monthlyTransactions(pending: false)
        let pendingTransactions = monthlyTransactions(pending: true)
        let unknownTransactions = monthlyTransactions(pending: nil)
        let shortMetadata = TransactionSnapshotMetadata(
            windowStart: "2026-06-12",
            windowEnd: "2026-07-12",
            lookbackDays: 30,
            totalTransactions: 3,
            returnedTransactions: 3,
            complete: true,
            partialFailure: false
        )

        XCTAssertEqual(
            RecurringExpenseSuggestionEngine.minimumRequiredHistoryDays,
            48
        )
        XCTAssertTrue(
            suggestions(
                transactions: postedTransactions,
                metadata: shortMetadata
            ).isEmpty
        )
        XCTAssertTrue(
            suggestions(
                transactions: pendingTransactions,
                metadata: completeMetadata(returnedTransactions: 3)
            ).isEmpty
        )
        XCTAssertTrue(
            suggestions(
                transactions: unknownTransactions,
                metadata: completeMetadata(returnedTransactions: 3)
            ).isEmpty
        )
    }

    func testSufficientCompletePostedHistoryStillProducesSuggestion() {
        let result = suggestions(
            transactions: monthlyTransactions(pending: false),
            metadata: completeMetadata(returnedTransactions: 3)
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].merchantName, "Example Utility")
        XCTAssertEqual(result[0].occurrenceCount, 3)
    }

    func testCardPaymentDetectionIsBlockedWithoutExplicitCompleteness() {
        let refreshedAt = date(2026, 7, 12)

        XCTAssertFalse(
            eligibility(
                metadata: .unknown,
                refreshedAt: refreshedAt
            )
        )
    }

    private func decodeResponse(
        metadataJSON: String
    ) throws -> TransactionsResponse {
        let separator = metadataJSON.isEmpty ? "" : ","
        let json = """
        {
          "transactions": [
            {
              "transaction_id": "transaction-1",
              "name": "Example Utility",
              "amount": 80,
              "date": "2026-07-01",
              "pending": false
            }
          ],
          "transactions_enabled": true
          \(separator)
          \(metadataJSON)
        }
        """

        return try JSONDecoder().decode(
            TransactionsResponse.self,
            from: Data(json.utf8)
        )
    }

    private func eligibility(
        metadata: TransactionSnapshotMetadata,
        refreshedAt: Date,
        transactionState: BankSyncResourceState = .updated,
        hasMatchingManualRefresh: Bool = true,
        snapshotBelongsToCurrentSession: Bool = true
    ) -> Bool {
        TransactionAutomationEligibility.canEvaluate(
            backendTransactionsEnabled: true,
            transactionState: transactionState,
            hasUsableTransactions: true,
            lastSuccessfulTransactionRefresh: refreshedAt,
            lastSuccessfulManualTransactionRefresh: hasMatchingManualRefresh
                ? refreshedAt
                : nil,
            snapshotMetadata: metadata,
            transactionCount: 1,
            snapshotBelongsToCurrentSession: snapshotBelongsToCurrentSession
        )
    }

    private func suggestions(
        transactions: [PlaidTransaction],
        metadata: TransactionSnapshotMetadata
    ) -> [RecurringExpenseSuggestion] {
        RecurringExpenseSuggestionEngine.suggestions(
            transactions: transactions,
            existingEvents: [],
            snapshotMetadata: metadata,
            automationIsEligible: true,
            now: date(2026, 7, 12),
            calendar: calendar
        )
    }

    private func completeMetadata(
        returnedTransactions: Int
    ) -> TransactionSnapshotMetadata {
        TransactionSnapshotMetadata(
            windowStart: "2026-05-01",
            windowEnd: "2026-07-12",
            lookbackDays: 72,
            totalTransactions: returnedTransactions,
            returnedTransactions: returnedTransactions,
            complete: true,
            partialFailure: false
        )
    }

    private func monthlyTransactions(
        pending: Bool?
    ) -> [PlaidTransaction] {
        [
            transaction(id: "may", date: "2026-05-01", pending: pending),
            transaction(id: "june", date: "2026-06-01", pending: pending),
            transaction(id: "july", date: "2026-07-01", pending: pending),
        ]
    }

    private func transaction(
        id: String,
        date: String,
        pending: Bool? = false
    ) -> PlaidTransaction {
        PlaidTransaction(
            transaction_id: id,
            name: "Example Utility",
            amount: 80,
            date: date,
            pending: pending,
            account_id: "account-1"
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
}
