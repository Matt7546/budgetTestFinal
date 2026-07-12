import Foundation
import SwiftData

struct IncomeScheduleConfirmation: Equatable {
    let ownerScopeID: String
    let sourceLabel: String
    let takeHomeAmountCents: Int64
    let frequency: IncomeScheduleFrequency
    let lastPaydayDateKey: String
    let nextExpectedPaydayDateKey: String
    let dateBasis: IncomeScheduleDateBasis
    let sortOrder: Int

    var takeHomeAmount: Double {
        Double(takeHomeAmountCents) / 100
    }
}

struct IncomeScheduleDraft: Equatable {
    var takeHomeAmountText: String
    var frequency: IncomeScheduleFrequency
    var lastPayday: Date
    var explicitNextPayday: Date

    init(
        takeHomeAmountText: String = "",
        frequency: IncomeScheduleFrequency = .biweekly,
        lastPayday: Date = Date(),
        explicitNextPayday: Date = Date()
    ) {
        self.takeHomeAmountText = takeHomeAmountText
        self.frequency = frequency
        self.lastPayday = lastPayday
        self.explicitNextPayday = explicitNextPayday
    }

    init(
        schedule: IncomeSchedule,
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        let resolvedFrequency = schedule.frequency ?? .biweekly
        let lastPayday = IncomeScheduleCalendar.date(
            from: schedule.lastPaydayDateKey,
            calendar: calendar
        ) ?? today
        let nextPayday = IncomeScheduleCalendar.date(
            from: schedule.nextExpectedPaydayDateKey,
            calendar: calendar
        ) ?? today

        self.init(
            takeHomeAmountText: String(
                format: "%.2f",
                schedule.takeHomeAmount
            ),
            frequency: resolvedFrequency,
            lastPayday: lastPayday,
            explicitNextPayday: nextPayday
        )
    }

    func confirmation(
        ownerScopeID: String,
        sourceLabel: String = "Paycheck",
        sortOrder: Int = 0,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> IncomeScheduleConfirmation? {
        guard !ownerScopeID.isEmpty,
              let amountCents = IncomeScheduleMoney.cents(
                from: takeHomeAmountText
              ),
              IncomeScheduleCalendar.isValidLastPayday(
                lastPayday,
                today: today,
                calendar: calendar
              ) else {
            return nil
        }

        let nextPayday: Date
        let dateBasis: IncomeScheduleDateBasis

        if frequency.requiresExplicitNextPayday {
            guard IncomeScheduleCalendar.isValidExplicitNextPayday(
                explicitNextPayday,
                lastPayday: lastPayday,
                today: today,
                calendar: calendar
            ) else {
                return nil
            }

            nextPayday = explicitNextPayday
            dateBasis = .explicit
        } else {
            guard let calculated = IncomeScheduleCalendar.calculatedNextPayday(
                frequency: frequency,
                lastPayday: lastPayday,
                today: today,
                calendar: calendar
            ) else {
                return nil
            }

            nextPayday = calculated
            dateBasis = .calculated
        }

        return IncomeScheduleConfirmation(
            ownerScopeID: ownerScopeID,
            sourceLabel: sourceLabel,
            takeHomeAmountCents: amountCents,
            frequency: frequency,
            lastPaydayDateKey: IncomeScheduleCalendar.dateKey(
                for: lastPayday,
                calendar: calendar
            ),
            nextExpectedPaydayDateKey: IncomeScheduleCalendar.dateKey(
                for: nextPayday,
                calendar: calendar
            ),
            dateBasis: dateBasis,
            sortOrder: sortOrder
        )
    }
}

enum IncomeScheduleMoney {
    static func cents(from text: String) -> Int64? {
        let sanitized = MoneyAmountParser.sanitizedText(text)
        let components = sanitized.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )

        guard !sanitized.isEmpty,
              components.count <= 2,
              !components[0].isEmpty,
              components[0].allSatisfy(\.isNumber),
              components.count == 1 ||
                components[1].count <= 2 &&
                components[1].allSatisfy(\.isNumber),
              let decimal = Decimal(
                string: sanitized,
                locale: Locale(identifier: "en_US_POSIX")
              ),
              decimal > 0 else {
            return nil
        }

        let centsNumber = NSDecimalNumber(decimal: decimal * 100)
        guard centsNumber != .notANumber,
              centsNumber.compare(
                NSDecimalNumber(value: Int64.max)
              ) != .orderedDescending else {
            return nil
        }

        return centsNumber.int64Value
    }
}

