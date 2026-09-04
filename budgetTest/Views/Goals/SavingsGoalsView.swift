import SwiftUI
import SwiftData

private struct SavingsOverviewSnapshot {
    let debtAccounts: [PlaidAccount]
    let debtAccountByID: [String: PlaidAccount]
    let hasSavingsGoals: Bool
    let visibleSavingsGoals: [SavingsGoal]
    let hasUpcomingExpenses: Bool
    let visibleUpcomingExpenseRows: [SavingsUpcomingExpenseRow]
    let hasDebtPayoffBuckets: Bool
    let allDebtPayoffBuckets: [DebtPayoffBucket]
    let activeDebtPayoffBuckets: [DebtPayoffBucket]
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

enum SavingsGoalSheetRoute: Identifiable {
    case create(SavingsGoal)
    case update(SavingsGoal)

    var id: String {
        switch self {
        case .create(let goal):
            return "create-\(goal.id)"
        case .update(let goal):
            return "update-\(goal.id)"
        }
    }

    var goalID: UUID {
        switch self {
        case .create(let goal), .update(let goal):
            return goal.id
        }
    }

    var usesModernUpdateFlow: Bool {
        if case .update = self {
            return true
        }
        return false
    }

    static func quickContribution(
        to goal: SavingsGoal
    ) -> SavingsGoalSheetRoute {
        .update(goal)
    }

    static func existingGoal(
        _ goal: SavingsGoal
    ) -> SavingsGoalSheetRoute {
        .update(goal)
    }
}

struct SavingsGoalsView: View {

    init(
        initialPagerSection: SetAsidePagerSection = .defaultSelection
    ) {
        _selectedPagerSection = State(initialValue: initialPagerSection)
    }

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

    @Query
    private var paymentPlanCycles: [PaymentPlanCycle]

    @Query
    private var reserveSettings: [ReserveSettings]

    @AppStorage(SetAsidePagerFeature.storageKey)
    private var isSetAsidePagerStoredEnabled =
        SetAsidePagerFeature.defaultStoredValue

    private enum ActiveDebtPayoffSheet: Identifiable {
        case create
        case edit(
            DebtPayoffBucket,
            cycleID: UUID?,
            editor: SetAsidePagerPaymentPlanEditor
        )

        var id: String {
            switch self {
            case .create:
                return "create"

            case .edit(let bucket, let cycleID, let editor):
                return "\(bucket.id.uuidString)-\(cycleID?.uuidString ?? "legacy")-\(editor)"
            }
        }
    }

    @State private var activeGoalSheet: SavingsGoalSheetRoute?
    @State private var activeDebtPayoffSheet: ActiveDebtPayoffSheet?
    @State private var cashCushionAdjustmentMode:
        CashCushionAdjustmentMode?
    @State private var selectedEvent: PlannerEvent?
    @State private var selectedEventForecast: ForecastEvent?
    @State private var isAddingUpcomingExpense = false
    @State private var pagerSeeAllSection: SetAsidePagerSection?
    @State private var confirmationMessage: String?
    @State private var confirmationID = UUID()
    @State private var selectedPagerSection: SetAsidePagerSection

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
        let forecastEvents = makeForecastEvents()
        let expenseForecasts = forecastEvents.filter {
            $0.event.type == .expense
        }
        let allocationByOccurrenceID = allocationLookup()
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
        let activeDebtPayoffBuckets = sortedDebtPayoffBuckets.filter {
            PaymentPlanCycleStore.isActiveOrLegacy(
                paymentPlanID: $0.id,
                cycles: paymentPlanCycles
            )
        }

