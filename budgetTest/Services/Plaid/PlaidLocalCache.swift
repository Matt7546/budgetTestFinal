import Foundation

enum PlaidLocalCache {

    private static let accountsKey = "plaid_cached_accounts"
    private static let transactionsKey = "plaid_cached_transactions"
    private static let lastAccountsRefreshDateKey = "plaid_last_accounts_refresh_date"
    private static let lastTransactionsRefreshDateKey = "plaid_last_transactions_refresh_date"

    static func loadAccounts() -> [PlaidAccount] {
        let accounts = load(
            [PlaidAccount].self,
            forKey: accountsKey
        ) ?? []

        return accounts.deduplicatedForDisplayAndTotals
    }

    static func saveAccounts(
        _ accounts: [PlaidAccount]
    ) {
        save(
            accounts.deduplicatedForDisplayAndTotals,
            forKey: accountsKey
        )
    }

    static func loadLastAccountsRefreshDate() -> Date? {
        date(
            forKey: lastAccountsRefreshDateKey
        )
    }

    static func saveLastAccountsRefreshDate(
        _ date: Date
    ) {
        UserDefaults.standard.set(
            date,
            forKey: lastAccountsRefreshDateKey
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

    static func loadLastTransactionsRefreshDate() -> Date? {
        date(
            forKey: lastTransactionsRefreshDateKey
        )
    }

    static func saveLastTransactionsRefreshDate(
        _ date: Date
    ) {
        UserDefaults.standard.set(
            date,
            forKey: lastTransactionsRefreshDateKey
        )
    }

    static func clear() {
        UserDefaults.standard.removeObject(
            forKey: accountsKey
        )
        clearTransactions()
        UserDefaults.standard.removeObject(
            forKey: lastAccountsRefreshDateKey
        )
    }

    static func clearTransactions() {
        UserDefaults.standard.removeObject(
            forKey: transactionsKey
        )
        UserDefaults.standard.removeObject(
            forKey: lastTransactionsRefreshDateKey
        )
    }

    private static func date(
        forKey key: String
    ) -> Date? {
        UserDefaults.standard.object(
            forKey: key
        ) as? Date
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
