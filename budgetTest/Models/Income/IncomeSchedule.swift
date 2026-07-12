import CryptoKit
import Foundation
import SwiftData

enum IncomeScheduleFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case twiceMonthly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .biweekly:
            return "Every 2 weeks"
        case .twiceMonthly:
            return "Twice a month"
        case .monthly:
            return "Monthly"
        }
    }

    var summaryPhrase: String {
        switch self {
        case .weekly:
            return "weekly"
        case .biweekly:
            return "every 2 weeks"
        case .twiceMonthly:
            return "twice a month"
        case .monthly:
            return "monthly"
        }
    }

    var requiresExplicitNextPayday: Bool {
        switch self {
        case .weekly, .biweekly:
            return false
        case .twiceMonthly, .monthly:
            return true
        }
    }
}

enum IncomeScheduleDateBasis: String, Codable {
    case calculated
    case explicit
}

@Model
final class IncomeSchedule {
    @Attribute(.unique)
    var id: UUID

    var ownerScopeID: String
    var sourceLabel: String
    var takeHomeAmountCents: Int64
    var frequencyRawValue: String
    var lastPaydayDateKey: String
    var nextExpectedPaydayDateKey: String
    var dateBasisRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        ownerScopeID: String,
        sourceLabel: String = "Paycheck",
        takeHomeAmountCents: Int64,
        frequency: IncomeScheduleFrequency,
        lastPaydayDateKey: String,
        nextExpectedPaydayDateKey: String,
        dateBasis: IncomeScheduleDateBasis,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.ownerScopeID = ownerScopeID
        self.sourceLabel = sourceLabel
        self.takeHomeAmountCents = takeHomeAmountCents
        self.frequencyRawValue = frequency.rawValue
        self.lastPaydayDateKey = lastPaydayDateKey
        self.nextExpectedPaydayDateKey = nextExpectedPaydayDateKey
        self.dateBasisRawValue = dateBasis.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    var frequency: IncomeScheduleFrequency? {
        IncomeScheduleFrequency(rawValue: frequencyRawValue)
    }

    var dateBasis: IncomeScheduleDateBasis? {
        IncomeScheduleDateBasis(rawValue: dateBasisRawValue)
    }

    var takeHomeAmount: Double {
        Double(takeHomeAmountCents) / 100
    }
}

enum IncomeScheduleOwnerScope {
    private static let localScopeID = "income-schedule-local-device"

    static func current(authenticatedUserID: String?) -> String {
        guard let userID = authenticatedUserID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else {
            return localScopeID
        }

        let digest = SHA256.hash(data: Data(userID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum IncomeSchedulePhaseOnePolicy {
    static func visibleSchedule(
        from schedules: [IncomeSchedule],
        ownerScopeID: String
    ) -> IncomeSchedule? {
        schedules
            .filter { $0.ownerScopeID == ownerScopeID }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }

                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }

                return $0.id.uuidString < $1.id.uuidString
            }
            .first
    }
}
