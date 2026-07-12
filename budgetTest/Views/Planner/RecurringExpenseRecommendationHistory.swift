import CryptoKit
import Foundation

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
        cadence: String = "monthly"
    ) -> String {
        digest(
            [
                "family-v1",
                normalizedName,
                cadence,
                accountID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown-account"
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

    var id: String { stableID }
}

private struct RecurringExpenseRecommendationHistoryEnvelope: Codable {
    let version: Int
    let userScope: String
    let records: [RecurringExpenseRecommendationHistoryRecord]
}

struct RecurringExpenseRecommendationHistoryStore {
    static let legacyGlobalStatusKey =
        "caldera.recurringExpenseSuggestionStatuses"

    private static let storageKeyPrefix =
        "caldera.recurringExpenseRecommendationHistory.v1"

    private let defaults: UserDefaults
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now

        // The legacy dictionary had no owner, so assigning it to any user
        // would risk leaking another person's decisions.
        defaults.removeObject(
            forKey: Self.legacyGlobalStatusKey
        )
    }

    func records(
        for userID: String?
    ) -> [String: RecurringExpenseRecommendationHistoryRecord] {
        guard let userScope = scope(for: userID),
              let data = defaults.data(
                forKey: storageKey(for: userScope)
              ),
              let envelope = try? JSONDecoder().decode(
                RecurringExpenseRecommendationHistoryEnvelope.self,
                from: data
              ),
              envelope.version == 1,
              envelope.userScope == userScope else {
            return [:]
        }

        return envelope.records.reduce(
            into: [String: RecurringExpenseRecommendationHistoryRecord]()
        ) { result, record in
            guard record.userScope == userScope else {
                return
            }

            result[record.stableID] = record
        }
    }

    @discardableResult
    func record(
        _ suggestion: RecurringExpenseSuggestion,
        status: RecurringExpenseSuggestionStatus,
        plannerEventID: UUID?,
        for userID: String?
    ) -> RecurringExpenseRecommendationHistoryRecord? {
        guard let userScope = scope(for: userID) else {
            return nil
        }

        var records = records(for: userID)
        let timestamp = now()
        let record = RecurringExpenseRecommendationHistoryRecord(
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

        records[record.stableID] = record
        save(
            records,
            userScope: userScope
        )

        return record
    }

    func removeDecision(
        stableID: String,
        for userID: String?
    ) {
        guard let userScope = scope(for: userID) else {
            return
        }

        var records = records(for: userID)
        records.removeValue(forKey: stableID)
        save(
            records,
            userScope: userScope
        )
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

    private func save(
        _ records: [String: RecurringExpenseRecommendationHistoryRecord],
        userScope: String
    ) {
        let key = storageKey(for: userScope)

        guard !records.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }

        let envelope = RecurringExpenseRecommendationHistoryEnvelope(
            version: 1,
            userScope: userScope,
            records: records.values.sorted {
                $0.stableID < $1.stableID
            }
        )

        guard let data = try? JSONEncoder().encode(envelope) else {
            return
        }

        defaults.set(data, forKey: key)
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
        "\(Self.storageKeyPrefix).\(userScope)"
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
        suggestion?.merchantName ?? history?.displayName ?? "Upcoming expense"
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
        let dayText = Self.ordinalFormatter.string(
            from: NSNumber(value: dayOfMonth)
        ) ?? "\(dayOfMonth)"

        return "\(displayName) looks monthly around the \(dayText) for about \(AppFormatters.currency(amount))."
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

    var totalCount: Int {
        needsReview.count + added.count + dismissed.count +
            noLongerInPlan.count
    }

    init(
        suggestions: [RecurringExpenseSuggestion],
        history: [String: RecurringExpenseRecommendationHistoryRecord],
        existingExpenseIDs: Set<UUID>
    ) {
        var needsReview = [RecurringExpenseRecommendationItem]()
        var added = [RecurringExpenseRecommendationItem]()
        var dismissed = [RecurringExpenseRecommendationItem]()
        var noLongerInPlan = [RecurringExpenseRecommendationItem]()
        var handledHistoryIDs = Set<String>()

        for suggestion in suggestions {
            let record = history[suggestion.historyID]
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

            case .pending,
                 nil:
                if suggestion.isAlreadyInPlan {
                    added.append(item)
                } else {
                    needsReview.append(item)
                }
            }
        }

        for record in history.values
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

enum RecurringExpenseRecommendationSaveCoordinator {
    static func persistThenRecord(
        eventID: UUID,
        persist: () throws -> Void,
        onPersisted: (UUID) -> Void
    ) throws {
        try persist()
        onPersisted(eventID)
    }
}
