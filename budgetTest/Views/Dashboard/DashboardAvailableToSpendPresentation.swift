import Foundation

enum DashboardAvailableToSpendPresentation: Equatable {
    case unavailable
    case planningUnavailable(isLoading: Bool)
    case calculated(Double)

    static func make(
        canShowBankData: Bool,
        planningSnapshotAvailability: PlanningSnapshotAvailability = .available,
        safeToSpend: Double
    ) -> DashboardAvailableToSpendPresentation {
        guard canShowBankData else { return .unavailable }
        guard planningSnapshotAvailability == .available else {
            return .planningUnavailable(
                isLoading: planningSnapshotAvailability == .loading
            )
        }
        return .calculated(safeToSpend)
    }

    func amountText(
        isSensitiveDataHidden: Bool = false
    ) -> String {
        switch self {
        case .unavailable,
             .planningUnavailable:
            return "—"
        case .calculated(let safeToSpend):
            return SensitiveValueFormatter.amount(
                safeToSpend,
                isHidden: isSensitiveDataHidden
            )
        }
    }

    var unavailableGuidance: String? {
        switch self {
        case .unavailable:
            return "Sign in and link accounts to estimate from your balances."
        case .planningUnavailable(let isLoading):
            return isLoading
                ? "Loading your Set Aside plan before calculating this amount."
                : "Your Set Aside plan couldn’t load, so this amount is paused. Your saved plan is unchanged."
        case .calculated:
            return nil
        }
    }

    func accessibilityValue(
        isSensitiveDataHidden: Bool = false
    ) -> String {
        switch self {
        case .unavailable:
            return "Not ready yet. Sign in and link accounts to calculate Available to Spend."
        case .planningUnavailable(let isLoading):
            return isLoading
                ? "Loading your Set Aside plan before calculating Available to Spend."
                : "Available to Spend is unavailable because your Set Aside plan could not load."
        case .calculated(let safeToSpend):
            return isSensitiveDataHidden
                ? "Hidden"
                : AppFormatters.currency(safeToSpend)
        }
    }
}