        return SavingsOverviewSnapshot(
            debtAccounts: debtAccounts,
            debtAccountByID: debtAccountByID,
            hasSavingsGoals: !plaid.savingsGoals.isEmpty,
            visibleSavingsGoals: visibleSavingsGoals,
            hasUpcomingExpenses: !expenseForecasts.isEmpty,
            visibleUpcomingExpenseRows: Array(upcomingExpenseRows),
            hasDebtPayoffBuckets: !activeDebtPayoffBuckets.isEmpty,
            allDebtPayoffBuckets: sortedDebtPayoffBuckets,
            activeDebtPayoffBuckets: activeDebtPayoffBuckets,
            visibleDebtPayoffBuckets: Array(
                activeDebtPayoffBuckets.prefix(3)
            )
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

                switch setAsideExperience {
                case .legacy:
                    legacySetAsideContent(snapshot)

                case .pager:
                    pagerSetAsideContent(snapshot)
                }
            }
            .calderaTopScrollFade(mood: .savings)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Set Aside")
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .navigationDestination(item: $pagerSeeAllSection) { section in
                pagerSeeAllDestination(
                    section,
                    snapshot: snapshot
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calderaConfirmationOverlay(message: confirmationMessage)
        .sheet(item: $cashCushionAdjustmentMode) { mode in
            CashCushionEditorView(
                mode: mode,
                reserveBalance: plaid.reserveBalance,
                submitAction: { amount in
                    switch mode {
                    case .add:
                        return addToReserve(amount)
                    case .use:
                        return subtractFromReserve(amount)
                    }
                }
            )
        }
        .sheet(item: $activeGoalSheet) { sheet in
            switch sheet {
            case .create(let goal):
                NewSavingsGoalCreateView(
                    goal: goal,
                    onSaved: {
                        showConfirmation(
                            "Goal added to your plan."
                        )
                    }
                )
                .environmentObject(plaid)

            case .update(let goal):
                EditGoalView(
                    goal: goal,
                    isNew: false,
                    onSaved: { _ in
                        showConfirmation("Goal updated.")
                    },
                    onDeleted: {
                        showConfirmation("Goal deleted.")
                    }
                )
                .environmentObject(plaid)
            }
        }
        .sheet(
            item: $selectedEvent,
            onDismiss: {
                selectedEventForecast = nil
            }
        ) { event in
            PlannerEventEditorDestination(
                editingEvent: event,
                forecast: selectedEventForecast,
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
            NewUpcomingExpenseCreateView {
                showPlannerEventConfirmation(
                    type: .expense,
                    isEditing: false
                )
            }
        }
        .sheet(item: $activeDebtPayoffSheet) { sheet in
            switch sheet {
            case .create:
                NewPaymentPlanCreateView(
                    debtAccounts: snapshot.debtAccounts,
                    existingPaymentPlans: snapshot.allDebtPayoffBuckets,
                    onSave: saveDebtPayoffBucket,
                    onSaved: {
                        showConfirmation("Payment plan added.")
                    }
                )
                .environmentObject(plaid)

            case .edit(let bucket, let cycleID, let editor):
                if editor == .modernCard {
                    EditPaymentPlanView(
                        bucket: bucket,
                        debtAccounts: snapshot.debtAccounts,
                        paymentPlanCycles: paymentPlanCycles,
                        requestedCycleID: cycleID,
                        balanceLastUpdatedText:
                            plaid.accountsLastUpdatedText,
                        onSave: { draft in
                            updateDebtPayoffBucket(
                                bucket,
                                draft: draft
                            )
                        },
                        onSaved: {
                            showConfirmation("Payment plan updated.")
                        },
                        onDelete: deleteDebtPayoffBucket,
                        onDeleted: {
                            showConfirmation("Payment plan deleted.")
                        }
                    )
                    .environmentObject(plaid)
                } else {
                    DebtPayoffBucketEditorView(
                        debtAccounts: snapshot.debtAccounts,
                        existingPaymentPlans:
                            snapshot.allDebtPayoffBuckets,
                        balanceLastUpdatedText:
                            plaid.accountsLastUpdatedText,
                        bucket: bucket,
                        paymentPlanCycles: paymentPlanCycles,
                        onSave: { draft in
                            if updateDebtPayoffBucket(
                                bucket,
                                draft: draft
                            ) {
                                showConfirmation(
                                    "Payment plan updated."
                                )
                            }
                        },
                        onDelete: { bucket in
                            if deleteDebtPayoffBucket(bucket) {
                                showConfirmation(
                                    "Payment plan deleted."
                                )
                            }
                        }
                    )
                }
            }
        }
        .onAppear {
            consumeSetAsideSectionRequest()
            consumeSavingsGoalEditRequest()
            consumeDebtPayoffEditRequest()
        }
        .onChange(of: navigation.setAsideSectionToOpen) { _, _ in
            consumeSetAsideSectionRequest()
        }
        .onChange(of: navigation.savingsGoalToEditID) { _, _ in
            consumeSavingsGoalEditRequest()
        }
        .onChange(of: navigation.debtPayoffToEditID) { _, _ in
            consumeDebtPayoffEditRequest()
        }
    }

    private var setAsideExperience: SetAsidePagerExperience {
        SetAsidePagerFeature.experience(
            storedValue: isSetAsidePagerStoredEnabled
        )
    }

    private func legacySetAsideContent(
        _ snapshot: SavingsOverviewSnapshot
    ) -> some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.screen
            ) {
                header

                ForEach(SetAsideSectionKind.displayOrder, id: \.self) { kind in
                    setAsideSection(
                        for: kind,
                        snapshot: snapshot
                    )
                }
            }
            .padding(.all)
            .padding(.bottom, AppSpacing.floatingTabClearance)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pagerSetAsideContent(
        _ overview: SavingsOverviewSnapshot
    ) -> some View {
        let pagerSnapshot = SetAsidePagerSnapshotBuilder.build(
            from: SetAsidePagerSnapshotBuilder.Input(
                reserveBalance: plaid.reserveBalance,
                savingsGoals: plaid.savingsGoals,
                events: events,
                allocations: allocations,
                occurrenceStatuses: occurrenceStatuses,
                paymentPlans: debtPayoffBuckets,
                paymentPlanCycles: paymentPlanCycles,
                debtAccounts: overview.debtAccounts
            )
        )

        return VStack(
            alignment: .leading,
            spacing: AppSpacing.regular
        ) {
            pagerHeader

            SetAsidePagerView(
                snapshot: pagerSnapshot,
                selectedSection: $selectedPagerSection,
                performDestination: { destination in
                    handlePagerDestination(
                        destination
                    )
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, AppSpacing.regular)
        .padding(.top, AppSpacing.regular)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func pagerSeeAllDestination(
        _ section: SetAsidePagerSection,
        snapshot: SavingsOverviewSnapshot
    ) -> some View {
        switch section {
        case .upcomingExpenses:
            AllTimelineExpensesView()

        case .paymentPlans:
            AllDebtPayoffBucketsView(
                buckets: snapshot.allDebtPayoffBuckets,
                paymentPlanCycles: paymentPlanCycles,
                accountByID: snapshot.debtAccountByID,
                balanceLastUpdatedText: plaid.accountsLastUpdatedText,
                editAction: showPaymentPlanEditor,
                addAction: {
                    activeDebtPayoffSheet = .create
                }
            )

        case .savingsGoals:
            AllSavingsGoalsView()
                .environmentObject(plaid)
        }
    }

    private func handlePagerDestination(
        _ destination: SetAsidePagerDestination
    ) {
        switch SetAsidePagerRouteResolver.resolve(destination) {
        case .adjustCashCushion(let mode):
            cashCushionAdjustmentMode = mode

        case .createSavingsGoal:
            createSavingsGoal()

        case .seeAllSavingsGoals:
            pagerSeeAllSection = .savingsGoals

        case .editSavingsGoal(let goalID):
            guard let goal = plaid.savingsGoals.first(where: {
                $0.id == goalID
            }) else {
                return
            }
            activeGoalSheet = .existingGoal(goal)

        case .createPaymentPlan:
            activeDebtPayoffSheet = .create

        case .seeAllPaymentPlans:
            pagerSeeAllSection = .paymentPlans

        case .editPaymentPlan(let bucketID, let cycleID, let editor):
            guard let bucket = debtPayoffBuckets.first(where: {
                $0.id == bucketID
            }) else {
                return
            }

            let resolvedCycleID = cycleID.flatMap { requestedID in
                paymentPlanCycles.first(where: {
                    $0.id == requestedID &&
                        $0.paymentPlanID == bucketID
                })?.id
            }
            activeDebtPayoffSheet = .edit(
                bucket,
                cycleID: resolvedCycleID,
                editor: editor
            )

        case .createUpcomingExpense:
            isAddingUpcomingExpense = true

        case .seeAllUpcomingExpenses:
            pagerSeeAllSection = .upcomingExpenses

        case .editUpcomingExpense(let eventID, let occurrenceID):
            guard let forecast = makeForecastEvents().first(where: {
                $0.event.id == eventID &&
                    $0.occurrenceID == occurrenceID
            }) else {
                return
            }

            selectedEventForecast = forecast
            selectedEvent = forecast.event

        }
    }

    @ViewBuilder
    private func setAsideSection(
        for kind: SetAsideSectionKind,
        snapshot: SavingsOverviewSnapshot
    ) -> some View {
        switch kind {
        case .upcomingExpenses:
            SavingsUpcomingExpensesSection(
                hasUpcomingExpenses: snapshot.hasUpcomingExpenses,
                visibleRows: snapshot.visibleUpcomingExpenseRows,
                trailing: upcomingExpensesHeaderActions(),
                addAction: {
                    isAddingUpcomingExpense = true
                },
                selectAction: { forecast in
                    selectedEventForecast = forecast
                    selectedEvent = forecast.event
                }
            )
        case .paymentPlans:
            SavingsDebtPayoffSection(
                hasDebtPayoffBuckets: snapshot.hasDebtPayoffBuckets,
                activeBuckets: snapshot.activeDebtPayoffBuckets,
                visibleBuckets: snapshot.visibleDebtPayoffBuckets,
                paymentPlanCycles: paymentPlanCycles,
                accountByID: snapshot.debtAccountByID,
                balanceLastUpdatedText: plaid.accountsLastUpdatedText,
                trailing: debtPayoffHeaderActions(snapshot),
                addAction: {
                    activeDebtPayoffSheet = .create
                },
                editAction: showPaymentPlanEditor
            )
        case .savingsGoals:
            SavingsGoalsSection(
                hasSavingsGoals: snapshot.hasSavingsGoals,
                visibleSavingsGoals: snapshot.visibleSavingsGoals,
                trailing: savingsGoalsHeaderActions(),
                createAction: createSavingsGoal,
                editAction: showEditGoal,
                addMoneyAction: showAddMoney
            )
        case .cashCushion:
            CashCushionBalanceCard(
                balance: plaid.reserveBalance,
                addAction: {
                    cashCushionAdjustmentMode = .add
                },
                useAction: {
                    cashCushionAdjustmentMode = .use
                }
            )
        }
    }

    private func consumeDebtPayoffEditRequest() {
        guard let bucketID = navigation.debtPayoffToEditID else {
            return
        }

        let requestedCycleID = navigation.debtPayoffCycleToEditID

        guard let bucket = debtPayoffBuckets.first(where: {
            $0.id == bucketID
        }) else {
            navigation.debtPayoffToEditID = nil
            navigation.debtPayoffCycleToEditID = nil
            return
        }

        navigation.debtPayoffToEditID = nil
        navigation.debtPayoffCycleToEditID = nil
        showPaymentPlanEditor(
            bucket,
            requestedCycleID: requestedCycleID
        )
    }

    private func consumeSetAsideSectionRequest() {
        guard let requestedSection = navigation.setAsideSectionToOpen else {
            return
        }

        selectedPagerSection = requestedSection
        navigation.setAsideSectionToOpen = nil
    }

    private func consumeSavingsGoalEditRequest() {
        guard let goalID = navigation.savingsGoalToEditID else {
            return
        }

        navigation.savingsGoalToEditID = nil

        guard let goal = plaid.savingsGoals.first(where: {
            $0.id == goalID
        }) else {
            return
        }

        activeGoalSheet = .existingGoal(goal)
    }

    private var header: some View {
        CalderaPageHeader(
            eyebrow: "Money kept out of Available to Spend",
            title: "Set Aside",
            titleAccessory: {
                ContextHelpButton(
                    title: "Set Aside",
                    bodyText: "Set Aside is money Caldera keeps out of Available to Spend. Use Cash Cushion for flexible extra money, Savings Goals for things you’re saving toward, Upcoming Expenses for planned bills, and Payment Plans for payments you want to plan for."
                )
            }
        )
    }

    private var pagerHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text("SET ASIDE")
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.secondaryText)

            Text("A calmer plan for what matters next.")
                .font(.title3.weight(.bold))
                .foregroundColor(AppColors.primaryText)
        }
        .accessibilityElement(children: .combine)
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
                    paymentPlanCycles: paymentPlanCycles,
                    accountByID: snapshot.debtAccountByID,
                    balanceLastUpdatedText: plaid.accountsLastUpdatedText,
                    editAction: showPaymentPlanEditor,
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

        activeGoalSheet = .create(draft)
    }

    private func showPaymentPlanEditor(
        _ bucket: DebtPayoffBucket
    ) {
        showPaymentPlanEditor(
            bucket,
            requestedCycleID: PaymentPlanCycleStore.activeCycle(
                for: bucket.id,
                in: paymentPlanCycles
            )?.id
        )
    }

    private func showPaymentPlanEditor(
        _ bucket: DebtPayoffBucket,
        requestedCycleID: UUID?
    ) {
        let resolvedCycleID = requestedCycleID.flatMap { cycleID in
            paymentPlanCycles.first(where: {
                $0.id == cycleID &&
                    $0.paymentPlanID == bucket.id
            })?.id
        }

        activeDebtPayoffSheet = .edit(
            bucket,
            cycleID: resolvedCycleID,
            editor: PaymentPlanUpdateRouting.usesModernEditor(for: bucket)
                ? .modernCard
                : .legacyDebt
        )
    }

    private func showAddMoney(
        for goal: SavingsGoal
    ) {
        activeGoalSheet = .quickContribution(to: goal)
    }

    private func showEditGoal(
        for goal: SavingsGoal
    ) {
        activeGoalSheet = .existingGoal(goal)
    }

    private func addToReserve(
        _ amount: Double
    ) -> CashCushionPersistenceResult {
        let result = CashCushionPersistenceCoordinator.add(
            amount,
            to: plaid.reserveBalance,
            settings: cashCushionSettings,
            applyBalance: { plaid.reserveBalance = $0 },
            insertSettings: modelContext.insert,
            persistChanges: modelContext.save,
            rollback: modelContext.rollback
        )

        guard result.didSave else {
            return result
        }

        showConfirmation("Cash Cushion updated.")
        return result
    }

    private func subtractFromReserve(
        _ amount: Double
    ) -> CashCushionPersistenceResult {
        let result = CashCushionPersistenceCoordinator.use(
            amount,
            from: plaid.reserveBalance,
            settings: cashCushionSettings,
            applyBalance: { plaid.reserveBalance = $0 },
            insertSettings: modelContext.insert,
            persistChanges: modelContext.save,
            rollback: modelContext.rollback
        )

        guard result.didSave else {
            return result
        }

        showConfirmation("Cash Cushion updated.")
        return result
    }

    private var cashCushionSettings: ReserveSettings? {
        reserveSettings.first {
            $0.id == ReserveSettings.defaultID
        }
    }

    private func saveDebtPayoffBucket(
        _ draft: DebtPayoffBucketDraft
    ) -> Bool {
        let bucket = DebtPayoffBucket(
                plaidAccountID: draft.plaidAccountID,
                accountName: draft.accountName,
                institutionName: draft.institutionName,
                dueDate: draft.dueDate,
                paymentTargetAmount: draft.paymentTargetAmount,
                protectedAmount: draft.protectedAmount,
                debtKind: draft.debtKind,
                paymentTargetChoice: draft.paymentTargetChoice,
                targetChosenAt: draft.targetChosenAt,
                targetStatementIssueDate: draft.targetStatementIssueDate,
                manualCurrentBalance: draft.manualCurrentBalance,
                monthlyPayment: draft.monthlyPayment,
                originalBalance: draft.originalBalance,
                interestRate: draft.interestRate,
                notes: draft.notes,
                hasPaymentDueDate: draft.hasPaymentDueDate,
                startDate: draft.startDate,
                endDate: draft.endDate
        )
        modelContext.insert(bucket)

        if draft.shouldCreateActiveCycle,
           let cycle = PaymentPlanCycleStore.makeActiveCycle(
                for: bucket,
                dueDate: draft.dueDate,
                targetAmount: draft.paymentTargetAmount,
                dueDayAnchor: draft.cycleDueDayAnchor,
                existingCycles: paymentPlanCycles
           ) {
            modelContext.insert(cycle)
        }

        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            AppLogger.error(
                "Payment Plan creation persistence error: \(error.localizedDescription)",
                category: .persistence
            )
            return false
        }
    }

