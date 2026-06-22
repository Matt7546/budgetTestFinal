import Foundation
import SwiftData

@Model
final class EventAllocation {

    @Attribute(.unique)
    var occurrenceID: String

    var id: UUID
    var sourceEventID: UUID
    var occurrenceDate: Date
    var allocatedAmount: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        occurrenceID: String,
        sourceEventID: UUID,
        occurrenceDate: Date,
        allocatedAmount: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.occurrenceID = occurrenceID
        self.sourceEventID = sourceEventID
        self.occurrenceDate = occurrenceDate
        self.allocatedAmount = allocatedAmount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension EventAllocation {

    func apply(
        amount: Double,
        eventAmount: Double
    ) {
        allocatedAmount = min(
            max(allocatedAmount + amount, 0),
            eventAmount
        )
        updatedAt = Date()
    }
}
