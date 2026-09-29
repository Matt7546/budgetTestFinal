import Foundation
import SwiftData

enum ExpenseOccurrenceResolution: String, Codable, CaseIterable {
    case paid
    case skipped
    case chargedToCard
    case postedFromChecking

    var isManualResolution: Bool {
        switch self {
        case .paid, .skipped:
            return true

        case .chargedToCard, .postedFromChecking:
            return false
        }
    }
}

enum ExpenseOccurrenceLifecycle {
    case upcoming
    case overdue
    case paid
    case skipped
    case chargedToCard
    case postedFromChecking

    var isResolved: Bool {
        switch self {
        case .upcoming, .overdue:
            return false

        case .paid,
                .skipped,
                .chargedToCard,
                .postedFromChecking:
            return true
        }
    }
}

@Model
final class ExpenseOccurrenceStatus {

    var occurrenceID: String

    var id: UUID
    var ownerScopeID: String?
    var sourceEventID: UUID
    var occurrenceDate: Date
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerScopeID: String? = PlanningOwnerScope.local,
        occurrenceID: String,
        sourceEventID: UUID,
        occurrenceDate: Date,
        status: ExpenseOccurrenceResolution,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerScopeID = ownerScopeID
        self.occurrenceID = occurrenceID
        self.sourceEventID = sourceEventID
        self.occurrenceDate = occurrenceDate
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: ExpenseOccurrenceResolution? {
        ExpenseOccurrenceResolution(rawValue: statusRawValue)
    }

    func setStatus(
        _ status: ExpenseOccurrenceResolution,
        now: Date = Date()
    ) {
        statusRawValue = status.rawValue
        updatedAt = now
    }
}

extension ExpenseOccurrenceStatus: PlanningOwnedRecord {}

/// Owner + exact occurrence is the lifecycle identity. Timestamps have no
/// documented supersession meaning. Differing resolution, provenance, or
/// date is an integrity conflict, even if both resolutions release funding.
enum ExpenseOccurrenceStatusResolver {
    static func grouped(_ statuses: [ExpenseOccurrenceStatus])
        -> [BillOccurrenceRecordKey: [ExpenseOccurrenceStatus]] {
        Dictionary(grouping: statuses) {
            BillOccurrenceRecordKey(
                ownerScopeID: $0.ownerScopeID,
                occurrenceID: $0.occurrenceID
            )
        }
    }

    static func resolve(
        occurrenceID: String,
        ownerScopeID: String?,
        in statuses: [ExpenseOccurrenceStatus]
    ) -> BillOccurrenceRecordResolution<ExpenseOccurrenceStatus> {
        let matches = statuses.filter {
            $0.ownerScopeID == ownerScopeID && $0.occurrenceID == occurrenceID
        }
        return resolve(matches: matches)
    }

    static func resolve(matches: [ExpenseOccurrenceStatus])
        -> BillOccurrenceRecordResolution<ExpenseOccurrenceStatus> {
        guard let first = matches.first else { return .absent }
        guard matches.allSatisfy({
                  $0.statusRawValue == first.statusRawValue &&
                      $0.sourceEventID == first.sourceEventID &&
                      $0.occurrenceDate == first.occurrenceDate
              }) else { return .conflict }
        let representative = matches.min {
            $0.id.uuidString < $1.id.uuidString
        } ?? first
        return .canonical(record: representative, duplicateCount: matches.count)
    }

    static func conflictingKeys(in statuses: [ExpenseOccurrenceStatus])
        -> Set<BillOccurrenceRecordKey> {
        Set(grouped(statuses).compactMap { key, matches in
            resolve(matches: matches).isConflict ? key : nil
        })
    }

    static func resolvedKeys(in statuses: [ExpenseOccurrenceStatus])
        -> Set<BillOccurrenceRecordKey> {
        var resolved = Set<BillOccurrenceRecordKey>()
        for (key, matches) in grouped(statuses) {
            guard case let .canonical(record, _) = resolve(matches: matches),
                  record.status != nil else { continue }
            resolved.insert(key)
        }
        return resolved
    }
}

/// A calculation-pass lookup using the same canonical status result as detail.
struct ExpenseOccurrenceStatusLookup {
    private let resolvedByKey:
        [BillOccurrenceRecordKey: BillOccurrenceRecordResolution<ExpenseOccurrenceStatus>]
    let hasConflict: Bool

    init<Values: Sequence>(statuses: Values) where Values.Element == ExpenseOccurrenceStatus {
        let groups = ExpenseOccurrenceStatusResolver.grouped(Array(statuses))
        var resolved:
            [BillOccurrenceRecordKey: BillOccurrenceRecordResolution<ExpenseOccurrenceStatus>] = [:]
        for (key, matches) in groups {
            resolved[key] = ExpenseOccurrenceStatusResolver.resolve(matches: matches)
        }
        resolvedByKey = resolved
        hasConflict = resolvedByKey.values.contains { $0.isConflict }
    }

