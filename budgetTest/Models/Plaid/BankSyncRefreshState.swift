import Foundation

enum BankSyncRefreshPhase: Equatable {
    case idle
    case loading
    case fullyUpdated
    case partiallyUpdated
    case showingEarlierData
    case unavailable
    case rateLimited
    case notConnected
    case authenticationRequired
}

enum BankSyncResourceState: Equatable {
    case notRequested
    case loading
    case updated
    case partiallyUpdated
    case showingEarlierData
    case unavailable
    case rateLimited
    case disabled
    case notConnected
}

enum BankSyncFetchOutcome: Equatable {
    case success
    case partialSuccess
    case failure
    case rateLimited(String)
    case notLinked
    case authenticationRequired
    case disabled

    var rateLimitMessage: String? {
        guard case .rateLimited(let message) = self else {
            return nil
        }

        return message
    }
}

struct BankSyncRefreshState: Equatable {
    let phase: BankSyncRefreshPhase
    let balances: BankSyncResourceState
    let transactions: BankSyncResourceState
    let lastSuccessfulBalanceRefresh: Date?
    let lastSuccessfulTransactionRefresh: Date?
    let hasUsableBalances: Bool
    let hasUsableTransactions: Bool
    let rateLimitMessage: String?

    static func initial(
        hasCachedBalances: Bool,
        hasCachedTransactions: Bool,
        lastSuccessfulBalanceRefresh: Date?,
        lastSuccessfulTransactionRefresh: Date?,
        requiresAuthentication: Bool
    ) -> BankSyncRefreshState {
        if requiresAuthentication {
            return authenticationRequired(
                previousBalanceRefresh: lastSuccessfulBalanceRefresh,
                previousTransactionRefresh: lastSuccessfulTransactionRefresh
            )
        }

        return BankSyncRefreshState(
            phase: hasCachedBalances ? .showingEarlierData : .idle,
            balances: hasCachedBalances ? .showingEarlierData : .notRequested,
            transactions: hasCachedTransactions ? .showingEarlierData : .notRequested,
            lastSuccessfulBalanceRefresh: lastSuccessfulBalanceRefresh,
            lastSuccessfulTransactionRefresh: lastSuccessfulTransactionRefresh,
            hasUsableBalances: hasCachedBalances,
            hasUsableTransactions: hasCachedTransactions,
            rateLimitMessage: nil
        )
    }

    static func authenticationRequired(
        previousBalanceRefresh: Date?,
        previousTransactionRefresh: Date?
    ) -> BankSyncRefreshState {
        return BankSyncRefreshState(
            phase: .authenticationRequired,
            balances: .notRequested,
            transactions: .notRequested,
            lastSuccessfulBalanceRefresh: previousBalanceRefresh,
            lastSuccessfulTransactionRefresh: previousTransactionRefresh,
            hasUsableBalances: false,
            hasUsableTransactions: false,
            rateLimitMessage: nil
        )
    }

    static var notConnected: BankSyncRefreshState {
        BankSyncRefreshState(
            phase: .notConnected,
            balances: .notConnected,
            transactions: .notConnected,
            lastSuccessfulBalanceRefresh: nil,
            lastSuccessfulTransactionRefresh: nil,
            hasUsableBalances: false,
            hasUsableTransactions: false,
            rateLimitMessage: nil
        )
    }

    func loading(
        includesTransactions: Bool
    ) -> BankSyncRefreshState {
        BankSyncRefreshState(
            phase: .loading,
            balances: .loading,
            transactions: includesTransactions ? .loading : .disabled,
            lastSuccessfulBalanceRefresh: lastSuccessfulBalanceRefresh,
            lastSuccessfulTransactionRefresh: includesTransactions
                ? lastSuccessfulTransactionRefresh
                : nil,
            hasUsableBalances: hasUsableBalances,
            hasUsableTransactions: includesTransactions && hasUsableTransactions,
            rateLimitMessage: nil
        )
    }

    func rateLimited(
        message: String,
        includesTransactions: Bool
    ) -> BankSyncRefreshState {
        BankSyncRefreshState(
            phase: .rateLimited,
            balances: .rateLimited,
            transactions: includesTransactions ? .rateLimited : .disabled,
            lastSuccessfulBalanceRefresh: lastSuccessfulBalanceRefresh,
            lastSuccessfulTransactionRefresh: includesTransactions
                ? lastSuccessfulTransactionRefresh
                : nil,
            hasUsableBalances: hasUsableBalances,
            hasUsableTransactions: includesTransactions && hasUsableTransactions,
            rateLimitMessage: message
        )
    }

    func disablingTransactions() -> BankSyncRefreshState {
        let nextPhase: BankSyncRefreshPhase = balances == .updated
            ? .fullyUpdated
            : phase

        return BankSyncRefreshState(
            phase: nextPhase,
            balances: balances,
            transactions: .disabled,
            lastSuccessfulBalanceRefresh: lastSuccessfulBalanceRefresh,
            lastSuccessfulTransactionRefresh: nil,
            hasUsableBalances: hasUsableBalances,
            hasUsableTransactions: false,
            rateLimitMessage: rateLimitMessage
        )
    }

    var balanceNeedsAttention: Bool {
        switch balances {
        case .partiallyUpdated,
             .showingEarlierData,
             .unavailable,
             .rateLimited:
            return true

        case .notRequested,
             .loading,
             .updated,
             .disabled,
             .notConnected:
            return false
        }
    }

    var shouldOfferRetry: Bool {
        switch phase {
        case .partiallyUpdated,
             .showingEarlierData,
             .unavailable,
             .rateLimited:
            return true

        case .idle,
             .loading,
             .fullyUpdated,
             .notConnected,
             .authenticationRequired:
            return false
        }
    }

