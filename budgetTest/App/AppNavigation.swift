import SwiftUI
import Combine

struct UpcomingExpenseEditNavigationRequest: Equatable {
    let eventID: UUID
    let occurrenceID: String
}

@MainActor
final class AppNavigation: ObservableObject {

    @Published var selectedTab = 0

    @Published var shouldCreateUpcomingExpense = false
    @Published var savingsGoalToEditID: UUID?
    @Published var upcomingExpenseToEditRequest:
        UpcomingExpenseEditNavigationRequest?
    @Published var debtPayoffToEditID: UUID?
    @Published var debtPayoffCycleToEditID: UUID?
    @Published var shouldOpenReviewUpdates = false
    @Published var recurringRecommendationToReviewID: String?
    @Published var shouldOpenPlanAheadPastDue = false
    @Published var setAsideSectionToOpen: SetAsidePagerSection?

    @Published var expandChecking = false
    @Published var expandSavings = false

    @Published var expandCredit = false
    @Published var expandLoans = false
    @Published var shouldOpenLinkedAccounts = false

    // Avoid the iOS 26.1 executor-isolated deinit crash; this type owns no teardown work.
    nonisolated deinit {}

    func openSavings() {
        openSavings(section: .defaultSelection)
    }

    func openSavings(section: SetAsidePagerSection) {
        setAsideSectionToOpen = section
        selectedTab = 1
    }

    func openTimelineCreateExpense() {
        selectedTab = 2
        shouldCreateUpcomingExpense = true
    }

    func openSavingsEditGoal(_ id: UUID) {
        savingsGoalToEditID = id
        openSavings(section: .savingsGoals)
    }

    func openTimelineEditUpcomingExpense(
        eventID: UUID,
        occurrenceID: String
    ) {
        selectedTab = 2
        upcomingExpenseToEditRequest = UpcomingExpenseEditNavigationRequest(
            eventID: eventID,
            occurrenceID: occurrenceID
        )
    }

    func openSavingsEditDebtPayoff(
        _ id: UUID,
        cycleID: UUID? = nil
    ) {
        debtPayoffToEditID = id
        debtPayoffCycleToEditID = cycleID
        openSavings(section: .paymentPlans)
    }

    func openReviewUpdates() {
        selectedTab = 2
        shouldOpenReviewUpdates = true
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
        savingsGoalToEditID = nil
        upcomingExpenseToEditRequest = nil
        debtPayoffToEditID = nil
        debtPayoffCycleToEditID = nil
        shouldOpenReviewUpdates = false
        recurringRecommendationToReviewID = nil
        shouldOpenPlanAheadPastDue = false
        setAsideSectionToOpen = nil
        expandChecking = false
        expandSavings = false
        expandCredit = false
        expandLoans = false
        shouldOpenLinkedAccounts = false
    }
    #endif
}
