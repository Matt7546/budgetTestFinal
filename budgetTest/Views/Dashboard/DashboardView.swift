import SwiftUI
import SwiftData

struct DashboardView: View {

    @EnvironmentObject var plaid: PlaidService
    @EnvironmentObject var summary: SummaryViewModel
    @EnvironmentObject var navigation: AppNavigation

    @Query
    private var events: [PlannerEvent]

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @State private var showNetWorthSnapshot = false
    @State private var showAvailableSnapshot = false

    private var greeting: String {

        let hour = Calendar.current.component(
            .hour,
            from: Date()
        )

        switch hour {

        case 5..<12:
            return "Good Morning"

        case 12..<17:
            return "Good Afternoon"

        default:
            return "Good Evening"
        }
    }

    private var nextExpense: ForecastEvent? {
        dashboardForecastCalculator
        .nextExpense
    }

    private var dashboardForecastCalculator: PlannerForecastCalculator {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: summary.totalAvailable,
            totalGoalAllocated: summary.totalGoalAllocated,
            reserveBalance: summary.reserveBalance,
            protectedEventAllocations: activeProtectedEventAllocations,
            includeFutureIncome: true,
            protectGoals: true,
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
    }

    private var baseDashboardForecastEvents: [ForecastEvent] {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: summary.totalAvailable,
            totalGoalAllocated: summary.totalGoalAllocated,
            reserveBalance: summary.reserveBalance,
            includeFutureIncome: true,
            protectGoals: true,
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
        .forecastEvents
    }

    private var inactiveOccurrenceIDs: Set<String> {
        ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: occurrenceStatuses
        )
    }

    private var activeProtectedEventAllocations: Double {
        EventAllocationTotals.activeTotal(
            allocations: allocations,
            forecastEvents: baseDashboardForecastEvents
        )
    }

    private var dashboardProtectedMoney: Double {
        summary.totalGoalAllocated + summary.reserveBalance + activeProtectedEventAllocations
    }

    private var dashboardAvailableToSpend: Double {
        summary.totalAvailable - activeProtectedEventAllocations
    }

    private var nextExpenseValueText: String {
        guard let nextExpense else {
            return "None"
        }

        return AppFormatters.currency(
            nextExpense.event.amount
        )
    }

    private var nextExpenseIsCovered: Bool {
        guard let nextExpense else {
            return false
        }

        return allocatedAmount(for: nextExpense) + 0.005 >= nextExpense.event.amount
    }

    private var nextExpenseAccentColor: Color {
        guard nextExpense != nil else {
            return AppColors.secondaryText
        }

        return nextExpenseIsCovered
            ? AppColors.spendable
            : AppColors.obligation
    }

    private func allocatedAmount(
        for forecast: ForecastEvent
    ) -> Double {
        allocations.first {
            $0.occurrenceID == forecast.occurrenceID
        }?
        .allocatedAmount ?? 0
    }

    private var nextExpenseSubtitle: String {
        guard let nextExpense else {
            return "No upcoming expenses"
        }

        let dateText = AppFormatters.abbreviatedMonthDay(
            nextExpense.occurrenceDate
        )

        return "\(nextExpense.event.name) · \(dateText)"
    }

    private var showsFirstRunEmptyState: Bool {
        plaid.accounts.isEmpty &&
        plaid.savingsGoals.isEmpty &&
        plaid.reserveBalance == 0 &&
        events.isEmpty &&
        plaid.transactions.isEmpty
    }

    var body: some View {

        ZStack {
            AnimatedBackgroundView()
                .ignoresSafeArea()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.screen
                ) {
                    DashboardHeaderView(
                        greeting: greeting,
                        onSettings: showSettings
                    )

                    divider

                    if showsFirstRunEmptyState {
                        EmptyStateView(
                            systemImage: "wallet.pass.fill",
                            title: "Your financial snapshot starts here",
                            description: "Connect accounts or add your first goal to see what is spendable, protected, and upcoming.",
                            primaryActionTitle: "Connect Account",
                            primaryAction: showAccounts,
                            secondaryActionTitle: "Create Savings Goal",
                            secondaryAction: showSavings,
                            color: AppColors.spendable
                        )
                    } else {
                        Button {
                            showNetWorthSnapshot = true
                        } label: {
                            DashboardHeroCard(
                                netWorth: summary.totalNetWorth
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        DashboardMetricGrid(
                            totalCash: summary.totalCash,
                            totalDebt: summary.totalDebt,
                            totalSavings: dashboardProtectedMoney,
                            reserveBalance: summary.reserveBalance,
                            totalAvailable: dashboardAvailableToSpend,
                            nextExpenseValueText: nextExpenseValueText,
                            nextExpenseSubtitle: nextExpenseSubtitle,
                            hasNextExpense: nextExpense != nil,
                            nextExpenseAccentColor: nextExpenseAccentColor,
                            onCash: showCashAccounts,
                            onDebt: showDebtAccounts,
                            onSavings: showSavings,
                            onReserve: showSavings,
                            onAvailable: showAvailableDetails,
                            onNextExpense: showPlanner
                        )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(.horizontal, 20)
                .padding(.top, AppSpacing.screen)
                .padding(.bottom, 120)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNetWorthSnapshot) {
            NetWorthSnapshotView()
                .environmentObject(plaid)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAvailableSnapshot) {
            FinancialSnapshotView()
                .environmentObject(plaid)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        AppColors.accentSecondary.opacity(0.18),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    private func showCashAccounts() {
        navigation.selectedTab = 3
        navigation.expandChecking = true
        navigation.expandSavings = true
    }

    private func showDebtAccounts() {
        navigation.selectedTab = 3
        navigation.expandCredit = true
        navigation.expandLoans = true
    }

    private func showAccounts() {
        navigation.selectedTab = 3
    }

    private func showSavings() {
        navigation.selectedTab = 1
    }

    private func showAvailableDetails() {
        showAvailableSnapshot = true
    }

    private func showPlanner() {
        navigation.selectedTab = 2
    }

    private func showSettings() {
        navigation.selectedTab = 4
    }
}
