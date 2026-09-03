import Foundation

enum CoverInFullPolicy {

    static let amountTolerance = 0.005
    static let actionTitle = "Cover in Full"
    static let holdActionTitle = "Hold to Cover in Full"
    static let failureMessage =
        "This update wasn’t saved. Please try again."

    static func remainingAmount(
        target: Double,
        current: Double
    ) -> Double {
        guard target.isFinite,
              current.isFinite,
              target > 0 else {
            return 0
        }

        let remaining = max(
            target - max(current, 0),
            0
        )

        return remaining <= amountTolerance
            ? 0
            : remaining
    }

    static func confirmationMessage(
        amount: Double,
        name: String
    ) -> String {
        "Set aside \(AppFormatters.currency(amount)) to cover \(name) in full? This updates your plan; no money moves."
    }

    static func successMessage(
        name: String
    ) -> String {
        "\(name) fully covered"
    }

    static func inputAmountText(_ amount: Double) -> String {
        String(format: "%.2f", max(amount, 0))
    }
}

struct CoverInFullRequest: Identifiable, Equatable {

    let id = UUID()
    let name: String
    let amount: Double

    var confirmationMessage: String {
        CoverInFullPolicy.confirmationMessage(
            amount: amount,
            name: name
        )
    }
}
