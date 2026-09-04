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
    let targetAmount: Double?
    let setAsideAmount: Double?
    let destination: DashboardWidgetDestinationIdentity?
    let accessibilityLabel: String

    init(
        id: String,
        title: String,
        context: String,
        primaryValue: String,
        secondaryValue: String?,
        progress: Double?,
        targetAmount: Double? = nil,
        setAsideAmount: Double? = nil,
        destination: DashboardWidgetDestinationIdentity?,
        accessibilityLabel: String
    ) {
        self.id = id
        self.title = title
        self.context = context
        self.primaryValue = primaryValue
        self.secondaryValue = secondaryValue
        self.progress = progress
        self.targetAmount = targetAmount
        self.setAsideAmount = setAsideAmount
        self.destination = destination
        self.accessibilityLabel = accessibilityLabel
    }
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
    let timeframe: DashboardWidgetTimeframe?

    init(
        kind: DashboardWidgetKind,
        title: String,
        subtitle: String,
        primaryValue: String,
        secondaryValue: String?,
        status: String?,
        progress: Double?,
        categoryRole: CalderaFinanceSemanticRole,
        destination: DashboardWidgetDestinationIdentity?,
        contentState: DashboardWidgetContentState,
        items: [DashboardWidgetItemSnapshot],
        accessibilityLabel: String,
        timeframe: DashboardWidgetTimeframe? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.secondaryValue = secondaryValue
        self.status = status
        self.progress = progress
        self.categoryRole = categoryRole
        self.destination = destination
        self.contentState = contentState
        self.items = items
        self.accessibilityLabel = accessibilityLabel
        self.timeframe = timeframe
    }

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
