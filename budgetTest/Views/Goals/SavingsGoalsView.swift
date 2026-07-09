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

struct SavingsUpcomingExpenseRow: Identifiable {
    let forecast: ForecastEvent
    let allocatedAmount: Double
    let remainingAmount: Double
    let progress: Double

    var id: String {
        forecast.id
    }
}

func debtPayoffCategoryStyle(
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

func clampedProgressValue(
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
    @State private var isEditingCashCushion = false
    @State private var selectedAllocationForecast: ForecastEvent?
    @State private var selectedEvent: PlannerEvent?
    @State private var isAddingUpcomingExpense = false
    @State private var confirmationMessage: String?
    @State private var confirmationID = UUID()

    private var canShowBankData: Bool {
        !AppConfig.requiresAuthenticatedBankData || auth.isSignedIn
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
                CalderaPageBackground(mood: .savings)

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.screen
                    ) {
                        header

                        SavingsHeaderMetricsSection(
                            goalsTotal: snapshot.totalSaved,
                            upcomingExpensesTotal: snapshot.totalUpcomingExpenseAllocated,
                            debtPayoffTotal: snapshot.totalDebtPayoffSetAside
                        )

                        SavingsGoalsSection(
                            cashCushionAmount: plaid.reserveBalance,
                            hasSavingsGoals: snapshot.hasSavingsGoals,
                            visibleSavingsGoals: snapshot.visibleSavingsGoals,
                            trailing: savingsGoalsHeaderActions(),
                            cashCushionAction: {
                                isEditingCashCushion = true
                            },
                            createAction: createSavingsGoal,
                            editAction: showEditGoal,
                            addMoneyAction: showAddMoney
                        )

                        SavingsUpcomingExpensesSection(
                            hasUpcomingExpenses: snapshot.hasUpcomingExpenses,
                            visibleRows: snapshot.visibleUpcomingExpenseRows,
                            trailing: upcomingExpensesHeaderActions(),
                            addAction: {
                                isAddingUpcomingExpense = true
                            },
                            selectAction: { forecast in
                                selectedAllocationForecast = forecast
                            }
                        )

                        SavingsDebtPayoffSection(
                            hasDebtPayoffBuckets: snapshot.hasDebtPayoffBuckets,
                            visibleBuckets: snapshot.visibleDebtPayoffBuckets,
                            accountByID: snapshot.debtAccountByID,
                            balanceLastUpdatedText: plaid.accountsLastUpdatedText,
                            trailing: debtPayoffHeaderActions(snapshot),
                            addAction: {
                                activeDebtPayoffSheet = .create
                            },
                            editAction: { bucket in
                                activeDebtPayoffSheet = .edit(bucket)
                            }
                        )
                    }
                    .padding(.all)
                    .padding(.bottom, AppSpacing.floatingTabClearance)
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .calderaTopScrollFade(mood: .savings)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Set Aside")
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calderaConfirmationOverlay(message: confirmationMessage)
        .sheet(isPresented: $isEditingCashCushion) {
            CashCushionEditorView(
                reserveBalance: plaid.reserveBalance,
                addAction: addToReserve,
                useAction: subtractFromReserve
            )
        }
        .sheet(item: $activeGoalSheet) { sheet in
            switch sheet {
            case .addMoney(let goal):
                AddMoneyView(
                    goal: goal,
                    onSaved: { _ in
                        showConfirmation("Goal updated.")
                    }
                )
                .environmentObject(plaid)

            case .editGoal(
                let goal,
                let isNew
            ):
                EditGoalView(
                    goal: goal,
                    isNew: isNew,
                    onSaved: { wasNew in
                        showConfirmation(
                            wasNew
                                ? "Goal added to your plan."
                                : "Goal updated."
                        )
                    },
                    onDeleted: {
                        showConfirmation("Goal deleted.")
                    }
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
                editingEvent: event,
                onSaved: { type, isEditing in
                    showPlannerEventConfirmation(
                        type: type,
                        isEditing: isEditing
                    )
                },
                onScheduleReset: {
                    showConfirmation(
                        "Expense updated. Set-aside tracking was reset for the new schedule."
                    )
                },
                onDeleted: { type in
                    showConfirmation(
                        type == .expense
                            ? "Upcoming Expense deleted."
                            : "Income deleted."
                    )
                }
            )
        }
        .sheet(isPresented: $isAddingUpcomingExpense) {
            AddPlannerEventView(
                editingEvent: nil,
                onSaved: { type, isEditing in
                    showPlannerEventConfirmation(
                        type: type,
                        isEditing: isEditing
                    )
                }
            )
        }
        .sheet(item: $activeDebtPayoffSheet) { sheet in
            switch sheet {
            case .create:
                DebtPayoffBucketEditorView(
                    debtAccounts: snapshot.debtAccounts,
                    existingPaymentPlans: snapshot.allDebtPayoffBuckets,
                    balanceLastUpdatedText: plaid.accountsLastUpdatedText,
                    bucket: nil,
                    onSave: saveDebtPayoffBucket
                )

            case .edit(let bucket):
                DebtPayoffBucketEditorView(
                    debtAccounts: snapshot.debtAccounts,
                    existingPaymentPlans: snapshot.allDebtPayoffBuckets,
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
        .onChange(of: navigation.debtPayoffToEditID) { _, _ in
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

        consumeDebtPayoffEditRequest()
    }

    private func consumeDebtPayoffEditRequest() {
        guard let bucketID = navigation.debtPayoffToEditID else {
            return
        }

        guard let bucket = debtPayoffBuckets.first(where: {
            $0.id == bucketID
        }) else {
            navigation.debtPayoffToEditID = nil
            return
        }

        navigation.debtPayoffToEditID = nil
        activeDebtPayoffSheet = .edit(bucket)
    }

    private var header: some View {
        CalderaPageHeader(
            eyebrow: "Money kept out of Available to Spend",
            title: "Set Aside",
            titleAccessory: {
                ContextHelpButton(
                    title: "Set Aside",
                    bodyText: "Set Aside is money Caldera keeps out of Available to Spend. Use Cash Cushion for flexible extra money, Savings Goals for things you’re saving toward, Upcoming Expenses for planned bills, and Payment Planning for payments you want to plan for."
                )
            }
        )
    }

    private func savingsGoalsHeaderActions() -> AnyView {
        AnyView(
            NavigationLink {
                AllSavingsGoalsView()
                    .environmentObject(plaid)
            } label: {
                SavingsSeeAllLabel()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all savings goals")
        )
    }

    private func upcomingExpensesHeaderActions() -> AnyView {
        AnyView(
            NavigationLink {
                AllTimelineExpensesView()
            } label: {
                SavingsSeeAllLabel()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all upcoming expenses")
        )
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
                SavingsSeeAllLabel()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all payment plans")
        )
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

    private func addToReserve(
        _ amount: Double
    ) {
        plaid.addToReserve(amount)
        showConfirmation("Cash Cushion updated.")
    }

    private func subtractFromReserve(
        _ amount: Double
    ) {
        plaid.subtractFromReserve(amount)
        showConfirmation("Cash Cushion updated.")
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

        if saveDebtPayoffContext() {
            showConfirmation("Payment plan added.")
        }
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

        if saveDebtPayoffContext() {
            showConfirmation("Payment plan updated.")
        }
    }

    private func deleteDebtPayoffBucket(
        _ bucket: DebtPayoffBucket
    ) {
        modelContext.delete(bucket)

        if saveDebtPayoffContext() {
            showConfirmation("Payment plan deleted.")
        }
    }

    @discardableResult
    private func saveDebtPayoffContext() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            AppLogger.error(
                "Debt payoff persistence error: \(error.localizedDescription)",
                category: .persistence
            )
            return false
        }
    }

    private func showPlannerEventConfirmation(
        type: PlannerEventType,
        isEditing: Bool
    ) {
        switch type {
        case .expense:
            showConfirmation(
                isEditing
                    ? "Upcoming Expense updated."
                    : "Upcoming Expense added to your plan."
            )

        case .income:
            showConfirmation(
                isEditing
                    ? "Income updated."
                    : "Income added to your timeline."
            )
        }
    }

    private func showConfirmation(
        _ message: String
    ) {
        let id = UUID()
        confirmationID = id
        confirmationMessage = message

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)

            if confirmationID == id {
                confirmationMessage = nil
            }
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
            usesNavigationStack: false,
            backgroundStyle: .page(.savings)
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
        .navigationTitle("Payment Plans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addAction()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(AppColors.accent)
                }
                .accessibilityLabel("Plan a payment")
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: CalderaCategoryStyle.style(for: .debtPayoff).icon,
            title: "Nothing planned here yet",
            description: "Plan a payment when you want it reflected in your spending plan.",
            primaryActionTitle: "Plan a Payment",
            primaryAction: addAction,
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
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
