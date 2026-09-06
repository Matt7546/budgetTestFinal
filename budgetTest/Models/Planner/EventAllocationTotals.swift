import Foundation

/// A render-pass lookup for the existing raw allocation `.first` behavior.
/// This is not the authoritative funding total: it deliberately preserves the
/// first record (including zero/non-finite values) and leaves row caps intact.
/// Rebuild from current query results each pass; do not cache across mutations.
struct EventAllocationAmountLookup {
    private let amountsByOccurrenceID: [String: Double]

    init<Values: Sequence>(allocations: Values) where Values.Element == EventAllocation {
        var amounts: [String: Double] = [:]
        for allocation in allocations where amounts[allocation.occurrenceID] == nil {
            amounts[allocation.occurrenceID] = allocation.allocatedAmount
        }
        amountsByOccurrenceID = amounts
    }

    func allocatedAmount(for forecast: ForecastEvent) -> Double {
        amountsByOccurrenceID[forecast.occurrenceID] ?? 0
    }
}

/// Authoritative funding is derived from durable allocations, never from a
/// bounded forecast or the rows currently visible on a screen. This snapshot
/// reads records only; it cannot create, release, or reassign Set Aside.
struct UpcomingExpenseFundingSnapshot {
    let fundedOccurrences: [ForecastEvent]
    let totalSetAside: Double
    /// Unrepaired legacy provenance conflicts; funding stays on its unique key.
    let sourceMismatchOccurrenceIDs: Set<String>
    private let amountsByOccurrenceID: [String: Double]
    private let resolvedOccurrenceIDs: Set<String>

    init(
        events: [PlannerEvent],
        allocations: [EventAllocation],
        occurrenceStatuses: [ExpenseOccurrenceStatus]
    ) {
        let eventsByID = events.reduce(into: [UUID: PlannerEvent]()) { result, event in
            result[event.id] = event
        }
        let resolvedIDs = ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: occurrenceStatuses
        )
        resolvedOccurrenceIDs = resolvedIDs
        // SwiftData enforces unique occurrence IDs. Deterministic selection also
        // keeps unsaved/fixture duplicates from being counted more than once.
        let allocationsByID = allocations.reduce(into: [String: EventAllocation]()) {
            result, allocation in
            if let existing = result[allocation.occurrenceID],
               existing.updatedAt > allocation.updatedAt ||
                (existing.updatedAt == allocation.updatedAt &&
                 existing.id.uuidString > allocation.id.uuidString) {
                return
            }
            result[allocation.occurrenceID] = allocation
        }
        var amounts: [String: Double] = [:]
        var occurrences: [ForecastEvent] = []
        var sourceMismatches = Set<String>()

        for allocation in allocationsByID.values {
            guard !resolvedIDs.contains(allocation.occurrenceID),
                  let keyOwnerID = UUID(uuidString: String(allocation.occurrenceID.prefix(36))),
                  let event = eventsByID[keyOwnerID],
                  event.type == .expense,
                  event.amount.isFinite, event.amount > 0,
                  allocation.allocatedAmount.isFinite,
                  allocation.allocatedAmount > 0,
                  let occurrence = ForecastEvent.restoring(
                    event: event,
                    occurrenceID: allocation.occurrenceID,
                    storedDate: allocation.occurrenceDate
                  ) else {
                // Orphans/invalid keys have no safe actionable owner. Leave the
                // records untouched; this is not a legacy-data repair policy.
                continue
            }

            if allocation.sourceEventID != event.id {
                // Existing totals and allocation/status actions use occurrenceID.
                // Preserve that association when redundant provenance conflicts;
                // do not release money or rewrite the source as a side effect.
                sourceMismatches.insert(allocation.occurrenceID)
            }
            amounts[occurrence.occurrenceID] = min(allocation.allocatedAmount, event.amount)
            occurrences.append(occurrence)
        }

        fundedOccurrences = Self.sorted(occurrences)
        amountsByOccurrenceID = amounts
        sourceMismatchOccurrenceIDs = sourceMismatches
        totalSetAside = fundedOccurrences.reduce(0) {
            $0 + (amounts[$1.occurrenceID] ?? 0)
        }
    }

    func allocatedAmount(for forecast: ForecastEvent) -> Double {
        amountsByOccurrenceID[forecast.occurrenceID] ?? 0
    }

    func mergingFundedOccurrences(with forecasts: [ForecastEvent]) -> [ForecastEvent] {
        var byID = forecasts.reduce(into: [String: ForecastEvent]()) { result, forecast in
            if !resolvedOccurrenceIDs.contains(forecast.occurrenceID) {
                result[forecast.occurrenceID] = forecast
            }
        }
        for occurrence in fundedOccurrences where byID[occurrence.occurrenceID] == nil {
            byID[occurrence.occurrenceID] = occurrence
        }
        return Self.sorted(Array(byID.values))
    }

    func reviewableExpenses(
        in forecasts: [ForecastEvent],
        now: Date,
        calendar: Calendar
    ) -> [ForecastEvent] {
        let today = calendar.startOfDay(for: now)
        return mergingFundedOccurrences(with: forecasts).filter {
            $0.event.type == .expense &&
                (calendar.startOfDay(for: $0.occurrenceDate) >= today ||
                 allocatedAmount(for: $0) > 0)
        }
    }

    /// Keep the existing one-row-per-expense management list, plus every
    /// separately funded occurrence so none of its money is hidden by deduping.
    func managementExpenses(in forecasts: [ForecastEvent]) -> [ForecastEvent] {
        var seenEventIDs = Set<UUID>()
        let primaryIDs = Set(forecasts.compactMap { forecast -> String? in
            guard forecast.event.type == .expense,
                  seenEventIDs.insert(forecast.event.id).inserted else {
                return nil
            }
            return forecast.occurrenceID
        })
        return mergingFundedOccurrences(with: forecasts).filter { forecast in
            forecast.event.type == .expense &&
                (primaryIDs.contains(forecast.occurrenceID) ||
                 allocatedAmount(for: forecast) > 0)
        }
    }

    private static func sorted(_ occurrences: [ForecastEvent]) -> [ForecastEvent] {
        occurrences.sorted {
            if $0.occurrenceDate != $1.occurrenceDate {
                return $0.occurrenceDate < $1.occurrenceDate
            }
            return $0.occurrenceID < $1.occurrenceID
        }
    }
}

enum EventAllocationTotals {

    // Window-scoped subtotal retained for legacy/Lab callers. Production
    // Available to Spend uses UpcomingExpenseFundingSnapshot instead.
    static func activeTotal(
        allocations: [EventAllocation],
        forecastEvents: [ForecastEvent]
    ) -> Double {
        let activeForecastByOccurrenceID = Dictionary(
            uniqueKeysWithValues: forecastEvents
                .filter {
                    $0.event.type == .expense
                }
                .map {
                    ($0.occurrenceID, $0)
                }
        )

        let latestAllocationByOccurrence =
            Dictionary(
                allocations.map {
                    (
                        $0.occurrenceID,
                        max($0.allocatedAmount, 0)
                    )
                },
                uniquingKeysWith: { _, latest in
                    latest
                }
            )

        return latestAllocationByOccurrence.reduce(0) { total, entry in
            guard let forecast = activeForecastByOccurrenceID[entry.key] else {
                return total
            }

            return total + min(
                entry.value,
                forecast.event.amount
            )
        }
    }
}
