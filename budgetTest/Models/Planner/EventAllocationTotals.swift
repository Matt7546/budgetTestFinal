import Foundation

struct BillOccurrenceRecordKey: Hashable {
    let ownerScopeID: String?
    let occurrenceID: String
}

enum BillOccurrenceRecordResolution<Record> {
    case absent
    case canonical(record: Record, duplicateCount: Int)
    case conflict

    var record: Record? {
        guard case let .canonical(record, _) = self else { return nil }
        return record
    }

    var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }

    var hasDuplicates: Bool {
        guard case let .canonical(_, count) = self else { return false }
        return count > 1
    }
}

/// Occurrence ID and owner are the identity. Neither updatedAt nor insertion
/// order is documented as supersession evidence. Equivalent physical rows
/// describe one financial fact; differing amount, source, or date is a conflict.
enum EventAllocationResolver {
    static func grouped(_ allocations: [EventAllocation])
        -> [BillOccurrenceRecordKey: [EventAllocation]] {
        Dictionary(grouping: allocations) {
            BillOccurrenceRecordKey(
                ownerScopeID: $0.ownerScopeID,
                occurrenceID: $0.occurrenceID
            )
        }
    }

    static func resolve(
        occurrenceID: String,
        ownerScopeID: String?,
        in allocations: [EventAllocation]
    ) -> BillOccurrenceRecordResolution<EventAllocation> {
        let matches = allocations.filter {
            $0.ownerScopeID == ownerScopeID && $0.occurrenceID == occurrenceID
        }
        return resolve(matches: matches)
    }

    static func resolve(matches: [EventAllocation])
        -> BillOccurrenceRecordResolution<EventAllocation> {
        guard let first = matches.first else { return .absent }
        guard matches.allSatisfy({
            $0.sourceEventID == first.sourceEventID &&
                $0.occurrenceDate == first.occurrenceDate &&
                $0.allocatedAmount.isFinite &&
                $0.allocatedAmount >= 0 &&
                first.allocatedAmount.isFinite &&
                first.allocatedAmount >= 0 &&
                $0.allocatedAmount == first.allocatedAmount
        }) else { return .conflict }
        // Selecting an ID here is only a stable way to refer to equivalent
        // read-only rows. Writes against multiple physical rows are blocked.
        let representative = matches.min {
            $0.id.uuidString < $1.id.uuidString
        } ?? first
        return .canonical(record: representative, duplicateCount: matches.count)
    }

    static func conflictingKeys(in allocations: [EventAllocation])
        -> Set<BillOccurrenceRecordKey> {
        Set(grouped(allocations).compactMap { key, matches in
            resolve(matches: matches).isConflict ? key : nil
        })
    }
}

enum BillOccurrenceRecordIntegrity {
    static func hasConflict(
        allocations: [EventAllocation],
        statuses: [ExpenseOccurrenceStatus]
    ) -> Bool {
        !EventAllocationResolver.conflictingKeys(in: allocations).isEmpty ||
            !ExpenseOccurrenceStatusResolver.conflictingKeys(in: statuses).isEmpty
    }

    static func hasDuplicateRows(
        allocations: [EventAllocation],
        statuses: [ExpenseOccurrenceStatus]
    ) -> Bool {
        EventAllocationResolver.grouped(allocations).values.contains {
            $0.count > 1
        } || ExpenseOccurrenceStatusResolver.grouped(statuses).values.contains {
            $0.count > 1
        }
    }
}

/// A render-pass lookup over the same allocation resolution as funding.
struct EventAllocationAmountLookup {
    private let resolvedByKey:
        [BillOccurrenceRecordKey: BillOccurrenceRecordResolution<EventAllocation>]
    let hasConflict: Bool

    init<Values: Sequence>(allocations: Values) where Values.Element == EventAllocation {
        let groups = EventAllocationResolver.grouped(Array(allocations))
        var resolved:
            [BillOccurrenceRecordKey: BillOccurrenceRecordResolution<EventAllocation>] = [:]
        for (key, matches) in groups {
            resolved[key] = EventAllocationResolver.resolve(matches: matches)
        }
        resolvedByKey = resolved
        hasConflict = resolvedByKey.values.contains { $0.isConflict }
    }

    func allocatedAmount(for forecast: ForecastEvent) -> Double {
        let key = BillOccurrenceRecordKey(
            ownerScopeID: forecast.event.ownerScopeID,
            occurrenceID: forecast.occurrenceID
        )
        switch resolvedByKey[key] ?? .absent {
        case .absent:
            return 0
        case .canonical(let record, _):
            return record.allocatedAmount
        case .conflict:
            // Calling presentation must gate on hasConflict. Never turn
            // ambiguous protected money into a legitimate-looking zero.
            return .nan
        }
    }
}

