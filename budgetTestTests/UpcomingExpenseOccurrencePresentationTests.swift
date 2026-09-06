import XCTest

@testable import Caldera_Money

@MainActor
final class UpcomingExpenseOccurrencePresentationTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testPastRecurringOccurrenceUsesDueAndIncludesPriorYear() {
        let forecast = recurringForecast(on: date(2025, 7, 1))

        XCTAssertEqual(
            UpcomingExpenseOccurrencePresentation.subtitle(
                for: forecast,
                now: date(2026, 8, 10),
                calendar: calendar
            ),
            "Due Jul 1, 2025 · Monthly"
        )
    }

    func testCurrentYearFutureRecurringOccurrenceKeepsConciseNextLabel() {
        let forecast = recurringForecast(on: date(2026, 9, 1))

        XCTAssertEqual(
            UpcomingExpenseOccurrencePresentation.subtitle(
                for: forecast,
                now: date(2026, 8, 10),
                calendar: calendar
            ),
            "Next Sep 1 · Monthly"
        )
    }

    func testCurrentYearPastRecurringOccurrenceNeverSaysNext() {
        let forecast = recurringForecast(on: date(2026, 7, 1))

        XCTAssertEqual(
            UpcomingExpenseOccurrencePresentation.subtitle(
                for: forecast,
                now: date(2026, 8, 10),
                calendar: calendar
            ),
            "Due Jul 1 · Monthly"
        )
    }

    func testNextYearRecurringOccurrenceIncludesYear() {
        let forecast = recurringForecast(on: date(2027, 1, 1))

        XCTAssertEqual(
            UpcomingExpenseOccurrencePresentation.subtitle(
                for: forecast,
                now: date(2026, 8, 10),
                calendar: calendar
            ),
            "Next Jan 1, 2027 · Monthly"
        )
    }

    func testHistoricalOccurrenceKeepsExactRouteAndEditorForecast() {
        let forecast = recurringForecast(on: date(2025, 7, 1))
        let destination = SetAsidePagerRouteResolver.resolve(
            .updateUpcomingExpense(
                eventID: forecast.event.id,
                occurrenceID: forecast.occurrenceID
            )
        )
        let editor = PlannerEventEditorDestination(
            editingEvent: forecast.event,
            forecast: forecast
        )

        XCTAssertEqual(
            destination,
            .editUpcomingExpense(
                eventID: forecast.event.id,
                occurrenceID: forecast.occurrenceID
            )
        )
        XCTAssertEqual(editor.forecast?.occurrenceID, forecast.occurrenceID)
    }

    private func recurringForecast(on occurrenceDate: Date) -> ForecastEvent {
        let event = PlannerEvent(
            name: "Rent",
            amount: 1_200,
            date: date(2025, 7, 1),
            frequency: .monthly,
            type: .expense
        )
        return ForecastEvent(event: event, occurrenceDate: occurrenceDate)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )!
    }
}