    var statusTitle: String {
        switch phase {
        case .idle:
            return "Bank Sync status"
        case .loading:
            return "Refreshing bank data"
        case .fullyUpdated:
            return "Bank data updated"
        case .partiallyUpdated:
            return "Partially updated"
        case .showingEarlierData:
            return "Showing earlier data"
        case .unavailable:
            return "Bank Sync unavailable"
        case .rateLimited:
            return "Bank Sync briefly paused"
        case .notConnected:
            return "No linked accounts"
        case .authenticationRequired:
            return "Sign in required"
        }
    }

    var statusMessage: String? {
        switch phase {
        case .idle,
             .notConnected:
            return nil

        case .loading:
            return "Refreshing linked balances and recent activity."

        case .fullyUpdated:
            return "Bank data refreshed."

        case .partiallyUpdated:
            if balances == .updated {
                return "Balances refreshed. Some recent activity couldn't update."
            }

            return "Some bank information couldn't update. Showing your most recent balances."

        case .showingEarlierData:
            return "Some bank information couldn't update. Showing your most recent balances."

        case .unavailable:
            return "Bank Sync is unavailable right now. Try again when you're ready."

        case .rateLimited:
            if balances == .updated {
                return "Balances refreshed. Recent activity is briefly paused."
            }

            if hasUsableBalances {
                return "\(rateLimitMessage ?? "Bank Sync is briefly paused.") Showing your most recent balances."
            }

            return rateLimitMessage ?? "Bank Sync is briefly paused. Please try again in a moment."

        case .authenticationRequired:
            return "Sign in with Apple to use Bank Sync."
        }
    }
}

enum BankSyncRefreshReducer {
    static func resolve(
        accountOutcome: BankSyncFetchOutcome,
        transactionOutcome: BankSyncFetchOutcome,
        previousState: BankSyncRefreshState,
        hasUsableBalances: Bool,
        hasUsableTransactions: Bool,
        completedAt: Date
    ) -> BankSyncRefreshState {
        if accountOutcome == .authenticationRequired ||
            transactionOutcome == .authenticationRequired {
            return .authenticationRequired(
                previousBalanceRefresh: previousState.lastSuccessfulBalanceRefresh,
                previousTransactionRefresh: previousState.lastSuccessfulTransactionRefresh
            )
        }

        if accountOutcome == .notLinked {
            return .notConnected
        }

        let balanceState = resourceState(
            for: accountOutcome,
            hasUsableData: hasUsableBalances
        )
        let transactionState = resourceState(
            for: transactionOutcome,
            hasUsableData: hasUsableTransactions
        )
        let balanceRefreshDate = accountOutcome == .success
            ? completedAt
            : previousState.lastSuccessfulBalanceRefresh
        let transactionRefreshDate: Date?

        switch transactionOutcome {
        case .success:
            transactionRefreshDate = completedAt
        case .disabled:
            transactionRefreshDate = nil
        case .partialSuccess,
             .failure,
             .rateLimited,
             .notLinked,
             .authenticationRequired:
            transactionRefreshDate = previousState.lastSuccessfulTransactionRefresh
        }

        let rateLimitMessage = accountOutcome.rateLimitMessage ??
            transactionOutcome.rateLimitMessage
        let phase = refreshPhase(
            accountOutcome: accountOutcome,
            transactionOutcome: transactionOutcome,
            hasUsableBalances: hasUsableBalances
        )

        return BankSyncRefreshState(
            phase: phase,
            balances: balanceState,
            transactions: transactionState,
            lastSuccessfulBalanceRefresh: balanceRefreshDate,
            lastSuccessfulTransactionRefresh: transactionRefreshDate,
            hasUsableBalances: hasUsableBalances,
            hasUsableTransactions: transactionOutcome != .disabled && hasUsableTransactions,
            rateLimitMessage: rateLimitMessage
        )
    }

    private static func resourceState(
        for outcome: BankSyncFetchOutcome,
        hasUsableData: Bool
    ) -> BankSyncResourceState {
        switch outcome {
        case .success:
            return .updated
        case .partialSuccess:
            return hasUsableData ? .partiallyUpdated : .unavailable
        case .failure,
             .notLinked:
            return hasUsableData ? .showingEarlierData : .unavailable
        case .rateLimited:
            return .rateLimited
        case .authenticationRequired:
            return .notRequested
        case .disabled:
            return .disabled
        }
    }

    private static func refreshPhase(
        accountOutcome: BankSyncFetchOutcome,
        transactionOutcome: BankSyncFetchOutcome,
        hasUsableBalances: Bool
    ) -> BankSyncRefreshPhase {
        if accountOutcome.rateLimitMessage != nil ||
            transactionOutcome.rateLimitMessage != nil {
            return .rateLimited
        }

        switch accountOutcome {
        case .failure:
            return hasUsableBalances ? .showingEarlierData : .unavailable
        case .partialSuccess:
            return hasUsableBalances ? .partiallyUpdated : .unavailable
        case .success:
            switch transactionOutcome {
            case .success,
                 .disabled:
                return .fullyUpdated
            case .partialSuccess,
                 .failure,
                 .notLinked:
                return .partiallyUpdated
            case .rateLimited:
                return .rateLimited
            case .authenticationRequired:
                return .authenticationRequired
            }
        case .rateLimited:
            return .rateLimited
        case .notLinked:
            return .notConnected
        case .authenticationRequired:
            return .authenticationRequired
        case .disabled:
            return .unavailable
        }
    }
}
