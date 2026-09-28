import Foundation

struct PlaidAccount: Codable, Identifiable {
    let account_id: String
    let name: String
    let official_name: String?
    let type: String
    let subtype: String?
    let mask: String?
    let balances: PlaidBalance
    var item_id: String? = nil
    var institution_name: String? = nil
    var institution_id: String? = nil

    var id: String { account_id }
}

struct PlaidBalance: Codable {
    let available: Double?
    let current: Double
    var limit: Double? = nil
    var iso_currency_code: String? = nil
    var unofficial_currency_code: String? = nil
}

private struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(
        from decoder: Decoder
    ) throws {
        value = try? Value(from: decoder)
    }
}

enum BankSyncItemRecoveryCategory: String, Codable, Equatable {
    case retryable
    case reconnectRequired
    case additionalConsentRequired
    case capabilityUnavailable
    case unknownFailure

    init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknownFailure
    }
}

struct BankSyncItemOutcome: Decodable, Equatable, Identifiable {
    let error: String
    let itemID: String
    let institutionID: String?
    let institutionName: String?
    let recoveryCategory: BankSyncItemRecoveryCategory

    var id: String { itemID }

    enum CodingKeys: String, CodingKey {
        case error
        case itemID = "item_id"
        case institutionID = "institution_id"
        case institutionName = "institution_name"
        case recoveryCategory = "recovery_category"
    }
}

struct BankSyncItemRecoveryFeedback: Equatable {
    let itemID: String
    let message: String
}

enum BankSyncItemRecoveryAction: Equatable {
    case reconnect
    case retry
}

enum BankSyncItemRecoveryPresentation {
    static func action(
        for category: BankSyncItemRecoveryCategory
    ) -> BankSyncItemRecoveryAction? {
        switch category {
        case .reconnectRequired:
            return .reconnect
        case .retryable,
             .unknownFailure:
            return .retry
        case .additionalConsentRequired,
             .capabilityUnavailable:
            return nil
        }
    }

    static func peerStatus(
        itemID: String,
        refreshedItemIDs: [String]
    ) -> String {
        let anotherItemUpdated = refreshedItemIDs.contains { refreshedItemID in
            refreshedItemID != itemID
        }

        return anotherItemUpdated
            ? "Some other institutions updated successfully."
            : "Other connected institutions may still be current."
    }
}

struct AccountsResponse: Decodable {
    let accounts: [PlaidAccount]
    let partial_failure: Bool?
    let rejectedAccountCount: Int
    let itemOutcomes: [BankSyncItemOutcome]
    let evaluatedItemIDs: [String]?
    private let backendRefreshedItemIDs: [String]?

    var refreshedItemIDs: [String] {
        if let backendRefreshedItemIDs {
            return backendRefreshedItemIDs
        }

        return Array(
            Set(
                accounts.compactMap { account in
                    let itemID = account.item_id?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return itemID?.isEmpty == false
                        ? itemID
                        : nil
                }
            )
        )
        .sorted()
    }

    enum CodingKeys: String, CodingKey {
        case accounts
        case partial_failure
        case item_errors
        case refreshed_item_ids
        case evaluated_item_ids
    }

    init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        let decodedAccounts = try container.decode(
            [FailableDecodable<PlaidAccount>].self,
            forKey: .accounts
        )
        let backendPartialFailure = try container.decodeIfPresent(
            Bool.self,
            forKey: .partial_failure
        )
        let decodedItemOutcomes = try container.decodeIfPresent(
            [FailableDecodable<BankSyncItemOutcome>].self,
            forKey: .item_errors
        ) ?? []
        let decodedRefreshedItemIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .refreshed_item_ids
        )
        let decodedEvaluatedItemIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .evaluated_item_ids
        )

        accounts = decodedAccounts.compactMap(\.value).filter { account in
            !account.account_id.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }
        rejectedAccountCount = decodedAccounts.count - accounts.count
        itemOutcomes = decodedItemOutcomes.compactMap(\.value)
        backendRefreshedItemIDs = decodedRefreshedItemIDs?.normalizedItemIDs
        evaluatedItemIDs = decodedEvaluatedItemIDs?.normalizedItemIDs
        partial_failure = rejectedAccountCount > 0 || !itemOutcomes.isEmpty
            ? true
            : backendPartialFailure
    }
}

private extension Array where Element == String {
    var normalizedItemIDs: [String] {
        return Array(
            Set(
                compactMap { value in
                    let trimmedValue = value.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    return trimmedValue.isEmpty ? nil : trimmedValue
                }
            )
        )
        .sorted()
    }
}

