import Foundation

struct DashboardWidgetPreferences: Equatable {
    static let storageKey = "dashboard.widgets.layout.v1"

    private static let currentVersion = 1

    private struct StoredLayout: Codable {
        let version: Int
        let order: [String]
        let hidden: [String]
    }

    private(set) var orderedKinds: [DashboardWidgetKind]
    private(set) var hiddenKinds: Set<DashboardWidgetKind>

    init(
        orderedKinds: [DashboardWidgetKind] = DashboardWidgetKind.defaultOrder,
        hiddenKinds: Set<DashboardWidgetKind> = []
    ) {
        self.orderedKinds = Self.normalizedOrder(orderedKinds)
        self.hiddenKinds = hiddenKinds.intersection(
            Set(DashboardWidgetKind.allCases)
        )
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
        self.init(
            orderedKinds: decodedOrder,
            hiddenKinds: decodedHidden
        )
    }

    var visibleKinds: [DashboardWidgetKind] {
        orderedKinds.filter { !hiddenKinds.contains($0) }
    }

    var hiddenKindsInDefaultOrder: [DashboardWidgetKind] {
        DashboardWidgetKind.defaultOrder.filter(hiddenKinds.contains)
    }

    var isDefault: Bool {
        orderedKinds == DashboardWidgetKind.defaultOrder && hiddenKinds.isEmpty
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

    mutating func reset() {
        self = DashboardWidgetPreferences()
    }

    func storedValue() -> String {
        let stored = StoredLayout(
            version: Self.currentVersion,
            order: orderedKinds.map(\.rawValue),
            hidden: DashboardWidgetKind.defaultOrder
                .filter(hiddenKinds.contains)
                .map(\.rawValue)
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
