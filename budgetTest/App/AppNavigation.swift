import SwiftUI
import Combine

@MainActor
final class AppNavigation: ObservableObject {

    @Published var selectedTab = 0

    @Published var shouldCreateUpcomingExpense = false
    @Published var debtPayoffToEditID: UUID?
    @Published var recurringRecommendationToReviewID: String?
    @Published var shouldOpenPlanAheadPastDue = false

    @Published var expandChecking = false
    @Published var expandSavings = false

    @Published var expandCredit = false
    @Published var expandLoans = false
    @Published var shouldOpenLinkedAccounts = false

    // Avoid the iOS 26.1 executor-isolated deinit crash; this type owns no teardown work.
    nonisolated deinit {}

    func openSavings() {
        selectedTab = 1
    }

    func openTimelineCreateExpense() {
        selectedTab = 2
        shouldCreateUpcomingExpense = true
    }

    func openSavingsEditDebtPayoff(_ id: UUID) {
        selectedTab = 1
        debtPayoffToEditID = id
    }

    func openTimelineRecurringRecommendation(
        _ historyID: String
    ) {
        selectedTab = 2
        recurringRecommendationToReviewID = historyID
    }

    func openPlanAheadPastDue() {
        selectedTab = 2
        shouldOpenPlanAheadPastDue = true
    }

    func openBankSync() {
        selectedTab = 3
        shouldOpenLinkedAccounts = true
    }

    #if DEBUG
    func resetForUXResearch() {
        guard AppConfig.isDebugLocal else {
            return
        }

        selectedTab = 0
        shouldCreateUpcomingExpense = false
        debtPayoffToEditID = nil
        recurringRecommendationToReviewID = nil
        shouldOpenPlanAheadPastDue = false
        expandChecking = false
        expandSavings = false
        expandCredit = false
        expandLoans = false
        shouldOpenLinkedAccounts = false
    }
    #endif
}
