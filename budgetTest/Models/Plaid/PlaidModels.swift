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
    var account_id: String? = nil
    var item_id: String? = nil
    var institution_name: String? = nil
    var institution_id: String? = nil

    var id: String { transaction_id }
}

struct TransactionsResponse: Codable {
    let transactions: [PlaidTransaction]
    let partial_failure: Bool?
    let transactions_enabled: Bool?
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
}

struct LinkedCardPaymentDetails: Codable, Identifiable {
    let account_id: String?
    let account_name: String?
    let institution_name: String?
    let mask: String?
    let current_balance: Double?
    let available_credit: Double?
    let last_statement_balance: Double?
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
