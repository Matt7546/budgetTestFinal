#if DEBUG

import SwiftUI

enum LabDashboardWidgetSize: String, CaseIterable, Identifiable, Hashable {
    case square
    case wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square:
            return "Square"
        case .wide:
            return "Wide"
        }
    }

    var systemImage: String {
        switch self {
        case .square:
            return "square"
        case .wide:
            return "rectangle"
        }
    }
}

enum LabDashboardWidgetContentMode: String {
    case individual
    case aggregate
    case selectable
}

enum LabDashboardWidgetType: String, CaseIterable, Identifiable {
    case availableToSpend
    case setAside
    case paymentPlans
    case upcomingExpenses
    case savingsGoal
    case planAhead
    case reviewUpdates
    case bankSync

    var id: String { rawValue }
}

struct LabDashboardWidgetSample: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let contentMode: LabDashboardWidgetContentMode
    let supportedSizes: [LabDashboardWidgetSize]
    let recommendedSize: LabDashboardWidgetSize
}

struct LabDashboardWidgetDefinition: Identifiable {
    let type: LabDashboardWidgetType
    let displayName: String
    let purpose: String
    let systemImage: String
    let style: CalderaCategoryStyle
    let supportedSizes: [LabDashboardWidgetSize]
    let recommendedSize: LabDashboardWidgetSize
    let contentMode: LabDashboardWidgetContentMode
    let samples: [LabDashboardWidgetSample]
    let defaultSampleID: String?

    var id: LabDashboardWidgetType { type }

    var needsInformationSelection: Bool {
        !samples.isEmpty
    }

    var defaultSample: LabDashboardWidgetSample? {
        guard let defaultSampleID else { return samples.first }
        return samples.first { $0.id == defaultSampleID } ?? samples.first
    }

    func sample(id: String?) -> LabDashboardWidgetSample? {
        guard let id else { return defaultSample }
        return samples.first { $0.id == id } ?? defaultSample
    }

    func sizes(for sampleID: String?) -> [LabDashboardWidgetSize] {
        sample(id: sampleID)?.supportedSizes ?? supportedSizes
    }

    func recommendedSize(for sampleID: String?) -> LabDashboardWidgetSize {
        sample(id: sampleID)?.recommendedSize ?? recommendedSize
    }
}

struct LabDashboardWidgetInstance: Identifiable, Equatable {
    let id: UUID
    var type: LabDashboardWidgetType
    var size: LabDashboardWidgetSize
    var sampleID: String?

    init(
        id: UUID = UUID(),
        type: LabDashboardWidgetType,
        size: LabDashboardWidgetSize,
        sampleID: String? = nil
    ) {
        self.id = id
        self.type = type
        self.size = size
        self.sampleID = sampleID
    }

    var definition: LabDashboardWidgetDefinition {
        LabDashboardWidgetCatalog.definition(for: type)
    }

    var sample: LabDashboardWidgetSample? {
        definition.sample(id: sampleID)
    }
}

struct LabDashboardWidgetConfigurationRequest: Identifiable {
    let id = UUID()
    let widget: LabDashboardWidgetInstance?
}

enum LabDashboardWidgetCatalog {
    static let definitions: [LabDashboardWidgetDefinition] = [
        LabDashboardWidgetDefinition(
            type: .availableToSpend,
            displayName: "Available to Spend",
            purpose: "Your main spending answer",
            systemImage: "sparkles",
            style: CalderaCategoryStyle.style(for: .safeToSpend),
            supportedSizes: [.wide],
            recommendedSize: .wide,
            contentMode: .aggregate,
            samples: [],
            defaultSampleID: nil
        ),
        LabDashboardWidgetDefinition(
            type: .setAside,
            displayName: "Set Aside",
            purpose: "Money held back by purpose",
            systemImage: "wallet.pass.fill",
            style: CalderaCategoryStyle.style(for: .reserve),
            supportedSizes: [.square],
            recommendedSize: .square,
            contentMode: .aggregate,
            samples: [],
            defaultSampleID: nil
        ),
        LabDashboardWidgetDefinition(
            type: .paymentPlans,
            displayName: "Payment Plans",
            purpose: "Funding for one plan or the next three",
            systemImage: "creditcard.fill",
            style: CalderaCategoryStyle.style(for: .debtPayoff),
            supportedSizes: [.square, .wide],
            recommendedSize: .wide,
            contentMode: .selectable,
            samples: paymentPlanSamples,
            defaultSampleID: "payment.nextThree"
        ),
        LabDashboardWidgetDefinition(
            type: .upcomingExpenses,
            displayName: "Upcoming Expenses",
            purpose: "One expense or the next three",
            systemImage: CalderaCategoryStyle.style(for: .upcomingExpense).icon,
            style: CalderaCategoryStyle.style(for: .upcomingExpense),
            supportedSizes: [.square, .wide],
            recommendedSize: .square,
            contentMode: .selectable,
            samples: upcomingExpenseSamples,
            defaultSampleID: "expense.rent"
        ),
        LabDashboardWidgetDefinition(
            type: .savingsGoal,
            displayName: "Savings Goal",
            purpose: "Progress toward one goal",
            systemImage: "target",
            style: CalderaCategoryStyle.style(for: .savingsGoal),
            supportedSizes: [.square],
            recommendedSize: .square,
            contentMode: .individual,
            samples: savingsGoalSamples,
            defaultSampleID: "goal.vacation"
        ),
        LabDashboardWidgetDefinition(
            type: .planAhead,
            displayName: "Plan Ahead",
            purpose: "The next three dated items",
            systemImage: "calendar",
            style: CalderaCategoryStyle.style(for: .bankAccount),
            supportedSizes: [.wide],
            recommendedSize: .wide,
            contentMode: .aggregate,
            samples: [],
            defaultSampleID: nil
        ),
        LabDashboardWidgetDefinition(
            type: .reviewUpdates,
            displayName: "Review Updates",
            purpose: "A calm count of items to review",
            systemImage: "checklist",
            style: CalderaCategoryStyle.style(for: .needsMoney),
            supportedSizes: [.square],
            recommendedSize: .square,
            contentMode: .aggregate,
            samples: [],
            defaultSampleID: nil
        ),
        LabDashboardWidgetDefinition(
            type: .bankSync,
            displayName: "Bank Sync",
            purpose: "Data freshness and account status",
            systemImage: "building.columns.fill",
            style: CalderaCategoryStyle.style(for: .bankAccount),
            supportedSizes: [.square],
            recommendedSize: .square,
            contentMode: .aggregate,
            samples: [],
            defaultSampleID: nil
        )
    ]

