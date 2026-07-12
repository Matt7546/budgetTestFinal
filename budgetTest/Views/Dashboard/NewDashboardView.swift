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

    private var firstUnresolvedPastDueExpense: ForecastEvent? {
        ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
            from: forecastCalculator.forecastEvents,
            statuses: occurrenceStatuses
        )
        .first
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

    private var sortedPaymentPlans: [DebtPayoffBucket] {
        activeOrLegacyPaymentPlans.sorted {
            if Calendar.current.isDate($0.dueDate, inSameDayAs: $1.dueDate) {
                return $0.accountName.localizedCaseInsensitiveCompare($1.accountName) == .orderedAscending
            }

            return $0.dueDate < $1.dueDate
        }
    }

    private var relevantPaymentPlan: DebtPayoffBucket? {
        let today = Calendar.current.startOfDay(for: Date())

        return sortedPaymentPlans.first {
            Calendar.current.startOfDay(for: $0.dueDate) >= today
        } ?? sortedPaymentPlans.first
    }

    private var paymentPlansDueSoonCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.date(
            byAdding: .day,
            value: 30,
            to: today
        ) ?? today

        return sortedPaymentPlans.filter {
            guard $0.shouldDisplayDueDate else {
                return false
            }

            let date = calendar.startOfDay(for: $0.dueDate)
            return date >= today && date <= end
        }
        .count
    }

    private var totalDebtPayoffTarget: Double {
        activeOrLegacyPaymentPlans.reduce(0) {
            $0 + max($1.paymentTargetAmount, $1.protectedAmount)
        }
    }

    private var savingsGoalsCurrentAmount: Double {
        plaid.savingsGoals.totalSaved
    }

    private var savingsGoalsTargetAmount: Double {
        plaid.savingsGoals.totalTarget
    }

    private var firstPaymentPlanWithSuggestedUpdate: DebtPayoffBucket? {
        activeOrLegacyPaymentPlans.first { bucket in
            paymentPlanHasSuggestedUpdate(bucket)
        }
    }

    private func paymentPlanHasSuggestedUpdate(
        _ bucket: DebtPayoffBucket
    ) -> Bool {
        guard bucket.isLinkedCreditCard,
              !bucket.plaidAccountID.isEmpty,
              let card = plaid.cardPaymentDetails.first(where: {
                  $0.account_id == bucket.plaidAccountID
              }) else {
            return false
        }

        return statementTargetSuggestionExists(
            card: card,
            for: bucket
        ) || paymentTargetSuggestionExists(
            kind: .minimumPayment,
            amount: card.minimum_payment_amount,
            for: bucket
        ) || paymentTargetSuggestionExists(
            kind: .currentBalance,
            amount: card.current_balance,
            for: bucket
        ) || dueDateSuggestionExists(
            card.next_payment_due_date,
            for: bucket
        )
    }

    private func statementTargetSuggestionExists(
        card: LinkedCardPaymentDetails,
        for bucket: DebtPayoffBucket
    ) -> Bool {
        PaymentPlanSuggestedUpdateRules.statementSuggestionReason(
            liveStatementBalance: card.last_statement_balance,
            liveStatementIssueDate: PaymentPlanStatementIssueDate.parse(
                card.last_statement_issue_date
            ),
            storedChoice: bucket.paymentTargetChoice,
            currentTarget: bucket.paymentTargetAmount,
            storedStatementIssueDate: bucket.targetStatementIssueDate
        ) != nil
    }

    private func paymentTargetSuggestionExists(
        kind: PaymentPlanLiveAmountKind,
        amount: Double?,
        for bucket: DebtPayoffBucket
    ) -> Bool {
        PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
            kind: kind,
            liveAmount: amount,
            storedChoice: bucket.paymentTargetChoice,
            currentTarget: bucket.paymentTargetAmount
        )
    }

    private func dueDateSuggestionExists(
        _ value: String?,
        for bucket: DebtPayoffBucket
    ) -> Bool {
        guard bucket.shouldDisplayDueDate,
              let cardDueDate = parsedCardPaymentDueDate(value) else {
            return false
        }

        return !Calendar.current.isDate(
            cardDueDate,
            inSameDayAs: bucket.dueDate
        )
    }

    private var dashboardNextAction: DashboardNextAction {
        DashboardNextActionPriority.resolve(
            hasBankRefreshWarning: hasBankRefreshWarning,
            needsAccountScope: hasLinkedBanks &&
                !visibleBankAccounts.cashAccounts.isEmpty &&
                !hasIncludedCashAccounts,
            pastDueExpense: firstUnresolvedPastDueExpense,
            hasSuggestedUpdate: firstPaymentPlanWithSuggestedUpdate != nil,
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
                    HStack(spacing: AppSpacing.xSmall) {
                        Image(systemName: bankRefreshStatusIcon)
                            .font(.caption.weight(.bold))
                            .foregroundColor(bankRefreshStatusColor)

                        Text(bankRefreshStatusText)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, AppSpacing.xxSmall)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Bank data \(bankRefreshStatusText)")
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
            setAsideMetric: DashboardCardsMetric(
                title: "Set Aside",
                value: AppFormatters.currency(dashboardFinancialSummary.protectedMoney),
                subtitle: "Includes Cash Cushion",
                style: CalderaCategoryStyle.style(for: .reserve),
                systemImage: "wallet.pass.fill"
            ),
            upcomingMetric: DashboardCardsMetric(
                title: "Upcoming",
                value: nextSevenDayUpcomingForecasts.isEmpty
                    ? "None"
                    : AppFormatters.currency(nextSevenDayUpcomingTotal),
                subtitle: nextSevenDayUpcomingForecasts.isEmpty
                    ? "Next 7 days"
                    : "\(nextSevenDayUpcomingForecasts.count) due soon",
                style: CalderaCategoryStyle.style(for: .upcomingExpense),
                systemImage: CalderaCategoryStyle.style(for: .upcomingExpense).icon
            ),
            paymentsMetric: DashboardCardsMetric(
                title: "Payments",
                value: activeOrLegacyPaymentPlans.isEmpty
                    ? AppFormatters.currency(0)
                    : AppFormatters.currency(totalDebtPayoffTarget),
                subtitle: activeOrLegacyPaymentPlans.isEmpty
                    ? "No plans"
                    : "Payment targets",
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                systemImage: CalderaCategoryStyle.style(for: .debtPayoff).icon
            ),
            showsNextAction: !shouldShowSetupChecklist &&
                !plaid.isLoadingLinkedAccountsAfterAuthentication,
            nextAction: dashboardNextAction,
            performNextAction: { action in
                perform(action)
            },
            comingUp: dashboardComingUpCardItem,
            paymentPlan: dashboardPaymentPlanCardItem,
            bankSyncChangeSummary: plaid.latestBankSyncChangeSummary,
            openBankSync: {
                showsLinkedAccountsSetup = true
            },
            goalsProgress: DashboardGoalsProgressSummary(
                currentAmount: savingsGoalsCurrentAmount,
                targetAmount: savingsGoalsTargetAmount,
                hasGoals: !plaid.savingsGoals.isEmpty
            ),
            openGoals: {
                navigation.openSavings()
            }
        )
    }

    private var dashboardComingUpCardItem: DashboardCardsMiniItem? {
        guard let forecast = nextExpense else {
            return nil
        }

        let remainingAmount = remainingAmount(for: forecast)
        let style = CalderaCategoryStyle.style(for: .upcomingExpense)

        return DashboardCardsMiniItem(
            systemImage: style.icon,
            style: style,
            title: forecast.event.name,
            subtitle: dueTimingText(for: forecast.occurrenceDate),
            value: AppFormatters.currency(forecast.event.amount),
            badge: remainingAmount <= 0.005
                ? "Covered"
                : "Still needs \(AppFormatters.currency(remainingAmount))",
            badgeStyle: remainingAmount <= 0.005
                ? CalderaCategoryStyle.style(for: .covered)
                : CalderaCategoryStyle.style(for: .needsMoney),
            actionTitle: "Details",
            action: {
                selectedExpense = forecast
            }
        )
    }

    private var dashboardPaymentPlanCardItem: DashboardCardsMiniItem? {
        guard let bucket = relevantPaymentPlan else {
            return nil
        }

        let remainingAmount = paymentPlanRemainingAmount(for: bucket)
        let style = CalderaCategoryStyle.style(for: .debtPayoff)

        return DashboardCardsMiniItem(
            systemImage: style.icon,
            style: style,
            title: paymentPlanTitle(for: bucket),
            subtitle: bucket.shouldDisplayDueDate
                ? "Due \(AppFormatters.abbreviatedMonthDay(bucket.dueDate))"
                : "Due date not set",
            value: AppFormatters.currency(max(bucket.paymentTargetAmount, bucket.protectedAmount)),
            badge: paymentPlanStatusText(for: bucket),
            badgeStyle: remainingAmount <= 0.005
                ? CalderaCategoryStyle.style(for: .covered)
                : CalderaCategoryStyle.style(for: .needsMoney),
            actionTitle: "Plan",
            action: {
                navigation.openSavingsEditDebtPayoff(bucket.id)
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

        case .upcomingNeedsMoney(let forecast):
            selectedExpense = forecast

        case .pastDueExpense(let forecast):
            selectedExpense = forecast

        case .allClear:
            break
        }
    }

    private func paymentPlanRemainingAmount(
        for bucket: DebtPayoffBucket
    ) -> Double {
        max(
            bucket.paymentTargetAmount - bucket.protectedAmount,
            0
        )
    }

    private func paymentPlanStatusText(
        for bucket: DebtPayoffBucket
    ) -> String {
        let remainingAmount = paymentPlanRemainingAmount(for: bucket)

        return remainingAmount <= 0.005
            ? "Covered"
            : "Still needs \(AppFormatters.currency(remainingAmount))"
    }

    private func paymentPlanTitle(
        for bucket: DebtPayoffBucket
    ) -> String {
        let trimmedName = bucket.accountName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if !trimmedName.isEmpty {
            return trimmedName
        }

        if let account = visibleBankAccounts.first(where: {
            $0.account_id == bucket.plaidAccountID
        }) {
            return account.name
        }

        return bucket.isLinkedCreditCard ? "Credit Card" : "Payment Plan"
    }

    private func allocatedAmount(
        for forecast: ForecastEvent
    ) -> Double {
        allocations.first {
            $0.occurrenceID == forecast.occurrenceID
        }?
        .allocatedAmount ?? 0
    }

    private func remainingAmount(
        for forecast: ForecastEvent
    ) -> Double {
        max(
            forecast.event.amount - allocatedAmount(for: forecast),
            0
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

    private func parsedCardPaymentDueDate(
        _ value: String?
    ) -> Date? {
        guard let value,
              !value.isEmpty else {
            return nil
        }

        return Self.cardPaymentDueDateFormatter.date(from: value)
    }

    private static let cardPaymentDueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

}

enum DashboardNextActionPriority {

    static func resolve(
        hasBankRefreshWarning: Bool,
        needsAccountScope: Bool,
        pastDueExpense: ForecastEvent?,
        hasSuggestedUpdate: Bool,
        upcomingExpenseNeedingMoney: ForecastEvent?,
        hasPaymentPlanNeedingMoney: Bool
    ) -> DashboardNextAction {
        if hasBankRefreshWarning {
            return .bankSync
        }

        if needsAccountScope {
            return .accountScope
        }

        if let pastDueExpense {
            return .pastDueExpense(pastDueExpense)
        }

        if hasSuggestedUpdate {
            return .suggestedUpdate
        }

        if let upcomingExpenseNeedingMoney {
            return .upcomingNeedsMoney(upcomingExpenseNeedingMoney)
        }

        if hasPaymentPlanNeedingMoney {
            return .paymentPlanNeedsMoney
        }

        return .allClear
    }
}

enum DashboardNextAction {

    case bankSync
    case accountScope
    case suggestedUpdate
    case pastDueExpense(ForecastEvent)
    case upcomingNeedsMoney(ForecastEvent)
    case paymentPlanNeedsMoney
    case allClear

    var title: String {
        switch self {
        case .bankSync:
            return "Check Bank Sync"

        case .accountScope:
            return "Choose cash accounts"

        case .suggestedUpdate:
            return "Review suggested update"

        case .pastDueExpense:
            return "Review past-due expense"

        case .upcomingNeedsMoney,
             .paymentPlanNeedsMoney:
            return "Still needs money"

        case .allClear:
            return "You're set for now"
        }
    }

    var message: String {
        switch self {
        case .bankSync:
            return "Some balances may need refreshing before your spending picture is complete."

        case .accountScope:
            return "No linked cash accounts are currently counted in Available to Spend."

        case .suggestedUpdate:
            return "Caldera found card details that may help update a payment plan."

        case .pastDueExpense(let forecast):
            return "\(forecast.event.name) was due \(AppFormatters.abbreviatedMonthDay(forecast.occurrenceDate)). Review what happened and update your plan."

        case .upcomingNeedsMoney:
            return "One planned item needs more set aside."

        case .paymentPlanNeedsMoney:
            return "One payment plan needs more set aside."

        case .allClear:
            return "Your planned expenses are covered based on your current setup."
        }
    }

    var actionTitle: String? {
        switch self {
        case .bankSync:
            return "Check Bank Sync"

        case .accountScope:
            return "Review Bank Sync"

        case .suggestedUpdate:
            return "Review suggested update"

        case .pastDueExpense:
            return "Review expense"

        case .upcomingNeedsMoney:
            return "Set Aside"

        case .paymentPlanNeedsMoney:
            return "Open Set Aside"

        case .allClear:
            return nil
        }
    }

    var style: CalderaCategoryStyle {
        switch self {
        case .bankSync,
             .accountScope:
            return CalderaCategoryStyle.style(for: .bankAccount)

        case .suggestedUpdate:
            return CalderaCategoryStyle.style(for: .debtPayoff)

        case .pastDueExpense,
             .upcomingNeedsMoney,
             .paymentPlanNeedsMoney:
            return CalderaCategoryStyle.style(for: .needsMoney)

        case .allClear:
            return CalderaCategoryStyle.style(for: .covered)
        }
    }

    var icon: String {
        switch self {
        case .bankSync,
             .accountScope:
            return "building.columns.fill"

        case .suggestedUpdate:
            return "creditcard.fill"

        case .pastDueExpense,
             .upcomingNeedsMoney,
             .paymentPlanNeedsMoney:
            return "calendar.badge.exclamationmark"

        case .allClear:
            return "checkmark.circle.fill"
        }
    }
}
