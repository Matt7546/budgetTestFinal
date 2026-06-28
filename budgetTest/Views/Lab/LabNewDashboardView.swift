import SwiftUI
import SwiftData

struct NewDashboardView: View {

    let showsNavigationTitle: Bool

    init(
        showsNavigationTitle: Bool = false
    ) {
        self.showsNavigationTitle = showsNavigationTitle
    }

    @EnvironmentObject private var plaid: PlaidService
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.colorScheme) private var colorScheme

    @Query
    private var events: [PlannerEvent]

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @Query
    private var debtPayoffBuckets: [DebtPayoffBucket]

    @State private var selectedGoal: SavingsGoal?
    @State private var selectedExpense: ForecastEvent?

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            ScrollView {
                VStack(spacing: AppSpacing.large) {
                    heroSection

                    HStack(spacing: AppSpacing.medium) {
                        protectedMetricCard

                        upcomingExpenseMetricCard
                    }

                    goalsCard

                    upcomingExpensesCard
                }
                .padding(.horizontal, AppSpacing.screen)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.emptyState)
            }
        }
        .navigationTitle(showsNavigationTitle ? "New Dashboard" : "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedGoal) { goal in
            EditGoalView(goal: goal)
                .environmentObject(plaid)
        }
        .sheet(item: $selectedExpense) { forecast in
            EventAllocationDetailView(forecast: forecast) {
                selectedExpense = nil
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(
            .hour,
            from: Date()
        )

        switch hour {
        case 5..<12:
            return "Good morning,"

        case 12..<17:
            return "Good afternoon,"

        default:
            return "Good evening,"
        }
    }

    private var baseFinancialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: plaid.accounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance
        )
    }

    private var dashboardFinancialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: plaid.accounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance,
            upcomingExpensesSetAside: activeProtectedEventAllocations,
            debtPaymentsSetAside: totalDebtPayoffSetAside
        )
    }

    private var totalDebtPayoffSetAside: Double {
        debtPayoffBuckets.totalProtectedAmount
    }

    private var safeToSpendBeforeUpcomingAfterDebtPayoff: Double {
        baseFinancialSummary.safeToSpendBeforeUpcomingExpenses - totalDebtPayoffSetAside
    }

    private var inactiveOccurrenceIDs: Set<String> {
        ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: occurrenceStatuses
        )
    }

    private var baseForecastEvents: [ForecastEvent] {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: safeToSpendBeforeUpcomingAfterDebtPayoff,
            totalGoalAllocated: baseFinancialSummary.savingsGoalsSetAside,
            reserveBalance: baseFinancialSummary.reserve,
            includeFutureIncome: true,
            protectGoals: true,
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
        .forecastEvents
    }

    private var activeProtectedEventAllocations: Double {
        FinancialSummaryCalculator.activeUpcomingExpensesSetAside(
            allocations: allocations,
            forecastEvents: baseForecastEvents
        )
    }

    private var forecastCalculator: PlannerForecastCalculator {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: safeToSpendBeforeUpcomingAfterDebtPayoff,
            totalGoalAllocated: baseFinancialSummary.savingsGoalsSetAside,
            reserveBalance: baseFinancialSummary.reserve,
            protectedEventAllocations: activeProtectedEventAllocations,
            includeFutureIncome: true,
            protectGoals: true,
            allocatedAmountProvider: { forecast in
                allocatedAmount(for: forecast)
            },
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
    }

    private var nextExpense: ForecastEvent? {
        forecastCalculator.nextExpense
    }

    private var upcomingExpenseForecasts: [ForecastEvent] {
        let startOfToday = Calendar.current.startOfDay(for: Date())

        return forecastCalculator.forecastEvents
            .filter {
                $0.event.type == .expense
            }
            .filter {
                Calendar.current.startOfDay(for: $0.occurrenceDate) >= startOfToday
            }
    }

    private var visibleUpcomingExpenseForecasts: [ForecastEvent] {
        Array(
            upcomingExpenseForecasts.prefix(2)
        )
    }

    private var visibleGoals: [SavingsGoal] {
        let activeGoals = plaid.savingsGoals.filter {
            $0.currentAmount + 0.005 < $0.targetAmount
        }
        let source = activeGoals.isEmpty ? plaid.savingsGoals : activeGoals

        return Array(
            source
                .sorted(by: goalSort)
                .prefix(2)
        )
    }

    private var protectedTarget: Double {
        let goalTargets = plaid.savingsGoals.reduce(0) {
            $0 + max($1.targetAmount, 0)
        }
        let expenseTargets = upcomingExpenseForecasts.reduce(0) {
            $0 + max($1.event.amount, 0)
        }
        let debtTarget = debtPayoffBuckets.reduce(0) {
            $0 + max($1.paymentTargetAmount, $1.protectedAmount)
        }

        return plaid.reserveBalance + goalTargets + expenseTargets + debtTarget
    }

    private var protectedProgress: Double {
        guard protectedTarget > 0 else {
            return 0
        }

        let value = dashboardFinancialSummary.protectedMoney / protectedTarget
        guard value.isFinite else {
            return 0
        }

        return min(
            max(value, 0),
            1
        )
    }

    private var availableToSpendCaption: String {
        dashboardFinancialSummary.safeToSpend >= 0
            ? "After protected money and upcoming expenses."
            : "Upcoming obligations exceed available cash."
    }

    private var protectedMetricCaption: String {
        totalDebtPayoffSetAside > 0
            ? "Reserve, goals, expenses, and debt payoff"
            : "Reserve, goals, and expenses"
    }

    private var availableToSpendColor: Color {
        dashboardFinancialSummary.safeToSpend >= 0
            ? CalderaVisualStyle.primaryText(colorScheme)
            : AppColors.negative
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(greeting)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

                Text("Matthew")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
            }

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Available to spend")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

                Text(AppFormatters.currency(dashboardFinancialSummary.safeToSpend))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(availableToSpendColor)
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)

                Text(availableToSpendCaption)
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppSpacing.xxSmall)
        .padding(.bottom, AppSpacing.small)
        .frame(minHeight: 186)
    }

    private var protectedMetricCard: some View {
        Button {
            navigation.selectedTab = 1
        } label: {
            DashboardMetricCard {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                metricHeader(
                    title: "Protected",
                    systemImage: "lock.shield.fill",
                    colors: [
                        Color(red: 0.56, green: 0.33, blue: 1.0),
                        Color(red: 0.95, green: 0.31, blue: 0.72)
                    ]
                )

                Text(AppFormatters.currency(dashboardFinancialSummary.protectedMoney))
                    .font(.title3.bold())
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .monospacedDigit()

                Text(protectedMetricCaption)
                    .font(.caption)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

                CalderaProgressBar(progress: protectedProgress, colors: CalderaVisualStyle.dashboardProgressGradient)

                Text("\(Int(protectedProgress * 100))% of target")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(red: 0.56, green: 0.33, blue: 1.0))
            }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Savings protected money")
    }

    private var upcomingExpenseMetricCard: some View {
        Button {
            navigation.selectedTab = 2
        } label: {
            DashboardMetricCard {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                metricHeader(
                    title: "Upcoming expense",
                    systemImage: "calendar.badge.clock",
                    colors: [
                        Color(red: 0.20, green: 0.58, blue: 1.0),
                        Color(red: 0.55, green: 0.31, blue: 1.0)
                    ]
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(nextExpense?.event.name ?? "No upcoming expense")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                    Text(nextExpense.map { AppFormatters.currency($0.event.amount) } ?? "You're clear")
                        .font(.title3.bold())
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .monospacedDigit()

                    Text(nextExpense.map { upcomingExpenseStatusText(for: $0) } ?? "No upcoming expenses due")
                        .font(.caption)
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                }

                Text("View all upcoming")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color(red: 0.23, green: 0.48, blue: 1.0))
            }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Timeline upcoming expenses")
    }

    private var goalsCard: some View {
        DashboardSectionCard(
            title: "Goals",
            seeAllAction: {
                navigation.selectedTab = 1
            },
            emptyTitle: "No goals yet",
            emptySubtitle: "Create a goal to protect money for something specific.",
            emptySystemImage: "target",
            rows: visibleGoals.map(goalRow)
        )
    }

    private var upcomingExpensesCard: some View {
        DashboardSectionCard(
            title: "Upcoming expenses",
            seeAllAction: {
                navigation.selectedTab = 2
            },
            emptyTitle: "No upcoming expenses",
            emptySubtitle: "Add bills in Timeline to see what needs to be covered next.",
            emptySystemImage: "calendar.badge.exclamationmark",
            rows: visibleUpcomingExpenseForecasts.map(upcomingExpenseRow)
        )
    }

    private func goalSort(
        lhs: SavingsGoal,
        rhs: SavingsGoal
    ) -> Bool {
        switch (lhs.saveByDate, rhs.saveByDate) {
        case (.some(let lhsDate), .some(let rhsDate)):
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }

        case (.some, .none):
            return true

        case (.none, .some):
            return false

        case (.none, .none):
            break
        }

        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func goalRow(
        _ goal: SavingsGoal
    ) -> DashboardRow {
        DashboardRow(
            id: goal.id.uuidString,
            title: goal.name.isEmpty ? "Untitled Savings Goal" : goal.name,
            subtitle: goalSubtitle(for: goal),
            amount: "\(AppFormatters.currency(goal.currentAmount)) of \(AppFormatters.currency(goal.targetAmount))",
            trailing: "\(Int(goal.progress * 100))%",
            systemImage: "target",
            progress: goal.progress,
            action: {
                selectedGoal = goal
            }
        )
    }

    private func goalSubtitle(
        for goal: SavingsGoal
    ) -> String {
        guard let saveByDate = goal.saveByDate else {
            return "Target: \(AppFormatters.currency(goal.targetAmount))"
        }

        return AppFormatters.abbreviatedMonthDayYear(saveByDate)
    }

    private func upcomingExpenseRow(
        _ forecast: ForecastEvent
    ) -> DashboardRow {
        let allocatedAmount = allocatedAmount(for: forecast)
        let remainingAmount = max(
            forecast.event.amount - allocatedAmount,
            0
        )
        let trailing = remainingAmount <= 0.005
            ? "Covered"
            : "Needs \(AppFormatters.currency(remainingAmount))"

        return DashboardRow(
            id: forecast.id,
            title: forecast.event.name,
            subtitle: dueTimingText(for: forecast.occurrenceDate),
            amount: AppFormatters.currency(forecast.event.amount),
            trailing: trailing,
            systemImage: "calendar.badge.exclamationmark",
            progress: progress(
                allocated: allocatedAmount,
                amount: forecast.event.amount
            ),
            action: {
                selectedExpense = forecast
            }
        )
    }

    private func upcomingExpenseStatusText(
        for forecast: ForecastEvent
    ) -> String {
        let allocatedAmount = allocatedAmount(for: forecast)
        let remainingAmount = max(
            forecast.event.amount - allocatedAmount,
            0
        )
        let status = remainingAmount <= 0.005
            ? "Covered"
            : "Needs \(AppFormatters.currency(remainingAmount))"

        return "\(dueTimingText(for: forecast.occurrenceDate)) · \(status)"
    }

    private func allocatedAmount(
        for forecast: ForecastEvent
    ) -> Double {
        allocations.first {
            $0.occurrenceID == forecast.occurrenceID
        }?
        .allocatedAmount ?? 0
    }

    private func progress(
        allocated: Double,
        amount: Double
    ) -> Double {
        guard amount > 0 else {
            return 0
        }

        let value = allocated / amount
        guard value.isFinite else {
            return 0
        }

        return min(
            max(value, 0),
            1
        )
    }

    private func dueTimingText(
        for date: Date
    ) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents(
            [.day],
            from: today,
            to: dueDate
        )
        .day ?? 0

        switch days {
        case ..<0:
            return "Due \(AppFormatters.abbreviatedMonthDay(date))"

        case 0:
            return "Due today"

        case 1:
            return "Due tomorrow"

        case 2...30:
            return "Due in \(days) days"

        default:
            return "Due \(AppFormatters.abbreviatedMonthDay(date))"
        }
    }

    private func metricHeader(
        title: String,
        systemImage: String,
        colors: [Color]
    ) -> some View {
        HStack(spacing: AppSpacing.small) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: colors,
                size: 30,
                iconSize: 12
            )

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(CalderaVisualStyle.tertiaryText(colorScheme))
                .lineLimit(2)
        }
    }
}