enum IncomeScheduleCalendar {
    static func dateKey(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )

        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(
        from key: String,
        calendar: Calendar = .current
    ) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let candidate = calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: calendar.timeZone,
                    year: year,
                    month: month,
                    day: day
                )
              ) else {
            return nil
        }

        let resolved = calendar.dateComponents(
            [.year, .month, .day],
            from: candidate
        )

        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day else {
            return nil
        }

        return calendar.startOfDay(for: candidate)
    }

    static func calculatedNextPayday(
        frequency: IncomeScheduleFrequency,
        lastPayday: Date,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let interval: Int

        switch frequency {
        case .weekly:
            interval = 7
        case .biweekly:
            interval = 14
        case .twiceMonthly, .monthly:
            return nil
        }

        guard isValidLastPayday(
            lastPayday,
            today: today,
            calendar: calendar
        ) else {
            return nil
        }

        let todayStart = calendar.startOfDay(for: today)
        var candidate = calendar.startOfDay(for: lastPayday)
        var iterationCount = 0

        repeat {
            guard let advanced = calendar.date(
                byAdding: .day,
                value: interval,
                to: candidate
            ) else {
                return nil
            }

            candidate = calendar.startOfDay(for: advanced)
            iterationCount += 1
        } while candidate < todayStart && iterationCount < 5_000

        guard candidate >= todayStart,
              iterationCount < 5_000 else {
            return nil
        }

        return candidate
    }

    static func isValidLastPayday(
        _ lastPayday: Date,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: lastPayday) <=
            calendar.startOfDay(for: today)
    }

    static func isValidExplicitNextPayday(
        _ nextPayday: Date,
        lastPayday: Date,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let next = calendar.startOfDay(for: nextPayday)
        let last = calendar.startOfDay(for: lastPayday)
        let todayStart = calendar.startOfDay(for: today)

        return next > last && next >= todayStart
    }

    static func nextDisplayDate(
        for schedule: IncomeSchedule,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard let frequency = schedule.frequency,
              let lastPayday = date(
                from: schedule.lastPaydayDateKey,
                calendar: calendar
              ) else {
            return nil
        }

        if frequency.requiresExplicitNextPayday {
            guard let explicitDate = date(
                from: schedule.nextExpectedPaydayDateKey,
                calendar: calendar
            ),
                  calendar.startOfDay(for: explicitDate) >=
                    calendar.startOfDay(for: today) else {
                return nil
            }

            return explicitDate
        }

        return calculatedNextPayday(
            frequency: frequency,
            lastPayday: lastPayday,
            today: today,
            calendar: calendar
        )
    }

    static func needsExplicitPaydayUpdate(
        _ schedule: IncomeSchedule,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard schedule.frequency?.requiresExplicitNextPayday == true,
              let nextDate = date(
                from: schedule.nextExpectedPaydayDateKey,
                calendar: calendar
              ) else {
            return false
        }

        return calendar.startOfDay(for: nextDate) <
            calendar.startOfDay(for: today)
    }
}

@MainActor
enum IncomeScheduleSaveCoordinator {
    @discardableResult
    static func save(
        _ confirmation: IncomeScheduleConfirmation,
        editing schedule: IncomeSchedule?,
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws -> IncomeSchedule {
        let savedSchedule: IncomeSchedule

        if let schedule {
            guard schedule.ownerScopeID == confirmation.ownerScopeID else {
                throw IncomeScheduleSaveError.ownerScopeMismatch
            }

            schedule.sourceLabel = confirmation.sourceLabel
            schedule.takeHomeAmountCents = confirmation.takeHomeAmountCents
            schedule.frequencyRawValue = confirmation.frequency.rawValue
            schedule.lastPaydayDateKey = confirmation.lastPaydayDateKey
            schedule.nextExpectedPaydayDateKey = confirmation.nextExpectedPaydayDateKey
            schedule.dateBasisRawValue = confirmation.dateBasis.rawValue
            schedule.sortOrder = confirmation.sortOrder
            schedule.updatedAt = now
            savedSchedule = schedule
        } else {
            let newSchedule = IncomeSchedule(
                ownerScopeID: confirmation.ownerScopeID,
                sourceLabel: confirmation.sourceLabel,
                takeHomeAmountCents: confirmation.takeHomeAmountCents,
                frequency: confirmation.frequency,
                lastPaydayDateKey: confirmation.lastPaydayDateKey,
                nextExpectedPaydayDateKey: confirmation.nextExpectedPaydayDateKey,
                dateBasis: confirmation.dateBasis,
                createdAt: now,
                updatedAt: now,
                sortOrder: confirmation.sortOrder
            )
            modelContext.insert(newSchedule)
            savedSchedule = newSchedule
        }

        try modelContext.save()
        return savedSchedule
    }
}

enum IncomeScheduleSaveError: Error {
    case ownerScopeMismatch
}
