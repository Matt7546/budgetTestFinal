import Foundation

enum DashboardWidgetTimeframe: String, CaseIterable, Codable, Identifiable {
    case next7Days
    case next14Days
    case next30Days
    case next60Days

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .next7Days:
            return 7
        case .next14Days:
            return 14
        case .next30Days:
            return 30
        case .next60Days:
            return 60
        }
    }

    var displayName: String {
        "Next \(dayCount) days"
    }
}

struct DashboardWidgetPreferences: Equatable {
    static let storageKey = "dashboard.widgets.layout.v1"

    private static let currentVersion = 1

    private struct StoredLayout: Codable {
        let version: Int
        let order: [String]
        let hidden: [String]
        let timeframes: [String: String]?
    }

    private(set) var orderedKinds: [DashboardWidgetKind]
    private(set) var hiddenKinds: Set<DashboardWidgetKind>
    private(set) var timeframes: [DashboardWidgetKind: DashboardWidgetTimeframe]

    init(
        orderedKinds: [DashboardWidgetKind] = DashboardWidgetKind.defaultOrder,
        hiddenKinds: Set<DashboardWidgetKind> = [],
        timeframes: [DashboardWidgetKind: DashboardWidgetTimeframe] = [:]
    ) {
        self.orderedKinds = Self.normalizedOrder(orderedKinds)
        self.hiddenKinds = hiddenKinds.intersection(
            Set(DashboardWidgetKind.allCases)
        )
        self.timeframes = timeframes.filter { kind, timeframe in
            kind.timeframeOptions.contains(timeframe) &&
                timeframe != kind.defaultTimeframe
        }
    }

    init(storedValue: String) {
        guard !storedValue.isEmpty,
              let data = storedValue.data(using: .utf8),
              let stored = try? JSONDecoder().decode(
                  StoredLayout.self,
                  from: data
              ),
              stored.version == Self.currentVersion else {
            self.init()
            return
        }

        let decodedOrder = stored.order.compactMap(DashboardWidgetKind.init(rawValue:))
        let decodedHidden = Set(
            stored.hidden.compactMap(DashboardWidgetKind.init(rawValue:))
        )
        let decodedTimeframes = (stored.timeframes ?? [:]).reduce(
            into: [DashboardWidgetKind: DashboardWidgetTimeframe]()
        ) { result, entry in
            guard let kind = DashboardWidgetKind(rawValue: entry.key),
                  let timeframe = DashboardWidgetTimeframe(
                      rawValue: entry.value
                  ) else {
                return
            }

            result[kind] = timeframe
        }
        self.init(
            orderedKinds: decodedOrder,
            hiddenKinds: decodedHidden,
            timeframes: decodedTimeframes
        )
    }

    var visibleKinds: [DashboardWidgetKind] {
        orderedKinds.filter { !hiddenKinds.contains($0) }
    }

    var hiddenKindsInDefaultOrder: [DashboardWidgetKind] {
        DashboardWidgetKind.defaultOrder.filter(hiddenKinds.contains)
    }

    var isDefault: Bool {
        orderedKinds == DashboardWidgetKind.defaultOrder &&
            hiddenKinds.isEmpty &&
            timeframes.isEmpty
    }

    func timeframe(
        for kind: DashboardWidgetKind
    ) -> DashboardWidgetTimeframe? {
        guard let defaultTimeframe = kind.defaultTimeframe else {
            return nil
        }

        return timeframes[kind] ?? defaultTimeframe
    }

    func canMoveUp(_ kind: DashboardWidgetKind) -> Bool {
        guard let index = visibleKinds.firstIndex(of: kind) else {
            return false
        }

        return index > visibleKinds.startIndex
    }

    func canMoveDown(_ kind: DashboardWidgetKind) -> Bool {
        guard let index = visibleKinds.firstIndex(of: kind) else {
            return false
        }

        return index < visibleKinds.index(before: visibleKinds.endIndex)
    }

    mutating func hide(_ kind: DashboardWidgetKind) {
        hiddenKinds.insert(kind)
    }

