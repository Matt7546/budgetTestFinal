import Foundation

struct SavingsGoal: Identifiable, Codable, Equatable {

    let id: UUID
    var name: String
    var targetAmount: Double
    var currentAmount: Double
    var isPinned: Bool
    var saveByDate: Date?

    var progress: Double {
        guard targetAmount > 0 else { return 0 }

        let value = currentAmount / targetAmount
        guard value.isFinite else { return 0 }

        return min(
            max(value, 0),
            1
        )
    }

    init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Double,
        currentAmount: Double = 0,
        isPinned: Bool = false,
        saveByDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.isPinned = isPinned
        self.saveByDate = saveByDate
    }
}

extension SavingsGoal {

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case targetAmount
        case currentAmount
        case isPinned
        case saveByDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decode(
            UUID.self,
            forKey: .id
        )

        name = try container.decode(
            String.self,
            forKey: .name
        )

        targetAmount = try container.decode(
            Double.self,
            forKey: .targetAmount
        )

        currentAmount = try container.decode(
            Double.self,
            forKey: .currentAmount
        )

        isPinned = try container.decodeIfPresent(
            Bool.self,
            forKey: .isPinned
        ) ?? false

        saveByDate = try container.decodeIfPresent(
            Date.self,
            forKey: .saveByDate
        )
    }
}
