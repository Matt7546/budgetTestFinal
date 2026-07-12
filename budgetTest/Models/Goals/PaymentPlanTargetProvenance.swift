import Foundation

enum DebtPayoffLinkedCardPaymentTargetChoice: String, CaseIterable, Identifiable {
    case statementBalance
    case minimumPayment
    case currentBalance
    case customAmount

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .statementBalance:
            return "Statement balance"
        case .minimumPayment:
            return "Minimum payment"
        case .currentBalance:
            return "Full current balance"
        case .customAmount:
            return "Custom amount"
        }
    }

    func suggestedAmount(
        statementBalance: Double?,
        minimumPayment: Double?,
        currentBalance: Double?
    ) -> Double? {
        let value: Double?

        switch self {
        case .statementBalance:
            value = statementBalance
        case .minimumPayment:
            value = minimumPayment
        case .currentBalance:
            value = currentBalance
        case .customAmount:
            value = nil
        }

        guard let value,
              value > 0 else {
            return nil
        }

        return value
    }
}

enum DebtPayoffLinkedCardPaymentTargetValidation {

    static func isReady(
        choice: DebtPayoffLinkedCardPaymentTargetChoice?,
        paymentTarget: Double
    ) -> Bool {
        choice != nil && paymentTarget > 0
    }
}

enum PaymentPlanLiveAmountKind {
    case statementBalance
    case minimumPayment
    case currentBalance
}

enum PaymentPlanStatementSuggestedUpdateReason: Equatable {
    case newerStatement
    case statementAmountChanged
    case legacyReview
}

enum PaymentPlanStatementIssueDate {

    static func parse(_ value: String?) -> Date? {
        guard let value,
              !value.isEmpty else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    static func anchor(
        for choice: DebtPayoffLinkedCardPaymentTargetChoice?,
        liveValue: String?
    ) -> Date? {
        guard choice == .statementBalance else {
            return nil
        }

        return parse(liveValue)
    }
}

/// Choice-aware rules for linked-card Suggested Updates.
///
/// A plan's saved target choice decides which live card amounts are allowed
/// to suggest a target change. A Statement balance plan is not second-guessed
/// by newer spending on the current balance, and a Custom amount plan is not
/// second-guessed by any live amount. Plans saved before target provenance
/// existed have no stored choice and keep the earlier behavior, where every
/// live amount may surface for review.
enum PaymentPlanSuggestedUpdateRules {

    static let amountTolerance = 0.005

    static func amountsMatch(
        _ lhs: Double,
        _ rhs: Double
    ) -> Bool {
        abs(lhs - rhs) < amountTolerance
    }

    static func allowsTargetSuggestion(
        kind: PaymentPlanLiveAmountKind,
        storedChoice: DebtPayoffLinkedCardPaymentTargetChoice?
    ) -> Bool {
        guard let storedChoice else {
            return true
        }

        switch storedChoice {
        case .customAmount:
            return false

        case .statementBalance:
            return kind == .statementBalance

        case .minimumPayment:
            return kind == .minimumPayment

        case .currentBalance:
            return kind == .currentBalance
        }
    }

    static func shouldSuggestTargetUpdate(
        kind: PaymentPlanLiveAmountKind,
        liveAmount: Double?,
        storedChoice: DebtPayoffLinkedCardPaymentTargetChoice?,
        currentTarget: Double?
    ) -> Bool {
        guard let liveAmount,
              liveAmount > 0,
              allowsTargetSuggestion(
                kind: kind,
                storedChoice: storedChoice
              ) else {
            return false
        }

        guard let currentTarget,
              currentTarget > 0 else {
            return true
        }

        return !amountsMatch(
            currentTarget,
            liveAmount
        )
    }

    static func statementSuggestionReason(
        liveStatementBalance: Double?,
        liveStatementIssueDate: Date?,
        storedChoice: DebtPayoffLinkedCardPaymentTargetChoice?,
        currentTarget: Double?,
        storedStatementIssueDate: Date?
    ) -> PaymentPlanStatementSuggestedUpdateReason? {
        guard let liveStatementBalance,
              liveStatementBalance > 0,
              allowsTargetSuggestion(
                kind: .statementBalance,
                storedChoice: storedChoice
              ) else {
            return nil
        }

        let amountChanged: Bool

        if let currentTarget,
           currentTarget > 0 {
            amountChanged = !amountsMatch(
                currentTarget,
                liveStatementBalance
            )
        } else {
            amountChanged = true
        }

        if let storedStatementIssueDate,
           let liveStatementIssueDate {
            if liveStatementIssueDate > storedStatementIssueDate {
                return .newerStatement
            }

            if liveStatementIssueDate < storedStatementIssueDate {
                return nil
            }

            return amountChanged ? .statementAmountChanged : nil
        }

        guard amountChanged else {
            return nil
        }

        if storedStatementIssueDate == nil {
            return .legacyReview
        }

        return .statementAmountChanged
    }
}
