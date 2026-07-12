import SwiftUI
import Combine

@MainActor
final class AppNavigation: ObservableObject {

    @Published var selectedTab = 0

    @Published var shouldCreateSavingsGoal = false
    @Published var shouldCreateUpcomingExpense = false
    @Published var shouldCreateDebtPayoff = false
    @Published var debtPayoffToEditID: UUID?
    @Published var recurringRecommendationToReviewID: String?

    @Published var expandChecking = false
    @Published var expandSavings = false

    @Published var expandCredit = false
    @Published var expandLoans = false

    func openSavings() {
        selectedTab = 1
    }

    func openTimelineCreateExpense() {
        selectedTab = 2
        shouldCreateUpcomingExpense = true
    }

    func openSavingsCreateGoal() {
        selectedTab = 1
        shouldCreateSavingsGoal = true
    }

    func openSavingsCreateDebtPayoff() {
        selectedTab = 1
        shouldCreateDebtPayoff = true
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
}
