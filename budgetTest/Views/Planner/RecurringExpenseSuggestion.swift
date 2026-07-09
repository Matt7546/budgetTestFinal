import Foundation

enum RecurringExpenseSuggestionStatus: String, Codable {
    case pending
    case added
    case dismissed
}

struct RecurringExpenseRecommendationGroups {
    let needsReview: [RecurringExpenseSuggestion]
    let added: [RecurringExpenseSuggestion]
    let dismissed: [RecurringExpenseSuggestion]

    var totalCount: Int {
        needsReview.count + added.count + dismissed.count
    }

    init(
        suggestions: [RecurringExpenseSuggestion],
        statuses: [String: RecurringExpenseSuggestionStatus]
    ) {
        var needsReview = [RecurringExpenseSuggestion]()
        var added = [RecurringExpenseSuggestion]()
        var dismissed = [RecurringExpenseSuggestion]()

        for suggestion in suggestions {
            let status = statuses[suggestion.id] ?? .pending

            if suggestion.isAlreadyInPlan || status == .added {
                added.append(suggestion)
            } else if status == .dismissed {
                dismissed.append(suggestion)
            } else {
                needsReview.append(suggestion)
            }
        }

        self.needsReview = needsReview
        self.added = added
        self.dismissed = dismissed
    }
}

struct RecurringExpenseSuggestion: Identifiable {
    let id: String
    let merchantName: String
    let normalizedName: String
    let amount: Double
    let nextDueDate: Date
    let dayOfMonth: Int
    let occurrenceCount: Int
    let isAlreadyInPlan: Bool

    var bodyText: String {
        "\(merchantName) looks monthly around the \(dayText) for about \(AppFormatters.currency(amount))."
    }

    var plannerDraft: PlannerEventDraft {
        PlannerEventDraft(
            name: merchantName,
            amount: amount,
            date: nextDueDate,
            type: .expense,
            frequency: .monthly,
            accentColorID: nil
        )
    }

    private var dayText: String {
        Self.ordinalFormatter.string(
            from: NSNumber(value: dayOfMonth)
        ) ?? "\(dayOfMonth)"
    }

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}

enum RecurringExpenseSuggestionEngine {
    private struct CandidateTransaction {
        let rawName: String
        let normalizedName: String
        let amount: Double
        let date: Date
    }

