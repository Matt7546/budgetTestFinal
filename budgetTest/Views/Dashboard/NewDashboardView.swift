import SwiftUI
import SwiftData

struct NewDashboardView: View {

    let showsNavigationTitle: Bool

    init(
        showsNavigationTitle: Bool = false
    ) {
        self.showsNavigationTitle = showsNavigationTitle
    }

    @EnvironmentObject private var auth: AuthManager
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

    @Query
    private var paymentPlanCycles: [PaymentPlanCycle]

    @State private var selectedExpense: ForecastEvent?
    @State private var showsAvailableInsights = false
    @State private var showsLinkedAccountsSetup = false

    @AppStorage(AppPersonalizationKeys.preferredName)
    private var preferredName = ""

    private enum Layout {
        static let pageHorizontalPadding = AppSpacing.regular
    }

    private let recurringRecommendationHistoryStore =
        RecurringExpenseRecommendationHistoryStore()

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            ScrollView {
                VStack(spacing: AppSpacing.screen) {
                    heroSection

                    if shouldShowSetupChecklist {
                        setupChecklistCard
                    }

                    dashboardCardsSection

                    if !shouldShowSetupChecklist,
                       hasIncompleteOptionalSetupSteps {
                        setupChecklistCard
                    }
                }
                .padding(.horizontal, Layout.pageHorizontalPadding)
                .padding(.top, CalderaPageChrome.topContentPadding)
                .padding(.bottom, AppSpacing.floatingTabClearance)
            }
            .scrollContentBackground(.hidden)
        }
        .calderaTopScrollFade(mood: .dashboard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(showsNavigationTitle ? "New Dashboard" : "")
        .navigationBarTitleDisplayMode(.inline)
        .calderaTransparentNavigationSurface()
        .sheet(item: $selectedExpense) { forecast in
            EventAllocationDetailView(forecast: forecast) {
                selectedExpense = nil
            }
        }
        .sheet(isPresented: $showsAvailableInsights) {
            AvailableToSpendInsightsSheet(
                summary: dashboardFinancialSummary,
                canShowBankData: canShowBankData,
                hasLinkedAccounts: hasLinkedBanks,
                hasEligibleCashAccounts: !visibleBankAccounts.cashAccounts.isEmpty,
                hasIncludedCashAccounts: hasIncludedCashAccounts,
                bankSyncState: plaid.bankSyncRefreshState
            )
        }
        .sheet(isPresented: $showsLinkedAccountsSetup) {
            NavigationStack {
                LinkBankView()
                    .navigationTitle("Linked Accounts")
                    .navigationBarTitleDisplayMode(.inline)
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
            return "Good morning"

        case 12..<17:
            return "Good afternoon"

        default:
            return "Good evening"
        }
    }

    private var preferredDisplayName: String? {
        AppPersonalization.preferredDisplayName(
            from: preferredName
        )
    }

    private var baseFinancialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: financialSummaryAccounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance
        )
    }

    private var dashboardFinancialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: financialSummaryAccounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance,
            upcomingExpensesSetAside: activeProtectedEventAllocations,
            debtPaymentsSetAside: totalDebtPayoffSetAside
        )
    }

    private var canShowBankData: Bool {
        !AppConfig.requiresAuthenticatedBankData || auth.isSignedIn
    }

    private var visibleBankAccounts: [PlaidAccount] {
        canShowBankData
            ? plaid.accounts.deduplicatedForDisplayAndTotals
            : []
    }

    private var financialSummaryAccounts: [PlaidAccount] {
        canShowBankData
            ? plaid.financialSummaryAccounts
            : []
    }

    private var displayedSafeToSpend: Double {
        canShowBankData ? dashboardFinancialSummary.safeToSpend : 0
    }

    private var hasLinkedBanks: Bool {
        !visibleBankAccounts.isEmpty
    }

    private var hasIncludedCashAccounts: Bool {
        !financialSummaryAccounts.cashAccounts.isEmpty
    }

    private var hasBankRefreshWarning: Bool {
        plaid.bankSyncRefreshState.balanceNeedsAttention
    }

    private var bankRefreshStatusText: String? {
        guard canShowBankData else {
            return nil
        }

        if plaid.isLoadingLinkedAccountsAfterAuthentication {
            return "Loading linked accounts…"
        }

        if plaid.isRefreshingPlaidData {
            return "Refreshing balances…"
        }

        switch plaid.bankSyncRefreshState.balances {
        case .updated:
            return plaid.accountsLastUpdatedText.replacingOccurrences(
                of: "Last refreshed",
                with: "Updated"
            )
        case .partiallyUpdated:
            return "Some balances couldn't update. Showing your most recent balances."
        case .showingEarlierData:
            return "Showing your most recent balances."
        case .unavailable:
            return "Bank Sync unavailable"
        case .rateLimited:
            return plaid.bankSyncRefreshState.hasUsableBalances
                ? "Bank Sync briefly paused. Showing your most recent balances."
                : "Bank Sync briefly paused"
        case .notRequested:
            return hasLinkedBanks ? "Balances not refreshed yet" : nil
        case .loading:
            return "Refreshing balances…"
        case .disabled:
            return "Linked balances unavailable"
        case .notConnected:
            return nil
        }
    }

    private var bankRefreshStatusIcon: String {
        if hasBankRefreshWarning {
            return "wifi.exclamationmark"
        }

        if plaid.isRefreshingPlaidData ||
            plaid.isLoadingLinkedAccountsAfterAuthentication {
            return "arrow.clockwise.circle.fill"
        }

        return plaid.bankSyncRefreshState.balances == .updated
            ? "checkmark.circle.fill"
            : "clock.fill"
    }

    private var bankRefreshStatusColor: Color {
        if hasBankRefreshWarning {
            return CalderaCategoryStyle.style(for: .needsMoney).primary
        }

        if plaid.isRefreshingPlaidData ||
            plaid.isLoadingLinkedAccountsAfterAuthentication {
            return CalderaCategoryStyle.style(for: .bankAccount).primary
        }

        return plaid.bankSyncRefreshState.balances == .updated
            ? CalderaCategoryStyle.style(for: .covered).primary
            : AppColors.secondaryText
    }

    private var hasCashCushion: Bool {
        plaid.reserveBalance > 0.005
    }

    private var hasUpcomingExpense: Bool {
        events.contains {
            $0.type == .expense
        }
    }

    private var hasGoal: Bool {
        !plaid.savingsGoals.isEmpty
    }

    private var hasDebtPayoff: Bool {
        !debtPayoffBuckets.isEmpty
    }

    /// Required steps are the minimum for the Dashboard to give a useful
    /// Next Action: being signed in and having Bank Sync connected. Cash
    /// Cushion, Upcoming Expenses, Goals, and Payment Plans are optional
    /// planning steps and must not permanently block Next Action.
    private var isRequiredDashboardSetupComplete: Bool {
        auth.isSignedIn && hasLinkedBanks
    }

    private var shouldShowSetupChecklist: Bool {
        !plaid.isLoadingLinkedAccountsAfterAuthentication &&
        !isRequiredDashboardSetupComplete
    }

    private var hasIncompleteOptionalSetupSteps: Bool {
        !(
            hasCashCushion &&
            hasUpcomingExpense &&
            hasGoal &&
            hasDebtPayoff
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

    private var nextSevenDayUpcomingForecasts: [ForecastEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(
            byAdding: .day,
            value: 7,
            to: today
        ) ?? today

        return upcomingExpenseForecasts.filter {
            let date = calendar.startOfDay(for: $0.occurrenceDate)
            return date >= today && date <= end
        }
    }

    private var nextSevenDayUpcomingTotal: Double {
        nextSevenDayUpcomingForecasts.reduce(0) {
            $0 + max($1.event.amount, 0)
        }
    }

    private var hasUpcomingExpenseNeedingAttention: Bool {
        upcomingExpenseForecasts.contains {
            remainingAmount(for: $0) > 0.005
        }
    }

    private var firstUpcomingExpenseNeedingMoney: ForecastEvent? {
        upcomingExpenseForecasts.first {
            remainingAmount(for: $0) > 0.005
        }
    }

    private var unresolvedPastDueExpenses: [ForecastEvent] {
        ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
            from: forecastCalculator.forecastEvents,
            statuses: occurrenceStatuses
        )
    }

    private var firstPaymentPlanNeedingMoney: DebtPayoffBucket? {
        activeOrLegacyPaymentPlans.first {
            paymentPlanRemainingAmount(for: $0) > 0.005
        }
    }

    private var activeOrLegacyPaymentPlans: [DebtPayoffBucket] {
        debtPayoffBuckets.filter { bucket in
            PaymentPlanCycleStore.isActiveOrLegacy(
                paymentPlanID: bucket.id,
                cycles: paymentPlanCycles
            )
        }
    }

    private var pastDuePaymentPlans: [DebtPayoffBucket] {
        let startOfToday = Calendar.current.startOfDay(for: Date())

        return activeOrLegacyPaymentPlans.filter { bucket in
            bucket.shouldDisplayDueDate &&
                Calendar.current.startOfDay(for: bucket.dueDate) <
                    startOfToday
        }
    }

    private var sortedPaymentPlans: [DebtPayoffBucket] {
        activeOrLegacyPaymentPlans.sorted {
            if Calendar.current.isDate($0.dueDate, inSameDayAs: $1.dueDate) {
                return $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending
            }

            return $0.dueDate < $1.dueDate
        }
    }

    private var totalDebtPayoffTarget: Double {
        activeOrLegacyPaymentPlans.reduce(0) {
            $0 + max($1.paymentTargetAmount, $1.protectedAmount)
        }
    }

    private var likelyPostedCardPaymentCandidates:
        [PaymentPlanPaymentCandidate] {
        sortedPaymentPlans.compactMap { bucket in
            guard let cycle = PaymentPlanCycleStore.activeCycle(
                for: bucket.id,
                in: paymentPlanCycles
            ) else {
                return nil
            }

            return plaid.likelyPostedCardPayment(
                for: bucket,
                cycle: cycle
            )
        }
    }

    private var dashboardRecurringRecommendations:
        [RecurringExpenseRecommendationItem] {
        guard auth.isSignedIn else {
            return []
        }

        let suggestions = RecurringExpenseSuggestionEngine.suggestions(
            transactions: plaid.transactions,
            existingEvents: events,
            snapshotMetadata: plaid.transactionSnapshotMetadata,
            automationIsEligible: plaid.transactionAutomationIsEligible
        )
        let groups = RecurringExpenseRecommendationGroups(
            suggestions: suggestions,
            history: recurringRecommendationHistoryStore.records(
                for: auth.user?.id
            ),
            existingExpenseIDs: Set(
                events
                    .filter { $0.type == .expense }
                    .map(\.id)
            )
        )

        return groups.needsReview
    }

    private var dashboardReviewItems: [ReviewUpdateItem] {
        ReviewUpdateSourceAssembler.make(
            .init(
                pastDueExpenses: unresolvedPastDueExpenses,
                pastDuePaymentPlans: pastDuePaymentPlans,
                likelyPostedCardPayments: likelyPostedCardPaymentCandidates,
                paymentPlans: activeOrLegacyPaymentPlans,
                cardPaymentDetails: plaid.cardPaymentDetails,
                recurringRecommendations: dashboardRecurringRecommendations
            )
        )
    }

    private var dashboardNextAction: DashboardNextAction {
        DashboardNextActionPriority.resolve(
            hasBankRefreshWarning: hasBankRefreshWarning,
            needsAccountScope: hasLinkedBanks &&
                !visibleBankAccounts.cashAccounts.isEmpty &&
                !hasIncludedCashAccounts,
            reviewItem: ReviewUpdateItems.highestPriority(
                in: dashboardReviewItems
            ),
            upcomingExpenseNeedingMoney: firstUpcomingExpenseNeedingMoney,
            hasPaymentPlanNeedingMoney: firstPaymentPlanNeedingMoney != nil
        )
    }

    private var availableToSpendCaption: String {
        if !canShowBankData {
            return "Sign in and link accounts to estimate from your balances."
        }

        if plaid.isLoadingLinkedAccountsAfterAuthentication {
            return "Loading the accounts already connected to Bank Sync."
        }

        switch plaid.bankSyncRefreshState.balances {
        case .partiallyUpdated,
             .showingEarlierData:
            return "Using your most recent linked balances. Some bank information couldn't update."
        case .unavailable:
            return "Bank Sync couldn't update. Available to Spend may be incomplete."
        case .rateLimited:
            return plaid.bankSyncRefreshState.hasUsableBalances
                ? "Using your most recent linked balances while Bank Sync is briefly paused."
                : "Bank Sync is briefly paused. Available to Spend may be incomplete."
        case .notRequested,
             .loading,
             .updated,
             .disabled,
             .notConnected:
            break
        }

        if !hasLinkedBanks {
            return "Link accounts to estimate from your balances."
        }

        if !hasIncludedCashAccounts {
            return visibleBankAccounts.cashAccounts.isEmpty
                ? "Link a checking or savings account to estimate from your balances."
                : "No linked cash accounts are counted in Available to Spend. Choose accounts in Bank Sync."
        }

        return dashboardFinancialSummary.safeToSpend >= 0
            ? "Cash left after set-asides."
            : "Your planned set-aside money is higher than your current available cash."
    }

    private var availableToSpendColor: Color {
        displayedSafeToSpend >= 0
            ? CalderaVisualStyle.primaryText(colorScheme)
            : CalderaCategoryStyle.style(for: .shortfall).primary
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.panel) {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                if let preferredDisplayName {
                    Text("\(greeting),")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

                    Text(preferredDisplayName)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                } else {
                    Text(greeting)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .accessibilityLabel(greeting)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                HStack(spacing: AppSpacing.xxSmall) {
                    Text("Available to Spend")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                    ContextHelpButton(
                        title: "Available to Spend",
                        bodyText: "Available to Spend is your cash balance minus money you’ve set aside inside \(AppBrand.shortName).",
                        breakdownItems: [
                            "Cash Balance",
                            "− Cash Cushion",
                            "− Savings Goals",
                            "− Upcoming Expenses",
                            "− Payment Plans",
                            "= Available to Spend"
                        ],
                        footnote: "Set-asides are virtual. Your money stays in your bank account, but \(AppBrand.shortName) treats it as unavailable for everyday spending."
                    )
                }

                Text(AppFormatters.currency(displayedSafeToSpend))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(availableToSpendColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(availableToSpendCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppSpacing.xSmall)

                if let bankRefreshStatusText {
                    Button {
                        showsLinkedAccountsSetup = true
                    } label: {
                        HStack(spacing: AppSpacing.xSmall) {
                            Image(systemName: bankRefreshStatusIcon)
                                .font(.caption.weight(.bold))
                                .foregroundColor(bankRefreshStatusColor)

                            Text(bankRefreshStatusText)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(
                                    CalderaVisualStyle.primaryText(colorScheme)
                                )
                                .fixedSize(horizontal: false, vertical: true)

                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.xxSmall)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Bank data \(bankRefreshStatusText)")
                    .accessibilityHint("Open Bank Sync.")
                }

                availableInsightsButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppSpacing.regular)
        .padding(.bottom, AppSpacing.screen)
        .frame(minHeight: 278)
    }

    private var availableInsightsButton: some View {
        Button {
            showsAvailableInsights = true
        } label: {
            HStack(spacing: AppSpacing.xSmall) {
                Text("View insights")

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .font(.caption.weight(.bold))
            .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.small)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.10)
                            : Color.white.opacity(0.86)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.16)
                                    : Color.white.opacity(0.76),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.045),
                        radius: 12,
                        x: 0,
                        y: 6
                    )
            }
        }
        .buttonStyle(.plain)
        .padding(.top, AppSpacing.medium)
        .accessibilityLabel("View Available to Spend insights")
    }

    private var setupChecklistCard: some View {
        DashboardSetupChecklistCard(
            isRequiredSetupComplete: isRequiredDashboardSetupComplete,
            isSignedIn: auth.isSignedIn,
            isSigningIn: auth.isBusy,
            hasLinkedBanks: hasLinkedBanks,
            hasCashCushion: hasCashCushion,
            hasUpcomingExpense: hasUpcomingExpense,
            hasGoal: hasGoal,
            hasDebtPayoff: hasDebtPayoff,
            signInRequest: auth.configureAppleRequest,
            signInCompletion: auth.handleAppleCompletion,
            connectBanksAction: {
                showsLinkedAccountsSetup = true
            },
            cashCushionAction: {
                navigation.openSavings()
            },
            upcomingExpenseAction: {
                navigation.openTimelineCreateExpense()
            },
            goalAction: {
                navigation.openSavingsCreateGoal()
            },
            debtPayoffAction: {
                navigation.openSavingsCreateDebtPayoff()
            }
        )
    }

    private var dashboardCardsSection: some View {
        DashboardCardsSection(
            planStatusItems: [
                DashboardPlanStatusItem(
                    id: "total-set-aside",
                    title: "Total Set Aside",
                    value: AppFormatters.currency(
                        dashboardFinancialSummary.protectedMoney
                    ),
                    detail: "Cash Cushion, Savings Goals, Upcoming Expenses, and Payment Plans.",
                    style: CalderaCategoryStyle.style(for: .reserve),
                    systemImage: "wallet.pass.fill",
                    actionTitle: "Open Set Aside",
                    action: {
                        navigation.openSavings()
                    }
                ),
                DashboardPlanStatusItem(
                    id: "upcoming-expenses",
                    title: "Upcoming Expenses",
                    value: nextSevenDayUpcomingForecasts.isEmpty
                        ? "None"
                        : AppFormatters.currency(nextSevenDayUpcomingTotal),
                    detail: nextSevenDayUpcomingForecasts.isEmpty
                        ? "No Upcoming Expenses in the next 7 days."
                        : "\(nextSevenDayUpcomingForecasts.count) due in the next 7 days.",
                    style: CalderaCategoryStyle.style(for: .upcomingExpense),
                    systemImage: CalderaCategoryStyle.style(
                        for: .upcomingExpense
                    ).icon,
                    actionTitle: "Open Plan Ahead",
                    action: {
                        navigation.selectedTab = 2
                    }
                ),
                DashboardPlanStatusItem(
                    id: "payment-plan-targets",
                    title: "Payment Plan targets",
                    value: activeOrLegacyPaymentPlans.isEmpty
                        ? AppFormatters.currency(0)
                        : AppFormatters.currency(totalDebtPayoffTarget),
                    detail: activeOrLegacyPaymentPlans.isEmpty
                        ? "No Payment Plans yet."
                        : activeOrLegacyPaymentPlans.count == 1
                            ? "1 Payment Plan."
                            : "\(activeOrLegacyPaymentPlans.count) Payment Plans.",
                    style: CalderaCategoryStyle.style(for: .debtPayoff),
                    systemImage: CalderaCategoryStyle.style(
                        for: .debtPayoff
                    ).icon,
                    actionTitle: "Open Payment Plans",
                    action: {
                        navigation.openSavings()
                    }
                )
            ],
            showsNextAction: !shouldShowSetupChecklist &&
                !plaid.isLoadingLinkedAccountsAfterAuthentication,
            nextAction: dashboardNextAction,
            performNextAction: { action in
                perform(action)
            }
        )
    }

    private func perform(
        _ nextAction: DashboardNextAction
    ) {
        switch nextAction {
        case .bankSync,
             .accountScope:
            showsLinkedAccountsSetup = true

        case .suggestedUpdate,
             .paymentPlanNeedsMoney:
            navigation.selectedTab = 1

        case .possibleCardPayment(let candidate):
            navigation.openSavingsEditDebtPayoff(
                candidate.paymentPlanID
            )

        case .paymentPlanSuggestedUpdate(let paymentPlanID):
            navigation.openSavingsEditDebtPayoff(
                paymentPlanID
            )

        case .recurringExpenseRecommendation(let historyID):
            navigation.openTimelineRecurringRecommendation(
                historyID
            )

        case .upcomingNeedsMoney(let forecast):
            selectedExpense = forecast

        case .pastDueExpense(let forecast):
            selectedExpense = forecast

        case .pastDuePaymentPlan:
            navigation.openPlanAheadPastDue()

        case .allClear:
            break
        }
    }

    private func allocatedAmount(
        for forecast: ForecastEvent
    ) -> Double {
        allocations.first {
            $0.occurrenceID == forecast.occurrenceID
        }?
        .allocatedAmount ?? 0
    }

    private func paymentPlanRemainingAmount(
        for bucket: DebtPayoffBucket
    ) -> Double {
        max(
            bucket.paymentTargetAmount - bucket.protectedAmount,
            0
        )
    }

    private func remainingAmount(
        for forecast: ForecastEvent
    ) -> Double {
        max(
            forecast.event.amount - allocatedAmount(for: forecast),
            0
        )
    }

}
