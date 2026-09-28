import Foundation

struct CachedPlaidAccountSnapshot: Codable {
    let accounts: [PlaidAccount]
    let lastSuccessfulRefresh: Date?
    let ownerUserID: String

    func canRestore(
        for userID: String?
    ) -> Bool {
        guard let canonicalOwner = Self.canonicalUserID(ownerUserID),
              canonicalOwner == ownerUserID,
              let canonicalUserID = Self.canonicalUserID(userID) else {
            return false
        }

        return canonicalOwner == canonicalUserID
    }

    private static func canonicalUserID(
        _ userID: String?
    ) -> String? {
        guard let userID = userID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else {
            return nil
        }

        return userID
    }
}

struct CachedPlaidTransactionSnapshot: Codable {
    let transactions: [PlaidTransaction]
    let metadata: TransactionSnapshotMetadata
    let lastSuccessfulRefresh: Date?
    let ownerUserID: String?

    func canRestore(
        for userID: String?
    ) -> Bool {
        guard let ownerUserID else {
            // Legacy cache records had no owner and carry unknown metadata.
            return metadata == .unknown
        }

        return ownerUserID == userID
    }
}

enum PlaidLocalCache {

    private static let accountSnapshotKey = "plaid_cached_account_snapshot"
    private static let legacyAccountsKey = "plaid_cached_accounts"
    private static let transactionsKey = "plaid_cached_transactions"
    private static let transactionSnapshotKey = "plaid_cached_transaction_snapshot"
    private static let legacyAccountsRefreshDateKey = "plaid_last_accounts_refresh_date"
    private static let lastTransactionsRefreshDateKey = "plaid_last_transactions_refresh_date"

    static func loadAccountSnapshot(
        for userID: String?,
        defaults: UserDefaults = .standard
    ) -> CachedPlaidAccountSnapshot? {
        discardLegacyAccountCache(defaults: defaults)

        guard let snapshot = load(
            CachedPlaidAccountSnapshot.self,
            forKey: accountSnapshotKey,
            defaults: defaults
        ),
        snapshot.canRestore(for: userID) else {
            return nil
        }

        return CachedPlaidAccountSnapshot(
            accounts: snapshot.accounts.deduplicatedForDisplayAndTotals,
            lastSuccessfulRefresh: snapshot.lastSuccessfulRefresh,
            ownerUserID: snapshot.ownerUserID
        )
    }

    @discardableResult
    static func saveAccountSnapshot(
        accounts: [PlaidAccount],
        lastSuccessfulRefresh: Date?,
        ownerUserID: String?,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let ownerUserID = ownerUserID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !ownerUserID.isEmpty else {
            return false
        }

        let didSave = save(
            CachedPlaidAccountSnapshot(
                accounts: accounts.deduplicatedForDisplayAndTotals,
                lastSuccessfulRefresh: lastSuccessfulRefresh,
                ownerUserID: ownerUserID
            ),
            forKey: accountSnapshotKey,
            defaults: defaults
        )

        if didSave {
            discardLegacyAccountCache(defaults: defaults)
        }

        return didSave
    }

    static func loadTransactionSnapshot(
        defaults: UserDefaults = .standard
    ) -> CachedPlaidTransactionSnapshot {
        if let snapshot = load(
            CachedPlaidTransactionSnapshot.self,
            forKey: transactionSnapshotKey,
            defaults: defaults
        ) {
            return snapshot
        }

        let legacyTransactions = load(
            [PlaidTransaction].self,
            forKey: transactionsKey,
            defaults: defaults
        ) ?? []
        let legacyRefreshDate = date(
            forKey: lastTransactionsRefreshDateKey,
            defaults: defaults
        )

        return CachedPlaidTransactionSnapshot(
            transactions: legacyTransactions,
            metadata: .unknown,
            lastSuccessfulRefresh: legacyRefreshDate,
            ownerUserID: nil
        )
    }

    static func saveTransactionSnapshot(
        _ snapshot: CachedPlaidTransactionSnapshot,
        defaults: UserDefaults = .standard
    ) {
        guard save(
            snapshot,
            forKey: transactionSnapshotKey,
            defaults: defaults
        ) else {
            return
        }

        defaults.removeObject(
            forKey: transactionsKey
        )
        defaults.removeObject(
            forKey: lastTransactionsRefreshDateKey
        )
    }

    static func clear(
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(
            forKey: accountSnapshotKey
        )
        discardLegacyAccountCache(defaults: defaults)
        clearTransactions(defaults: defaults)
    }

    static func clear(
        ownerScopeID: String,
        defaults: UserDefaults = .standard
    ) {
        if let accountSnapshot = load(
            CachedPlaidAccountSnapshot.self,
            forKey: accountSnapshotKey,
            defaults: defaults
        ),
           PlanningOwnerScope.authenticated(
               accountSnapshot.ownerUserID
           ) == ownerScopeID {
            defaults.removeObject(forKey: accountSnapshotKey)
        }

        if let transactionSnapshot = load(
            CachedPlaidTransactionSnapshot.self,
            forKey: transactionSnapshotKey,
            defaults: defaults
        ),
           PlanningOwnerScope.authenticated(
               transactionSnapshot.ownerUserID
           ) == ownerScopeID {
            clearTransactions(defaults: defaults)
        }
    }

    static func clearTransactions(
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(
            forKey: transactionSnapshotKey
        )
        defaults.removeObject(
            forKey: transactionsKey
        )
        defaults.removeObject(
            forKey: lastTransactionsRefreshDateKey
        )
    }

    private static func discardLegacyAccountCache(
        defaults: UserDefaults
    ) {
        defaults.removeObject(
            forKey: legacyAccountsKey
        )
        defaults.removeObject(
            forKey: legacyAccountsRefreshDateKey
        )
    }

    private static func date(
        forKey key: String,
        defaults: UserDefaults
    ) -> Date? {
        defaults.object(
            forKey: key
        ) as? Date
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        forKey key: String,
        defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(
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

    @discardableResult
    private static func save<T: Encodable>(
        _ value: T,
        forKey key: String,
        defaults: UserDefaults
    ) -> Bool {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(
                data,
                forKey: key
            )
            return true
        } catch {
            AppLogger.warning(
                "encode failed: \(error.localizedDescription)",
                category: .plaidCache
            )
            return false
        }
    }
}
