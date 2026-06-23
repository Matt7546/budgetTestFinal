import SwiftUI
import Combine
import SwiftData

@main
struct budgetTestApp: App {

    @StateObject private var plaid: PlaidService
    @StateObject private var summary: SummaryViewModel
    @StateObject private var navigation = AppNavigation()

    init() {

        #if DEBUG
        print("[Environment] \(AppConfig.environmentDisplayName)")
        print("[Environment] Backend: \(AppConfig.backendBaseURL.absoluteString)")
        print("[Environment] Expected Plaid: \(AppConfig.expectedPlaidEnvironment)")
        print("[Environment] API key configured: \(AppConfig.isBackendAPIKeyConfigured)")
        AppConfig.debugConfigurationWarnings.forEach { warning in
            print("[Environment Warning] \(warning)")
        }
        #endif

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