struct PlaidTransaction: Codable, Identifiable {
    let transaction_id: String
    let name: String
    let amount: Double
    let date: String
    var pending: Bool? = nil
    var pending_transaction_id: String? = nil
    var account_id: String? = nil
    var item_id: String? = nil
    var institution_name: String? = nil
    var institution_id: String? = nil

    var id: String { transaction_id }
}

/// Identity is scoped to a Plaid Item and account. Amount, name and date may
/// change without creating a second transaction; an absent ID is not evidence.
struct PlaidTransactionIdentity: Hashable {
    let itemID: String
    let accountID: String
    let transactionID: String

    init?(itemID: String?, accountID: String?, transactionID: String) {
        guard let itemID, !itemID.isEmpty,
              let accountID, !accountID.isEmpty,
              !transactionID.isEmpty else {
            return nil
        }
        self.itemID = itemID
        self.accountID = accountID
        self.transactionID = transactionID
    }

    init?(_ transaction: PlaidTransaction) {
        self.init(
            itemID: transaction.item_id,
            accountID: transaction.account_id,
            transactionID: transaction.transaction_id
        )
    }
}

/// `/transactions/get` supplies current rows, not modification/removal events.
/// A complete replacement drops removed rows and updates modified rows in
/// place. Only explicitly posted rows can become payment evidence.
enum PlaidTransactionLifecycle {
    static func current(
        in transactions: [PlaidTransaction]
    ) -> [PlaidTransaction] {
        let supersededPending = Set(transactions.compactMap { transaction in
            guard transaction.pending == false,
                  let pendingID = transaction.pending_transaction_id else {
                return nil as PlaidTransactionIdentity?
            }
            return PlaidTransactionIdentity(
                itemID: transaction.item_id,
                accountID: transaction.account_id,
                transactionID: pendingID
            )
        })

        return transactions.filter { transaction in
            guard transaction.pending == true,
                  let identity = PlaidTransactionIdentity(transaction) else {
                return true
            }
            return !supersededPending.contains(identity)
        }
    }

    static func postedEvidence(
        in transactions: [PlaidTransaction]
    ) -> [PlaidTransaction] {
        var seen = Set<PlaidTransactionIdentity>()
        return Array(current(in: transactions).reversed().filter { transaction in
            guard transaction.pending == false,
                  let identity = PlaidTransactionIdentity(transaction) else {
                return false
            }
            return seen.insert(identity).inserted
        }.reversed())
    }
}

struct TransactionItemEvidence: Codable, Equatable {
    let itemID: String
    let historicalReady: Bool?
    let historicalReadyAt: String?
    let providerLastSuccessfulUpdate: String?
    let providerObservedAt: String?
    let snapshotFetchedAt: String?

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case historicalReady = "historical_ready"
        case historicalReadyAt = "historical_ready_at"
        case providerLastSuccessfulUpdate = "provider_last_successful_update"
        case providerObservedAt = "provider_observed_at"
        case snapshotFetchedAt = "snapshot_fetched_at"
    }
}

struct TransactionSnapshotMetadata: Codable, Equatable {
    let windowStart: String?
    let windowEnd: String?
    let lookbackDays: Int?
    let totalTransactions: Int?
    let returnedTransactions: Int?
    let complete: Bool?
    let partialFailure: Bool?
    let itemEvidence: [TransactionItemEvidence]?
    let evaluatedItemIDs: [String]?

    static let unknown = TransactionSnapshotMetadata()

    enum CodingKeys: String, CodingKey {
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case lookbackDays = "lookback_days"
        case totalTransactions = "total_transactions"
        case returnedTransactions = "returned_transactions"
        case complete
        case partialFailure = "partial_failure"
        case itemEvidence = "item_evidence"
        case evaluatedItemIDs = "evaluated_item_ids"
    }

