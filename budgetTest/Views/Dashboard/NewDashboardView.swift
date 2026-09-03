import SwiftUI
import SwiftData
import UIKit

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
    @Environment(\.isSensitiveDataHidden)
    private var isSensitiveDataHidden

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
    private var availableToSpendAccountPreferences:
        [AvailableToSpendAccountPreference]

    @State private var selectedExpense: ForecastEvent?
    @State private var expenseToEdit: ForecastEvent?
    @State private var pendingExpenseToEdit: ForecastEvent?
    @State private var showsAvailableInsights = false
    @State private var showsLinkedAccountsSetup = false
    @State private var presentedDashboardSheet: PresentedDashboardSheet?
    @State private var ambientBlobActivity = DashboardAmbientBlobActivity()
    @State private var dashboardRefreshNotice: DashboardRefreshNotice?

    @AppStorage(AppPersonalizationKeys.preferredName)
    private var preferredName = ""

    @AppStorage(DashboardSetupManualCompletionPreference.storageKey)
    private var manuallyCompletedSetupSteps = ""

    @AppStorage(DashboardWidgetPreferences.storageKey)
    private var storedDashboardWidgetPreferences = ""

    @AppStorage(DashboardNextActionCollapsePreference.storageKey)
    private var isNextActionCollapsed = false

    private enum PresentedDashboardSheet: String, Identifiable {
        case widgetManager

        var id: String { rawValue }
    }

    private enum DashboardRefreshNotice: String, Identifiable {
        case signInRequired
        case linkAccountRequired

        var id: String { rawValue }
    }

    private enum Layout {
        static let pageHorizontalPadding = AppSpacing.regular
        static let refreshButtonWidth: CGFloat = 112
    }

    private let recurringRecommendationHistoryStore =
        RecurringExpenseRecommendationHistoryStore()

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            DashboardAmbientBlobView(
                isVisible: navigation.selectedTab == 0 &&
                    !isDashboardPresentationActive,
                activity: ambientBlobActivity
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(false)

            ScrollView(.vertical) {
                VStack(spacing: AppSpacing.screen) {
                    heroSection

                    if shouldShowSetupChecklist {
                        setupChecklistCard
                    }

                    dashboardCardsSection

                    dashboardWidgetGrid
                }
                .padding(.horizontal, Layout.pageHorizontalPadding)
                .padding(.top, CalderaPageChrome.topContentPadding)
                .padding(.bottom, AppSpacing.floatingTabClearance)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .containerRelativeFrame(.horizontal)
                .background {
                    DashboardVerticalScrollConfigurator()
                }
            }
            .scrollContentBackground(.hidden)
            .onScrollPhaseChange { _, newPhase in
                ambientBlobActivity.isScrolling = newPhase.isScrolling
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .calderaTopScrollFade(mood: .dashboard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(showsNavigationTitle ? "New Dashboard" : "")
        .navigationBarTitleDisplayMode(.inline)
        .calderaTransparentNavigationSurface()
        .alert(item: $dashboardRefreshNotice) { notice in
            switch notice {
            case .signInRequired:
                return Alert(
                    title: Text("Sign in to refresh bank data"),
                    message: Text("Open More to sign in, then refresh your linked accounts."),
                    primaryButton: .default(Text("Open More")) {
                        navigation.selectedTab = 3
                    },
                    secondaryButton: .cancel()
                )

            case .linkAccountRequired:
                return Alert(
                    title: Text("Link an account to refresh balances"),
                    message: Text("Connect a checking, savings, or card account before refreshing."),
                    primaryButton: .default(Text("Link Account")) {
                        showsLinkedAccountsSetup = true
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .sheet(
            item: $selectedExpense,
            onDismiss: {
                guard let forecast = pendingExpenseToEdit else {
                    return
                }

                pendingExpenseToEdit = nil
                expenseToEdit = forecast
            }
        ) { forecast in
            EventAllocationDetailView(forecast: forecast) {
                pendingExpenseToEdit = forecast
                selectedExpense = nil
            }
        }
        .sheet(item: $expenseToEdit) { forecast in
            PlannerEventEditorDestination(
                editingEvent: forecast.event,
                forecast: forecast
            )
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
        .sheet(item: $presentedDashboardSheet) { sheet in
            switch sheet {
            case .widgetManager:
                DashboardWidgetManagerSheet(
                    storedValue: $storedDashboardWidgetPreferences,
                    unavailableKinds: unavailableDashboardWidgetKinds
                )
            }
        }
    }

    private var isDashboardPresentationActive: Bool {
        selectedExpense != nil ||
            expenseToEdit != nil ||
            pendingExpenseToEdit != nil ||
            showsAvailableInsights ||
            showsLinkedAccountsSetup ||
            presentedDashboardSheet != nil ||
            dashboardRefreshNotice != nil
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

    private var availableToSpendPresentation: DashboardAvailableToSpendPresentation {
        DashboardAvailableToSpendPresentation.make(
            canShowBankData: canShowBankData,
            safeToSpend: dashboardFinancialSummary.safeToSpend
        )
    }

    private var hasLinkedBanks: Bool {
        !visibleBankAccounts.isEmpty
    }

    private var hasIncludedCashAccounts: Bool {
        !financialSummaryAccounts.cashAccounts.isEmpty
    }

    private var hasConfiguredSpendingAccounts: Bool {
        AvailableToSpendAccountScope.hasExplicitSelection(
            userID: auth.user?.id,
            linkedCashAccountIDs: Set(
                visibleBankAccounts.cashAccounts.map(\.account_id)
            ),
            selections: availableToSpendAccountPreferences.map(\.selection)
        )
    }

    private var hasBankRefreshWarning: Bool {
        plaid.bankSyncRefreshState.balanceNeedsAttention
    }

    private var isDashboardRefreshInProgress: Bool {
        plaid.isRefreshingPlaidData ||
            plaid.isLoadingLinkedAccountsAfterAuthentication
    }

    private var bankRefreshStatusText: String? {
        guard canShowBankData else {
            return nil
        }

        return DashboardRefreshPresentation.statusText(
            isRefreshing: isDashboardRefreshInProgress,
            state: plaid.bankSyncRefreshState,
            accountsLastUpdatedText: plaid.accountsLastUpdatedText
        )
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

    private var hasSetAsideItem: Bool {
        hasCashCushion || hasGoal || hasDebtPayoff
    }

    private var hasPlanItem: Bool {
        hasUpcomingExpense || hasDebtPayoff
    }

    private var dashboardSetupProgress: DashboardSetupProgress {
        DashboardSetupProgress(
            isSignedIn: auth.isSignedIn,
            hasLinkedBanks: hasLinkedBanks,
            hasConfiguredSpendingAccounts: hasConfiguredSpendingAccounts,
            hasSetAsideItem: hasSetAsideItem,
            hasPlanItem: hasPlanItem,
            manuallyCompletedSteps: DashboardSetupManualCompletionPreference.steps(
                from: manuallyCompletedSetupSteps
            )
        )
    }

    private var shouldShowSetupChecklist: Bool {
        !plaid.isLoadingLinkedAccountsAfterAuthentication &&
        !dashboardSetupProgress.isComplete
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

    private var dashboardWidgetSnapshots: DashboardWidgetSnapshotCollection {
        let now = Date()

        return DashboardWidgetSnapshotBuilder.build(
            from: DashboardWidgetSnapshotBuilder.Input(
                financialSummary: dashboardFinancialSummary,
                isSignedIn: auth.isSignedIn,
                canShowBankData: canShowBankData,
                linkedAccounts: visibleBankAccounts,
                bankSyncState: plaid.bankSyncRefreshState,
                accountsLastUpdatedText: plaid.accountsLastUpdatedText,
                savingsGoals: plaid.savingsGoals,
                events: events,
                allocations: allocations,
                occurrenceStatuses: occurrenceStatuses,
                paymentPlans: debtPayoffBuckets,
                paymentPlanCycles: paymentPlanCycles,
                reviewItems: dashboardReviewItems,
                now: now,
                calendar: .current
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
        if let unavailableGuidance = availableToSpendPresentation.unavailableGuidance {
            return unavailableGuidance
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
        switch availableToSpendPresentation {
        case .unavailable:
            return CalderaVisualStyle.primaryText(colorScheme)
        case .calculated(let safeToSpend):
            return safeToSpend >= 0
                ? CalderaVisualStyle.primaryText(colorScheme)
                : CalderaCategoryStyle.style(for: .shortfall).primary
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.panel) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    if let preferredDisplayName {
                        Text("\(greeting),")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

                        Text(preferredDisplayName)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    } else {
                        Text(greeting)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .accessibilityLabel(greeting)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: AppSpacing.xSmall)

                dashboardRefreshButton
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

                Text(
                    availableToSpendPresentation.amountText(
                        isSensitiveDataHidden: isSensitiveDataHidden
                    )
                )
                    .privacySensitive()
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(availableToSpendColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .accessibilityLabel("Available to Spend")
                    .accessibilityValue(
                        availableToSpendPresentation.accessibilityValue(
                            isSensitiveDataHidden: isSensitiveDataHidden
                        )
                    )

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

    private var dashboardRefreshButton: some View {
        Button {
            refreshDashboard()
        } label: {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.bold))
                    .symbolEffect(
                        .rotate,
                        options: .repeat(.continuous),
                        isActive: isDashboardRefreshInProgress
                    )

                Text("Refresh")
            }
            .font(.caption.weight(.bold))
            .foregroundColor(AppColors.accent)
            .padding(.horizontal, AppSpacing.medium)
            .frame(width: Layout.refreshButtonWidth)
            .frame(minHeight: 42)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.10)
                            : Color.white.opacity(0.82)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.16)
                                    : Color.white.opacity(0.72),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(isDashboardRefreshInProgress)
        .accessibilityLabel(
            DashboardRefreshPresentation.buttonTitle(
                isRefreshing: isDashboardRefreshInProgress
            )
        )
        .accessibilityHint("Refresh linked balances and recent activity.")
    }

    private func refreshDashboard() {
        switch DashboardRefreshPresentation.tapDecision(
            isSignedIn: auth.isSignedIn,
            hasLinkedAccounts: hasLinkedBanks,
            isRefreshing: isDashboardRefreshInProgress
        ) {
        case .signInRequired:
            dashboardRefreshNotice = .signInRequired

        case .linkAccountRequired:
            dashboardRefreshNotice = .linkAccountRequired

        case .startRefresh:
            plaid.refreshPlaidDataFromSettings()

        case .ignoreWhileRefreshing:
            break
        }
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
            progress: dashboardSetupProgress,
            isSigningIn: auth.isBusy,
            signInRequest: auth.configureAppleRequest,
            signInCompletion: auth.handleAppleCompletion,
            continueAction: continueDashboardSetup,
            markCompletedAction: markDashboardSetupStepCompleted
        )
    }

    private var dashboardCardsSection: some View {
        DashboardCardsSection(
            planStatusItems: [
                DashboardPlanStatusItem(
                    id: "total-set-aside",
                    title: "Set Aside",
                    value: AppFormatters.currency(
                        dashboardFinancialSummary.protectedMoney
                    ),
                    detail: "Total set aside",
                    style: CalderaCategoryStyle.style(for: .reserve),
                    systemImage: "wallet.pass.fill",
                    actionTitle: "Open Set Aside",
                    action: {
                        navigation.openSavings()
                    }
                ),
                DashboardPlanStatusItem(
                    id: "upcoming-expenses",
                    title: "Upcoming",
                    value: nextSevenDayUpcomingForecasts.isEmpty
                        ? "None"
                        : AppFormatters.currency(nextSevenDayUpcomingTotal),
                    detail: nextSevenDayUpcomingForecasts.isEmpty
                        ? "Next 7 days"
                        : nextSevenDayUpcomingForecasts.count == 1
                            ? "1 due in next 7 days"
                            : "\(nextSevenDayUpcomingForecasts.count) due in next 7 days",
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
                    title: "Payments",
                    value: activeOrLegacyPaymentPlans.isEmpty
                        ? AppFormatters.currency(0)
                        : AppFormatters.currency(totalDebtPayoffTarget),
                    detail: activeOrLegacyPaymentPlans.isEmpty
                        ? "No Payment Plans"
                        : activeOrLegacyPaymentPlans.count == 1
                            ? "1 Payment Plan target"
                            : "\(activeOrLegacyPaymentPlans.count) Payment Plan targets",
                    style: CalderaCategoryStyle.style(for: .debtPayoff),
                    systemImage: CalderaCategoryStyle.style(
                        for: .debtPayoff
                    ).icon,
                    actionTitle: "Open Payment Plans",
                    action: {
                        navigation.openSavings(section: .paymentPlans)
                    }
                )
            ],
            showsNextAction: !shouldShowSetupChecklist &&
                !plaid.isLoadingLinkedAccountsAfterAuthentication,
            nextAction: dashboardNextAction,
            isNextActionCollapsed: $isNextActionCollapsed,
            performNextAction: { action in
                perform(action)
            }
        )
    }

    private var dashboardWidgetGrid: some View {
        let preferences = DashboardWidgetPreferences(
            storedValue: storedDashboardWidgetPreferences
        )

        return DashboardWidgetGrid(
            snapshots: preferences.renderableSnapshots(
                from: dashboardWidgetSnapshots
            ),
            canPerform: canPerformDashboardWidgetAction,
            perform: performDashboardWidgetAction,
            customize: {
                presentedDashboardSheet = .widgetManager
            }
        )
    }

    private var unavailableDashboardWidgetKinds: Set<DashboardWidgetKind> {
        Set(
            dashboardWidgetSnapshots.orderedSnapshots.compactMap { snapshot in
                snapshot.contentState == .hidden ? snapshot.kind : nil
            }
        )
    }

    private func canPerformDashboardWidgetAction(
        _ action: DashboardWidgetAction
    ) -> Bool {
        switch action {
        case .openSetAside,
             .openBankSync,
             .openPlanAhead:
            return true

        case .openReviewUpdates:
            return !dashboardReviewItems.isEmpty

        case .openSavingsGoal(let goalID):
            return plaid.savingsGoals.contains { $0.id == goalID }

        case .openUpcomingExpense(let eventID, let occurrenceID):
            return upcomingExpenseForecasts.contains {
                $0.event.id == eventID &&
                    $0.occurrenceID == occurrenceID
            }

        case .openPaymentPlan:
            return DashboardWidgetActionResolver.paymentPlanEditorRoute(
                for: action,
                in: debtPayoffBuckets
            ) != nil
        }
    }

    private func performDashboardWidgetAction(
        _ action: DashboardWidgetAction
    ) {
        switch action {
        case .openSetAside:
            navigation.openSavings()

        case .openBankSync:
            navigation.openBankSync()

        case .openReviewUpdates:
            navigation.openReviewUpdates()

        case .openSavingsGoal(let goalID):
            navigation.openSavingsEditGoal(goalID)

        case .openUpcomingExpense(let eventID, let occurrenceID):
            navigation.openTimelineEditUpcomingExpense(
                eventID: eventID,
                occurrenceID: occurrenceID
            )

        case .openPaymentPlan(let bucketID, let cycleID):
            guard DashboardWidgetActionResolver.paymentPlanEditorRoute(
                for: action,
                in: debtPayoffBuckets
            ) != nil else {
                return
            }

            navigation.openSavingsEditDebtPayoff(
                bucketID,
                cycleID: cycleID
            )

        case .openPlanAhead:
            navigation.selectedTab = 2
        }
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
                candidate.paymentPlanID,
                cycleID: candidate.cycleID
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

    private func continueDashboardSetup(
        _ step: DashboardSetupStep
    ) {
        switch step.destination {
        case nil,
             .signInWithApple:
            break

        case .linkedAccounts:
            if step.expandsLinkedCashAccountGroups {
                navigation.expandChecking = true
                navigation.expandSavings = true
            }
            showsLinkedAccountsSetup = true

        case .setAside:
            navigation.openSavings()

        case .addUpcomingExpense:
            navigation.openTimelineCreateExpense()
        }
    }

    private func markDashboardSetupStepCompleted(
        _ step: DashboardSetupStep
    ) {
        manuallyCompletedSetupSteps =
            DashboardSetupManualCompletionPreference.markingCurrentStepCompleted(
                step,
                in: dashboardSetupProgress,
                storedValue: manuallyCompletedSetupSteps
            )
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

private struct DashboardVerticalScrollConfigurator: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        configureEnclosingScrollView(from: uiView)

        DispatchQueue.main.async { [weak uiView] in
            guard let uiView else {
                return
            }

            configureEnclosingScrollView(from: uiView)
        }
    }

    private func configureEnclosingScrollView(from view: UIView) {
        guard let scrollView = enclosingScrollView(from: view) else {
            return
        }

        scrollView.isDirectionalLockEnabled = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.bouncesHorizontally = false
        scrollView.showsHorizontalScrollIndicator = false

        guard !scrollView.isTracking, !scrollView.isDragging else {
            return
        }

        let horizontalOrigin = -scrollView.adjustedContentInset.left
        guard abs(scrollView.contentOffset.x - horizontalOrigin) > 0.5 else {
            return
        }

        scrollView.contentOffset.x = horizontalOrigin
    }

    private func enclosingScrollView(from view: UIView) -> UIScrollView? {
        var ancestor = view.superview

        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }

            ancestor = current.superview
        }

        return nil
    }
}
