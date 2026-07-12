import Foundation
import SwiftData

enum ExpenseOccurrenceResolution: String, Codable, CaseIterable {
    case paid
    case skipped
}

enum ExpenseOccurrenceLifecycle {
    case upcoming
    case overdue
    case paid
    case skipped
}

@Model
final class ExpenseOccurrenceStatus {

    @Attribute(.unique)
    var occurrenceID: String

    var id: UUID
    var sourceEventID: UUID
    var occurrenceDate: Date
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        occurrenceID: String,
        sourceEventID: UUID,
        occurrenceDate: Date,
        status: ExpenseOccurrenceResolution,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.occurrenceID = occurrenceID
        self.sourceEventID = sourceEventID
        self.occurrenceDate = occurrenceDate
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: ExpenseOccurrenceResolution {
        get {
            ExpenseOccurrenceResolution(rawValue: statusRawValue) ?? .skipped
        }
        set {
            statusRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }
}

enum ExpenseOccurrenceLifecycleResolver {

    static func resolvedOccurrenceIDs(
        from statuses: [ExpenseOccurrenceStatus]
    ) -> Set<String> {
        Set(
            statuses
                .filter {
                    $0.status == .paid ||
                    $0.status == .skipped
                }
                .map(\.occurrenceID)
        )
    }

    static func statusRecord(
        for forecast: ForecastEvent,
        in statuses: [ExpenseOccurrenceStatus]
    ) -> ExpenseOccurrenceStatus? {
        statuses.first {
            $0.occurrenceID == forecast.occurrenceID
        }
    }

    static func lifecycle(
        for forecast: ForecastEvent,
        statuses: [ExpenseOccurrenceStatus],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ExpenseOccurrenceLifecycle {
        if let status = statusRecord(
            for: forecast,
            in: statuses
        )?.status {
            switch status {
            case .paid:
                return .paid

            case .skipped:
                return .skipped
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
        forecasts
            .filter { forecast in
                forecast.event.type == .expense &&
                lifecycle(
                    for: forecast,
                    statuses: statuses,
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
            existingStatus.status = resolution
            return undo
        }

        let status = ExpenseOccurrenceStatus(
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
