import SwiftUI
import Combine
import SwiftData

@main
struct budgetTestApp: App {

    @StateObject private var plaid: PlaidService
    @StateObject private var summary: SummaryViewModel
    @StateObject private var navigation = AppNavigation()

    init() {

        print("Caldera backend base URL: \(AppConfig.backendBaseURL.absoluteString)")

        let plaidService = PlaidService()

        _plaid = StateObject(
            wrappedValue: plaidService
        )

        _summary = StateObject(
            wrappedValue: SummaryViewModel(
                accountsPublisher: plaidService.$accounts.eraseToAnyPublisher(),
                goalsPublisher: plaidService.$savingsGoals.eraseToAnyPublisher(),
                reservePublisher: plaidService.$reserveBalance.eraseToAnyPublisher()
            )
        )
    }

    var body: some Scene {

        WindowGroup {

            AppRootView()
                .environmentObject(plaid)
                .environmentObject(summary)
                .environmentObject(navigation)
        }
        .modelContainer(
            for: [
                PlannerEvent.self,
                EventAllocation.self,
                ExpenseOccurrenceStatus.self,
                SavingsGoalRecord.self,
                ReserveSettings.self
            ]
        )
    }
}