    static let defaultInstances: [LabDashboardWidgetInstance] = [
        LabDashboardWidgetInstance(type: .availableToSpend, size: .wide),
        LabDashboardWidgetInstance(type: .setAside, size: .square),
        LabDashboardWidgetInstance(
            type: .savingsGoal,
            size: .square,
            sampleID: "goal.vacation"
        ),
        LabDashboardWidgetInstance(
            type: .paymentPlans,
            size: .wide,
            sampleID: "payment.nextThree"
        ),
        LabDashboardWidgetInstance(
            type: .upcomingExpenses,
            size: .square,
            sampleID: "expense.rent"
        ),
        LabDashboardWidgetInstance(type: .reviewUpdates, size: .square),
        LabDashboardWidgetInstance(type: .planAhead, size: .wide),
        LabDashboardWidgetInstance(type: .bankSync, size: .square)
    ]

    static func definition(
        for type: LabDashboardWidgetType
    ) -> LabDashboardWidgetDefinition {
        definitions.first { $0.type == type } ?? definitions[0]
    }

    private static let paymentPlanSamples: [LabDashboardWidgetSample] = [
        LabDashboardWidgetSample(
            id: "payment.platinum",
            title: "Platinum Card®",
            subtitle: "$451 of $700 set aside",
            contentMode: .individual,
            supportedSizes: [.square],
            recommendedSize: .square
        ),
        LabDashboardWidgetSample(
            id: "payment.amex",
            title: "American Express Gold Card",
            subtitle: "$384 of $384 set aside",
            contentMode: .individual,
            supportedSizes: [.square],
            recommendedSize: .square
        ),
        LabDashboardWidgetSample(
            id: "payment.nextThree",
            title: "Next 3 Payment Plans",
            subtitle: "$835 of $1,586 set aside",
            contentMode: .aggregate,
            supportedSizes: [.wide],
            recommendedSize: .wide
        )
    ]

    private static let upcomingExpenseSamples: [LabDashboardWidgetSample] = [
        LabDashboardWidgetSample(
            id: "expense.rent",
            title: "Rent",
            subtitle: "$1,120 of $1,700 set aside",
            contentMode: .individual,
            supportedSizes: [.square],
            recommendedSize: .square
        ),
        LabDashboardWidgetSample(
            id: "expense.insurance",
            title: "Insurance",
            subtitle: "$180 of $240 set aside",
            contentMode: .individual,
            supportedSizes: [.square],
            recommendedSize: .square
        ),
        LabDashboardWidgetSample(
            id: "expense.phone",
            title: "Phone Bill",
            subtitle: "$80 of $95 set aside",
            contentMode: .individual,
            supportedSizes: [.square],
            recommendedSize: .square
        ),
        LabDashboardWidgetSample(
            id: "expense.nextThree",
            title: "Next 3 Upcoming Expenses",
            subtitle: "$1,380 of $2,035 set aside",
            contentMode: .aggregate,
            supportedSizes: [.wide],
            recommendedSize: .wide
        )
    ]

    private static let savingsGoalSamples: [LabDashboardWidgetSample] = [
        LabDashboardWidgetSample(
            id: "goal.emergency",
            title: "Emergency Fund",
            subtitle: "$7,600 of $10,000",
            contentMode: .individual,
            supportedSizes: [.square],
            recommendedSize: .square
        ),
        LabDashboardWidgetSample(
            id: "goal.vacation",
            title: "Vacation",
            subtitle: "$3,400 of $5,000",
            contentMode: .individual,
            supportedSizes: [.square],
            recommendedSize: .square
        ),
        LabDashboardWidgetSample(
            id: "goal.car",
            title: "New Car",
            subtitle: "$4,400 of $20,000",
            contentMode: .individual,
            supportedSizes: [.square],
            recommendedSize: .square
        )
    ]
}

#endif
