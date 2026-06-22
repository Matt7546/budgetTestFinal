import Foundation

enum EventAllocationTotals {

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

        let latestAllocationByOccurrence =
            Dictionary(
                allocations.map {
                    (
                        $0.occurrenceID,
                        max($0.allocatedAmount, 0)
                    )
                },
                uniquingKeysWith: { _, latest in
                    latest
                }
            )

        return latestAllocationByOccurrence.reduce(0) { total, entry in
            guard let forecast = activeForecastByOccurrenceID[entry.key] else {
                return total
            }

            return total + min(
                entry.value,
                forecast.event.amount
            )
        }
    }
}
