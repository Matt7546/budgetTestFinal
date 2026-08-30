import Foundation

enum DashboardSetupDestination: Equatable {
    case signInWithApple
    case linkedAccounts
    case setAside
    case addUpcomingExpense
}

enum DashboardSetupStep: String, CaseIterable, Identifiable {
    case downloadCaldera
    case signIn
    case connectBank
    case chooseSpendingAccounts
    case setAside
    case addToPlan

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .downloadCaldera:
            return "Download Caldera"
        case .signIn:
            return "Sign in with Apple"
        case .connectBank:
            return "Connect your bank"
        case .chooseSpendingAccounts:
            return "Choose accounts"
        case .setAside:
            return "Set money aside"
        case .addToPlan:
            return "Add an Upcoming Expense"
        }
    }

    var detail: String {
        switch self {
        case .downloadCaldera:
            return "Install the app and start your setup."
        case .signIn:
            return "Create your private Caldera account."
        case .connectBank:
            return "Link accounts so Caldera can estimate from your balances."
        case .chooseSpendingAccounts:
            return "Choose which linked cash accounts count toward Available to Spend."
        case .setAside:
            return "Create your first Set Aside item."
        case .addToPlan:
            return "Add a future expense so Caldera can help you plan ahead."
        }
    }

    var nextMessage: String {
        switch self {
        case .downloadCaldera:
            return "Setup complete"
        case .signIn:
            return "Next: Sign in with Apple"
        case .connectBank:
            return "Next: Connect your bank"
        case .chooseSpendingAccounts:
            return "Next: Choose which accounts count"
        case .setAside:
            return "Next: Set money aside"
        case .addToPlan:
            return "Next: Add an Upcoming Expense"
        }
    }

    var systemImage: String {
        switch self {
        case .downloadCaldera:
            return "arrow.down.app.fill"
        case .signIn:
            return "person.crop.circle.fill"
        case .connectBank:
            return "building.columns.fill"
        case .chooseSpendingAccounts:
            return "checklist"
        case .setAside:
            return "wallet.pass.fill"
        case .addToPlan:
            return "calendar.badge.plus"
        }
    }

    var destination: DashboardSetupDestination? {
        switch self {
        case .downloadCaldera:
            return nil
        case .signIn:
            return .signInWithApple
        case .connectBank,
             .chooseSpendingAccounts:
            return .linkedAccounts
        case .setAside:
            return .setAside
        case .addToPlan:
            return .addUpcomingExpense
        }
    }

    var expandsLinkedCashAccountGroups: Bool {
        self == .chooseSpendingAccounts
    }

    var allowsManualCompletion: Bool {
        self != .signIn
    }
}

struct DashboardSetupProgressItem: Identifiable {
    let step: DashboardSetupStep
    let isComplete: Bool

    var id: DashboardSetupStep {
        step
    }

    var accessibilityLabel: String {
        "\(step.title). \(isComplete ? "Complete" : "Not complete"). \(step.detail)"
    }
}

struct DashboardSetupProgress {
    let items: [DashboardSetupProgressItem]

    init(
        isSignedIn: Bool,
        hasLinkedBanks: Bool,
        hasConfiguredSpendingAccounts: Bool,
        hasSetAsideItem: Bool,
        hasPlanItem: Bool,
        manuallyCompletedSteps: Set<DashboardSetupStep> = []
    ) {
        items = [
            DashboardSetupProgressItem(
                step: .downloadCaldera,
                isComplete: true
            ),
            DashboardSetupProgressItem(
                step: .signIn,
                isComplete: isSignedIn
            ),
            DashboardSetupProgressItem(
                step: .connectBank,
                isComplete: hasLinkedBanks || manuallyCompletedSteps.contains(.connectBank)
            ),
            DashboardSetupProgressItem(
                step: .chooseSpendingAccounts,
                isComplete: hasConfiguredSpendingAccounts ||
                    manuallyCompletedSteps.contains(.chooseSpendingAccounts)
            ),
            DashboardSetupProgressItem(
                step: .setAside,
                isComplete: hasSetAsideItem || manuallyCompletedSteps.contains(.setAside)
            ),
            DashboardSetupProgressItem(
                step: .addToPlan,
                isComplete: hasPlanItem || manuallyCompletedSteps.contains(.addToPlan)
            )
        ]
    }

    var completedCount: Int {
        items.filter(\.isComplete).count
    }

    var totalCount: Int {
        items.count
    }

    var isComplete: Bool {
        completedCount == totalCount
    }

    var nextIncompleteItem: DashboardSetupProgressItem? {
        items.first { !$0.isComplete }
    }

    var hasFutureIncompleteSteps: Bool {
        guard let nextIncompleteItem else {
            return false
        }

        return items.contains {
            !$0.isComplete && $0.id != nextIncompleteItem.id
        }
    }

    func visibleItems(
        showingFutureSteps: Bool
    ) -> [DashboardSetupProgressItem] {
        guard !showingFutureSteps,
              let nextIncompleteItem else {
            return items
        }

        return items.filter {
            $0.isComplete || $0.id == nextIncompleteItem.id
        }
    }

    var progressAccessibilityValue: String {
        "\(completedCount) of \(totalCount) setup steps complete"
    }
}

enum DashboardSetupManualCompletionPreference {
    static let storageKey = "dashboard.setup.manuallyCompletedSteps"

    static func steps(from storedValue: String) -> Set<DashboardSetupStep> {
        Set(
            storedValue
                .split(separator: ",")
                .compactMap { DashboardSetupStep(rawValue: String($0)) }
                .filter(\.allowsManualCompletion)
        )
    }

    static func storedValue(
        for steps: Set<DashboardSetupStep>
    ) -> String {
        DashboardSetupStep.allCases
            .filter(\.allowsManualCompletion)
            .filter(steps.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }

    static func markingCompleted(
        _ step: DashboardSetupStep,
        in storedValue: String
    ) -> String {
        guard step.allowsManualCompletion else {
            return self.storedValue(for: steps(from: storedValue))
        }

        var steps = steps(from: storedValue)
        steps.insert(step)
        return self.storedValue(for: steps)
    }

    static func markingCurrentStepCompleted(
        _ step: DashboardSetupStep,
        in progress: DashboardSetupProgress,
        storedValue: String
    ) -> String {
        guard step.allowsManualCompletion,
              progress.nextIncompleteItem?.step == step else {
            return self.storedValue(for: steps(from: storedValue))
        }

        return markingCompleted(step, in: storedValue)
    }
}
