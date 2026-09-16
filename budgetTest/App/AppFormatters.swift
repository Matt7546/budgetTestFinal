import Foundation

enum AppFormatters {

    static func currency(
        _ value: Double
    ) -> String {
        value.formatted(
            .currency(
                code: "USD"
            )
        )
    }

    static func wholeCurrency(
        _ value: Double
    ) -> String {
        value.formatted(
            .currency(
                code: "USD"
            )
            .precision(
                .fractionLength(0)
            )
        )
    }

    static func abbreviatedMonth(
        _ date: Date
    ) -> String {
        date.formatted(
            .dateTime.month(.abbreviated)
        )
    }

    static func day(
        _ date: Date
    ) -> String {
        date.formatted(
            .dateTime.day()
        )
    }

    static func abbreviatedMonthDay(
        _ date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        abbreviatedDate(
            date,
            includesYear: false,
            calendar: calendar,
            locale: locale
        )
    }

    static func abbreviatedMonthDayYear(
        _ date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        abbreviatedDate(
            date,
            includesYear: true,
            calendar: calendar,
            locale: locale
        )
    }

    static func abbreviatedMonthDayIncludingYearOutsideReferenceYear(
        _ date: Date,
        relativeTo referenceDate: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        calendar.isDate(date, equalTo: referenceDate, toGranularity: .year)
            ? abbreviatedMonthDay(
                date,
                calendar: calendar,
                locale: locale
            )
            : abbreviatedMonthDayYear(
                date,
                calendar: calendar,
                locale: locale
            )
    }

    private static func abbreviatedDate(
        _ date: Date,
        includesYear: Bool,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(
            includesYear ? "MMM d y" : "MMM d"
        )
        return formatter.string(from: date)
    }
}