    mutating func show(_ kind: DashboardWidgetKind) {
        hiddenKinds.remove(kind)
        orderedKinds.removeAll { $0 == kind }
        orderedKinds.append(kind)
    }

    mutating func moveUp(_ kind: DashboardWidgetKind) {
        move(kind, offset: -1)
    }

    mutating func moveDown(_ kind: DashboardWidgetKind) {
        move(kind, offset: 1)
    }

    mutating func setTimeframe(
        _ timeframe: DashboardWidgetTimeframe,
        for kind: DashboardWidgetKind
    ) {
        guard kind.timeframeOptions.contains(timeframe) else {
            return
        }

        if timeframe == kind.defaultTimeframe {
            timeframes.removeValue(forKey: kind)
        } else {
            timeframes[kind] = timeframe
        }
    }

    mutating func reset() {
        self = DashboardWidgetPreferences()
    }

    func storedValue() -> String {
        let stored = StoredLayout(
            version: Self.currentVersion,
            order: orderedKinds.map(\.rawValue),
            hidden: DashboardWidgetKind.defaultOrder
                .filter(hiddenKinds.contains)
                .map(\.rawValue),
            timeframes: timeframes.isEmpty
                ? nil
                : Dictionary(
                    uniqueKeysWithValues: timeframes.map {
                        ($0.key.rawValue, $0.value.rawValue)
                    }
                )
        )

        guard let data = try? JSONEncoder().encode(stored),
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }

        return value
    }

    func renderableSnapshots(
        from collection: DashboardWidgetSnapshotCollection
    ) -> [DashboardWidgetSnapshot] {
        visibleKinds.compactMap { kind in
            guard let snapshot = collection.snapshot(for: kind),
                  snapshot.contentState != .hidden else {
                return nil
            }

            return snapshot
        }
    }

    private mutating func move(
        _ kind: DashboardWidgetKind,
        offset: Int
    ) {
        var visible = visibleKinds
        guard let sourceIndex = visible.firstIndex(of: kind) else {
            return
        }

        let destinationIndex = sourceIndex + offset
        guard visible.indices.contains(destinationIndex) else {
            return
        }

        visible.swapAt(sourceIndex, destinationIndex)
        let hidden = orderedKinds.filter(hiddenKinds.contains)
        orderedKinds = visible + hidden
    }

    private static func normalizedOrder(
        _ kinds: [DashboardWidgetKind]
    ) -> [DashboardWidgetKind] {
        var seen: Set<DashboardWidgetKind> = []
        let knownOrder = kinds.filter { seen.insert($0).inserted }
        let newDefaults = DashboardWidgetKind.defaultOrder.filter {
            !seen.contains($0)
        }

        return knownOrder + newDefaults
    }
}

extension DashboardWidgetKind {
    var timeframeOptions: [DashboardWidgetTimeframe] {
        switch self {
        case .upcomingExpenses:
            return DashboardWidgetTimeframe.allCases
        case .setAside,
             .bankSync,
             .reviewUpdates,
             .savingsGoal,
             .paymentPlans,
             .planAhead:
            return []
        }
    }

    var defaultTimeframe: DashboardWidgetTimeframe? {
        switch self {
        case .upcomingExpenses:
            return .next30Days
        case .setAside,
             .bankSync,
             .reviewUpdates,
             .savingsGoal,
             .paymentPlans,
             .planAhead:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .setAside:
            return "Set Aside"
        case .bankSync:
            return "Bank Sync"
        case .reviewUpdates:
            return "Review Updates"
        case .savingsGoal:
            return "Savings Goal"
        case .upcomingExpenses:
            return "Upcoming Expenses"
        case .paymentPlans:
            return "Payment Plans"
        case .planAhead:
            return "Plan Ahead"
        }
    }

    var categoryRole: CalderaFinanceSemanticRole {
        switch self {
        case .setAside:
            return .reserve
        case .bankSync,
             .planAhead:
            return .bankAccount
        case .reviewUpdates:
            return .needsMoney
        case .savingsGoal:
            return .savingsGoal
        case .upcomingExpenses:
            return .upcomingExpense
        case .paymentPlans:
            return .debtPayoff
        }
    }
}
