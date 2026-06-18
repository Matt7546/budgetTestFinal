import SwiftUI
import Combine
import SwiftData

@main
struct budgetTestApp: App {

    @StateObject private var plaid: PlaidService
    @StateObject private var summary: SummaryViewModel
    @StateObject private var navigation = AppNavigation()

    init() {

        let plaidService = PlaidService()

        _plaid = StateObject(
            wrappedValue: plaidService
        )

        _summary = StateObject(
            wrappedValue: SummaryViewModel(
                accountsPublisher: plaidService.$accounts.eraseToAnyPublisher(),
                goalsPublisher: plaidService.$savingsGoals.eraseToAnyPublisher()
            )
        )
    }

    var body: some Scene {

        WindowGroup {

            ContentView()
                .environmentObject(plaid)
                .environmentObject(summary)
                .environmentObject(navigation)
        }
        .modelContainer(
            for: [
                PlannerEvent.self
            ]
        )
    }
}
