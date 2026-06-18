import Foundation

struct PlaidAccount: Codable, Identifiable {
    let account_id: String
    let name: String
    let type: String
    let subtype: String?
    let balances: PlaidBalance

    var id: String { account_id }
}

struct PlaidBalance: Codable {
    let available: Double?
    let current: Double
}

struct AccountsResponse: Codable {
    let accounts: [PlaidAccount]
}

struct PlaidTransaction: Codable, Identifiable {
    let transaction_id: String
    let name: String
    let amount: Double
    let date: String

    var id: String { transaction_id }
}

struct TransactionsResponse: Codable {
    let transactions: [PlaidTransaction]
}
