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
        _ date: Date
    ) -> String {
        date.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
        )
    }

    static func abbreviatedMonthDayYear(
        _ date: Date
    ) -> String {
        date.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .year()
        )
    }
}
