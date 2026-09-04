import CryptoKit
import Foundation
import SwiftData

enum TransactionMatchedExpenseResolutionOutcome: String, Codable, CaseIterable {
    case ignored
    case released
    case reassigned
}

enum TransactionMatchedExpenseResolutionIdentity {
    static let matchKeyVersion = 1
    static let matcherVersion = 1

    static func ownerScopeID(
        authenticatedUserID: String?
    ) -> String? {
        guard let normalizedUserID = authenticatedUserID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedUserID.isEmpty else {
            return nil
        }

        return digest(
            lengthPrefixed([
                "transaction-matched-expense-owner-v1",
                normalizedUserID
            ])
        )
    }

    static func matchKey(
        hashedOwnerScopeID: String,
        accountID: String,
        transactionID: String,
        occurrenceID: String
    ) -> String {
        let payload = lengthPrefixed([
            "transaction-matched-expense-match-v\(matchKeyVersion)",
            hashedOwnerScopeID,
            accountID,
            transactionID,
            occurrenceID
        ])

        return "v\(matchKeyVersion):\(digest(payload))"
    }

    private static func lengthPrefixed(
        _ components: [String]
    ) -> String {
        components
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
    }

    private static func digest(
        _ value: String
    ) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

@Model
final class TransactionMatchedExpenseResolution {
    @Attribute(.unique)
    var id: UUID

    @Attribute(.unique)
    var matchKey: String

    var ownerScopeID: String
    var matcherVersion: Int
    var transactionID: String
    var accountID: String
    var itemID: String?
    var transactionPostedDateKey: String
    var transactionAmountCents: Int64
    var sourceEventID: UUID
    var occurrenceID: String
    var occurrenceDateKey: String
    var outcomeRawValue: String
    var appliedSetAsideAmountCents: Int64
    var paymentPlanID: UUID?
    var paymentPlanCycleID: UUID?
    var createdAt: Date
    var decidedAt: Date

    init(
        id: UUID = UUID(),
        hashedOwnerScopeID: String,
        matcherVersion: Int = TransactionMatchedExpenseResolutionIdentity.matcherVersion,
        transactionID: String,
        accountID: String,
        itemID: String? = nil,
        transactionPostedDateKey: String,
        transactionAmountCents: Int64,
        sourceEventID: UUID,
        occurrenceID: String,
        occurrenceDateKey: String,
        outcome: TransactionMatchedExpenseResolutionOutcome,
        appliedSetAsideAmountCents: Int64,
        paymentPlanID: UUID? = nil,
        paymentPlanCycleID: UUID? = nil,
        createdAt: Date = Date(),
        decidedAt: Date = Date()
    ) {
        self.id = id
        self.matchKey = TransactionMatchedExpenseResolutionIdentity.matchKey(
            hashedOwnerScopeID: hashedOwnerScopeID,
            accountID: accountID,
            transactionID: transactionID,
            occurrenceID: occurrenceID
        )
        self.ownerScopeID = hashedOwnerScopeID
        self.matcherVersion = matcherVersion
        self.transactionID = transactionID
        self.accountID = accountID
        self.itemID = itemID
        self.transactionPostedDateKey = transactionPostedDateKey
        self.transactionAmountCents = transactionAmountCents
        self.sourceEventID = sourceEventID
        self.occurrenceID = occurrenceID
        self.occurrenceDateKey = occurrenceDateKey
        self.outcomeRawValue = outcome.rawValue
        self.appliedSetAsideAmountCents = appliedSetAsideAmountCents
        self.paymentPlanID = paymentPlanID
        self.paymentPlanCycleID = paymentPlanCycleID
        self.createdAt = createdAt
        self.decidedAt = decidedAt
    }

    var outcome: TransactionMatchedExpenseResolutionOutcome? {
        TransactionMatchedExpenseResolutionOutcome(
            rawValue: outcomeRawValue
        )
    }
}
