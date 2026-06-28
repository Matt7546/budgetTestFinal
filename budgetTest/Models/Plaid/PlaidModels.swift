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
