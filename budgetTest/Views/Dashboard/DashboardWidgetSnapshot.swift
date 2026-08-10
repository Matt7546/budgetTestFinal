import Foundation

enum DashboardWidgetKind: String, CaseIterable, Identifiable {
    case setAside
    case bankSync
    case reviewUpdates
    case savingsGoal
    case upcomingExpenses
    case paymentPlans
    case planAhead

    var id: String { rawValue }

    static let defaultOrder: [DashboardWidgetKind] = [
        .setAside,
        .bankSync,
        .reviewUpdates,
        .savingsGoal,
        .upcomingExpenses,
        .paymentPlans,
        .planAhead
    ]
}

enum DashboardWidgetContentState: Equatable {
    case content
    case empty
    case hidden
}

enum DashboardWidgetDestinationIdentity: Hashable {
    case setAside
    case bankSync
    case reviewUpdates
    case savingsGoal(UUID)
    case upcomingExpense(eventID: UUID, occurrenceID: String)
    case paymentPlan(bucketID: UUID, cycleID: UUID?)
    case planAhead
}

struct DashboardWidgetItemSnapshot: Identifiable {
    let id: String
    let title: String
    let context: String
    let primaryValue: String
    let secondaryValue: String?
    let progress: Double?
    let destination: DashboardWidgetDestinationIdentity?
    let accessibilityLabel: String
}

struct DashboardWidgetSnapshot: Identifiable {
    let kind: DashboardWidgetKind
    let title: String
    let subtitle: String
    let primaryValue: String
    let secondaryValue: String?
    let status: String?
    let progress: Double?
    let categoryRole: CalderaFinanceSemanticRole
    let destination: DashboardWidgetDestinationIdentity?
    let contentState: DashboardWidgetContentState
    let items: [DashboardWidgetItemSnapshot]
    let accessibilityLabel: String

    var id: DashboardWidgetKind { kind }
}

struct DashboardWidgetSnapshotCollection {
    let orderedSnapshots: [DashboardWidgetSnapshot]

    var visibleSnapshots: [DashboardWidgetSnapshot] {
        orderedSnapshots.filter { $0.contentState != .hidden }
    }

    func snapshot(
        for kind: DashboardWidgetKind
    ) -> DashboardWidgetSnapshot? {
        orderedSnapshots.first { $0.kind == kind }
    }
}
