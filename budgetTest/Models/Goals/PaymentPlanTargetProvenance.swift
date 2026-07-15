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

enum PaymentPlanCalendarDate {

    /// Converts a Plaid `YYYY-MM-DD` calendar-date key into the `Date`
    /// compatibility representation used by the existing Payment Plan models.
    ///
    /// The source value is not an instant in UTC. Building it in the caller's
    /// calendar preserves the supplied year, month, and day when the existing
    /// Date-backed editor, bucket, and cycle APIs consume it.
    static func parse(
        _ value: String?,
        calendar: Calendar = .current
    ) -> Date? {
        guard let value,
              value.utf8.count == 10,
              value.utf8.enumerated().allSatisfy({ index, byte in
                if index == 4 || index == 7 {
                    return byte == 45
                }

                return byte >= 48 && byte <= 57
              }) else {
            return nil
        }

        let parts = value.split(
            separator: "-",
            omittingEmptySubsequences: false
        )
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = Locale(identifier: "en_US_POSIX")
        gregorian.timeZone = calendar.timeZone

        var components = DateComponents()
        components.calendar = gregorian
        components.timeZone = gregorian.timeZone
        components.year = year
        components.month = month
        components.day = day
        // The existing editor and persistence APIs use Date for calendar days.
        // Midnight in the caller's calendar keeps their comparisons aligned
        // without first turning the source key into a UTC instant.
        components.hour = 0

        guard let date = gregorian.date(from: components) else {
            return nil
        }

        let roundTrip = gregorian.dateComponents(
            [.year, .month, .day],
            from: date
        )
        guard roundTrip.year == year,
              roundTrip.month == month,
              roundTrip.day == day else {
            return nil
        }

        return date
    }

    static func abbreviatedMonthDay(
        _ date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = locale
        gregorian.timeZone = calendar.timeZone

        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.locale = locale
        formatter.timeZone = gregorian.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    static func anchor(
        for choice: DebtPayoffLinkedCardPaymentTargetChoice?,
        liveValue: String?,
        calendar: Calendar = .current
    ) -> Date? {
        guard choice == .statementBalance else {
            return nil
        }

        return parse(
            liveValue,
            calendar: calendar
        )
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

struct PaymentPlanSuggestedUpdateSnapshot: Equatable {

    enum Fact: Equatable {
        case statementBalance(
            amount: Double,
            reason: PaymentPlanStatementSuggestedUpdateReason,
            issueDate: Date?
        )
        case minimumPayment(amount: Double)
        case currentBalance(amount: Double)
        case dueDate(Date)
    }

    let facts: [Fact]
    let liveStatementIssueDate: Date?
    let liveDueDate: Date?

    init(
        currentPaymentTarget: Double?,
        storedTargetChoice: DebtPayoffLinkedCardPaymentTargetChoice?,
        storedStatementIssueDate: Date?,
        dueDate: Date,
        shouldDisplayDueDate: Bool,
        cardPaymentDetails: LinkedCardPaymentDetails?,
        calendar: Calendar = .current
    ) {
        guard let cardPaymentDetails else {
            facts = []
            liveStatementIssueDate = nil
            liveDueDate = nil
            return
        }

        let liveStatementIssueDate = PaymentPlanCalendarDate.parse(
            cardPaymentDetails.last_statement_issue_date,
            calendar: calendar
        )
        let liveDueDate = PaymentPlanCalendarDate.parse(
            cardPaymentDetails.next_payment_due_date,
            calendar: calendar
        )
        var facts: [Fact] = []
        var suggestedAmounts: [Double] = []

        if let statementBalance = cardPaymentDetails.last_statement_balance,
           let reason = PaymentPlanSuggestedUpdateRules.statementSuggestionReason(
                liveStatementBalance: statementBalance,
                liveStatementIssueDate: liveStatementIssueDate,
                storedChoice: storedTargetChoice,
                currentTarget: currentPaymentTarget,
                storedStatementIssueDate: storedStatementIssueDate
           ) {
            facts.append(
                .statementBalance(
                    amount: statementBalance,
                    reason: reason,
                    issueDate: liveStatementIssueDate
                )
            )
            suggestedAmounts.append(statementBalance)
        }

        Self.appendTargetFact(
            .minimumPayment,
            liveAmount: cardPaymentDetails.minimum_payment_amount,
            storedTargetChoice: storedTargetChoice,
            currentPaymentTarget: currentPaymentTarget,
            facts: &facts,
            suggestedAmounts: &suggestedAmounts
        )
        Self.appendTargetFact(
            .currentBalance,
            liveAmount: cardPaymentDetails.current_balance,
            storedTargetChoice: storedTargetChoice,
            currentPaymentTarget: currentPaymentTarget,
            facts: &facts,
            suggestedAmounts: &suggestedAmounts
        )

        if shouldDisplayDueDate,
           let liveDueDate,
           !calendar.isDate(liveDueDate, inSameDayAs: dueDate) {
            facts.append(.dueDate(liveDueDate))
        }

        self.facts = facts
        self.liveStatementIssueDate = liveStatementIssueDate
        self.liveDueDate = liveDueDate
    }

    init(
        paymentPlan: DebtPayoffBucket,
        cardPaymentDetails: LinkedCardPaymentDetails?,
        calendar: Calendar = .current
    ) {
        self.init(
            currentPaymentTarget: paymentPlan.paymentTargetAmount,
            storedTargetChoice: paymentPlan.paymentTargetChoice,
            storedStatementIssueDate: paymentPlan.targetStatementIssueDate,
            dueDate: paymentPlan.dueDate,
            shouldDisplayDueDate: paymentPlan.shouldDisplayDueDate,
            cardPaymentDetails: cardPaymentDetails,
            calendar: calendar
        )
    }

    private static func appendTargetFact(
        _ kind: PaymentPlanLiveAmountKind,
        liveAmount: Double?,
        storedTargetChoice: DebtPayoffLinkedCardPaymentTargetChoice?,
        currentPaymentTarget: Double?,
        facts: inout [Fact],
        suggestedAmounts: inout [Double]
    ) {
        guard let liveAmount,
              PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: kind,
                liveAmount: liveAmount,
                storedChoice: storedTargetChoice,
                currentTarget: currentPaymentTarget
              ),
              !suggestedAmounts.contains(where: {
                  PaymentPlanSuggestedUpdateRules.amountsMatch(
                    $0,
                    liveAmount
                  )
              }) else {
            return
        }

        switch kind {
        case .statementBalance:
            return
        case .minimumPayment:
            facts.append(.minimumPayment(amount: liveAmount))
        case .currentBalance:
            facts.append(.currentBalance(amount: liveAmount))
        }

        suggestedAmounts.append(liveAmount)
    }
}
