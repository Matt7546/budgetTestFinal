import XCTest

@testable import Caldera_Money

@MainActor
final class ExpenseOccurrenceLookupTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testLargeHistoricalAllocationLookupConsumesInputOnceAndRetainsEveryExactOccurrence() {
        let history = historicalOccurrences()
        let allocations = history.occurrences.enumerated().map { index, forecast in
            allocation(forecast, amount: Double(index + 1))
        }
        let traversal = TraversalCount()
        let lookup = EventAllocationAmountLookup(
            allocations: countedSequence(allocations, traversal: traversal)
        )

        XCTAssertEqual(history.events.count, 20)
        XCTAssertEqual(history.occurrences.count, 2_000)
        XCTAssertEqual(Set(history.occurrences.map(\.occurrenceID)).count, 2_000)
        XCTAssertEqual(traversal.iteratorCreations, 1)
        XCTAssertEqual(traversal.elementsVisited, allocations.count)

        for _ in 0..<2 {
            for (index, forecast) in history.occurrences.enumerated() {
                XCTAssertEqual(lookup.allocatedAmount(for: forecast), Double(index + 1))
            }
        }
        XCTAssertEqual(traversal.iteratorCreations, 1)
        XCTAssertEqual(traversal.elementsVisited, allocations.count)

        let funding = UpcomingExpenseFundingSnapshot(
            events: history.events, allocations: allocations, occurrenceStatuses: []
        )
        XCTAssertEqual(funding.fundedOccurrences.count, 2_000)
        XCTAssertEqual(funding.totalSetAside, 2_001_000)
        for (index, forecast) in history.occurrences.enumerated() {
            XCTAssertEqual(funding.allocatedAmount(for: forecast), Double(index + 1))
        }
    }

    func testAllocationLookupUsesExactOwnerAndOccurrenceNotNameOrDateAlone() {
        let first = expense(name: "Same expense")
        let second = expense(name: "Same expense")
        let firstJuly = forecast(first, date: date(2026, 7, 1))
        let firstAugust = forecast(first, date: date(2026, 8, 1))
        let secondJuly = forecast(second, date: firstJuly.occurrenceDate)
        let secondAugust = forecast(second, date: firstAugust.occurrenceDate)
        let lookup = EventAllocationAmountLookup(allocations: [
            allocation(firstJuly, amount: 400),
            allocation(firstAugust, amount: 100),
            allocation(secondJuly, amount: 75),
        ])

        XCTAssertEqual(lookup.allocatedAmount(for: firstJuly), 400)
        XCTAssertEqual(lookup.allocatedAmount(for: firstAugust), 100)
        XCTAssertEqual(lookup.allocatedAmount(for: secondJuly), 75)
        XCTAssertEqual(lookup.allocatedAmount(for: secondAugust), 0)
    }

    func testConflictingAllocationsFailClosedInBothOrdersWithoutTimestampSupersession() {
        let event = expense()
        let occurrence = forecast(event)

        for firstAmount in [0.0, -5, 800, Double.nan, Double.infinity] {
            let first = allocation(occurrence, amount: firstAmount)
            first.updatedAt = date(2026, 7, 1)
            let newer = allocation(occurrence, amount: 1_000)
            newer.updatedAt = date(2026, 8, 1)

            for records in [[first, newer], [newer, first]] {
                let lookup = EventAllocationAmountLookup(allocations: records)
                XCTAssertTrue(lookup.hasConflict)
                XCTAssertTrue(lookup.allocatedAmount(for: occurrence).isNaN)
                let funding = UpcomingExpenseFundingSnapshot(
                    events: [event], allocations: records, occurrenceStatuses: []
                )
                XCTAssertFalse(funding.isAuthoritative)
                XCTAssertTrue(funding.totalSetAside.isNaN)
                XCTAssertEqual(funding.conflictingOccurrenceIDs, [occurrence.occurrenceID])
            }
        }
    }

    func testEquivalentAllocationRowsCountOnceInBothOrders() {
        let event = expense()
        let occurrence = forecast(event)
        let first = allocation(occurrence, amount: 125)
        let second = allocation(occurrence, amount: 125)
        first.updatedAt = date(2026, 7, 1)
        second.updatedAt = date(2026, 8, 1)
        for records in [[first, second], [second, first]] {
            XCTAssertFalse(EventAllocationAmountLookup(allocations: records).hasConflict)
            XCTAssertEqual(
                EventAllocationAmountLookup(allocations: records)
                    .allocatedAmount(for: occurrence), 125
            )
            let funding = UpcomingExpenseFundingSnapshot(
                events: [event], allocations: records, occurrenceStatuses: []
            )
            XCTAssertTrue(funding.isAuthoritative)
            XCTAssertEqual(funding.totalSetAside, 125)
        }
    }

    func testSingleNegativeAllocationCannotBeSkippedAsAuthoritativeZero() {
        let event = expense()
        let occurrence = forecast(event)
        let invalid = allocation(occurrence, amount: -5)
        let lookup = EventAllocationAmountLookup(allocations: [invalid])
        XCTAssertTrue(lookup.hasConflict)
        XCTAssertTrue(lookup.allocatedAmount(for: occurrence).isNaN)
        let funding = UpcomingExpenseFundingSnapshot(
            events: [event], allocations: [invalid], occurrenceStatuses: []
        )
        XCTAssertFalse(funding.isAuthoritative)
        XCTAssertTrue(funding.totalSetAside.isNaN)
        XCTAssertEqual(
            PlanningSnapshotAvailability.resolving(
                base: .available,
                failedRequiredReads: [],
                hasBillRecordConflict: BillOccurrenceRecordIntegrity.hasConflict(
                    allocations: [invalid], statuses: []
                )
            ), .unavailable
        )
    }

    func testMalformedAllocationKeysDoNotMatchAndConflictingMetadataIsNotRepaired() {
        let event = expense()
        let occurrence = forecast(event)
        let malformed = allocation(occurrence, amount: 900)
        malformed.occurrenceID += "_invalid"
        let malformedKey = malformed.occurrenceID
        let exact = allocation(occurrence, amount: 72)
        let conflictingOwner = UUID()
        let conflictingDate = date(2040, 1, 1)
        exact.sourceEventID = conflictingOwner
        exact.occurrenceDate = conflictingDate

        XCTAssertEqual(
            EventAllocationAmountLookup(allocations: [malformed])
                .allocatedAmount(for: occurrence),
            0
        )
        XCTAssertEqual(
            EventAllocationAmountLookup(allocations: [malformed, exact])
                .allocatedAmount(for: occurrence),
            72
        )
        XCTAssertEqual(malformed.occurrenceID, malformedKey)
        XCTAssertEqual(malformed.allocatedAmount, 900)
        XCTAssertEqual(exact.occurrenceID, occurrence.occurrenceID)
        XCTAssertEqual(exact.sourceEventID, conflictingOwner)
        XCTAssertEqual(exact.occurrenceDate, conflictingDate)
        XCTAssertEqual(exact.allocatedAmount, 72)
    }

    func testLargeStatusLookupConsumesInputOnceAndBulkPastDueClassificationIsUnchanged() {
        let history = historicalOccurrences()
        let rawStatuses = ["paid", "skipped", "chargedToCard", "postedFromChecking", "future-status"]
        var statuses: [ExpenseOccurrenceStatus] = []
        var expectedPastDueIDs = Set<String>()
        for (index, occurrence) in history.occurrences.enumerated() {
            let kind = index % 6
            if kind < rawStatuses.count {
                statuses.append(status(occurrence, rawValue: rawStatuses[kind]))
            }
            if kind >= 4 {
                expectedPastDueIDs.insert(occurrence.occurrenceID)
            }
        }
        let traversal = TraversalCount()
        let lookup = ExpenseOccurrenceStatusLookup(
            statuses: countedSequence(statuses, traversal: traversal)
        )

        for _ in 0..<2 {
            for (index, occurrence) in history.occurrences.enumerated() {
                let kind = index % 6
                let expected = kind < 4
                    ? ExpenseOccurrenceResolution(rawValue: rawStatuses[kind]) : nil
                XCTAssertEqual(lookup.status(for: occurrence), expected)
            }
        }
        XCTAssertEqual(traversal.iteratorCreations, 1)
        XCTAssertEqual(traversal.elementsVisited, statuses.count)

        let pastDue = ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
            from: history.occurrences,
            statuses: statuses,
            now: date(2028, 1, 1),
            calendar: calendar
        )
        XCTAssertEqual(pastDue.count, expectedPastDueIDs.count)
        XCTAssertEqual(Set(pastDue.map(\.occurrenceID)), expectedPastDueIDs)
        XCTAssertEqual(
            pastDue.map(\.normalizedOccurrenceDate),
            pastDue.map(\.normalizedOccurrenceDate).sorted()
        )
        for (index, occurrence) in history.occurrences.prefix(6).enumerated() {
            let lifecycle = ExpenseOccurrenceLifecycleResolver.lifecycle(
                for: occurrence, statuses: statuses, now: date(2028, 1, 1), calendar: calendar
            )
            XCTAssertEqual(lifecycle.isResolved, index < 4)
            if index >= 4 {
                XCTAssertEqual(lifecycle, .overdue)
            }
        }
    }

    func testConflictingStatusesCannotSelectFirstRowInEitherOrder() {
        let occurrence = forecast(expense())
        let unknown = status(occurrence, rawValue: "future-status")
        let paid = status(occurrence, rawValue: "paid")
        paid.updatedAt = date(2027, 1, 1)

        for records in [[unknown, paid], [paid, unknown]] {
            let lookup = ExpenseOccurrenceStatusLookup(statuses: records)
            XCTAssertTrue(lookup.hasConflict)
            XCTAssertNil(lookup.status(for: occurrence))
            XCTAssertTrue(UpcomingExpenseFundingSnapshot(
                events: [occurrence.event],
                allocations: [allocation(occurrence, amount: 400)],
                occurrenceStatuses: records
            ).totalSetAside.isNaN)
        }
        let skipped = status(occurrence, rawValue: "skipped")
        XCTAssertTrue(ExpenseOccurrenceStatusLookup(statuses: [skipped, paid]).hasConflict)
        XCTAssertEqual(
            ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
                from: [occurrence], statuses: [unknown, paid], now: date(2027, 1, 1), calendar: calendar
            ).map(\.occurrenceID),
            [occurrence.occurrenceID]
        )
        XCTAssertEqual(
            ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
                from: [occurrence], statuses: [paid, unknown], now: date(2027, 1, 1), calendar: calendar
            ).count, 1
        )
        XCTAssertEqual(
            ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(from: [unknown, paid]),
            []
        )
        XCTAssertEqual(unknown.statusRawValue, "future-status")
    }

    func testEquivalentStatusesResolveOnceInBothOrders() {
        let occurrence = forecast(expense())
        let first = status(occurrence, rawValue: "postedFromChecking")
        let second = status(occurrence, rawValue: "postedFromChecking")
        for records in [[first, second], [second, first]] {
            let lookup = ExpenseOccurrenceStatusLookup(statuses: records)
            XCTAssertFalse(lookup.hasConflict)
            XCTAssertEqual(lookup.status(for: occurrence), .postedFromChecking)
            let funding = UpcomingExpenseFundingSnapshot(
                events: [occurrence.event],
                allocations: [allocation(occurrence, amount: 400)],
                occurrenceStatuses: records
            )
            XCTAssertTrue(funding.isAuthoritative)
            XCTAssertEqual(funding.totalSetAside, 0)
        }
    }

    func testMalformedAndMissingStatusRemainUnresolvedWithoutChangingMetadata() {
        let event = expense()
        let occurrence = forecast(event)
        let malformed = status(occurrence, rawValue: "paid")
        malformed.occurrenceID += "_invalid"
        let malformedKey = malformed.occurrenceID
        let exact = status(occurrence, rawValue: "skipped")
        let conflictingOwner = UUID()
        let conflictingDate = date(2040, 1, 1)
        exact.sourceEventID = conflictingOwner
        exact.occurrenceDate = conflictingDate

        XCTAssertNil(ExpenseOccurrenceStatusLookup(statuses: [malformed]).status(for: occurrence))
        XCTAssertEqual(
            ExpenseOccurrenceStatusLookup(statuses: [malformed, exact]).status(for: occurrence), .skipped
        )
        let future = forecast(event, date: date(2030, 1, 1))
        XCTAssertNil(ExpenseOccurrenceStatusLookup(statuses: [exact]).status(for: future))
        XCTAssertEqual(
            ExpenseOccurrenceLifecycleResolver.lifecycle(
                for: future, statuses: [malformed, exact], now: date(2027, 1, 1), calendar: calendar
            ), .upcoming
        )
        XCTAssertEqual(malformed.occurrenceID, malformedKey)
        XCTAssertEqual(exact.sourceEventID, conflictingOwner)
        XCTAssertEqual(exact.occurrenceDate, conflictingDate)
        XCTAssertEqual(exact.statusRawValue, "skipped")
    }

    func testRebuildingAllocationLookupReflectsMutableAmountsAndExactKeys() {
        let event = expense()
        let july = forecast(event)
        let august = forecast(event, date: date(2026, 8, 1))
        let record = allocation(july, amount: 400)
        XCTAssertEqual(
            EventAllocationAmountLookup(allocations: [record]).allocatedAmount(for: july), 400
        )

        record.allocatedAmount = 100
        XCTAssertEqual(
            EventAllocationAmountLookup(allocations: [record]).allocatedAmount(for: july), 100
        )
        record.occurrenceID = august.occurrenceID
        let rebuilt = EventAllocationAmountLookup(allocations: [record])
        XCTAssertEqual(rebuilt.allocatedAmount(for: july), 0)
        XCTAssertEqual(rebuilt.allocatedAmount(for: august), 100)
    }

    func testRebuildingStatusLookupReflectsMutableRawStatusAndExactKeys() {
        let event = expense()
        let july = forecast(event)
        let august = forecast(event, date: date(2026, 8, 1))
        let record = status(july, rawValue: "paid")
        XCTAssertEqual(ExpenseOccurrenceStatusLookup(statuses: [record]).status(for: july), .paid)

        record.statusRawValue = "future-status"
        XCTAssertNil(ExpenseOccurrenceStatusLookup(statuses: [record]).status(for: july))
        record.statusRawValue = "skipped"
        record.occurrenceID = august.occurrenceID
        let rebuilt = ExpenseOccurrenceStatusLookup(statuses: [record])
        XCTAssertNil(rebuilt.status(for: july))
        XCTAssertEqual(rebuilt.status(for: august), .skipped)
    }

    private func historicalOccurrences() -> (events: [PlannerEvent], occurrences: [ForecastEvent]) {
        let firstDate = date(2018, 1, 1)
        let events = (0..<20).map { _ in
            PlannerEvent(
                name: "Recurring expense", amount: 5_000, date: firstDate,
                frequency: .monthly, type: .expense
            )
        }
        let occurrences = events.flatMap { event in
            (0..<100).map { month in
                forecast(event, date: calendar.date(byAdding: .month, value: month, to: firstDate)!)
            }
        }
        return (events, occurrences)
    }

    private func expense(name: String = "Monthly expense") -> PlannerEvent {
        PlannerEvent(
            name: name, amount: 400, date: date(2026, 7, 1), frequency: .monthly, type: .expense
        )
    }

    private func forecast(_ event: PlannerEvent, date: Date? = nil) -> ForecastEvent {
        ForecastEvent(event: event, occurrenceDate: date ?? event.date)
    }

    private func allocation(_ forecast: ForecastEvent, amount: Double) -> EventAllocation {
        EventAllocation(
            occurrenceID: forecast.occurrenceID, sourceEventID: forecast.event.id,
            occurrenceDate: forecast.occurrenceDate, allocatedAmount: amount
        )
    }

    private func status(_ forecast: ForecastEvent, rawValue: String) -> ExpenseOccurrenceStatus {
        let record = ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID, sourceEventID: forecast.event.id,
            occurrenceDate: forecast.occurrenceDate, status: .paid
        )
        record.statusRawValue = rawValue
        return record
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private nonisolated final class TraversalCount {
        var iteratorCreations = 0
        var elementsVisited = 0
    }

    private func countedSequence<Element>(
        _ values: [Element],
        traversal: TraversalCount
    ) -> AnySequence<Element> {
        AnySequence {
            traversal.iteratorCreations += 1
            var iterator = values.makeIterator()
            return AnyIterator<Element> {
                guard let value = iterator.next() else { return nil }
                traversal.elementsVisited += 1
                return value
            }
        }
    }
}
