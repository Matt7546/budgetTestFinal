import Foundation

struct PlaidAccount: Codable, Identifiable {
    let account_id: String
    let name: String
    let type: String
    let subtype: String?
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