    private func updateDebtPayoffBucket(
        _ bucket: DebtPayoffBucket,
        draft: DebtPayoffBucketDraft
    ) -> Bool {
        let activeCycle = PaymentPlanCycleStore.activeCycle(
            for: bucket.id,
            in: paymentPlanCycles
        )
        let result = PaymentPlanUpdatePersistenceCoordinator.persist(
            draft: draft,
            bucket: bucket,
            activeCycle: activeCycle,
            existingCycles: paymentPlanCycles,
            insertCycle: modelContext.insert,
            persistChanges: modelContext.save,
            rollback: modelContext.rollback
        )
        return result.startsSuccessFlow
    }

    @discardableResult
    private func deleteDebtPayoffBucket(
        _ bucket: DebtPayoffBucket
    ) -> Bool {
        PaymentPlanCycleStore.cycles(
            for: bucket.id,
            in: paymentPlanCycles
        )
        .forEach(modelContext.delete)
        modelContext.delete(bucket)

        if saveDebtPayoffContext() {
            return true
        }

        modelContext.rollback()
        return false
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
                    : "Income added to Plan Ahead."
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
    let paymentPlanCycles: [PaymentPlanCycle]
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
            linkedAccount: account,
            cycle: PaymentPlanCycleStore.latestCycle(
                for: bucket.id,
                in: paymentPlanCycles
            )
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
