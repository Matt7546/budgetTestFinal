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
}
