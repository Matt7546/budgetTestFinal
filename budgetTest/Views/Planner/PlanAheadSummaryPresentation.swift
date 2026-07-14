import Foundation

struct PlanAheadSummaryEntry: Equatable {
    /// `nil` means the item cannot contribute a trustworthy amount yet.
    let dueAmount: Double?
    let coveredAmount: Double
    let stillNeededAmount: Double

    init(
        dueAmount: Double?,
        coveredAmount: Double,
        stillNeededAmount: Double
    ) {
        self.dueAmount = dueAmount
        self.coveredAmount = coveredAmount
        self.stillNeededAmount = stillNeededAmount
    }
}

struct PlanAheadSummaryPresentation: Equatable {
    enum State: Equatable {
        case needsAttention
        case partlyCovered
        case fullyCovered
        case nothingDueSoon
    }

    let dueSoonAmount: Double
    let coveredAmount: Double
    let stillNeededAmount: Double
    let pastDueCount: Int
    let missingAmountCount: Int
    let state: State

    private let currencyTolerance = 0.005

    init(
        entries: [PlanAheadSummaryEntry],
        pastDueCount: Int
    ) {
        let knownEntries = entries.compactMap { entry -> PlanAheadSummaryEntry? in
            guard let dueAmount = entry.dueAmount,
                  dueAmount > 0 else {
                return nil
            }

            return PlanAheadSummaryEntry(
                dueAmount: dueAmount,
                coveredAmount: entry.coveredAmount,
                stillNeededAmount: entry.stillNeededAmount
            )
        }

        dueSoonAmount = knownEntries.reduce(0) { total, entry in
            total + (entry.dueAmount ?? 0)
        }
        coveredAmount = knownEntries.reduce(0) { total, entry in
            total + entry.coveredAmount
        }
        stillNeededAmount = knownEntries.reduce(0) { total, entry in
            total + entry.stillNeededAmount
        }
        self.pastDueCount = max(pastDueCount, 0)
        missingAmountCount = entries.count - knownEntries.count

        if self.pastDueCount > 0 || missingAmountCount > 0 ||
            stillNeededAmount > currencyTolerance {
            state = coveredAmount > currencyTolerance &&
                stillNeededAmount > currencyTolerance &&
                self.pastDueCount == 0 &&
                missingAmountCount == 0
                ? .partlyCovered
                : .needsAttention
        } else if dueSoonAmount > currencyTolerance {
            state = .fullyCovered
        } else {
            state = .nothingDueSoon
        }
    }

    var dueSoonValue: String {
        if dueSoonAmount <= currencyTolerance && missingAmountCount > 0 {
            return "—"
        }

        return AppFormatters.currency(dueSoonAmount)
    }

    var coveredValue: String {
        AppFormatters.currency(coveredAmount)
    }

    var stillNeededValue: String {
        AppFormatters.currency(stillNeededAmount)
    }

    var stateTitle: String {
        switch state {
        case .needsAttention:
            return "Needs attention"
        case .partlyCovered:
            return "Partly covered"
        case .fullyCovered:
            return "Fully covered"
        case .nothingDueSoon:
            return "Nothing due soon"
        }
    }

    var detail: String {
        if pastDueCount > 0 {
            return "\(pastDueCount) \(pastDueCount == 1 ? "item is" : "items are") past due."
        }

        if missingAmountCount > 0 {
            return "\(missingAmountCount) Payment \(missingAmountCount == 1 ? "Plan needs" : "Plans need") a planned payment."
        }

        switch state {
        case .needsAttention:
            return "\(stillNeededValue) still needs money."
        case .partlyCovered:
            return "\(stillNeededValue) still needs money."
        case .fullyCovered:
            return "Everything due soon is covered."
        case .nothingDueSoon:
            return "No Upcoming Expenses or Payment Plans in the next 30 days."
        }
    }

    var accessibilitySummary: String {
        let parts = [
            "Next 30 days",
            "Due soon \(dueSoonValue)",
            "Covered \(coveredValue)",
            "Still needed \(stillNeededValue)",
            stateTitle,
            detail
        ]

        return parts.joined(separator: ". ")
    }
}
