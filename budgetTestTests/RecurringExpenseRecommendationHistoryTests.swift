import SwiftData
import XCTest
@testable import Caldera_Money

private func XCTAssertSuccess<Success, Failure: Error>(
    _ result: Result<Success, Failure>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case .failure(let error) = result {
        XCTFail("Expected success, got \(error)", file: file, line: line)
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

// Existing healthy-history assertions keep their compact dictionary form.
// Production code uses the explicit read state; unavailable cases below do too.
extension RecurringExpenseRecommendationHistoryStore {
    func records(for userID: String?)
        -> [String: RecurringExpenseRecommendationHistoryRecord] {
        switch read(for: userID) {
        case .absent, .unavailable(.missingOwner): return [:]
        case .valid(let records): return records
        case .unavailable(let reason):
            XCTFail("Unexpected unavailable history: \(reason.rawValue)")
            return [:]
        }
    }
}

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

    func testAbsentHistoryAllowsFirstDecisionAndSameOwnerReload() {
        let store = makeStore()
        let suggestion = makeSuggestion()
        XCTAssertEqual(store.read(for: "user-a"), .absent)
        XCTAssertEqual(store.read(for: nil), .unavailable(.missingOwner))

        guard case .success = store.record(
            suggestion, status: .dismissed, plannerEventID: nil, for: "user-a"
        ) else { return XCTFail("First decision was not saved") }

        XCTAssertEqual(
            makeStore().records(for: "user-a")[suggestion.historyID]?.status,
            .dismissed
        )
        XCTAssertEqual(makeStore().read(for: "user-b"), .absent)
    }

    func testMalformedHistoryPreservesBytesAndSuppressesDismissedSuggestion() throws {
        let suggestion = makeSuggestion()
        let store = makeStore()
        XCTAssertSuccess(store.record(
            suggestion, status: .dismissed, plannerEventID: nil, for: "user-a"
        ))
        let raw = Data("not a history envelope".utf8)
        defaults.set(raw, forKey: historyKey(for: "user-a"))

        assertUnavailablePreservesBytes(raw, reason: .corrupt, suggestion: suggestion)
        let groups = RecurringExpenseRecommendationGroups(
            suggestions: [suggestion], history: store.read(for: "user-a"),
            existingExpenseIDs: []
        )
        XCTAssertFalse(groups.isHistoryAvailable)
        XCTAssertEqual(groups.totalCount, 0)
    }

    func testUnsupportedVersionPreservesBytesAndRejectsWrites() throws {
        let store = makeStore()
        let suggestion = makeSuggestion()
        XCTAssertSuccess(store.record(
            suggestion, status: .dismissed, plannerEventID: nil, for: "user-a"
        ))
        let key = historyKey(for: "user-a")
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(
            with: XCTUnwrap(defaults.data(forKey: key))
        ) as? [String: Any])
        payload["version"] = 2
        let raw = try JSONSerialization.data(withJSONObject: payload)
        defaults.set(raw, forKey: key)
        assertUnavailablePreservesBytes(raw, reason: .unsupportedVersion, suggestion: suggestion)
    }

    func testWrongOwnerEnvelopePreservesBytesAndNeverTransfersIt() throws {
        let store = makeStore()
        let suggestion = makeSuggestion()
        XCTAssertSuccess(store.record(
            suggestion, status: .dismissed, plannerEventID: nil, for: "user-a"
        ))
        let key = historyKey(for: "user-a")
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(
            with: XCTUnwrap(defaults.data(forKey: key))
        ) as? [String: Any])
        payload["userScope"] = RecurringExpenseRecommendationIdentity.userScope(
            userID: "user-b"
        )
        let raw = try JSONSerialization.data(withJSONObject: payload)
        defaults.set(raw, forKey: key)
        assertUnavailablePreservesBytes(raw, reason: .ownerMismatch, suggestion: suggestion)
        XCTAssertEqual(store.read(for: "user-b"), .absent)
    }

    func testPendingAcceptanceCannotBeRemovedOrOverwrittenByStaleDecision() throws {
        let store = makeStore()
        let suggestion = makeSuggestion()
        let eventID = UUID()
        XCTAssertSuccess(store.beginAcceptance(
            suggestion, plannerEventID: eventID, for: "user-a"
        ))
        let original = try XCTUnwrap(defaults.data(forKey: historyKey(for: "user-a")))

        XCTAssertEqual(store.removeDecision(
            stableID: suggestion.historyID, for: "user-a"
        ).failureValue, .decisionChanged)
        XCTAssertEqual(store.record(
            suggestion, status: .dismissed, plannerEventID: nil, for: "user-a"
        ).failureValue, .decisionChanged)
        XCTAssertEqual(defaults.data(forKey: historyKey(for: "user-a")), original)
        XCTAssertEqual(RecurringExpenseRecommendationGroups(
            suggestions: [suggestion], history: store.read(for: "user-a"),
            existingExpenseIDs: []
        ).totalCount, 0)
    }

    func testCorruptHistoryBlocksAcceptanceBeforeBillPersistence() {
        let suggestion = makeSuggestion()
        let raw = Data("corrupt".utf8)
        defaults.set(raw, forKey: historyKey(for: "user-a"))
        var persistCalls = 0
        XCTAssertThrowsError(try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: UUID(), acceptance: .init(
                suggestion: suggestion, ownerUserID: "user-a", historyStore: makeStore()
            ), isOwnerCurrent: { true }, persist: { persistCalls += 1 }
        ))
        XCTAssertEqual(persistCalls, 0)
        XCTAssertEqual(defaults.data(forKey: historyKey(for: "user-a")), raw)
    }

    func testEncodingFailureBeforeAcceptanceDoesNotPersistBillOrHistory() {
        let suggestion = RecurringExpenseSuggestion(
            id: "nonfinite-suggestion", historyID: "nonfinite-family",
            merchantName: "Invalid fixture", normalizedName: "invalid fixture",
            amount: .nan, nextDueDate: date(2026, 8, 15),
            dayOfMonth: 15, occurrenceCount: 3, isAlreadyInPlan: false
        )
        var persistCalls = 0
        XCTAssertThrowsError(try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: UUID(), acceptance: .init(
                suggestion: suggestion, ownerUserID: "user-a", historyStore: makeStore()
            ), isOwnerCurrent: { true }, persist: { persistCalls += 1 }
        )) { error in
            guard case RecurringExpenseRecommendationSaveFailure.history(.encodingFailed) = error
            else { return XCTFail("Unexpected failure: \(error)") }
        }
        XCTAssertEqual(persistCalls, 0)
        XCTAssertEqual(makeStore().read(for: "user-a"), .absent)
    }

    func testFirstHistoryWriteFailureDoesNotPersistBill() {
        let suggestion = makeSuggestion()
        var persistCalls = 0
        let store = makeStore(writeData: { _, _, _ in })
        XCTAssertThrowsError(try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: UUID(), acceptance: .init(
                suggestion: suggestion, ownerUserID: "user-a", historyStore: store
            ), isOwnerCurrent: { true }, persist: { persistCalls += 1 }
        )) { error in
            guard case RecurringExpenseRecommendationSaveFailure.history(.writeFailed) = error
            else { return XCTFail("Unexpected failure: \(error)") }
        }
        XCTAssertEqual(persistCalls, 0)
        XCTAssertEqual(store.read(for: "user-a"), .absent)
    }

    @MainActor
    func testAcceptedBillAndHistoryAgreeInPersistedContext() throws {
        let suggestion = makeSuggestion(itemID: "item-a")
        let store = makeStore()
        let schema = Schema([PlannerEvent.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                               cloudKitDatabase: .none)
        ])
        let context = ModelContext(container)
        let event = PlannerEvent(
            ownerScopeID: PlanningOwnerScope.authenticated("user-a"),
            name: suggestion.merchantName, amount: suggestion.amount,
            date: date(2026, 8, 15), frequency: .monthly, type: .expense
        )
        let outcome = try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: event.id, acceptance: .init(
                suggestion: suggestion, ownerUserID: "user-a", historyStore: store
            ), isOwnerCurrent: { true }, persist: {
                context.insert(event)
                try context.save()
            }
        )
        XCTAssertEqual(outcome, .saved)
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<PlannerEvent>()).first)
        let record = try XCTUnwrap(store.records(for: "user-a")[suggestion.historyID])
        XCTAssertEqual(saved.id, record.plannerEventID)
        XCTAssertEqual(record.itemID, "item-a")
        XCTAssertEqual(record.status, .added)
    }

    @MainActor
    func testHistoryWriteFailureAfterBillSaveRetainsPendingAndReportsPartial() throws {
        let suggestion = makeSuggestion(itemID: "item-a")
        var writes = 0
        let store = makeStore(writeData: { defaults, key, data in
            writes += 1
            if writes == 1 { defaults.set(data, forKey: key) }
        })
        let schema = Schema([PlannerEvent.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                               cloudKitDatabase: .none)
        ])
        let context = ModelContext(container)
        let event = PlannerEvent(
            ownerScopeID: PlanningOwnerScope.authenticated("user-a"),
            name: suggestion.merchantName, amount: suggestion.amount,
            date: date(2026, 8, 15), frequency: .monthly, type: .expense
        )
        let outcome = try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: event.id, acceptance: .init(
                suggestion: suggestion, ownerUserID: "user-a", historyStore: store
            ), isOwnerCurrent: { true }, persist: {
                context.insert(event)
                try context.save()
            }
        )
        XCTAssertEqual(outcome, .billSavedHistoryPending)
        XCTAssertEqual(writes, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PlannerEvent>()).count, 1)
        XCTAssertEqual(store.records(for: "user-a")[suggestion.historyID]?.status, .pending)
        XCTAssertEqual(store.records(for: "user-a")[suggestion.historyID]?.plannerEventID,
                       event.id)
        XCTAssertEqual(RecurringExpenseRecommendationGroups(
            suggestions: [suggestion], history: store.read(for: "user-a"),
            existingExpenseIDs: [event.id]
        ).totalCount, 0)
        let fresh = ModelContext(container)
        XCTAssertEqual(RecurringExpensePendingReconciler.reconcile(
            for: "user-a", store: makeStore(), planningAvailable: true,
            isOwnerCurrent: { true },
            loadPersistedEvents: { try fresh.fetch(FetchDescriptor<PlannerEvent>()) }
        ), .reconciled)
        XCTAssertEqual(makeStore().records(for: "user-a")[suggestion.historyID]?.status,
                       .added)
        XCTAssertEqual(RecurringExpensePendingReconciler.reconcile(
            for: "user-a", store: makeStore(), planningAvailable: true,
            isOwnerCurrent: { true },
            loadPersistedEvents: { try fresh.fetch(FetchDescriptor<PlannerEvent>()) }
        ), .noPending)
    }

    @MainActor
    func testSettledFailedSaveIsReconciledByFreshAbsenceAndCanBeRetried() throws {
        let suggestion = makeSuggestion(itemID: "item-a")
        let store = makeStore()
        let schema = Schema([PlannerEvent.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                               cloudKitDatabase: .none)
        ])
        let event = PlannerEvent(
            ownerScopeID: PlanningOwnerScope.authenticated("user-a"),
            name: suggestion.merchantName, amount: suggestion.amount,
            date: date(2026, 8, 15), type: .expense
        )
        enum SimulatedFailure: Error { case beforeSave }
        XCTAssertThrowsError(try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: event.id,
            acceptance: .init(suggestion: suggestion, ownerUserID: "user-a",
                              historyStore: store),
            isOwnerCurrent: { true }, persist: { throw SimulatedFailure.beforeSave }
        ))
        XCTAssertEqual(store.records(for: "user-a")[suggestion.historyID]?.status, .pending)
        let fresh = ModelContext(container)
        XCTAssertEqual(RecurringExpensePendingReconciler.reconcile(
            for: "user-a", store: store, planningAvailable: true,
            isOwnerCurrent: { true },
            loadPersistedEvents: { try fresh.fetch(FetchDescriptor<PlannerEvent>()) }
        ), .reconciled)
        XCTAssertNil(store.records(for: "user-a")[suggestion.historyID])
        let writer = ModelContext(container)
        XCTAssertEqual(try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: event.id,
            acceptance: .init(suggestion: suggestion, ownerUserID: "user-a",
                              historyStore: store),
            isOwnerCurrent: { true }, persist: {
                writer.insert(event)
                try writer.save()
            }
        ), .saved)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<PlannerEvent>()).count, 1)
        XCTAssertEqual(store.records(for: "user-a")[suggestion.historyID]?.status, .added)
    }

    @MainActor
    func testThrownAfterCommittedBillKeepsPendingUntilFreshPresenceConfirmsIt() throws {
        let suggestion = makeSuggestion(itemID: "item-a")
        let store = makeStore()
        let schema = Schema([PlannerEvent.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                               cloudKitDatabase: .none)
        ])
        let writer = ModelContext(container)
        let event = PlannerEvent(
            ownerScopeID: PlanningOwnerScope.authenticated("user-a"),
            name: suggestion.merchantName, amount: suggestion.amount,
            date: date(2026, 8, 15), type: .expense
        )
        enum LostAcknowledgment: Error { case afterCommit }
        XCTAssertThrowsError(try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: event.id,
            acceptance: .init(suggestion: suggestion, ownerUserID: "user-a",
                              historyStore: store),
            isOwnerCurrent: { true }, persist: {
                writer.insert(event)
                try writer.save()
                throw LostAcknowledgment.afterCommit
            }
        ))
        XCTAssertEqual(store.records(for: "user-a")[suggestion.historyID]?.status, .pending)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<PlannerEvent>()).count, 1)
        let fresh = ModelContext(container)
        XCTAssertEqual(RecurringExpensePendingReconciler.reconcile(
            for: "user-a", store: store, planningAvailable: true,
            isOwnerCurrent: { true },
            loadPersistedEvents: { try fresh.fetch(FetchDescriptor<PlannerEvent>()) }
        ), .reconciled)
        XCTAssertEqual(store.records(for: "user-a")[suggestion.historyID]?.status, .added)
        XCTAssertEqual(store.records(for: "user-a")[suggestion.historyID]?.plannerEventID,
                       event.id)
        XCTAssertEqual(store.beginAcceptance(suggestion, plannerEventID: UUID(),
                                             for: "user-a").failureValue,
                       .decisionChanged)
    }

    @MainActor
    func testPendingReconciliationFailsClosedOnUnavailableReadOrOwnerChange() throws {
        let suggestion = makeSuggestion(itemID: "item-a")
        let store = makeStore()
        let eventID = UUID()
        XCTAssertSuccess(store.beginAcceptance(suggestion, plannerEventID: eventID,
                                               for: "user-a"))
        let original = try XCTUnwrap(defaults.data(forKey: historyKey(for: "user-a")))
        enum ReadFailure: Error { case unavailable }
        XCTAssertEqual(RecurringExpensePendingReconciler.reconcile(
            for: "user-a", store: store, planningAvailable: true,
            isOwnerCurrent: { true }, loadPersistedEvents: { throw ReadFailure.unavailable }
        ), .unresolved)
        XCTAssertEqual(RecurringExpensePendingReconciler.reconcile(
            for: "user-a", store: store, planningAvailable: false,
            isOwnerCurrent: { true }, loadPersistedEvents: { [] }
        ), .unresolved)
        XCTAssertEqual(RecurringExpensePendingReconciler.reconcile(
            for: "user-a", store: store, planningAvailable: true,
            isOwnerCurrent: { false }, loadPersistedEvents: { [] }
        ), .unresolved)
        let wrongOwnerEvent = PlannerEvent(
            id: eventID, ownerScopeID: PlanningOwnerScope.authenticated("user-b"),
            name: suggestion.merchantName, amount: suggestion.amount,
            date: date(2026, 8, 15), type: .expense
        )
        XCTAssertEqual(RecurringExpensePendingReconciler.reconcile(
            for: "user-a", store: store, planningAvailable: true,
            isOwnerCurrent: { true }, loadPersistedEvents: { [wrongOwnerEvent] }
        ), .unresolved)
        XCTAssertEqual(defaults.data(forKey: historyKey(for: "user-a")), original)
        XCTAssertEqual(store.read(for: "user-b"), .absent)
    }

    func testStalePresentedOwnerCannotDismissOrReviewAgainForNewOwner() throws {
        let suggestion = makeSuggestion(itemID: "shared-item")
        let item = RecurringExpenseRecommendationItem(suggestion: suggestion, history: nil)
        let store = makeStore()
        XCTAssertSuccess(store.record(suggestion, status: .dismissed,
                                      plannerEventID: nil, for: "user-b"))
        let original = try XCTUnwrap(defaults.data(forKey: historyKey(for: "user-b")))
        XCTAssertEqual(RecurringExpenseRecommendationDecisionAction.dismiss(
            item, presentedOwnerUserID: "user-a", currentOwnerUserID: "user-b",
            presentedSessionFingerprint: "session-a",
            currentSessionFingerprint: "session-b",
            currentSuggestion: suggestion, store: store
        ).failureValue, .decisionChanged)
        XCTAssertEqual(RecurringExpenseRecommendationDecisionAction.reviewAgain(
            item, presentedOwnerUserID: "user-a", currentOwnerUserID: "user-b",
            presentedSessionFingerprint: "session-a",
            currentSessionFingerprint: "session-b",
            currentSuggestion: suggestion, store: store
        ).failureValue, .decisionChanged)
        XCTAssertEqual(RecurringExpenseRecommendationDecisionAction.reviewAgain(
            item, presentedOwnerUserID: "user-b", currentOwnerUserID: "user-b",
            presentedSessionFingerprint: "old-session",
            currentSessionFingerprint: "session-b",
            currentSuggestion: suggestion, store: store
        ).failureValue, .decisionChanged)
        XCTAssertEqual(defaults.data(forKey: historyKey(for: "user-b")), original)
        XCTAssertEqual(store.read(for: "user-a"), .absent)
        XCTAssertSuccess(RecurringExpenseRecommendationDecisionAction.reviewAgain(
            item, presentedOwnerUserID: "user-b", currentOwnerUserID: "user-b",
            presentedSessionFingerprint: "session-b",
            currentSessionFingerprint: "session-b",
            currentSuggestion: suggestion, store: store
        ))
        XCTAssertEqual(store.read(for: "user-b"), .absent)
    }

    func testOwnerSwitchAfterPersistenceKeepsFirstOwnerPendingAndSecondAbsent() throws {
        let store = makeStore()
        let suggestion = makeSuggestion()
        var currentOwner = "user-a"
        let eventID = UUID()
        let outcome = try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: eventID, acceptance: .init(
                suggestion: suggestion, ownerUserID: "user-a", historyStore: store
            ), isOwnerCurrent: { currentOwner == "user-a" }, persist: {
                currentOwner = "user-b"
            }
        )
        XCTAssertEqual(outcome, .billSavedHistoryPending)
        XCTAssertEqual(store.records(for: "user-a")[suggestion.historyID]?.status, .pending)
        XCTAssertEqual(store.read(for: "user-b"), .absent)
        XCTAssertEqual(makeStore().records(for: "user-a")[suggestion.historyID]?.plannerEventID,
                       eventID)
    }

    func testStaleOwnerActionBeforeAcceptanceCannotWriteEitherHistory() {
        let store = makeStore()
        let suggestion = makeSuggestion()
        var persistCalls = 0
        XCTAssertThrowsError(try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: UUID(), acceptance: .init(
                suggestion: suggestion, ownerUserID: "user-a", historyStore: store
            ), isOwnerCurrent: { false }, persist: { persistCalls += 1 }
        )) { error in
            guard case RecurringExpenseRecommendationSaveFailure.ownerChanged = error
            else { return XCTFail("Unexpected failure: \(error)") }
        }
        XCTAssertEqual(persistCalls, 0)
        XCTAssertEqual(store.read(for: "user-a"), .absent)
        XCTAssertEqual(store.read(for: "user-b"), .absent)
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
            history: store.read(for: "user-a"),
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
            history: store.read(for: "user-a"),
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

    func testLegacyAccountOnlyDecisionCannotAttachToReusedAccountOnAnotherItem() {
        let store = makeStore()
        let legacy = makeSuggestion()
        store.record(legacy, status: .dismissed,
                     plannerEventID: nil, for: "user-a")
        let relinked = makeSuggestion(itemID: "new-item")
        let originalItem = makeSuggestion(itemID: "original-item")

        XCTAssertNotEqual(legacy.historyID, relinked.historyID)
        XCTAssertNotEqual(originalItem.historyID, relinked.historyID)
        let groups = RecurringExpenseRecommendationGroups(
            suggestions: [relinked],
            history: store.read(for: "user-a"),
            existingExpenseIDs: []
        )
        XCTAssertEqual(groups.needsReview.map(\.historyID), [relinked.historyID])
        XCTAssertEqual(groups.dismissed.map(\.historyID), [legacy.historyID])
        XCTAssertFalse(groups.dismissed[0].hasCurrentEvidence)
        XCTAssertNil(groups.dismissed[0].history?.itemID)
    }

    func testLegacyStoredEnvelopeWithoutItemIDRemainsReadableAndUnverified() throws {
        let store = makeStore()
        let legacy = makeSuggestion()
        store.record(legacy, status: .dismissed,
                     plannerEventID: nil, for: "user-a")
        let key = try XCTUnwrap(defaults.dictionaryRepresentation().keys.first {
            $0.hasPrefix("caldera.recurringExpenseRecommendationHistory.v1")
        })
        let encoded = try XCTUnwrap(defaults.data(forKey: key))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(
            with: encoded
        ) as? [String: Any])
        var records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        records[0].removeValue(forKey: "itemID")
        envelope["records"] = records
        defaults.set(try JSONSerialization.data(withJSONObject: envelope),
                     forKey: key)

        let restored = try XCTUnwrap(store.records(for: "user-a")[legacy.historyID])
        XCTAssertEqual(restored.status, .dismissed)
        XCTAssertNil(restored.itemID)
        let relinked = makeSuggestion(itemID: "new-item")
        XCTAssertNil(store.records(for: "user-a")[relinked.historyID])
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

    func testThreePostedPaymentsProduceALikelyPatternWithDueWindow() throws {
        let transactions = [
            transaction("may", amount: 82, date: "2026-05-15"),
            transaction("june", amount: 82, date: "2026-06-15"),
            transaction("july", amount: 82, date: "2026-07-15")
        ]

        let suggestion = try XCTUnwrap(
            RecurringExpenseSuggestionEngine.suggestions(
                transactions: transactions,
                existingEvents: [],
                snapshotMetadata: completeMetadata(for: transactions),
                automationIsEligible: true,
                now: date(2026, 7, 16),
                calendar: calendar
            ).first
        )

        XCTAssertEqual(suggestion.confidence, .likely)
        XCTAssertEqual(suggestion.dueWindowDays, 2)
        XCTAssertEqual(
            suggestion.dueWindowText(calendar: calendar),
            "Expected between Aug 12 and Aug 16."
        )
    }

    func testFourTightPostedPaymentsProduceHighConfidence() throws {
        let transactions = [
            transaction("april", amount: 82, date: "2026-04-15"),
            transaction("may", amount: 81.50, date: "2026-05-15"),
            transaction("june", amount: 82.25, date: "2026-06-16"),
            transaction("july", amount: 82, date: "2026-07-15")
        ]

        let suggestion = try XCTUnwrap(
            RecurringExpenseSuggestionEngine.suggestions(
                transactions: transactions,
                existingEvents: [],
                snapshotMetadata: completeMetadata(for: transactions),
                automationIsEligible: true,
                now: date(2026, 7, 16),
                calendar: calendar
            ).first
        )

        XCTAssertEqual(suggestion.confidence, .high)
        XCTAssertEqual(suggestion.dueWindowDays, 2)
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
        let history = store.read(for: "user-a")

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
            history: store.read(for: "user-a"),
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
            history: store.read(for: "user-a"),
            existingExpenseIDs: []
        )
        let withoutEvidence = RecurringExpenseRecommendationGroups(
            suggestions: [],
            history: store.read(for: "user-a"),
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

        let outcome = try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
            eventID: eventID,
            acceptance: RecurringExpenseRecommendationAcceptance(
                suggestion: suggestion,
                ownerUserID: "user-a",
                historyStore: store
            ),
            isOwnerCurrent: { true },
            persist: {
                didPersist = true
            }
        )

        XCTAssertTrue(didPersist)
        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(
            store.records(for: "user-a")[suggestion.historyID]?.plannerEventID,
            eventID
        )
    }

    func testPersistenceFailureDoesNotMarkAdded() {
        let store = makeStore()
        let suggestion = makeSuggestion()
        let eventID = UUID()

        XCTAssertThrowsError(
            try RecurringExpenseRecommendationSaveCoordinator.persistThenRecord(
                eventID: eventID,
                acceptance: RecurringExpenseRecommendationAcceptance(
                    suggestion: suggestion,
                    ownerUserID: "user-a",
                    historyStore: store
                ),
                isOwnerCurrent: { true },
                persist: {
                    throw TestError.persistenceFailed
                }
            )
        )

        XCTAssertEqual(store.records(for: "user-a")[suggestion.historyID]?.status, .pending)
        XCTAssertEqual(store.records(for: "user-a")[suggestion.historyID]?.plannerEventID, eventID)
    }

    func testLegacyGlobalStatusIsPreservedButNeverAssignedToAUser() throws {
        let original = try JSONEncoder().encode(["unowned": "dismissed"])
        defaults.set(
            original,
            forKey: RecurringExpenseRecommendationHistoryStore
                .legacyGlobalStatusKey
        )

        _ = makeStore()

        XCTAssertEqual(
            defaults.data(
                forKey: RecurringExpenseRecommendationHistoryStore
                    .legacyGlobalStatusKey
            ),
            original
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

    private func makeStore(
        writeData: ((UserDefaults, String, Data) -> Void)? = nil
    ) -> RecurringExpenseRecommendationHistoryStore {
        RecurringExpenseRecommendationHistoryStore(
            defaults: defaults,
            storeKind: .production,
            now: { Date(timeIntervalSince1970: 1_750_000_000) },
            writeData: writeData
        )
    }

    private func historyKey(for userID: String) -> String {
        "caldera.recurringExpenseRecommendationHistory.v1." +
            RecurringExpenseRecommendationIdentity.userScope(userID: userID)
    }

    private func assertUnavailablePreservesBytes(
        _ raw: Data,
        reason: RecurringExpenseRecommendationHistoryUnavailableReason,
        suggestion: RecurringExpenseSuggestion
    ) {
        let store = makeStore()
        XCTAssertEqual(store.read(for: "user-a"), .unavailable(reason))
        XCTAssertEqual(store.record(
            suggestion, status: .dismissed, plannerEventID: nil, for: "user-a"
        ).failureValue, .unavailable(reason))
        XCTAssertEqual(store.removeDecision(
            stableID: suggestion.historyID, for: "user-a"
        ).failureValue, .unavailable(reason))
        XCTAssertEqual(defaults.data(forKey: historyKey(for: "user-a")), raw)
    }

    private func makeSuggestion(
        merchantName: String = "Example Wireless",
        normalizedName: String = "example wireless",
        accountID: String? = "card-a",
        itemID: String? = nil,
        amount: Double = 82,
        dayOfMonth: Int = 15
    ) -> RecurringExpenseSuggestion {
        let historyID = RecurringExpenseRecommendationIdentity.familyID(
            normalizedName: normalizedName,
            accountID: accountID,
            itemID: itemID
        )

        return RecurringExpenseSuggestion(
            id: RecurringExpenseRecommendationIdentity.suggestionID(
                familyID: historyID,
                amount: amount,
                dayOfMonth: dayOfMonth
            ),
            historyID: historyID,
            itemID: itemID,
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
        accountID: String = "card-a"
    ) -> PlaidTransaction {
        PlaidTransaction(
            transaction_id: id,
            name: "STREAMING SERVICE",
            amount: amount,
            date: date,
            pending: false,
            account_id: accountID,
            item_id: "item-1"
        )
    }

    private func completeMetadata(
        for transactions: [PlaidTransaction]
    ) -> TransactionSnapshotMetadata {
        TransactionSnapshotMetadata(
            windowStart: "2026-04-01",
            windowEnd: "2026-07-16",
            lookbackDays: 106,
            totalTransactions: transactions.count,
            returnedTransactions: transactions.count,
            complete: true,
            partialFailure: false
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
