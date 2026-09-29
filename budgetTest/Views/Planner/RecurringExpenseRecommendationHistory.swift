import CryptoKit
import Foundation
import SwiftData

enum RecurringExpenseSuggestionStatus: String, Codable {
    case pending
    case added
    case dismissed
}

enum RecurringExpenseRecommendationIdentity {

    /// Amount and due day are intentionally excluded so ordinary billing
    /// changes keep the same decision. Account ID separates the same merchant
    /// across linked accounts; multiple subscriptions on one account remain
    /// indistinguishable unless their transaction patterns fail validation.
    static func familyID(
        normalizedName: String,
        accountID: String?,
        itemID: String? = nil,
        cadence: String = "monthly"
    ) -> String {
        let accountComponent = accountID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown-account"
        if let itemID = itemID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !itemID.isEmpty {
            return digest(
                ["family-v2", itemID, normalizedName, cadence, accountComponent]
                    .joined(separator: "|")
            )
        }
        // Legacy account-only decisions remain readable but cannot establish
        // an Item relationship for a newly observed transaction.
        return digest(
            [
                "family-v1",
                normalizedName,
                cadence,
                accountComponent
            ]
            .joined(separator: "|")
        )
    }

    static func suggestionID(
        familyID: String,
        amount: Double,
        dayOfMonth: Int
    ) -> String {
        digest(
            [
                "suggestion-v1",
                familyID,
                String(Int((amount * 100).rounded())),
                String(dayOfMonth)
            ]
            .joined(separator: "|")
        )
    }

    static func userScope(
        userID: String
    ) -> String {
        digest("user-v1|\(userID)")
    }

    private static func digest(
        _ value: String
    ) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct RecurringExpenseRecommendationHistoryRecord: Codable, Equatable, Identifiable {
    let stableID: String
    let userScope: String
    let displayName: String
    let representativeAmount: Double
    let cadence: String
    let dayOfMonth: Int
    let status: RecurringExpenseSuggestionStatus
    let createdAt: Date
    let updatedAt: Date
    let plannerEventID: UUID?
    var itemID: String? = nil

    var id: String { stableID }
}

private struct RecurringExpenseRecommendationHistoryEnvelope: Codable {
    let version: Int
    let userScope: String
    let records: [RecurringExpenseRecommendationHistoryRecord]
}

private struct RecurringExpenseRecommendationHistoryVersion: Decodable {
    let version: Int
}

enum RecurringExpenseRecommendationHistoryUnavailableReason: String, Equatable {
    case missingOwner
    case corrupt
    case unsupportedVersion
    case ownerMismatch
}

enum RecurringExpenseRecommendationHistoryRead: Equatable {
    case absent
    case valid([String: RecurringExpenseRecommendationHistoryRecord])
    case unavailable(RecurringExpenseRecommendationHistoryUnavailableReason)

