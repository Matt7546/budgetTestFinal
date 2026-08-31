import Foundation

enum DashboardRefreshTapDecision: Equatable {
    case signInRequired
    case linkAccountRequired
    case startRefresh
    case ignoreWhileRefreshing
}

enum DashboardRefreshPresentation {

    static func tapDecision(
        isSignedIn: Bool,
        hasLinkedAccounts: Bool,
        isRefreshing: Bool
    ) -> DashboardRefreshTapDecision {
        if isRefreshing {
            return .ignoreWhileRefreshing
        }

        guard isSignedIn else {
            return .signInRequired
        }

        guard hasLinkedAccounts else {
            return .linkAccountRequired
        }

        return .startRefresh
    }

    static func buttonTitle(isRefreshing: Bool) -> String {
        isRefreshing ? "Refreshing…" : "Refresh"
    }

    static func statusText(
        isRefreshing: Bool,
        state: BankSyncRefreshState,
        accountsLastUpdatedText: String
    ) -> String? {
        if isRefreshing || state.phase == .loading {
            return "Refreshing…"
        }

        switch state.phase {
        case .fullyUpdated:
            return accountsLastUpdatedText.replacingOccurrences(
                of: "Last refreshed",
                with: "Updated"
            )

        case .partiallyUpdated:
            return "Couldn’t refresh everything. Showing your most recent data."

        case .showingEarlierData,
             .unavailable:
            return "Couldn’t refresh everything. Try again in a little bit."

        case .rateLimited:
            return "Try again in a little bit."

        case .idle,
             .loading,
             .notConnected,
             .authenticationRequired:
            return nil
        }
    }
}
