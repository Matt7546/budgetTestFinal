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

struct AccountsResponse: Codable {
    let accounts: [PlaidAccount]
    let partial_failure: Bool?
}

struct PlaidTransaction: Codable, Identifiable {
    let transaction_id: String
    let name: String
    let amount: Double
    let date: String
    var pending: Bool? = nil
    var account_id: String? = nil
    var item_id: String? = nil
    var institution_name: String? = nil
    var institution_id: String? = nil

    var id: String { transaction_id }
}

struct TransactionSnapshotMetadata: Codable, Equatable {
    let windowStart: String?
    let windowEnd: String?
    let lookbackDays: Int?
    let totalTransactions: Int?
    let returnedTransactions: Int?
    let complete: Bool?
    let partialFailure: Bool?

    static let unknown = TransactionSnapshotMetadata()

    enum CodingKeys: String, CodingKey {
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case lookbackDays = "lookback_days"
        case totalTransactions = "total_transactions"
        case returnedTransactions = "returned_transactions"
        case complete
        case partialFailure = "partial_failure"
    }

    init(
        windowStart: String? = nil,
        windowEnd: String? = nil,
        lookbackDays: Int? = nil,
        totalTransactions: Int? = nil,
        returnedTransactions: Int? = nil,
        complete: Bool? = nil,
        partialFailure: Bool? = nil
    ) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.lookbackDays = lookbackDays
        self.totalTransactions = totalTransactions
        self.returnedTransactions = returnedTransactions
        self.complete = complete
        self.partialFailure = partialFailure
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
              totalTransactions >= returnedTransactions,
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

        transactions = try container.decodeIfPresent(
            [PlaidTransaction].self,
            forKey: .transactions
        ) ?? []
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