#if DEBUG

struct LabNewDashboardView: View {

    var body: some View {
        NewDashboardView(
            showsNavigationTitle: true
        )
    }
}

#endif

private struct DashboardMetricCard<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .padding(AppSpacing.regular)
            .calderaGlassCard(
                cornerRadius: 24,
                fillOpacity: 0.88,
                strokeOpacity: 0.76,
                shadowOpacity: 0.045,
                shadowRadius: 18,
                shadowY: 8
            )
    }
}

private struct DashboardSectionCard: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let seeAllAction: () -> Void
    let emptyTitle: String
    let emptySubtitle: String
    let emptySystemImage: String
    let rows: [DashboardRow]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Spacer()

                Button(action: seeAllAction) {
                    Text("See all")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color(red: 0.23, green: 0.48, blue: 1.0))
                }
                .buttonStyle(.plain)
            }

            if rows.isEmpty {
                DashboardEmptyRow(
                    title: emptyTitle,
                    subtitle: emptySubtitle,
                    systemImage: emptySystemImage
                )
            } else {
                VStack(spacing: AppSpacing.medium) {
                    ForEach(rows) { row in
                        DashboardGoalRow(row: row)
                    }
                }
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: 28,
            fillOpacity: 0.86,
            strokeOpacity: 0.74,
            shadowOpacity: 0.042,
            shadowRadius: 18,
            shadowY: 9
        )
    }
}

