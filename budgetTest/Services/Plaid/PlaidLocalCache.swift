import Foundation

enum PlaidLocalCache {

    private static let accountsKey = "plaid_cached_accounts"
    private static let transactionsKey = "plaid_cached_transactions"

    static func loadAccounts() -> [PlaidAccount] {
        load(
            [PlaidAccount].self,
            forKey: accountsKey
        ) ?? []
    }

    static func saveAccounts(
        _ accounts: [PlaidAccount]
    ) {
        save(
            accounts,
            forKey: accountsKey
        )
    }

    static func loadTransactions() -> [PlaidTransaction] {
        load(
            [PlaidTransaction].self,
            forKey: transactionsKey
        ) ?? []
    }

    static func saveTransactions(
        _ transactions: [PlaidTransaction]
    ) {
        save(
            transactions,
            forKey: transactionsKey
        )
    }

    static func clear() {
        UserDefaults.standard.removeObject(
            forKey: accountsKey
        )
        UserDefaults.standard.removeObject(
            forKey: transactionsKey
        )
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        forKey key: String
    ) -> T? {
        guard let data = UserDefaults.standard.data(
            forKey: key
        ) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(
                type,
                from: data
            )
        } catch {
            AppLogger.warning(
                "decode failed: \(error.localizedDescription)",
                category: .plaidCache
            )
            return nil
        }
    }

    private static func save<T: Encodable>(
        _ value: T,
        forKey key: String
    ) {
        do {
            let data = try JSONEncoder().encode(value)
            UserDefaults.standard.set(
                data,
                forKey: key
            )
        } catch {
            AppLogger.warning(
                "encode failed: \(error.localizedDescription)",
                category: .plaidCache
            )
        }
    }
}
