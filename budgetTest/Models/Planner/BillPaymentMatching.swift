import Foundation
import SwiftData

/// A review proposal, not a financial mutation. Its full value is compared with
/// newly fetched evidence immediately before a decision is persisted.
struct BillPaymentMatch: Equatable, Identifiable {
    let ownerScopeID: String
    let eventID: UUID
    let occurrenceID: String
    let dueDateKey: String
    let billName: String
    let accountID: String
    let itemID: String?
    let transactionID: String
    let merchantName: String
    let postedDateKey: String
    let amountCents: Int64
    let snapshotGeneration: UInt64
    let snapshotRefreshDate: Date

    var id: String {
        TransactionMatchedExpenseResolutionIdentity.matchKey(
            hashedOwnerScopeID: ownerScopeID,
            accountID: accountID,
            transactionID: transactionID,
            occurrenceID: occurrenceID
        )
    }
}

enum BillPaymentMatcher {
    static let dueWindowDays = 2

    static func isFresh(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age <= 24 * 60 * 60
    }

    static func suggestions(
        ownerUserID: String?,
        snapshotOwnerUserID: String?,
        snapshotGeneration: UInt64,
        snapshotRefreshDate: Date?,
        forecasts: [ForecastEvent],
        statuses: [ExpenseOccurrenceStatus],
        decisions: [TransactionMatchedExpenseResolution],
        history: [String: RecurringExpenseRecommendationHistoryRecord],
        accounts: [PlaidAccount],
        transactions: [PlaidTransaction],
        metadata: TransactionSnapshotMetadata,
        balancesAreCurrent: Bool,
        automationIsEligible: Bool,
        now: Date = Date()
    ) -> [BillPaymentMatch] {
        guard let ownerUserID = ownerUserID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !ownerUserID.isEmpty,
              snapshotOwnerUserID == ownerUserID,
              let ownerScopeID = PlanningOwnerScope.authenticated(ownerUserID),
              let decisionOwnerScopeID =
                TransactionMatchedExpenseResolutionIdentity.ownerScopeID(
                    authenticatedUserID: ownerUserID
                ),
              let snapshotRefreshDate,
              isFresh(snapshotRefreshDate, now: now),
              balancesAreCurrent,
              automationIsEligible,
              metadata.isExplicitlyComplete(transactionCount: transactions.count),
              metadata.totalTransactions == metadata.returnedTransactions,
              let windowStart = metadata.windowStart,
              let windowEnd = metadata.windowEnd,
              Self.day(from: windowStart) != nil,
              Self.day(from: windowEnd) != nil else {
            return []
        }

        let accountsByID = Dictionary(
            accounts.map { ($0.account_id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let ownedStatuses = statuses.filter { $0.ownerScopeID == ownerScopeID }
        let ownedDecisions = decisions.filter {
            $0.ownerScopeID == decisionOwnerScopeID
        }
        let resolvedOccurrences = Set(ownedStatuses.map(\.occurrenceID))
        let committedOccurrences = Set(
            ownedDecisions.filter { $0.outcome != .ignored }.map(\.occurrenceID)
        )
        let committedTransactions = Set(
            ownedDecisions.filter { $0.outcome != .ignored }.map {
                "\($0.accountID)|\($0.transactionID)"
            }
        )
        var possible: [BillPaymentMatch] = []

        for forecast in forecasts {
            let event = forecast.event
            guard event.ownerScopeID == ownerScopeID,
                  event.type == .expense,
                  event.frequency == .monthly,
                  event.amount.isFinite,
                  event.amount > 0,
                  !resolvedOccurrences.contains(forecast.occurrenceID),
                  !committedOccurrences.contains(forecast.occurrenceID),
                  let dueDateKey = forecast.occurrenceID.split(separator: "_").last.map(String.init),
                  let dueDay = day(from: dueDateKey),
                  let rangeStart = calendar.date(
                    byAdding: .day, value: -dueWindowDays, to: dueDay
                  ),
                  let rangeEnd = calendar.date(
                    byAdding: .day, value: dueWindowDays, to: dueDay
                  ),
                  windowStart <= key(for: rangeStart),
                  windowEnd >= key(for: rangeEnd) else {
                continue
            }

            let normalizedBillName =
                RecurringExpenseSuggestionEngine.normalizedMerchantName(event.name)
            guard !normalizedBillName.isEmpty,
                  !RecurringExpenseSuggestionEngine.shouldIgnoreTransactionName(event.name) else {
                continue
            }

            for transaction in transactions {
                guard transaction.pending == false,
                      transaction.amount.isFinite,
                      transaction.amount > 0,
                      let accountID = transaction.account_id,
                      !accountID.isEmpty,
                      let account = accountsByID[accountID],
                      account.type.lowercased() == "depository",
                      account.subtype?.lowercased() == "checking",
                      let accountItemID = account.item_id,
                      !accountItemID.isEmpty,
                      transaction.item_id == accountItemID,
                      !committedTransactions.contains(
                        "\(accountID)|\(transaction.transaction_id)"
                      ),
                      !transaction.transaction_id.isEmpty,
                      !RecurringExpenseSuggestionEngine.shouldIgnoreTransactionName(
                        transaction.name
                      ),
                      RecurringExpenseSuggestionEngine.normalizedMerchantName(
                        transaction.name
                      ) == normalizedBillName,
                      let postedDay = day(from: transaction.date),
                      postedDay >= rangeStart,
                      postedDay <= rangeEnd,
                      let transactionCents = cents(transaction.amount),
                      let billCents = cents(event.amount),
                      abs(transactionCents - billCents) <= min(
                        100, max(0, billCents / 100)
                      ) else {
                    continue
                }

                // The recorded recommendation is the only existing production
                // provenance connecting a Bill to a particular bank account.
                let familyID = RecurringExpenseRecommendationIdentity.familyID(
                    normalizedName: normalizedBillName,
                    accountID: accountID
                )
                guard let record = history[familyID],
                      record.status == .added,
                      record.cadence == "monthly",
                      record.plannerEventID == event.id,
                      record.userScope ==
                        RecurringExpenseRecommendationIdentity.userScope(
                            userID: ownerUserID
                        ),
                      RecurringExpenseSuggestionEngine.normalizedMerchantName(
                        record.displayName
                      ) == normalizedBillName else {
                    continue
                }

                possible.append(
                    BillPaymentMatch(
                        ownerScopeID: decisionOwnerScopeID,
                        eventID: event.id,
                        occurrenceID: forecast.occurrenceID,
                        dueDateKey: dueDateKey,
                        billName: event.name,
                        accountID: accountID,
                        itemID: transaction.item_id,
                        transactionID: transaction.transaction_id,
                        merchantName: transaction.name,
                        postedDateKey: transaction.date,
                        amountCents: transactionCents,
                        snapshotGeneration: snapshotGeneration,
                        snapshotRefreshDate: snapshotRefreshDate
                    )
                )
            }
        }

        let byOccurrence = Dictionary(grouping: possible, by: \.occurrenceID)
        let byTransaction = Dictionary(grouping: possible) {
            "\($0.accountID)|\($0.transactionID)"
        }
        let ignoredKeys = Set(
            ownedDecisions.filter { $0.outcome == .ignored }.map(\.matchKey)
        )
        return possible.filter {
            byOccurrence[$0.occurrenceID]?.count == 1 &&
                byTransaction["\($0.accountID)|\($0.transactionID)"]?.count == 1 &&
                !ignoredKeys.contains($0.id)
        }
        .sorted {
            if $0.dueDateKey != $1.dueDateKey {
                return $0.dueDateKey < $1.dueDateKey
            }
            return $0.id < $1.id
        }
    }

    private static func cents(_ amount: Double) -> Int64? {
        guard amount.isFinite,
              amount > 0,
              amount < Double(Int64.max) / 100 else {
            return nil
        }
        return Int64((amount * 100).rounded())
    }

    private static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private static func day(from key: String) -> Date? {
        guard key.count == 10,
              key[key.index(key.startIndex, offsetBy: 4)] == "-",
              key[key.index(key.startIndex, offsetBy: 7)] == "-",
              let year = Int(key.prefix(4)),
              let month = Int(key.dropFirst(5).prefix(2)),
              let day = Int(key.suffix(2)),
              let result = calendar.date(
                from: DateComponents(year: year, month: month, day: day)
              ),
              self.key(for: result) == key else {
            return nil
        }
        return result
    }

    private static func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }
}

enum BillPaymentDecisionResult: Equatable {
    case saved
    case stale
    case failed
}

@MainActor
enum BillPaymentDecisionCoordinator {
    static func decide(
        _ outcome: TransactionMatchedExpenseResolutionOutcome,
        expected: BillPaymentMatch,
        userID: String?,
        snapshotOwnerUserID: String?,
        snapshotGeneration: UInt64,
        snapshotRefreshDate: Date?,
        planningAvailable: Bool,
        automationIsEligible: Bool,
        history: [String: RecurringExpenseRecommendationHistoryRecord],
        accounts: [PlaidAccount],
        transactions: [PlaidTransaction],
        metadata: TransactionSnapshotMetadata,
        balancesAreCurrent: Bool,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> BillPaymentDecisionResult {
        guard outcome == .ignored || outcome == .released,
              planningAvailable,
              balancesAreCurrent,
              automationIsEligible,
              BillPaymentMatcher.isFresh(snapshotRefreshDate, now: now),
              expected.snapshotGeneration == snapshotGeneration,
              expected.snapshotRefreshDate == snapshotRefreshDate else {
            return .stale
        }

        do {
            let events = try modelContext.fetch(FetchDescriptor<PlannerEvent>())
            let allocations = try modelContext.fetch(FetchDescriptor<EventAllocation>())
            let statuses = try modelContext.fetch(
                FetchDescriptor<ExpenseOccurrenceStatus>()
            )
            let decisions = try modelContext.fetch(
                FetchDescriptor<TransactionMatchedExpenseResolution>()
            )
            guard let planningOwner = PlanningOwnerScope.authenticated(userID),
                  events.contains(where: {
                    $0.id == expected.eventID &&
                        $0.ownerScopeID == planningOwner
                  }) else {
                return .stale
            }

            let ownedEvents = events.owned(by: planningOwner)
            let ownedAllocations = allocations.owned(by: planningOwner)
            let ownedStatuses = statuses.owned(by: planningOwner)
            let funding = UpcomingExpenseFundingSnapshot(
                events: ownedEvents,
                allocations: ownedAllocations,
                occurrenceStatuses: ownedStatuses
            )
            let currentForecasts = PlannerForecastCalculator(
                events: ownedEvents,
                totalAvailable: 0,
                totalGoalAllocated: 0,
                includeFutureIncome: false,
                protectGoals: true,
                inactiveOccurrenceIDs: Set(ownedStatuses.map(\.occurrenceID)),
                fundingSnapshot: funding
            ).forecastEvents
            let forecast = currentForecasts.first {
                $0.occurrenceID == expected.occurrenceID
            }
            guard let forecast,
                  !statuses.contains(where: {
                    $0.ownerScopeID == planningOwner &&
                        $0.occurrenceID == expected.occurrenceID
                  }) else {
                return .stale
            }

            let current = BillPaymentMatcher.suggestions(
                ownerUserID: userID,
                snapshotOwnerUserID: snapshotOwnerUserID,
                snapshotGeneration: snapshotGeneration,
                snapshotRefreshDate: snapshotRefreshDate,
                forecasts: currentForecasts,
                statuses: statuses,
                decisions: decisions,
                history: history,
                accounts: accounts,
                transactions: transactions,
                metadata: metadata,
                balancesAreCurrent: balancesAreCurrent,
                automationIsEligible: automationIsEligible,
                now: now
            )
            guard current.contains(expected) else {
                return .stale
            }
            let appliedCents = outcome == .released
                ? Int64((funding.allocatedAmount(for: forecast) * 100).rounded())
                : 0
            let decision = TransactionMatchedExpenseResolution(
                hashedOwnerScopeID: expected.ownerScopeID,
                transactionID: expected.transactionID,
                accountID: expected.accountID,
                itemID: expected.itemID,
                transactionPostedDateKey: expected.postedDateKey,
                transactionAmountCents: expected.amountCents,
                sourceEventID: expected.eventID,
                occurrenceID: expected.occurrenceID,
                occurrenceDateKey: expected.dueDateKey,
                outcome: outcome,
                appliedSetAsideAmountCents: appliedCents
            )
            modelContext.insert(decision)
            if outcome == .released {
                _ = ExpenseOccurrenceResolutionMutation.apply(
                    .postedFromChecking,
                    to: forecast,
                    existingStatus: nil,
                    in: modelContext
                )
            }
            try modelContext.save()
            return .saved
        } catch {
            modelContext.rollback()
            return .failed
        }
    }
}