    func status(for forecast: ForecastEvent) -> ExpenseOccurrenceResolution? {
        let key = BillOccurrenceRecordKey(
            ownerScopeID: forecast.event.ownerScopeID,
            occurrenceID: forecast.occurrenceID
        )
        return resolvedByKey[key]?.record?.status
    }
}

enum ExpenseOccurrenceLifecycleResolver {

    static func resolvedOccurrenceIDs(
        from statuses: [ExpenseOccurrenceStatus]
    ) -> Set<String> {
        // A release needs one canonical recognized resolution. Conflicting
        // physical rows are not resolution evidence; the integrity signal
        // separately makes the financial snapshot unavailable.
        Set(ExpenseOccurrenceStatusResolver.resolvedKeys(
            in: statuses
        ).map(\.occurrenceID))
    }

    static func statusRecord(
        for forecast: ForecastEvent,
        in statuses: [ExpenseOccurrenceStatus]
    ) -> ExpenseOccurrenceStatus? {
        ExpenseOccurrenceStatusResolver.resolve(
            occurrenceID: forecast.occurrenceID,
            ownerScopeID: forecast.event.ownerScopeID,
            in: statuses
        ).record
    }

    static func lifecycle(
        for forecast: ForecastEvent,
        statuses: [ExpenseOccurrenceStatus],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ExpenseOccurrenceLifecycle {
        lifecycle(
            for: forecast,
            status: statusRecord(for: forecast, in: statuses)?.status,
            now: now,
            calendar: calendar
        )
    }

    private static func lifecycle(
        for forecast: ForecastEvent,
        status: ExpenseOccurrenceResolution?,
        now: Date,
        calendar: Calendar
    ) -> ExpenseOccurrenceLifecycle {
        if let status {
            switch status {
            case .paid:
                return .paid

            case .skipped:
                return .skipped

            case .chargedToCard:
                return .chargedToCard

            case .postedFromChecking:
                return .postedFromChecking
            }
        }

        if forecast.normalizedOccurrenceDate < calendar.startOfDay(for: now) {
            return .overdue
        }

        return .upcoming
    }

    static func unresolvedPastDueForecasts(
        from forecasts: [ForecastEvent],
        statuses: [ExpenseOccurrenceStatus],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ForecastEvent] {
        let statusLookup = ExpenseOccurrenceStatusLookup(statuses: statuses)
        return forecasts
            .filter { forecast in
                forecast.event.type == .expense &&
                lifecycle(
                    for: forecast,
                    status: statusLookup.status(for: forecast),
                    now: now,
                    calendar: calendar
                ) == .overdue
            }
            .sorted { lhs, rhs in
                let lhsDate = calendar.startOfDay(
                    for: lhs.normalizedOccurrenceDate
                )
                let rhsDate = calendar.startOfDay(
                    for: rhs.normalizedOccurrenceDate
                )

                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }

                let nameComparison = lhs.event.name
                    .localizedCaseInsensitiveCompare(rhs.event.name)

                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }

                return lhs.occurrenceID < rhs.occurrenceID
            }
    }
}

struct ExpenseOccurrenceResolutionUndo {

    let statusRecord: ExpenseOccurrenceStatus
    let statusExisted: Bool
    let priorStatusRawValue: String?
    let priorUpdatedAt: Date?

    func restore(in modelContext: ModelContext) {
        if statusExisted,
           let priorStatusRawValue,
           let priorUpdatedAt {
            statusRecord.statusRawValue = priorStatusRawValue
            statusRecord.updatedAt = priorUpdatedAt
        } else {
            modelContext.delete(statusRecord)
        }
    }
}

enum ExpenseOccurrenceResolutionMutation {

    static func apply(
        _ resolution: ExpenseOccurrenceResolution,
        to forecast: ForecastEvent,
        existingStatus: ExpenseOccurrenceStatus?,
        in modelContext: ModelContext
    ) -> ExpenseOccurrenceResolutionUndo {
        if let existingStatus {
            let undo = ExpenseOccurrenceResolutionUndo(
                statusRecord: existingStatus,
                statusExisted: true,
                priorStatusRawValue: existingStatus.statusRawValue,
                priorUpdatedAt: existingStatus.updatedAt
            )
            existingStatus.setStatus(resolution)
            return undo
        }

        let status = ExpenseOccurrenceStatus(
            ownerScopeID: forecast.event.ownerScopeID,
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.normalizedOccurrenceDate,
            status: resolution
        )
        modelContext.insert(status)

        return ExpenseOccurrenceResolutionUndo(
            statusRecord: status,
            statusExisted: false,
            priorStatusRawValue: nil,
            priorUpdatedAt: nil
        )
    }
}
