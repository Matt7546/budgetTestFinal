import SwiftUI
import SwiftData

private struct SavingsOverviewSnapshot {
    let debtAccounts: [PlaidAccount]
    let debtAccountByID: [String: PlaidAccount]
    let totalSaved: Double
    let totalUpcomingExpenseAllocated: Double
    let totalDebtPayoffSetAside: Double
    let hasSavingsGoals: Bool
    let visibleSavingsGoals: [SavingsGoal]
    let hasUpcomingExpenses: Bool
    let visibleUpcomingExpenseRows: [SavingsUpcomingExpenseRow]
    let hasDebtPayoffBuckets: Bool
    let allDebtPayoffBuckets: [DebtPayoffBucket]
    let visibleDebtPayoffBuckets: [DebtPayoffBucket]
}

private struct SavingsUpcomingExpenseRow: Identifiable {
    let forecast: ForecastEvent
    let allocatedAmount: Double
    let remainingAmount: Double
    let progress: Double

    var id: String {
        forecast.id
    }
}

private func debtPayoffCategoryStyle(
    for bucket: DebtPayoffBucket,
    account: PlaidAccount?
) -> CalderaCategoryStyle {
    let baseStyle = CalderaCategoryStyle.style(for: .debtPayoff)

    if bucket.debtKind == .mortgage ||
        bucket.debtKind == .studentLoan ||
        bucket.debtKind == .autoLoan ||
        account?.isLoanGroupAccount == true {
        return CalderaCategoryStyle(
            role: .debtPayoff,
            icon: "banknote.fill",
            primary: baseStyle.primary,
            gradient: baseStyle.gradient
        )
    }

    guard bucket.debtKind == .linkedCreditCard else {
        return baseStyle
    }

    return CalderaCategoryStyle(
        role: .debtPayoff,
        icon: "creditcard.fill",
        primary: baseStyle.primary,
        gradient: baseStyle.gradient
    )
}

private func clampedProgressValue(
    _ value: Double
) -> Double {
    guard value.isFinite else {
        return 0
    }

    return min(
        max(value, 0),
        1
    )
}

private struct DebtPayoffCompactCard: View {

    let display: DebtPayoffDisplayModel
    let style: CalderaCategoryStyle
    let balanceLastUpdatedText: String?
    let action: () -> Void