/// Authoritative funding is derived from durable allocations, never from a
/// bounded forecast or the rows currently visible on a screen. This snapshot
/// reads records only; it cannot create, release, or reassign Set Aside.
struct UpcomingExpenseFundingSnapshot {
    let fundedOccurrences: [ForecastEvent]
    let totalSetAside: Double
    let conflictingOccurrenceIDs: Set<String>
    var isAuthoritative: Bool { conflictingOccurrenceIDs.isEmpty }
    /// Unrepaired legacy provenance conflicts; funding stays on its unique key.
    let sourceMismatchOccurrenceIDs: Set<String>
    private let amountsByOccurrenceKey: [BillOccurrenceRecordKey: Double]
    private let resolvedOccurrenceKeys: Set<BillOccurrenceRecordKey>

    init(
        events: [PlannerEvent],
        allocations: [EventAllocation],
        occurrenceStatuses: [ExpenseOccurrenceStatus]
    ) {
        let eventsByID = events.reduce(into: [UUID: PlannerEvent]()) { result, event in
            result[event.id] = event
        }
        let resolvedKeys = ExpenseOccurrenceStatusResolver.resolvedKeys(
            in: occurrenceStatuses
        )
        resolvedOccurrenceKeys = resolvedKeys
        let allocationConflicts = EventAllocationResolver.conflictingKeys(
            in: allocations
        )
        let statusConflicts = ExpenseOccurrenceStatusResolver.conflictingKeys(
            in: occurrenceStatuses
        )
        conflictingOccurrenceIDs = Set(
            allocationConflicts.union(statusConflicts).map(\.occurrenceID)
        )
        var amounts: [BillOccurrenceRecordKey: Double] = [:]
        var occurrences: [ForecastEvent] = []
        var sourceMismatches = Set<String>()

        for (key, matches) in EventAllocationResolver.grouped(allocations) {
            guard case let .canonical(allocation, _) =
                EventAllocationResolver.resolve(matches: matches) else { continue }
            guard !resolvedKeys.contains(key),
                  let keyOwnerID = UUID(uuidString: String(allocation.occurrenceID.prefix(36))),
                  let event = eventsByID[keyOwnerID],
                  event.ownerScopeID == allocation.ownerScopeID,
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
            amounts[key] = min(allocation.allocatedAmount, event.amount)
            occurrences.append(occurrence)
        }

        fundedOccurrences = Self.sorted(occurrences)
        amountsByOccurrenceKey = amounts
        sourceMismatchOccurrenceIDs = sourceMismatches
        totalSetAside = conflictingOccurrenceIDs.isEmpty
            ? fundedOccurrences.reduce(0) {
                $0 + (amounts[BillOccurrenceRecordKey(
                    ownerScopeID: $1.event.ownerScopeID,
                    occurrenceID: $1.occurrenceID
                )] ?? 0)
            }
            : .nan
    }

    func allocatedAmount(for forecast: ForecastEvent) -> Double {
        amountsByOccurrenceKey[BillOccurrenceRecordKey(
            ownerScopeID: forecast.event.ownerScopeID,
            occurrenceID: forecast.occurrenceID
        )] ?? 0
    }

    func mergingFundedOccurrences(with forecasts: [ForecastEvent]) -> [ForecastEvent] {
        var byID = forecasts.reduce(into: [BillOccurrenceRecordKey: ForecastEvent]()) {
            result, forecast in
            let key = BillOccurrenceRecordKey(
                ownerScopeID: forecast.event.ownerScopeID,
                occurrenceID: forecast.occurrenceID
            )
            if !resolvedOccurrenceKeys.contains(key) {
                result[key] = forecast
            }
        }
        for occurrence in fundedOccurrences {
            let key = BillOccurrenceRecordKey(
                ownerScopeID: occurrence.event.ownerScopeID,
                occurrenceID: occurrence.occurrenceID
            )
            if byID[key] == nil { byID[key] = occurrence }
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

        return EventAllocationResolver.grouped(allocations).reduce(0) { total, entry in
            let (key, matches) = entry
            guard let forecast = activeForecastByOccurrenceID[key.occurrenceID],
                  forecast.event.ownerScopeID == key.ownerScopeID else {
                return total
            }
            switch EventAllocationResolver.resolve(matches: matches) {
            case .absent:
                return total
            case .canonical(let record, _):
                return total + min(max(record.allocatedAmount, 0), forecast.event.amount)
            case .conflict:
                return .nan
            }
        }
    }
}
