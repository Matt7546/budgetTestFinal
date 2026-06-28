import SwiftUI
import Combine
import SwiftData

@main
struct budgetTestApp: App {

    @StateObject private var auth: AuthManager
    @StateObject private var plaid: PlaidService
    @StateObject private var summary: SummaryViewModel
    @StateObject private var navigation = AppNavigation()

    init() {

        AppLogger.environment(AppConfig.environmentDisplayName)
        AppLogger.environment("Backend: \(AppConfig.backendBaseURL.absoluteString)")
        AppLogger.environment("Expected Plaid: \(AppConfig.expectedPlaidEnvironment)")
        AppLogger.environment("API key configured: \(AppConfig.isBackendAPIKeyConfigured)")
        #if DEBUG
        AppConfig.debugConfigurationWarnings.forEach { warning in
            AppLogger.warning(
                warning,
                category: .environment
            )
        }
        #endif

        let authManager = AuthManager()
        let plaidService = PlaidService {
            authManager.backendSessionToken
        }

        _auth = StateObject(
            wrappedValue: authManager
        )

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

            SplashRootView {
                AppRootView()
            }
            .environmentObject(auth)
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
                ReserveSettings.self,
                DebtPayoffBucket.self
            ]
        )
    }
}