private struct DashboardGoalRow: View {

    @Environment(\.colorScheme) private var colorScheme

    let row: DashboardRow

    var body: some View {
        Button {
            row.action?()
        } label: {
            VStack(spacing: AppSpacing.small) {
                HStack(spacing: AppSpacing.medium) {
                    CalderaGradientIcon(
                        systemImage: row.systemImage,
                        colors: CalderaVisualStyle.dashboardProgressGradient,
                        size: 38,
                        iconSize: 14
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                            .lineLimit(1)

                        Text(row.subtitle)
                            .font(.caption)
                            .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xxSmall) {
                        Text(row.amount)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(row.trailing)
                            .font(.caption2.weight(.bold))
                            .foregroundColor(Color(red: 0.55, green: 0.31, blue: 1.0))
                            .lineLimit(1)
                    }
                }

                CalderaProgressBar(progress: row.progress, colors: CalderaVisualStyle.dashboardProgressGradient)
            }
        }
        .buttonStyle(.plain)
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: 20,
            fillOpacity: 0.84,
            strokeOpacity: 0.66,
            shadowOpacity: 0.025,
            shadowRadius: 12,
            shadowY: 5
        )
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardEmptyRow: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: CalderaVisualStyle.dashboardProgressGradient,
                size: 38,
                iconSize: 14
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: 20,
            fillOpacity: 0.84,
            strokeOpacity: 0.66,
            shadowOpacity: 0.025,
            shadowRadius: 12,
            shadowY: 5
        )
    }
}

private struct DashboardRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let amount: String
    let trailing: String
    let systemImage: String
    let progress: Double
    let action: (() -> Void)?
}
