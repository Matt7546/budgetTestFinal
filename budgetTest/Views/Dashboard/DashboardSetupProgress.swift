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
            return "Choose spending accounts"
        case .setAside:
            return "Set money aside"
        case .addToPlan:
            return "Add an Upcoming Expense"
        }
    }

    var detail: String {
        switch self {
        case .downloadCaldera:
            return "You're ready to start setting up your plan."
        case .signIn:
            return "Keep Bank Sync and your plan tied to your account."
        case .connectBank:
            return "Link balances so Caldera can estimate Available to Spend."
        case .chooseSpendingAccounts:
            return "Choose which linked cash accounts count toward Available to Spend."
        case .setAside:
            return "Create a Cash Cushion, Savings Goal, or Payment Plan."
        case .addToPlan:
            return "Add a bill, subscription, or planned expense."
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
        hasPlanItem: Bool
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
                isComplete: hasLinkedBanks
            ),
            DashboardSetupProgressItem(
                step: .chooseSpendingAccounts,
                isComplete: hasConfiguredSpendingAccounts
            ),
            DashboardSetupProgressItem(
                step: .setAside,
                isComplete: hasSetAsideItem
            ),
            DashboardSetupProgressItem(
                step: .addToPlan,
                isComplete: hasPlanItem
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

    var progressAccessibilityValue: String {
        "\(completedCount) of \(totalCount) setup steps complete"
    }
}