    var usableRecords: [String: RecurringExpenseRecommendationHistoryRecord]? {
        switch self {
        case .absent: return [:]
        case .valid(let records): return records
        case .unavailable: return nil
        }
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var unavailableReason: RecurringExpenseRecommendationHistoryUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

enum RecurringExpenseRecommendationHistoryMutationFailure: Error, Equatable {
    case unavailable(RecurringExpenseRecommendationHistoryUnavailableReason)
    case encodingFailed
    case writeFailed
    case decisionChanged
}

struct RecurringExpenseRecommendationHistoryStore {
    static let legacyGlobalStatusKey =
        "caldera.recurringExpenseSuggestionStatuses"

    private static let storageKeyPrefix =
        "caldera.recurringExpenseRecommendationHistory.v1"

    private let defaults: UserDefaults
    private let storeKind: CalderaSwiftDataStoreKind
    private let now: () -> Date
    private let writeData: ((UserDefaults, String, Data) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        storeKind: CalderaSwiftDataStoreKind = CalderaSwiftDataStore.kind(
            isDebugBuild: AppConfig.environment.isDebug,
            isLabEnabled: AppConfig.isLabEnabled
        ),
        now: @escaping () -> Date = Date.init,
        writeData: ((UserDefaults, String, Data) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.storeKind = storeKind
        self.now = now
        self.writeData = writeData
    }

    func read(
        for userID: String?
    ) -> RecurringExpenseRecommendationHistoryRead {
        guard let userScope = scope(for: userID) else {
            return .unavailable(.missingOwner)
        }
        let key = storageKey(for: userScope)
        guard let stored = defaults.object(forKey: key) else { return .absent }
        guard let data = stored as? Data,
              let version = try? JSONDecoder().decode(
                RecurringExpenseRecommendationHistoryVersion.self, from: data
              ) else { return .unavailable(.corrupt) }
        guard version.version == 1 else { return .unavailable(.unsupportedVersion) }
        guard let envelope = try? JSONDecoder().decode(
            RecurringExpenseRecommendationHistoryEnvelope.self, from: data
        ) else { return .unavailable(.corrupt) }
        guard envelope.userScope == userScope,
              envelope.records.allSatisfy({ $0.userScope == userScope }) else {
            return .unavailable(.ownerMismatch)
        }
        let records = Dictionary(
            envelope.records.map { ($0.stableID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard records.count == envelope.records.count,
              !records.keys.contains("") else { return .unavailable(.corrupt) }
        return .valid(records)
    }

    @discardableResult
    func record(
        _ suggestion: RecurringExpenseSuggestion,
        status: RecurringExpenseSuggestionStatus,
        plannerEventID: UUID?,
        for userID: String?
    ) -> Result<RecurringExpenseRecommendationHistoryRecord,
        RecurringExpenseRecommendationHistoryMutationFailure> {
        guard let userScope = scope(for: userID) else {
            return .failure(.unavailable(.missingOwner))
        }
        let current = read(for: userID)
        guard var records = current.usableRecords else {
            return .failure(.unavailable(current.unavailableReason ?? .corrupt))
        }
        // An unresolved Bill save may already exist. A stale dismiss/accept
        // callback must not erase the only fence against a duplicate Bill.
        guard records[suggestion.historyID]?.status != .pending else {
            return .failure(.decisionChanged)
        }
        let timestamp = now()
        var record = RecurringExpenseRecommendationHistoryRecord(
            stableID: suggestion.historyID,
            userScope: userScope,
            displayName: suggestion.merchantName,
            representativeAmount: suggestion.amount,
            cadence: "monthly",
            dayOfMonth: suggestion.dayOfMonth,
            status: status,
            createdAt: records[suggestion.historyID]?.createdAt ?? timestamp,
            updatedAt: timestamp,
            plannerEventID: plannerEventID
        )
        record.itemID = suggestion.itemID

        records[record.stableID] = record
        switch save(
            records,
            userScope: userScope
        ) {
        case .success: return .success(record)
        case .failure(let error): return .failure(error)
        }
    }

    @discardableResult
    func removeDecision(
        stableID: String,
        for userID: String?
    ) -> Result<Void, RecurringExpenseRecommendationHistoryMutationFailure> {
        guard let userScope = scope(for: userID) else {
            return .failure(.unavailable(.missingOwner))
        }
        let current = read(for: userID)
        guard var records = current.usableRecords else {
            return .failure(.unavailable(current.unavailableReason ?? .corrupt))
        }
        guard records[stableID]?.status != .pending else {
            return .failure(.decisionChanged)
        }
        guard records[stableID] != nil else { return .success(()) }
        records.removeValue(forKey: stableID)
        return save(
            records,
            userScope: userScope
        )
    }

    @discardableResult
    func beginAcceptance(
        _ suggestion: RecurringExpenseSuggestion,
        plannerEventID: UUID,
        for userID: String?
    ) -> Result<Void, RecurringExpenseRecommendationHistoryMutationFailure> {
        guard let userScope = scope(for: userID) else {
            return .failure(.unavailable(.missingOwner))
        }
        let current = read(for: userID)
        guard var records = current.usableRecords else {
            return .failure(.unavailable(current.unavailableReason ?? .corrupt))
        }
        guard records[suggestion.historyID] == nil else {
            return .failure(.decisionChanged)
        }
        let timestamp = now()
        var pending = RecurringExpenseRecommendationHistoryRecord(
            stableID: suggestion.historyID,
            userScope: userScope,
            displayName: suggestion.merchantName,
            representativeAmount: suggestion.amount,
            cadence: "monthly",
            dayOfMonth: suggestion.dayOfMonth,
            status: .pending,
            createdAt: timestamp,
            updatedAt: timestamp,
            plannerEventID: plannerEventID
        )
        pending.itemID = suggestion.itemID
        records[pending.stableID] = pending
        return save(records, userScope: userScope)
    }

    @discardableResult
    func finishAcceptance(
        _ suggestion: RecurringExpenseSuggestion,
        plannerEventID: UUID,
        for userID: String?
    ) -> Result<Void, RecurringExpenseRecommendationHistoryMutationFailure> {
        guard let userScope = scope(for: userID) else {
            return .failure(.unavailable(.missingOwner))
        }
        let current = read(for: userID)
        guard var records = current.usableRecords else {
            return .failure(.unavailable(current.unavailableReason ?? .corrupt))
        }
        guard let pending = records[suggestion.historyID],
              pending.status == .pending,
              pending.plannerEventID == plannerEventID,
              pending.userScope == userScope,
              pending.itemID == suggestion.itemID else {
            return .failure(.decisionChanged)
        }
        var added = RecurringExpenseRecommendationHistoryRecord(
            stableID: pending.stableID,
            userScope: pending.userScope,
            displayName: pending.displayName,
            representativeAmount: pending.representativeAmount,
            cadence: pending.cadence,
            dayOfMonth: pending.dayOfMonth,
            status: .added,
            createdAt: pending.createdAt,
            updatedAt: now(),
            plannerEventID: plannerEventID
        )
        added.itemID = pending.itemID
        records[added.stableID] = added
        return save(records, userScope: userScope)
    }

    /// Conditional reconciliation of only the exact pending acceptance read
    /// before the authoritative planning fetch. A changed decision is not ours
    /// to complete or remove.
    @discardableResult
    func reconcilePending(
        _ expected: RecurringExpenseRecommendationHistoryRecord,
        billExists: Bool,
        for userID: String?
    ) -> Result<Void, RecurringExpenseRecommendationHistoryMutationFailure> {
        guard let userScope = scope(for: userID) else {
            return .failure(.unavailable(.missingOwner))
        }
        let current = read(for: userID)
        guard var records = current.usableRecords else {
            return .failure(.unavailable(current.unavailableReason ?? .corrupt))
        }
        guard expected.status == .pending,
              expected.userScope == userScope,
              expected.plannerEventID != nil,
              records[expected.stableID] == expected else {
            return .failure(.decisionChanged)
        }
        if billExists {
            var added = RecurringExpenseRecommendationHistoryRecord(
                stableID: expected.stableID,
                userScope: expected.userScope,
                displayName: expected.displayName,
                representativeAmount: expected.representativeAmount,
                cadence: expected.cadence,
                dayOfMonth: expected.dayOfMonth,
                status: .added,
                createdAt: expected.createdAt,
                updatedAt: now(),
                plannerEventID: expected.plannerEventID
            )
            added.itemID = expected.itemID
            records[expected.stableID] = added
        } else {
            records.removeValue(forKey: expected.stableID)
        }
        return save(records, userScope: userScope)
    }

    func clearHistory(
        for userID: String?
    ) {
        guard let userScope = scope(for: userID) else {
            return
        }

        defaults.removeObject(
            forKey: storageKey(for: userScope)
        )
    }

    func clearHistory(
        forUserScope userScope: String
    ) {
        guard !userScope.isEmpty else {
            return
        }

        defaults.removeObject(
            forKey: storageKey(for: userScope)
        )
    }

    private func save(
        _ records: [String: RecurringExpenseRecommendationHistoryRecord],
        userScope: String
    ) -> Result<Void, RecurringExpenseRecommendationHistoryMutationFailure> {
        let key = storageKey(for: userScope)

        guard !records.isEmpty else {
            defaults.removeObject(forKey: key)
            guard defaults.object(forKey: key) == nil else {
                AppLogger.warning(
                    "Recurring recommendation history removal verification failed",
                    category: .persistence
                )
                return .failure(.writeFailed)
            }
            return .success(())
        }

        let envelope = RecurringExpenseRecommendationHistoryEnvelope(
            version: 1,
            userScope: userScope,
            records: records.values.sorted {
                $0.stableID < $1.stableID
            }
        )

        guard let data = try? JSONEncoder().encode(envelope) else {
            AppLogger.warning(
                "Recurring recommendation history encoding failed",
                category: .persistence
            )
            return .failure(.encodingFailed)
        }

        if let writeData {
            writeData(defaults, key, data)
        } else {
            defaults.set(data, forKey: key)
        }
        guard defaults.data(forKey: key) == data else {
            AppLogger.warning(
                "Recurring recommendation history write verification failed",
                category: .persistence
            )
            return .failure(.writeFailed)
        }
        return .success(())
    }

    private func scope(
        for userID: String?
    ) -> String? {
        guard let userID = userID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else {
            return nil
        }

        return RecurringExpenseRecommendationIdentity.userScope(
            userID: userID
        )
    }

    private func storageKey(
        for userScope: String
    ) -> String {
        switch storeKind {
        case .production:
            // Preserve the established Release/production key exactly.
            return "\(Self.storageKeyPrefix).\(userScope)"
        case .development,
             .lab:
            return "\(Self.storageKeyPrefix).\(storeKind.rawValue).\(userScope)"
        }
    }
}

struct RecurringExpenseRecommendationItem: Identifiable {
    let suggestion: RecurringExpenseSuggestion?
    let history: RecurringExpenseRecommendationHistoryRecord?

    var id: String {
        suggestion?.historyID ?? history?.stableID ?? "unknown"
    }

    var historyID: String { id }

    var displayName: String {
        suggestion?.merchantName ?? history?.displayName ?? "Bill"
    }

    var amount: Double {
        suggestion?.amount ?? history?.representativeAmount ?? 0
    }

    var dayOfMonth: Int {
        suggestion?.dayOfMonth ?? history?.dayOfMonth ?? 1
    }

    var hasCurrentEvidence: Bool {
        suggestion != nil
    }

    var bodyText: String {
        if let suggestion {
            return suggestion.bodyText
        }

        if history?.itemID == nil {
            return "Saved decision from an earlier connection. Its original bank relationship is not verified."
        }

        let dayText = Self.ordinalFormatter.string(
            from: NSNumber(value: dayOfMonth)
        ) ?? "\(dayOfMonth)"

        return "\(displayName) looks monthly around the \(dayText) for about \(AppFormatters.currency(amount))."
    }

    /// Historical records do not invent a due window or confidence level after
    /// their current transaction evidence is no longer available.
    var dueWindowText: String? {
        suggestion?.dueWindowText()
    }

    var confidenceTitle: String? {
        suggestion?.confidence.title
    }

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}

struct RecurringExpenseRecommendationGroups {
    let needsReview: [RecurringExpenseRecommendationItem]
    let added: [RecurringExpenseRecommendationItem]
    let dismissed: [RecurringExpenseRecommendationItem]
    let noLongerInPlan: [RecurringExpenseRecommendationItem]
    let isHistoryAvailable: Bool
    let pendingCount: Int

    var totalCount: Int {
        needsReview.count + added.count + dismissed.count +
            noLongerInPlan.count
    }

    init(
        suggestions: [RecurringExpenseSuggestion],
        history: RecurringExpenseRecommendationHistoryRead,
        existingExpenseIDs: Set<UUID>
    ) {
        guard let records = history.usableRecords else {
            needsReview = []
            added = []
            dismissed = []
            noLongerInPlan = []
            isHistoryAvailable = false
            pendingCount = 0
            return
        }
        var needsReview = [RecurringExpenseRecommendationItem]()
        var added = [RecurringExpenseRecommendationItem]()
        var dismissed = [RecurringExpenseRecommendationItem]()
        var noLongerInPlan = [RecurringExpenseRecommendationItem]()
        var handledHistoryIDs = Set<String>()

        for suggestion in suggestions {
            let record = records[suggestion.historyID]
            let item = RecurringExpenseRecommendationItem(
                suggestion: suggestion,
                history: record
            )
            handledHistoryIDs.insert(suggestion.historyID)

            switch record?.status {
            case .added:
                if let plannerEventID = record?.plannerEventID,
                   existingExpenseIDs.contains(plannerEventID) {
                    added.append(item)
                } else {
                    noLongerInPlan.append(item)
                }

            case .dismissed:
                dismissed.append(item)

            case .pending:
                // A pending acceptance may have saved its Bill while history
                // confirmation is uncertain. It is never a new suggestion.
                break

            case nil:
                if suggestion.isAlreadyInPlan {
                    added.append(item)
                } else {
                    needsReview.append(item)
                }
            }
        }

        for record in records.values
        where !handledHistoryIDs.contains(record.stableID) {
            let item = RecurringExpenseRecommendationItem(
                suggestion: nil,
                history: record
            )

            switch record.status {
            case .added:
                if let plannerEventID = record.plannerEventID,
                   existingExpenseIDs.contains(plannerEventID) {
                    added.append(item)
                } else {
                    noLongerInPlan.append(item)
                }

            case .dismissed:
                dismissed.append(item)

            case .pending:
                break
            }
        }

        self.needsReview = Self.sorted(needsReview)
        self.added = Self.sorted(added)
        self.dismissed = Self.sorted(dismissed)
        self.noLongerInPlan = Self.sorted(noLongerInPlan)
        self.isHistoryAvailable = true
        self.pendingCount = records.values.filter { $0.status == .pending }.count
    }

    private static func sorted(
        _ items: [RecurringExpenseRecommendationItem]
    ) -> [RecurringExpenseRecommendationItem] {
        items.sorted {
            $0.displayName.localizedCaseInsensitiveCompare(
                $1.displayName
            ) == .orderedAscending
        }
    }
}

enum RecurringExpensePendingReconciliationResult: Equatable {
    case noPending
    case reconciled
    case unresolved
}

/// Called only after the synchronous Bill save attempt has settled, or on a
/// subsequent foreground read. A fresh SwiftData context supplies persisted
/// evidence; a thrown save or a cached @Query array does not prove absence.
@MainActor
enum RecurringExpensePendingReconciler {
    static func reconcile(
        for userID: String?,
        store: RecurringExpenseRecommendationHistoryStore,
        planningAvailable: Bool,
        isOwnerCurrent: () -> Bool,
        loadPersistedEvents: () throws -> [PlannerEvent]
    ) -> RecurringExpensePendingReconciliationResult {
        guard planningAvailable, isOwnerCurrent(),
              let ownerID = PlanningOwnerScope.authenticated(userID),
              let records = store.read(for: userID).usableRecords else {
            return .unresolved
        }
        let pending = records.values.filter { $0.status == .pending }
        guard !pending.isEmpty else { return .noPending }
        let events: [PlannerEvent]
        do { events = try loadPersistedEvents() }
        catch { return .unresolved }

        var unresolved = false
        for record in pending {
            guard isOwnerCurrent(),
                  let eventID = record.plannerEventID else {
                unresolved = true
                continue
            }
            let exact = events.filter { $0.id == eventID }
            // A reused UUID, duplicate, or wrong-owner row is not evidence
            // that this owner's intended Bill is present or safely absent.
            guard exact.isEmpty ||
                    (exact.count == 1 && exact[0].ownerScopeID == ownerID &&
                     exact[0].type == .expense) else {
                unresolved = true
                continue
            }
            guard isOwnerCurrent() else { return .unresolved }
            if case .failure = store.reconcilePending(
                record, billExists: !exact.isEmpty, for: userID
            ) {
                unresolved = true
            }
        }
        return unresolved ? .unresolved : .reconciled
    }
}

enum RecurringExpenseRecommendationDecisionAction {
    static func dismiss(
        _ item: RecurringExpenseRecommendationItem,
        presentedOwnerUserID: String?,
        currentOwnerUserID: String?,
        presentedSessionFingerprint: String?,
        currentSessionFingerprint: String?,
        currentSuggestion: RecurringExpenseSuggestion?,
        store: RecurringExpenseRecommendationHistoryStore
    ) -> Result<Void, RecurringExpenseRecommendationHistoryMutationFailure> {
        guard let owner = presentedOwnerUserID,
              owner == currentOwnerUserID,
              let presentedSessionFingerprint,
              presentedSessionFingerprint == currentSessionFingerprint,
              let currentSuggestion,
              currentSuggestion.id == item.suggestion?.id,
              currentSuggestion.historyID == item.historyID else {
            return .failure(.decisionChanged)
        }
        return store.record(currentSuggestion, status: .dismissed,
                            plannerEventID: nil, for: owner).map { _ in () }
    }

    static func reviewAgain(
        _ item: RecurringExpenseRecommendationItem,
        presentedOwnerUserID: String?,
        currentOwnerUserID: String?,
        presentedSessionFingerprint: String?,
        currentSessionFingerprint: String?,
        currentSuggestion: RecurringExpenseSuggestion?,
        store: RecurringExpenseRecommendationHistoryStore
    ) -> Result<Void, RecurringExpenseRecommendationHistoryMutationFailure> {
        guard let owner = presentedOwnerUserID,
              owner == currentOwnerUserID,
              let presentedSessionFingerprint,
              presentedSessionFingerprint == currentSessionFingerprint,
              let currentSuggestion,
              currentSuggestion.id == item.suggestion?.id,
              currentSuggestion.historyID == item.historyID else {
            return .failure(.decisionChanged)
        }
        return store.removeDecision(stableID: item.historyID, for: owner)
    }
}

struct RecurringExpenseRecommendationAcceptance {
    let suggestion: RecurringExpenseSuggestion
    let ownerUserID: String
    let historyStore: RecurringExpenseRecommendationHistoryStore
}

enum RecurringExpenseRecommendationSaveOutcome: Equatable {
    case saved
    /// The Bill was saved, but its pending history could not be confirmed.
    /// A retry must not create a second Bill.
    case billSavedHistoryPending
}

enum RecurringExpenseRecommendationSaveFailure: Error {
    case ownerChanged
    case history(RecurringExpenseRecommendationHistoryMutationFailure)
}

enum RecurringExpenseRecommendationSaveCoordinator {
    static func persistThenRecord(
        eventID: UUID,
        acceptance: RecurringExpenseRecommendationAcceptance,
        isOwnerCurrent: () -> Bool,
        persist: () throws -> Void
    ) throws -> RecurringExpenseRecommendationSaveOutcome {
        guard isOwnerCurrent() else {
            throw RecurringExpenseRecommendationSaveFailure.ownerChanged
        }
        switch acceptance.historyStore.beginAcceptance(
            acceptance.suggestion,
            plannerEventID: eventID,
            for: acceptance.ownerUserID
        ) {
        case .success: break
        case .failure(let error):
            throw RecurringExpenseRecommendationSaveFailure.history(error)
        }

        do {
            try persist()
        } catch {
            // SwiftData does not give this coordinator a durable proof that a
            // thrown save never committed. Retain the pending marker and block
            // another acceptance until that outcome is reconciled.
            throw error
        }

        guard isOwnerCurrent() else { return .billSavedHistoryPending }
        switch acceptance.historyStore.finishAcceptance(
            acceptance.suggestion,
            plannerEventID: eventID,
            for: acceptance.ownerUserID
        ) {
        case .success: return .saved
        case .failure:
            // UserDefaults provides same-process readback, not an atomic
            // transaction with SwiftData or a crash-durable commit guarantee.
            return .billSavedHistoryPending
        }
    }
}