    static func suggestions(
        transactions: [PlaidTransaction],
        existingEvents: [PlannerEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RecurringExpenseSuggestion] {
        let candidates = transactions.compactMap { transaction -> CandidateTransaction? in
            guard transaction.amount > 0.01,
                  let date = transactionDateFormatter.date(from: transaction.date),
                  !shouldIgnoreTransactionName(transaction.name) else {
                return nil
            }

            let normalizedName = normalizedMerchantName(transaction.name)

            guard !normalizedName.isEmpty else {
                return nil
            }

            return CandidateTransaction(
                rawName: transaction.name,
                normalizedName: normalizedName,
                amount: transaction.amount,
                date: calendar.startOfDay(for: date)
            )
        }

        let groupedCandidates = Dictionary(
            grouping: candidates,
            by: \.normalizedName
        )

        return groupedCandidates.compactMap { normalizedName, group in
            suggestion(
                normalizedName: normalizedName,
                candidates: group,
                existingEvents: existingEvents,
                now: now,
                calendar: calendar
            )
        }
        .sorted { first, second in
            if calendar.isDate(first.nextDueDate, inSameDayAs: second.nextDueDate) {
                return first.merchantName < second.merchantName
            }

            return first.nextDueDate < second.nextDueDate
        }
    }

    private static func suggestion(
        normalizedName: String,
        candidates: [CandidateTransaction],
        existingEvents: [PlannerEvent],
        now: Date,
        calendar: Calendar
    ) -> RecurringExpenseSuggestion? {
        let occurrences = uniqueDailyOccurrences(
            candidates,
            calendar: calendar
        )
        .sorted { $0.date < $1.date }

        guard occurrences.count >= 3,
              hasMonthlyCadence(occurrences, calendar: calendar) else {
            return nil
        }

        let amounts = occurrences.map(\.amount)
        let suggestedAmount = median(amounts)

        guard amounts.allSatisfy({ amount in
            amountsAreSimilar(
                amount,
                suggestedAmount
            )
        }) else {
            return nil
        }

        guard let latestOccurrence = occurrences.last,
              let nextDueDate = nextMonthlyDate(
                after: latestOccurrence.date,
                now: now,
                calendar: calendar
              ) else {
            return nil
        }

        let alreadyInPlan = isAlreadyRepresented(
            normalizedName: normalizedName,
            amount: suggestedAmount,
            nextDueDate: nextDueDate,
            existingEvents: existingEvents,
            calendar: calendar
        )
        let dayOfMonth = calendar.component(
            .day,
            from: nextDueDate
        )
        let id = [
            normalizedName,
            "monthly",
            String(Int((suggestedAmount * 100).rounded())),
            String(dayOfMonth)
        ]
        .joined(separator: "|")

        return RecurringExpenseSuggestion(
            id: id,
            merchantName: displayName(from: latestOccurrence.rawName),
            normalizedName: normalizedName,
            amount: suggestedAmount,
            nextDueDate: nextDueDate,
            dayOfMonth: dayOfMonth,
            occurrenceCount: occurrences.count,
            isAlreadyInPlan: alreadyInPlan
        )
    }

    private static func uniqueDailyOccurrences(
        _ candidates: [CandidateTransaction],
        calendar: Calendar
    ) -> [CandidateTransaction] {
        candidates
            .sorted { first, second in
                if calendar.isDate(first.date, inSameDayAs: second.date) {
                    return first.amount > second.amount
                }

                return first.date < second.date
            }
            .reduce(into: [CandidateTransaction]()) { result, candidate in
                guard !result.contains(where: {
                    calendar.isDate($0.date, inSameDayAs: candidate.date)
                }) else {
                    return
                }

                result.append(candidate)
            }
    }

    private static func hasMonthlyCadence(
        _ occurrences: [CandidateTransaction],
        calendar: Calendar
    ) -> Bool {
        guard occurrences.count >= 3 else {
            return false
        }

        let intervals = zip(
            occurrences.dropLast(),
            occurrences.dropFirst()
        )
        .compactMap { previous, next in
            calendar.dateComponents(
                [.day],
                from: previous.date,
                to: next.date
            ).day
        }

        guard intervals.count == occurrences.count - 1 else {
            return false
        }

        return intervals.allSatisfy { interval in
            (24...38).contains(interval)
        }
    }

    private static func amountsAreSimilar(
        _ lhs: Double,
        _ rhs: Double
    ) -> Bool {
        abs(lhs - rhs) <= max(
            5,
            rhs * 0.15
        )
    }

    private static func isAlreadyRepresented(
        normalizedName: String,
        amount: Double,
        nextDueDate: Date,
        existingEvents: [PlannerEvent],
        calendar: Calendar
    ) -> Bool {
        existingEvents
            .filter { $0.type == .expense }
            .contains { event in
                let eventName = normalizedMerchantName(event.name)

                guard !eventName.isEmpty else {
                    return false
                }

                let nameMatches = eventName == normalizedName ||
                    eventName.contains(normalizedName) ||
                    normalizedName.contains(eventName)
                let amountMatches = amountsAreSimilar(
                    event.amount,
                    amount
                )
                let cadenceMatches = event.frequency == .monthly ||
                    dueDaysAreClose(
                        calendar.component(.day, from: event.date),
                        calendar.component(.day, from: nextDueDate)
                    )

                return nameMatches && amountMatches && cadenceMatches
            }
    }

    private static func dueDaysAreClose(
        _ lhs: Int,
        _ rhs: Int
    ) -> Bool {
        let distance = abs(lhs - rhs)
        return min(
            distance,
            31 - distance
        ) <= 4
    }

    private static func nextMonthlyDate(
        after latestDate: Date,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        var nextDate = calendar.date(
            byAdding: .month,
            value: 1,
            to: latestDate
        )
        let today = calendar.startOfDay(for: now)
        var attempts = 0

        while let candidate = nextDate,
              candidate < today,
              attempts < 12 {
            nextDate = calendar.date(
                byAdding: .month,
                value: 1,
                to: candidate
            )
            attempts += 1
        }

        return nextDate
    }

    private static func median(
        _ values: [Double]
    ) -> Double {
        let sortedValues = values.sorted()
        let middleIndex = sortedValues.count / 2

        if sortedValues.count.isMultiple(of: 2) {
            return (
                sortedValues[middleIndex - 1] + sortedValues[middleIndex]
            ) / 2
        }

        return sortedValues[middleIndex]
    }

    private static func normalizedMerchantName(
        _ value: String
    ) -> String {
        value
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9]+",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\b\\d+\\b",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayName(
        from value: String
    ) -> String {
        let cleaned = value
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return "Upcoming expense"
        }

        if cleaned == cleaned.uppercased() {
            return cleaned.localizedCapitalized
        }

        return cleaned
    }

    private static func shouldIgnoreTransactionName(
        _ name: String
    ) -> Bool {
        let value = name.lowercased()
        let ignoredFragments = [
            "refund",
            "deposit",
            "payroll",
            "salary",
            "transfer",
            "venmo",
            "zelle",
            "cash app"
        ]

        if ignoredFragments.contains(where: { value.contains($0) }) {
            return true
        }

        let paymentFragments = [
            "payment",
            "pymt"
        ]
        let accountPaymentFragments = [
            "amex",
            "american express",
            "capital one",
            "card",
            "cardmember",
            "chase",
            "citi",
            "credit",
            "discover",
            "loan",
            "mastercard",
            "visa"
        ]

        return paymentFragments.contains(where: { value.contains($0) }) &&
            accountPaymentFragments.contains(where: { value.contains($0) })
    }

    private static let transactionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