    private var plaidSyncLine: String? {
        guard display.isLinkedCreditCard else {
            return nil
        }

        guard display.fundingState != .balanceUnavailable else {
            return "Balance unavailable · Try refreshing bank data in More"
        }

        guard let balanceLastUpdatedText,
              balanceLastUpdatedText != "Not refreshed yet" else {
            return "Balance not refreshed yet"
        }

        return "Balance synced with Plaid · \(balanceLastUpdatedText)"
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xSmall
        ) {
            HStack(
                alignment: .top,
                spacing: AppSpacing.medium
            ) {
                CalderaGradientIcon(
                    style: style,
                    size: 32,
                    iconSize: 13
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(display.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Text(display.typeLabel)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.small)

                VStack(
                    alignment: .trailing,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(display.setAsideValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(style.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("set aside")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(display.dueDateValue)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)

                if let plaidSyncLine {
                    Text(plaidSyncLine)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(
                            display.fundingState == .balanceUnavailable
                                ? CalderaCategoryStyle.style(for: .needsMoney).primary
                                : AppColors.secondaryText.opacity(0.86)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                } else if let balanceLine = display.balanceLine {
                    Text(balanceLine)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.86))
                        .lineLimit(1)
                }
            }

            VStack(spacing: AppSpacing.xxSmall) {
                CalderaProgressBar(
                    progress: clampedProgressValue(display.progressValue),
                    colors: style.gradient
                )
                .accessibilityLabel(display.progressAccessibilityLabel)

                HStack(spacing: AppSpacing.small) {
                    Text(display.progressCaption)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: AppSpacing.small)

                    Text(display.progressTargetValue)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(style.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.80,
            strokeOpacity: 0.60,
            shadowOpacity: 0.012,
            shadowRadius: 8,
            shadowY: 3
        )
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(display.title), \(display.typeLabel), \(display.progressAccessibilityLabel)"
        )
    }
}

struct SavingsGoalsView: View {

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var plaid: PlaidService
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.modelContext)
    private var modelContext

    @Query
    private var events: [PlannerEvent]

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @Query
    private var debtPayoffBuckets: [DebtPayoffBucket]

    private enum ActiveGoalSheet: Identifiable {
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

    private enum ActiveDebtPayoffSheet: Identifiable {
        case create
        case edit(DebtPayoffBucket)

        var id: String {
            switch self {
            case .create:
                return "create"

            case .edit(let bucket):
                return bucket.id.uuidString
            }
        }
    }

    @State private var activeGoalSheet: ActiveGoalSheet?
    @State private var activeDebtPayoffSheet: ActiveDebtPayoffSheet?
    @State private var reserveAmountText = ""
    @State private var selectedAllocationForecast: ForecastEvent?
    @State private var selectedEvent: PlannerEvent?
    @State private var isAddingUpcomingExpense = false

    private var canShowBankData: Bool {
        !AppConfig.requiresAuthenticatedBankData || auth.isSignedIn
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

    private var overviewSnapshot: SavingsOverviewSnapshot {
        let visibleBankAccounts = canShowBankData
            ? plaid.accounts.deduplicatedForDisplayAndTotals
            : []
        let debtAccounts = visibleBankAccounts.debtAccounts
        let debtAccountByID = Dictionary(
            uniqueKeysWithValues: debtAccounts.map {
                ($0.account_id, $0)
            }
        )
        let baseFinancialSummary = FinancialSummaryCalculator.calculate(
            accounts: visibleBankAccounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance
        )
        let totalSaved = baseFinancialSummary.savingsGoalsSetAside
        let forecastEvents = makeForecastEvents()
        let expenseForecasts = forecastEvents.filter {
            $0.event.type == .expense
        }
        let allocationByOccurrenceID = allocationLookup()
        let totalUpcomingExpenseAllocated = expenseForecasts.reduce(0.0) { total, forecast in
            guard let allocation = allocationByOccurrenceID[forecast.occurrenceID] else {
                return total
            }

            return total + min(
                max(allocation.allocatedAmount, 0),
                forecast.event.amount
            )
        }
        let totalDebtPayoffSetAside = debtPayoffBuckets.totalProtectedAmount
        let pinnedGoals = plaid.savingsGoals.filter(\.isPinned)
        let visibleSavingsGoals = pinnedGoals.isEmpty
            ? Array(plaid.savingsGoals.prefix(3))
            : Array(pinnedGoals.prefix(3))
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let upcomingExpenseRows = expenseForecasts
            .filter {
                Calendar.current.startOfDay(for: $0.occurrenceDate) >= startOfToday
            }
            .prefix(3)
            .map { forecast in
                let allocatedAmount = allocationByOccurrenceID[forecast.occurrenceID]
                    .map {
                        min(
                            max($0.allocatedAmount, 0),
                            forecast.event.amount
                        )
                    } ?? 0
                let remainingAmount = max(
                    forecast.event.amount - allocatedAmount,
                    0
                )

                return SavingsUpcomingExpenseRow(
                    forecast: forecast,
                    allocatedAmount: allocatedAmount,
                    remainingAmount: remainingAmount,
                    progress: progress(
                        allocated: allocatedAmount,
                        amount: forecast.event.amount
                    )
                )
            }
        let sortedDebtPayoffBuckets = debtPayoffBuckets.sorted {
            $0.dueDate < $1.dueDate
        }

        return SavingsOverviewSnapshot(
            debtAccounts: debtAccounts,
            debtAccountByID: debtAccountByID,
            totalSaved: totalSaved,
            totalUpcomingExpenseAllocated: totalUpcomingExpenseAllocated,
            totalDebtPayoffSetAside: totalDebtPayoffSetAside,
            hasSavingsGoals: !plaid.savingsGoals.isEmpty,
            visibleSavingsGoals: visibleSavingsGoals,
            hasUpcomingExpenses: !expenseForecasts.isEmpty,
            visibleUpcomingExpenseRows: Array(upcomingExpenseRows),
            hasDebtPayoffBuckets: !debtPayoffBuckets.isEmpty,
            allDebtPayoffBuckets: sortedDebtPayoffBuckets,
            visibleDebtPayoffBuckets: Array(sortedDebtPayoffBuckets.prefix(3))
        )
    }

    private func makeForecastEvents() -> [ForecastEvent] {
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

    private func allocationLookup() -> [String: EventAllocation] {
        allocations.reduce(into: [:]) { result, allocation in
            if result[allocation.occurrenceID] == nil {
                result[allocation.occurrenceID] = allocation
            }
        }
    }

    var body: some View {
        let snapshot = overviewSnapshot

        NavigationStack {
            ZStack {
                CalderaPageBackground(
                    mood: .savings,
                    isActive: navigation.selectedTab == 1
                )

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.screen
                    ) {
                        header

                        compactSummaryMetrics(snapshot)

                        reserveCard

                        savingsGoalsSection(snapshot)

                        upcomingExpensesSection(snapshot)

                        debtPayoffSection(snapshot)
                    }
                    .padding(.all)
                    .padding(.bottom, AppSpacing.emptyState)
                }
            }
            .optionalTopScrollFade(isEnabled: true)
            .navigationTitle("Savings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $activeGoalSheet) { sheet in
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
        .sheet(item: $selectedAllocationForecast) { forecast in
            EventAllocationDetailView(
                forecast: forecast
            ) {
                selectedAllocationForecast = nil
                selectedEvent = forecast.event
            }
        }
        .sheet(item: $selectedEvent) { event in
            AddPlannerEventView(
                editingEvent: event
            )
        }
        .sheet(isPresented: $isAddingUpcomingExpense) {
            AddPlannerEventView(
                editingEvent: nil
            )
        }
        .sheet(item: $activeDebtPayoffSheet) { sheet in
            switch sheet {
            case .create:
                DebtPayoffBucketEditorView(
                    debtAccounts: snapshot.debtAccounts,
                    balanceLastUpdatedText: plaid.accountsLastUpdatedText,
                    bucket: nil,
                    onSave: saveDebtPayoffBucket
                )

            case .edit(let bucket):
                DebtPayoffBucketEditorView(
                    debtAccounts: snapshot.debtAccounts,
                    balanceLastUpdatedText: plaid.accountsLastUpdatedText,
                    bucket: bucket,
                    onSave: { draft in
                        updateDebtPayoffBucket(
                            bucket,
                            draft: draft
                        )
                    },
                    onDelete: deleteDebtPayoffBucket
                )
            }
        }
        .onAppear {
            consumeSetupNavigationRequests()
        }
        .onChange(of: navigation.shouldCreateSavingsGoal) { _, _ in
            consumeSetupNavigationRequests()
        }
        .onChange(of: navigation.shouldCreateDebtPayoff) { _, _ in
            consumeSetupNavigationRequests()
        }
    }

    private func consumeSetupNavigationRequests() {
        if navigation.shouldCreateSavingsGoal {
            navigation.shouldCreateSavingsGoal = false
            createSavingsGoal()
        }

        if navigation.shouldCreateDebtPayoff {
            navigation.shouldCreateDebtPayoff = false
            activeDebtPayoffSheet = .create
        }
    }

    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            Text("Money set aside")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            HStack(alignment: .center, spacing: AppSpacing.xxSmall) {
                Text("Savings")
                    .font(
                        .system(
                            size: 38,
                            weight: .bold
                        )
                    )
                    .foregroundColor(AppColors.primaryText)

                ContextHelpButton(
                    title: "Set Aside",
                    bodyText: "Savings is where you keep money out of everyday spending. Use Cash Cushion for flexible extra money, Savings Goals for things you’re saving toward, Upcoming Expenses for planned bills, and Debt Payoff for card or loan payments."
                )
            }
        }
    }

    private func compactSummaryMetrics(
        _ snapshot: SavingsOverviewSnapshot
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .flexible(),
                    spacing: AppSpacing.small
                ),
                GridItem(
                    .flexible(),
                    spacing: AppSpacing.small
                )
            ],
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            topSummaryMetricCard(
                title: "Cash Cushion",
                value: plaid.reserveBalance,
                style: CalderaCategoryStyle.style(for: .reserve)
            )

            topSummaryMetricCard(
                title: "Goals",
                value: snapshot.totalSaved,
                style: CalderaCategoryStyle.style(for: .savingsGoal)
            )

            topSummaryMetricCard(
                title: "Upcoming Expenses",
                value: snapshot.totalUpcomingExpenseAllocated,
                style: CalderaCategoryStyle.style(for: .upcomingExpense)
            )

            topSummaryMetricCard(
                title: "Debt Payoff",
                value: snapshot.totalDebtPayoffSetAside,
                style: CalderaCategoryStyle.style(for: .debtPayoff)
            )
        }
    }

    private var reserveCard: some View {
        let reserveStyle = CalderaCategoryStyle.style(for: .reserve)

        return VStack(
            alignment: .leading,
            spacing: AppSpacing.compact
        ) {
            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: reserveStyle,
                    size: 42,
                    iconSize: 18
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Cash Cushion")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)

                    Text("A simple set-aside buffer kept out of Available to Spend.")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(AppFormatters.currency(plaid.reserveBalance))
                    .font(.title2.bold())
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                Text("$")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.secondaryText)

                TextField(
                    "0.00",
                    text: $reserveAmountText
                )
                .keyboardType(.decimalPad)
                .keyboardDismissToolbar()
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(AppColors.primaryText)
            }
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.compact)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.88,
                strokeOpacity: 0.70,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0
            )
            .accessibilityLabel("Cash Cushion dollar amount")

            HStack(spacing: AppSpacing.medium) {
                cashCushionActionButton(
                    title: "Use from\nCushion",
                    systemImage: "minus.circle",
                    isPrimary: false,
                    isDisabled: !canAdjustReserve,
                    action: subtractFromReserve,
                    accessibilityLabel: "Use from Cash Cushion"
                )

                cashCushionActionButton(
                    title: "Add to\nCushion",
                    systemImage: "plus.circle.fill",
                    isPrimary: true,
                    isDisabled: !canAdjustReserve,
                    action: addToReserve,
                    accessibilityLabel: "Add to Cash Cushion"
                )
            }
        }
        .padding(AppSpacing.regular)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.90,
            strokeOpacity: 0.76,
            shadowOpacity: 0.038,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: reserveStyle.primary
        )
        .background {
            RoundedRectangle(cornerRadius: AppRadii.panel, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            reserveStyle.primary.opacity(0.16),
                            AppColors.accentSecondary.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 4)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadii.panel, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            reserveStyle.primary.opacity(0.72),
                            AppColors.accentSecondary.opacity(0.46),
                            reserveStyle.primary.opacity(0.34)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.1
                )
                .shadow(
                    color: reserveStyle.primary.opacity(0.18),
                    radius: 3,
                    x: 0,
                    y: 0
                )
                .shadow(
                    color: AppColors.accentSecondary.opacity(0.12),
                    radius: 4,
                    x: 0,
                    y: 0
                )
                .allowsHitTesting(false)
        }
        .shadow(
            color: reserveStyle.primary.opacity(0.08),
            radius: 6,
            x: 0,
            y: 3
        )
        .shadow(
            color: AppColors.accentSecondary.opacity(0.05),
            radius: 8,
            x: 0,
            y: 4
        )
    }

    private func cashCushionActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, AppSpacing.small)
            .foregroundColor(isPrimary ? .white : AppColors.secondaryText)
            .background {
                if isPrimary {
                    LinearGradient(
                        colors: [
                            AppColors.primaryButtonStart,
                            AppColors.primaryButtonEnd
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
                        .fill(Color.white.opacity(0.74))
                }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
                    .stroke(
                        isPrimary
                            ? Color.white.opacity(0.24)
                            : Color.white.opacity(0.72),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: isPrimary
                    ? AppColors.primaryButtonEnd.opacity(0.20)
                    : Color.black.opacity(0.035),
                radius: isPrimary ? 12 : 10,
                x: 0,
                y: isPrimary ? 7 : 5
            )
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.62 : 1.0)
        .accessibilityLabel(accessibilityLabel)
    }

    private func savingsGoalsSection(
        _ snapshot: SavingsOverviewSnapshot
    ) -> some View {
        redesignSection(
            title: "Savings Goals",
            style: CalderaCategoryStyle.style(for: .savingsGoal),
            trailing: savingsGoalsHeaderActions(snapshot)
        ) {
            VStack(spacing: AppSpacing.small) {
                if !snapshot.hasSavingsGoals {
                    emptyRedesignRow(
                        title: "No savings goals yet",
                        subtitle: "Create a Goal when you know what you're saving for. Goal money stays Set Aside from everyday spending.",
                        style: CalderaCategoryStyle.style(for: .savingsGoal)
                    )
                } else {
                    ForEach(snapshot.visibleSavingsGoals) { goal in
                        savingsGoalRow(goal)
                    }
                }

                sectionQuickAddButton(
                    title: "Add Savings Goal",
                    style: CalderaCategoryStyle.style(for: .savingsGoal),
                    accessibilityLabel: "Add savings goal",
                    action: createSavingsGoal
                )
            }
        }
    }

    private func savingsGoalsHeaderActions(
        _ snapshot: SavingsOverviewSnapshot
    ) -> AnyView {
        AnyView(
            NavigationLink {
                AllSavingsGoalsView()
                    .environmentObject(plaid)
            } label: {
                seeAllLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all savings goals")
        )
    }

    private func upcomingExpensesSection(
        _ snapshot: SavingsOverviewSnapshot
    ) -> some View {
        redesignSection(
            title: "Upcoming Expenses",
            style: CalderaCategoryStyle.style(for: .upcomingExpense),
            trailing: upcomingExpensesHeaderActions(snapshot)
        ) {
            VStack(spacing: AppSpacing.small) {
                if !snapshot.hasUpcomingExpenses {
                    emptyRedesignRow(
                        title: "No upcoming expenses yet",
                        subtitle: "Add rent, subscriptions, or bills so Caldera can show what needs money before it is due.",
                        style: CalderaCategoryStyle.style(for: .upcomingExpense)
                    )
                } else {
                    ForEach(snapshot.visibleUpcomingExpenseRows) { row in
                        upcomingExpenseRow(row)
                    }
                }

                sectionQuickAddButton(
                    title: "Add Upcoming Expense",
                    style: CalderaCategoryStyle.style(for: .upcomingExpense),
                    accessibilityLabel: "Add upcoming expense",
                    action: {
                        isAddingUpcomingExpense = true
                    }
                )
            }
        }
    }

    private func upcomingExpensesHeaderActions(
        _ snapshot: SavingsOverviewSnapshot
    ) -> AnyView {
        AnyView(
            NavigationLink {
                AllTimelineExpensesView()
            } label: {
                seeAllLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all upcoming expenses")
        )
    }

    private func debtPayoffSection(
        _ snapshot: SavingsOverviewSnapshot
    ) -> some View {
        redesignSection(
            title: "Debt Payoff",
            style: CalderaCategoryStyle.style(for: .debtPayoff),
            trailing: debtPayoffHeaderActions(snapshot)
        ) {
            VStack(spacing: AppSpacing.small) {
                if !snapshot.hasDebtPayoffBuckets {
                    emptyRedesignRow(
                        title: "No Debt Payoff items yet",
                        subtitle: "Plan money for cards, loans, or other debts. Debt balances only change when your bank or card issuer reports a real payment.",
                        style: CalderaCategoryStyle.style(for: .debtPayoff)
                    )
                } else {
                    setAsideExplanationRow(
                        text: "Debt Payoff is planning only. It does not make a payment or reduce the real debt balance."
                    )

                    ForEach(snapshot.visibleDebtPayoffBuckets) { bucket in
                        debtPayoffRow(
                            bucket,
                            accountByID: snapshot.debtAccountByID
                        )
                    }
                }

                sectionQuickAddButton(
                    title: "Add Debt Payoff",
                    style: CalderaCategoryStyle.style(for: .debtPayoff),
                    accessibilityLabel: "Add Debt Payoff",
                    action: {
                        activeDebtPayoffSheet = .create
                    }
                )
            }
        }
    }

    private func debtPayoffHeaderActions(
        _ snapshot: SavingsOverviewSnapshot
    ) -> AnyView {
        AnyView(
            NavigationLink {
                AllDebtPayoffBucketsView(
                    buckets: snapshot.allDebtPayoffBuckets,
                    accountByID: snapshot.debtAccountByID,
                    balanceLastUpdatedText: plaid.accountsLastUpdatedText,
                    editAction: { bucket in
                        activeDebtPayoffSheet = .edit(bucket)
                    },
                    addAction: {
                        activeDebtPayoffSheet = .create
                    }
                )
            } label: {
                seeAllLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all debt payoff items")
        )
    }

    private var seeAllLabel: some View {
        Text("See all")
            .font(.caption.weight(.bold))
            .foregroundColor(AppColors.accent)
    }

    private func sectionQuickAddButton(
        title: String,
        style: CalderaCategoryStyle,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))

                Text(title)
                    .font(.caption.weight(.bold))
            }
            .foregroundColor(style.primary)
            .frame(
                maxWidth: .infinity,
                minHeight: 42
            )
            .background(
                Capsule(style: .continuous)
                    .fill(style.primary.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        AppColors.glassSubtleHighlight,
                        lineWidth: 1
                    )
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: AppRadii.button,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func redesignSection<Content: View>(
        title: String,
        style: CalderaCategoryStyle,
        trailing: AnyView = AnyView(EmptyView()),
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    style: style,
                    size: 34,
                    iconSize: 14
                )

                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)

                Spacer()

                trailing
            }

            content()
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.72,
            shadowOpacity: 0.036,
            shadowRadius: 16,
            shadowY: 8
        )
    }

    private func topSummaryMetricCard(
        title: String,
        value: Double,
        style: CalderaCategoryStyle
    ) -> some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.small
        ) {
            CalderaGradientIcon(
                style: style,
                size: 38,
                iconSize: 15
            )
            .layoutPriority(1)

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppFormatters.currency(value))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(style.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AppSpacing.compact)
        .padding(.horizontal, AppSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: 0.88,
            strokeOpacity: 0.72,
            shadowOpacity: 0.036,
            shadowRadius: 14,
            shadowY: 7
        )
        .accessibilityElement(children: .combine)
    }

    private func savingsGoalRow(
        _ goal: SavingsGoal
    ) -> some View {
        compactRedesignRow(
            title: goal.name.isEmpty ? "Untitled Savings Goal" : goal.name,
            subtitle: "\(AppFormatters.currency(goal.currentAmount)) saved of \(AppFormatters.currency(goal.targetAmount))",
            value: "\(Int(goal.progress * 100))%",
            style: CalderaCategoryStyle.style(for: .savingsGoal),
            progress: goal.progress,
            rowAction: {
                showEditGoal(
                    for: goal
                )
            },
            accessorySystemImage: "plus.circle.fill",
            accessoryAccessibilityLabel: "Add money to \(goal.name)",
            accessoryAction: {
                showAddMoney(
                    for: goal
                )
            }
        )
    }

    private func upcomingExpenseRow(
        _ row: SavingsUpcomingExpenseRow
    ) -> some View {
        compactRedesignRow(
            title: row.forecast.event.name,
            subtitle: "\(AppFormatters.abbreviatedMonthDay(row.forecast.occurrenceDate)) · \(AppFormatters.currency(row.allocatedAmount)) set aside",
            value: row.remainingAmount <= 0
                ? "Covered"
                : "Needs \(AppFormatters.currency(row.remainingAmount))",
            style: CalderaCategoryStyle.style(for: .upcomingExpense),
            valueStyle: row.remainingAmount <= 0
                ? CalderaCategoryStyle.style(for: .covered)
                : CalderaCategoryStyle.style(for: .needsMoney),
            progress: row.progress,
            rowAction: {
                selectedAllocationForecast = row.forecast
            }
        )
    }

    private func debtPayoffRow(
        _ bucket: DebtPayoffBucket,
        accountByID: [String: PlaidAccount]
    ) -> some View {
        let account = accountByID[bucket.plaidAccountID]
        let display = DebtPayoffDisplayModel(
            bucket: bucket,
            linkedAccount: account
        )
        let style = debtPayoffCategoryStyle(
            for: bucket,
            account: account
        )

        return DebtPayoffCompactCard(
            display: display,
            style: style,
            balanceLastUpdatedText: bucket.isLinkedCreditCard
                ? plaid.accountsLastUpdatedText
                : nil
        ) {
            activeDebtPayoffSheet = .edit(bucket)
        }
    }

    private func emptyRedesignRow(
        title: String,
        subtitle: String,
        style: CalderaCategoryStyle
    ) -> some View {
        HStack(spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: style,
                size: 34,
                iconSize: 14
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.80,
            strokeOpacity: 0.60,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4
        )
    }

    private func setAsideExplanationRow(
        text: String
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            Image(systemName: "info.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
                .padding(.top, 1)

            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.74,
            strokeOpacity: 0.54,
            shadowOpacity: 0.0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
        )
    }

    private func compactRedesignRow(
        title: String,
        subtitle: String,
        value: String,
        style: CalderaCategoryStyle,
        valueStyle: CalderaCategoryStyle? = nil,
        progress: Double,
        rowAction: (() -> Void)? = nil,
        accessorySystemImage: String? = nil,
        accessoryAccessibilityLabel: String? = nil,
        accessoryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: AppSpacing.xSmall) {
            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: style,
                    size: 32,
                    iconSize: 13
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(
                        (valueStyle ?? style).primary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let accessorySystemImage,
                   let accessoryAction {
                    Button(
                        action: accessoryAction
                    ) {
                            Image(systemName: accessorySystemImage)
                                .font(.body.weight(.semibold))
                                .foregroundColor(style.primary)
                                .frame(
                                width: 32,
                                height: 32
                            )
                            .background(
                                Circle()
                                    .fill(style.primary.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        accessoryAccessibilityLabel ?? title
                    )
                }
            }

            CalderaProgressBar(
                progress: safeProgress(progress),
                colors: style.gradient
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            rowAction?()
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.80,
            strokeOpacity: 0.60,
            shadowOpacity: 0.012,
            shadowRadius: 8,
            shadowY: 3
        )
        .accessibilityElement(children: .combine)
    }

    private func createSavingsGoal() {
        let draft = SavingsGoal(
            name: "",
            targetAmount: 0,
            currentAmount: 0
        )

        activeGoalSheet = .editGoal(
            goal: draft,
            isNew: true
        )
    }

    private func showAddMoney(
        for goal: SavingsGoal
    ) {
        activeGoalSheet = .addMoney(goal)
    }

    private func showEditGoal(
        for goal: SavingsGoal
    ) {
        activeGoalSheet = .editGoal(
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

    private func saveDebtPayoffBucket(
        _ draft: DebtPayoffBucketDraft
    ) {
        modelContext.insert(
            DebtPayoffBucket(
                plaidAccountID: draft.plaidAccountID,
                accountName: draft.accountName,
                institutionName: draft.institutionName,
                dueDate: draft.dueDate,
                paymentTargetAmount: draft.paymentTargetAmount,
                protectedAmount: draft.protectedAmount,
                debtKind: draft.debtKind,
                manualCurrentBalance: draft.manualCurrentBalance,
                monthlyPayment: draft.monthlyPayment,
                originalBalance: draft.originalBalance,
                interestRate: draft.interestRate,
                notes: draft.notes,
                hasPaymentDueDate: draft.hasPaymentDueDate,
                startDate: draft.startDate,
                endDate: draft.endDate
            )
        )

        saveDebtPayoffContext()
    }

    private func updateDebtPayoffBucket(
        _ bucket: DebtPayoffBucket,
        draft: DebtPayoffBucketDraft
    ) {
        bucket.debtKind = draft.debtKind
        bucket.plaidAccountID = draft.plaidAccountID
        bucket.accountName = draft.accountName
        bucket.institutionName = draft.institutionName
        bucket.dueDate = draft.dueDate
        bucket.paymentTargetAmount = draft.paymentTargetAmount
        bucket.protectedAmount = draft.protectedAmount
        bucket.manualCurrentBalance = draft.manualCurrentBalance
        bucket.monthlyPayment = draft.monthlyPayment
        bucket.originalBalance = draft.originalBalance
        bucket.interestRate = draft.interestRate
        bucket.notes = draft.notes
        bucket.hasPaymentDueDate = draft.hasPaymentDueDate
        bucket.startDate = draft.startDate
        bucket.endDate = draft.endDate
        bucket.updatedAt = Date()

        saveDebtPayoffContext()
    }

    private func deleteDebtPayoffBucket(
        _ bucket: DebtPayoffBucket
    ) {
        modelContext.delete(bucket)
        saveDebtPayoffContext()
    }

    private func saveDebtPayoffContext() {
        do {
            try modelContext.save()
        } catch {
            AppLogger.error(
                "Debt payoff persistence error: \(error.localizedDescription)",
                category: .persistence
            )
        }
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

        return safeProgress(value)
    }

    private func safeProgress(
        _ value: Double
    ) -> Double {
        guard value.isFinite else {
            return 0
        }

        return min(
            max(value, 0),
            1
        )
    }
}

private struct AllDebtPayoffBucketsView: View {

    let buckets: [DebtPayoffBucket]
    let accountByID: [String: PlaidAccount]
    let balanceLastUpdatedText: String
    let editAction: (DebtPayoffBucket) -> Void
    let addAction: () -> Void

    private var sortedBuckets: [DebtPayoffBucket] {
        buckets.sorted {
            $0.dueDate < $1.dueDate
        }
    }

    var body: some View {
        AppScreen(
            usesNavigationStack: false
        ) {
            if sortedBuckets.isEmpty {
                emptyState
            } else {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.small
                ) {
                    ForEach(sortedBuckets) { bucket in
                        debtRow(bucket)
                    }
                }
            }
        }
        .navigationTitle("Debt Payoff")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addAction()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(AppColors.accent)
                }
                .accessibilityLabel("Add Debt Payoff")
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                size: 38,
                iconSize: 16
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("No debt payoff items yet")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)

                Text("Plan money for card, loan, or mortgage payments. Debt balances only change when your bank or card issuer reports a real payment.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                addAction()
            } label: {
                Text("Add Debt Payoff")
                    .font(.caption.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.xSmall)
                    .frame(minHeight: 34)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CalderaCategoryStyle.style(for: .debtPayoff).primary.opacity(0.12))
                    )
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Debt Payoff")
        }
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.82,
            strokeOpacity: 0.64,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
        )
    }

    private func debtRow(
        _ bucket: DebtPayoffBucket
    ) -> some View {
        let account = accountByID[bucket.plaidAccountID]
        let display = DebtPayoffDisplayModel(
            bucket: bucket,
            linkedAccount: account
        )
        let style = debtPayoffCategoryStyle(
            for: bucket,
            account: account
        )

        return DebtPayoffCompactCard(
            display: display,
            style: style,
            balanceLastUpdatedText: bucket.isLinkedCreditCard
                ? balanceLastUpdatedText
                : nil
        ) {
            editAction(bucket)
        }
    }
}

struct LegacySavingsGoalsView: View {

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

    private var baseFinancialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: plaid.accounts.deduplicatedForDisplayAndTotals,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance
        )
    }

    private var totalSaved: Double {
        baseFinancialSummary.savingsGoalsSetAside
    }

    private var totalTarget: Double {
        plaid.savingsGoals.totalTarget
    }

    private var overallProgress: Double {
        guard totalTarget > 0 else { return 0 }

        let value = totalSaved / totalTarget
        guard value.isFinite else { return 0 }

        return min(
            max(value, 0),
            1
        )
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
        .keyboardDismissToolbar()
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

            Text("Money set aside")
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
