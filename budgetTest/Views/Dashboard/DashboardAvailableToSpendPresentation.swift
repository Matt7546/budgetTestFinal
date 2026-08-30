import Foundation

enum DashboardAvailableToSpendPresentation: Equatable {
    case unavailable
    case calculated(Double)

    static func make(
        canShowBankData: Bool,
        safeToSpend: Double
    ) -> DashboardAvailableToSpendPresentation {
        canShowBankData ? .calculated(safeToSpend) : .unavailable
    }

    var amountText: String {
        switch self {
        case .unavailable:
            return "—"
        case .calculated(let safeToSpend):
            return AppFormatters.currency(safeToSpend)
        }
    }

    var unavailableGuidance: String? {
        guard case .unavailable = self else {
            return nil
        }

        return "Sign in and link accounts to estimate from your balances."
    }

    var accessibilityValue: String {
        switch self {
        case .unavailable:
            return "Not ready yet. Sign in and link accounts to calculate Available to Spend."
        case .calculated(let safeToSpend):
            return AppFormatters.currency(safeToSpend)
        }
    }
}
