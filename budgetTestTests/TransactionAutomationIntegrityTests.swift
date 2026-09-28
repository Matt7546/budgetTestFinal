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

    func testTransactionArrayMustBePresentButMayBeExplicitlyEmpty() throws {
        let metadata = """
        "window_start":"2026-07-01","window_end":"2026-07-12",
        "lookback_days":11,"total_transactions":0,
        "returned_transactions":0,"complete":true,"partial_failure":false
        """
        let missing = "{\(metadata)}"
        let null = "{\(metadata),\"transactions\":null}"
        let empty = "{\(metadata),\"transactions\":[]}"

        XCTAssertThrowsError(try JSONDecoder().decode(
            TransactionsResponse.self, from: Data(missing.utf8)
        ))
        XCTAssertThrowsError(try JSONDecoder().decode(
            TransactionsResponse.self, from: Data(null.utf8)
        ))
        let response = try JSONDecoder().decode(
            TransactionsResponse.self, from: Data(empty.utf8)
        )
        XCTAssertTrue(response.transactions.isEmpty)
        XCTAssertTrue(response.snapshotMetadata.isExplicitlyComplete(
            transactionCount: 0
        ))
    }

    func testCompleteEmptyIsValidNegativeEvidenceButIncompleteOrStaleIsNot() {
        let refreshedAt = date(2026, 7, 12)
        let complete = completeMetadata(returnedTransactions: 0)
        let incomplete = TransactionSnapshotMetadata(
            windowStart: "2026-05-01", windowEnd: "2026-07-12",
            lookbackDays: 72, totalTransactions: nil,
            returnedTransactions: 0, complete: false, partialFailure: true
        )
        func canEvaluate(_ metadata: TransactionSnapshotMetadata, now: Date) -> Bool {
            TransactionAutomationEligibility.canEvaluate(
                backendTransactionsEnabled: true,
                transactionState: .updated,
                hasUsableTransactions: false,
                lastSuccessfulTransactionRefresh: refreshedAt,
                lastSuccessfulManualTransactionRefresh: refreshedAt,
                snapshotMetadata: metadata,
                transactionCount: 0,
                snapshotBelongsToCurrentSession: true,
                now: now
            )
        }

        XCTAssertTrue(canEvaluate(complete, now: refreshedAt))
        XCTAssertFalse(canEvaluate(incomplete, now: refreshedAt))
        XCTAssertFalse(canEvaluate(
            complete, now: refreshedAt.addingTimeInterval(25 * 60 * 60)
        ))
        XCTAssertFalse(canEvaluate(
            complete, now: refreshedAt.addingTimeInterval(-1)
        ))
    }

    func testRawCountDeficitCannotAuthorizeRecurringConfidence() {
        let metadata = TransactionSnapshotMetadata(
            windowStart: "2026-05-01", windowEnd: "2026-07-12",
            lookbackDays: 72, totalTransactions: 4,
            returnedTransactions: 3, complete: true, partialFailure: false
        )
        XCTAssertFalse(metadata.isExplicitlyComplete(transactionCount: 3))
        XCTAssertTrue(suggestions(
            transactions: monthlyTransactions(pending: false),
            metadata: metadata
        ).isEmpty)
    }

    func testExplicitPendingReplacementAndDuplicateIdentityProduceOnePostedRecord() {
        let pending = transaction(id: "pending-1", date: "2026-07-01", pending: true)
        var posted = transaction(id: "posted-1", date: "2026-07-02", pending: false)
        posted.pending_transaction_id = "pending-1"
        let current = PlaidTransactionLifecycle.current(in: [pending, posted])

        XCTAssertEqual(current.map(\.transaction_id), ["posted-1"])
        XCTAssertEqual(PlaidTransactionLifecycle.postedEvidence(
            in: [pending, posted, posted]
        ).map(\.transaction_id), ["posted-1"])

        posted.item_id = "other-item"
        XCTAssertEqual(PlaidTransactionLifecycle.current(
            in: [pending, posted]
        ).count, 2)
    }

    func testProviderPendingReplacementLinkSurvivesDecodingAndCacheEncoding() throws {
        let json = """
        {"transaction_id":"posted-1","name":"Example Utility",
         "amount":80,"date":"2026-07-01","pending":false,
         "pending_transaction_id":"pending-1",
         "account_id":"account-1","item_id":"item-1"}
        """
        let posted = try JSONDecoder().decode(
            PlaidTransaction.self, from: Data(json.utf8)
        )
        XCTAssertEqual(posted.pending_transaction_id, "pending-1")
        let restored = try JSONDecoder().decode(
            PlaidTransaction.self, from: JSONEncoder().encode(posted)
        )
        XCTAssertEqual(restored.pending_transaction_id, "pending-1")
    }

    func testRepeatedProviderIdentityOnDifferentDatesCannotInflateRecurringPattern() {
        var transactions = monthlyTransactions(pending: false)
        transactions[2] = transaction(
            id: "june", date: "2026-07-01", pending: false
        )
        XCTAssertTrue(suggestions(
            transactions: transactions,
            metadata: completeMetadata(returnedTransactions: 3)
        ).isEmpty)
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

    func testTransactionFreshnessUsesSnapshotAcceptanceNotLaterAccountCompletion() {
        let transactionAcceptedAt = date(2026, 7, 12)
        let accountsCompletedAt = transactionAcceptedAt.addingTimeInterval(25 * 60 * 60)
        let previousState = BankSyncRefreshState(
            phase: .idle,
            balances: .unavailable,
            transactions: .unavailable,
            lastSuccessfulBalanceRefresh: nil,
            lastSuccessfulTransactionRefresh: nil,
            hasUsableBalances: false,
            hasUsableTransactions: false,
            rateLimitMessage: nil
        )
        let nextState = BankSyncRefreshReducer.resolve(
            accountOutcome: .success,
            transactionOutcome: .success,
            previousState: previousState,
            hasUsableBalances: true,
            hasUsableTransactions: true,
            completedAt: accountsCompletedAt,
            transactionCompletedAt: transactionAcceptedAt
        )

        XCTAssertEqual(nextState.lastSuccessfulBalanceRefresh, accountsCompletedAt)
        XCTAssertEqual(nextState.lastSuccessfulTransactionRefresh, transactionAcceptedAt)
        XCTAssertFalse(TransactionAutomationEligibility.canEvaluate(
            backendTransactionsEnabled: true,
            transactionState: nextState.transactions,
            hasUsableTransactions: true,
            lastSuccessfulTransactionRefresh: nextState.lastSuccessfulTransactionRefresh,
            lastSuccessfulManualTransactionRefresh: transactionAcceptedAt,
            snapshotMetadata: completeMetadata(returnedTransactions: 1),
            transactionCount: 1,
            snapshotBelongsToCurrentSession: true,
            now: accountsCompletedAt
        ))
    }

    func testProviderReadinessAndFreshnessAreBoundToAcceptedSnapshot() {
        let acceptedAt = ISO8601DateFormatter().date(
            from: "2026-07-12T12:00:00Z"
        )!
        let now = acceptedAt.addingTimeInterval(30)
        func metadata(
            ready: Bool = true,
            providerUpdate: String? = "2026-07-12T11:00:00Z",
            fetchedAt: String = "2026-07-12T11:31:00Z",
            itemID: String = "item-a"
        ) -> TransactionSnapshotMetadata {
            TransactionSnapshotMetadata(
                windowStart: "2026-04-12", windowEnd: "2026-07-12",
                lookbackDays: 91, totalTransactions: 1,
                returnedTransactions: 1, complete: true,
                partialFailure: false,
                itemEvidence: [TransactionItemEvidence(
                    itemID: itemID,
                    historicalReady: ready,
                    historicalReadyAt: "2026-07-12T09:00:00Z",
                    providerLastSuccessfulUpdate: providerUpdate,
                    providerObservedAt: "2026-07-12T11:30:00Z",
                    snapshotFetchedAt: fetchedAt
                )],
                evaluatedItemIDs: ["item-a"]
            )
        }
        func status(
            _ metadata: TransactionSnapshotMetadata
        ) -> TransactionAutomationEligibility.ProviderEvidenceStatus {
            TransactionAutomationEligibility.providerEvidenceStatus(
                snapshotMetadata: metadata, acceptedAt: acceptedAt, now: now
            )
        }

        XCTAssertEqual(status(metadata()), .ready)
        XCTAssertEqual(status(metadata(ready: false)), .waitingForHistory)
        XCTAssertEqual(status(metadata(providerUpdate: nil)), .waitingForHistory)
        XCTAssertEqual(status(metadata(providerUpdate: "malformed")),
                       .waitingForHistory)
        XCTAssertEqual(status(metadata(providerUpdate: "2026-07-13T11:00:00Z")),
                       .waitingForHistory)
        XCTAssertEqual(status(metadata(providerUpdate: "2026-07-09T11:00:00Z")),
                       .stale)
        XCTAssertEqual(status(metadata(fetchedAt: "2026-07-12T12:01:00Z")),
                       .waitingForHistory)
        XCTAssertEqual(status(metadata(itemID: "another-item")),
                       .waitingForHistory)
        XCTAssertEqual(status(.unknown), .waitingForHistory)
    }

    func testMixedItemReadinessNeverTurnsCompleteSnapshotIntoAuthority() {
        let acceptedAt = ISO8601DateFormatter().date(
            from: "2026-07-12T12:00:00Z"
        )!
        let ready = TransactionItemEvidence(
            itemID: "item-a", historicalReady: true,
            historicalReadyAt: "2026-07-12T09:00:00Z",
            providerLastSuccessfulUpdate: "2026-07-12T11:00:00Z",
            providerObservedAt: "2026-07-12T11:30:00Z",
            snapshotFetchedAt: "2026-07-12T11:31:00Z"
        )
        let loading = TransactionItemEvidence(
            itemID: "item-b", historicalReady: false,
            historicalReadyAt: nil,
            providerLastSuccessfulUpdate: "2026-07-12T11:00:00Z",
            providerObservedAt: "2026-07-12T11:30:00Z",
            snapshotFetchedAt: "2026-07-12T11:31:00Z"
        )
        let metadata = TransactionSnapshotMetadata(
            windowStart: "2026-04-12", windowEnd: "2026-07-12",
            lookbackDays: 91, totalTransactions: 1,
            returnedTransactions: 1, complete: true,
            partialFailure: false, itemEvidence: [ready, loading],
            evaluatedItemIDs: ["item-a", "item-b"]
        )
        XCTAssertEqual(
            TransactionAutomationEligibility.providerEvidenceStatus(
                snapshotMetadata: metadata, acceptedAt: acceptedAt,
                now: acceptedAt.addingTimeInterval(30)
            ),
            .waitingForHistory
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
            snapshotBelongsToCurrentSession: snapshotBelongsToCurrentSession,
            now: refreshedAt
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
            account_id: "account-1",
            item_id: "item-1"
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