    init(
        windowStart: String? = nil,
        windowEnd: String? = nil,
        lookbackDays: Int? = nil,
        totalTransactions: Int? = nil,
        returnedTransactions: Int? = nil,
        complete: Bool? = nil,
        partialFailure: Bool? = nil,
        itemEvidence: [TransactionItemEvidence]? = nil,
        evaluatedItemIDs: [String]? = nil
    ) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.lookbackDays = lookbackDays
        self.totalTransactions = totalTransactions
        self.returnedTransactions = returnedTransactions
        self.complete = complete
        self.partialFailure = partialFailure
        self.itemEvidence = itemEvidence
        self.evaluatedItemIDs = evaluatedItemIDs
    }

    func isExplicitlyComplete(
        transactionCount: Int
    ) -> Bool {
        guard complete == true,
              partialFailure == false,
              let windowStart,
              !windowStart.isEmpty,
              let windowEnd,
              !windowEnd.isEmpty,
              let lookbackDays,
              lookbackDays >= 0,
              let totalTransactions,
              totalTransactions >= 0,
              let returnedTransactions,
              returnedTransactions >= 0,
              totalTransactions == returnedTransactions,
              returnedTransactions == transactionCount else {
            return false
        }

        return true
    }
}

struct TransactionsResponse: Decodable {
    let transactions: [PlaidTransaction]
    let transactions_enabled: Bool?
    let snapshotMetadata: TransactionSnapshotMetadata

    enum CodingKeys: String, CodingKey {
        case transactions
        case transactions_enabled
    }

    init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        transactions = try container.decode(
            [PlaidTransaction].self,
            forKey: .transactions
        )
        transactions_enabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .transactions_enabled
        )
        snapshotMetadata = try TransactionSnapshotMetadata(
            from: decoder
        )
    }
}

struct PlaidCapabilitiesResponse: Codable {
    let accounts_enabled: Bool?
    let transactions_enabled: Bool?
    let liabilities_enabled: Bool?
    let liabilities_link_enabled: Bool?
}

struct CardPaymentDetailsResponse: Codable {
    let enabled: Bool?
    let cards: [LinkedCardPaymentDetails]
    let message: String?
    let error: String?
    let retry_after_seconds: Int?
    let consent_required: Bool?
    let partial_failure: Bool?
    let accounts_enabled: Bool?
    let transactions_enabled: Bool?
    let liabilities_enabled: Bool?
    let liabilities_link_enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case enabled
        case cards
        case message
        case error
        case retry_after_seconds
        case consent_required
        case partial_failure
        case accounts_enabled
        case transactions_enabled
        case liabilities_enabled
        case liabilities_link_enabled
    }

    init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        enabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .enabled
        )
        cards = try container.decodeIfPresent(
            [LinkedCardPaymentDetails].self,
            forKey: .cards
        ) ?? []
        message = try container.decodeIfPresent(
            String.self,
            forKey: .message
        )
        error = try container.decodeIfPresent(
            String.self,
            forKey: .error
        )
        retry_after_seconds = try container.decodeIfPresent(
            Int.self,
            forKey: .retry_after_seconds
        )
        consent_required = try container.decodeIfPresent(
            Bool.self,
            forKey: .consent_required
        )
        partial_failure = try container.decodeIfPresent(
            Bool.self,
            forKey: .partial_failure
        )
        accounts_enabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .accounts_enabled
        )
        transactions_enabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .transactions_enabled
        )
        liabilities_enabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .liabilities_enabled
        )
        liabilities_link_enabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .liabilities_link_enabled
        )
    }
}

struct CardPaymentDetailsUpdateLinkTokenResponse: Codable {
    let link_token: String?
    let mode: String?
    let item_id: String?
    let account_id: String?
    let liabilities_enabled: Bool?
    let liabilities_link_enabled: Bool?
    let error: String?
    let message: String?
    let retry_after_seconds: Int?
}

struct ItemRecoveryLinkTokenResponse: Codable {
    let link_token: String?
    let mode: String?
    let item_id: String?
    let institution_id: String?
    let institution_name: String?
    let error: String?
    let message: String?
    let retry_after_seconds: Int?
}

struct LinkedCardPaymentDetails: Codable, Identifiable {
    let account_id: String?
    let account_name: String?
    let institution_name: String?
    let mask: String?
    let current_balance: Double?
    let available_credit: Double?
    let last_statement_balance: Double?
    let last_statement_issue_date: String?
    let minimum_payment_amount: Double?
    let next_payment_due_date: String?
    let last_payment_amount: Double?
    let last_payment_date: String?
    let is_overdue: Bool?
    let last_refreshed_at: String?

    var id: String {
        account_id ?? UUID().uuidString
    }
}

struct DisconnectBanksResponse: Codable {
    let success: Bool?
    let linked: Bool?
    let retryable: Bool?
    let message: String?
    let total_items: Int?
    let removed_items: Int?
    let failed_items: Int?
    let removal_errors: [DisconnectBanksRemovalError]?
}

struct DisconnectBanksRemovalError: Codable {
    let error: String?
    let error_type: String?
    let error_code: String?
}
