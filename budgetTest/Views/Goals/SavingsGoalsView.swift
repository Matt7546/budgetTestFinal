import SwiftUI
import SwiftData

struct SavingsGoalsView: View {

    @EnvironmentObject var plaid: PlaidService

    @Query
    private var events: [PlannerEvent]

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    enum ActiveSheet: Identifiable {
        case addMoney(SavingsGoal)
        case editGoal(goal: SavingsGoal, isNew: Bool)

        var id: String {
            switch self {
            case .addMoney(let goal):
                return "add-\(goal.id)"

            case .editGoal(let goal, _):
                return "edit-\(goal.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var reserveAmountText = ""

    private var totalSaved: Double {
        plaid.savingsGoals.totalSaved
    }

    private var totalTarget: Double {
        plaid.savingsGoals.totalTarget
    }

    private var overallProgress: Double {
        guard totalTarget > 0 else { return 0 }
        return totalSaved / totalTarget
    }

    private var reserveAmount: Double? {
        Double(reserveAmountText)
    }

    private var canAdjustReserve: Bool {
        guard let reserveAmount else {
            return false
        }

        return reserveAmount > 0
    }

    private var hasSavingsGoals: Bool {
        !plaid.savingsGoals.isEmpty
    }

    private var shouldShowSavingsOverview: Bool {
        hasSavingsGoals ||
        totalSaved > 0 ||
        totalTarget > 0
    }

    private var forecastEvents: [ForecastEvent] {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: 0,
            totalGoalAllocated: 0,
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

    private var upcomingExpenseAllocations: [UpcomingExpenseAllocation] {
        forecastEvents
            .filter {
                $0.event.type == .expense
            }
            .compactMap { forecast in
                guard let allocation = allocations.first(
                    where: {
                        $0.occurrenceID == forecast.occurrenceID
                    }
                ),
                      allocation.allocatedAmount > 0
                else {
                    return nil
                }

                return UpcomingExpenseAllocation(
                    forecast: forecast,
                    allocatedAmount: min(
                        allocation.allocatedAmount,
                        forecast.event.amount
                    )
                )
            }
    }

    var body: some View {

        AppScreen {
            header

            if !upcomingExpenseAllocations.isEmpty {
                UpcomingExpensesSection(
                    expenses: upcomingExpenseAllocations
                )
            }

            ReserveBalanceCard(
                balance: plaid.reserveBalance,
                amountText: $reserveAmountText,
                canAdjust: canAdjustReserve,
                onAdd: addToReserve,
                onSubtract: subtractFromReserve
            )

            if hasSavingsGoals {
                PrimaryButton(
                    "Create Savings Goal",
                    systemImage: "plus.circle.fill",
                    trailingSystemImage: nil,
                    fillsWidth: true,
                    action: createSavingsGoal
                )
            }

            if shouldShowSavingsOverview {
                SavingsOverviewCard(
                    totalSaved: totalSaved,
                    totalTarget: totalTarget,
                    overallProgress: overallProgress,
                    goalCount: plaid.savingsGoals.count
                )
            }

            SavingsGoalListSection(
                goals: plaid.savingsGoals,
                onCreate: createSavingsGoal,
                onAdd: showAddMoney,
                onEdit: showEditGoal
            )
        }
        .sheet(item: $activeSheet) { sheet in

            switch sheet {

            case .addMoney(let goal):

                AddMoneyView(
                    goal: goal
                )
                .environmentObject(plaid)

            case .editGoal(
                let goal,
                let isNew
            ):

                EditGoalView(
                    goal: goal,
                    isNew: isNew
                )
                .environmentObject(plaid)
            }
        }
    }

    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {

            Text("Protection")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            Text("Savings")
                .font(
                    .system(
                        size: 38,
                        weight: .bold
                    )
                )
                .foregroundColor(AppColors.primaryText)
        }
    }

    private func createSavingsGoal() {
        let draft = SavingsGoal(
            name: "",
            targetAmount: 0,
            currentAmount: 0
        )

        activeSheet = .editGoal(
            goal: draft,
            isNew: true
        )
    }

    private func showAddMoney(
        for goal: SavingsGoal
    ) {
        activeSheet = .addMoney(goal)
    }

    private func showEditGoal(
        for goal: SavingsGoal
    ) {
        activeSheet = .editGoal(
            goal: goal,
            isNew: false
        )
    }

    private func addToReserve() {
        guard let reserveAmount else {
            return
        }

        plaid.addToReserve(reserveAmount)
        reserveAmountText = ""
    }

    private func subtractFromReserve() {
        guard let reserveAmount else {
            return
        }

        plaid.subtractFromReserve(reserveAmount)
        reserveAmountText = ""
    }
}
