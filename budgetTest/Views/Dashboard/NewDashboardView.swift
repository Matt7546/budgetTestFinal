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

    @State private var selectedGoal: SavingsGoal?
    @State private var selectedExpense: ForecastEvent?
    @State private var showsAvailableInsights = false
    @State private var showsLinkedAccountsSetup = false
    @State private var confirmationMessage: String?
    @State private var confirmationID = UUID()

    @AppStorage(AppPersonalizationKeys.preferredName)
    private var preferredName = ""

    private enum Layout {
        static let pageHorizontalPadding = AppSpacing.regular
        static let metricMinimumColumnWidth: CGFloat = 156
    }

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            ScrollView {
                VStack(spacing: AppSpacing.screen) {
                    heroSection

                    if shouldShowSetupChecklist {
                        setupChecklistCard
                    } else {
                        dashboardNextActionCard

                        if hasIncompleteOptionalSetupSteps {
                            setupChecklistCard
                        }
                    }

                    DashboardMetricPair(
                        minimumColumnWidth: Layout.metricMinimumColumnWidth
                    ) {
                        protectedMetricCard
                    } trailing: {
                        upcomingExpenseMetricCard
                    }

                    goalsCard

                    upcomingExpensesCard
                }
                .padding(.horizontal, Layout.pageHorizontalPadding)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.floatingTabClearance)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calderaConfirmationOverlay(message: confirmationMessage)
        .navigationTitle(showsNavigationTitle ? "New Dashboard" : "")
        .navigationBarTitleDisplayMode(.inline)
        .calderaTransparentNavigationSurface()
        .sheet(item: $selectedGoal) { goal in
            EditGoalView(
                goal: goal,
                onSaved: { _ in
                    showConfirmation("Goal updated.")
                },
                onDeleted: {
                    showConfirmation("Goal deleted.")
                }
            )
            .environmentObject(plaid)
        }
        .sheet(item: $selectedExpense) { forecast in
            EventAllocationDetailView(forecast: forecast) {
                selectedExpense = nil
            }
        }
        .sheet(isPresented: $showsAvailableInsights) {
            AvailableToSpendInsightsSheet(
                summary: dashboardFinancialSummary,
                canShowBankData: canShowBankData,
                hasBankAccounts: !visibleBankAccounts.isEmpty
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
            accounts: visibleBankAccounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance
        )
    }

    private var dashboardFinancialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: visibleBankAccounts,
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

    private var displayedSafeToSpend: Double {
        canShowBankData ? dashboardFinancialSummary.safeToSpend : 0
    }

    private var hasLinkedBanks: Bool {
        !visibleBankAccounts.isEmpty
    }

    private var hasBankRefreshWarning: Bool {
        guard hasLinkedBanks else {
            return false
        }

        if let message = plaid.accountRefreshMessage?.lowercased(),
           message.contains("refresh") {
            return true
        }

        if let message = plaid.manualPlaidRefreshMessage?.lowercased(),
           message.contains("refresh failed") || message.contains("need refreshing") {
            return true
        }

        return false
    }

    private var bankRefreshStatusText: String? {
        guard canShowBankData,
              hasLinkedBanks else {
            return nil
        }

        if plaid.isRefreshingPlaidData {
            return "Refreshing balances…"
        }

        if hasBankRefreshWarning {
            return "Some balances may need refreshing. Showing last saved balances."
        }

        if plaid.accountsLastUpdatedText == "Not refreshed yet" {
            return "Balances not refreshed yet"
        }

        return plaid.accountsLastUpdatedText.replacingOccurrences(
            of: "Last refreshed",
            with: "Updated"
        )
    }

    private var bankRefreshStatusIcon: String {
        if hasBankRefreshWarning {
            return "wifi.exclamationmark"
        }

        return plaid.isRefreshingPlaidData
            ? "arrow.clockwise.circle.fill"
            : "checkmark.circle.fill"
    }

    private var bankRefreshStatusColor: Color {
        if hasBankRefreshWarning {
            return CalderaCategoryStyle.style(for: .needsMoney).primary
        }

        return plaid.isRefreshingPlaidData
            ? CalderaCategoryStyle.style(for: .bankAccount).primary
            : CalderaCategoryStyle.style(for: .covered).primary
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

    private var firstPaymentPlanNeedingMoney: DebtPayoffBucket? {
        debtPayoffBuckets.first { bucket in
            bucket.paymentTargetAmount > 0 &&
                bucket.protectedAmount + 0.005 < bucket.paymentTargetAmount
        }
    }

    private var firstPaymentPlanWithSuggestedUpdate: DebtPayoffBucket? {
        debtPayoffBuckets.first { bucket in
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

        return paymentTargetSuggestionExists(
            amount: card.last_statement_balance,
            for: bucket
        ) || paymentTargetSuggestionExists(
            amount: card.minimum_payment_amount,
            for: bucket
        ) || paymentTargetSuggestionExists(
            amount: card.current_balance,
            for: bucket
        ) || dueDateSuggestionExists(
            card.next_payment_due_date,
            for: bucket
        )
    }

    private func paymentTargetSuggestionExists(
        amount: Double?,
        for bucket: DebtPayoffBucket
    ) -> Bool {
        guard let amount,
              amount > 0 else {
            return false
        }

        return !moneyValuesMatch(
            bucket.paymentTargetAmount,
            amount
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

    private func moneyValuesMatch(
        _ lhs: Double,
        _ rhs: Double
    ) -> Bool {
        abs(lhs - rhs) < 0.005
    }

    private var dashboardNextAction: DashboardNextAction {
        if hasBankRefreshWarning {
            return .bankSync
        }

        if firstPaymentPlanWithSuggestedUpdate != nil {
            return .suggestedUpdate
        }

        if let forecast = firstUpcomingExpenseNeedingMoney {
            return .upcomingNeedsMoney(forecast)
        }

        if firstPaymentPlanNeedingMoney != nil {
            return .paymentPlanNeedsMoney
        }

        return .allClear
    }

    private var shouldShowPlanningReassurance: Bool {
        canShowBankData &&
            hasLinkedBanks &&
            !hasBankRefreshWarning &&
            !shouldShowSetupChecklist &&
            !upcomingExpenseForecasts.isEmpty &&
            !hasUpcomingExpenseNeedingAttention
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
        if !canShowBankData {
            return "Sign in and link accounts to estimate from your balances."
        }

        if !hasLinkedBanks {
            return "Link accounts to estimate from your balances."
        }

        return dashboardFinancialSummary.safeToSpend >= 0
            ? "Cash left after set-asides."
            : "Your planned set-aside money is higher than your current available cash."
    }

    private var protectedMetricCaption: String {
        totalDebtPayoffSetAside > 0
            ? "Cash Cushion, Goals, Upcoming Expenses, and Payment Plans"
            : "Cash Cushion, Goals, and Upcoming Expenses"
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

    private var dashboardNextActionCard: some View {
        let nextAction = dashboardNextAction
        let style = nextAction.style

        return HStack(alignment: .top, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: style,
                size: 42,
                iconSize: 17
            )

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Next Action")
                    .font(.caption.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.tertiaryText(colorScheme))
                    .textCase(.uppercase)

                Text(nextAction.title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                Text(nextAction.message)
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle = nextAction.actionTitle {
                    Button {
                        perform(nextAction)
                    } label: {
                        HStack(spacing: AppSpacing.xSmall) {
                            Text(actionTitle)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(style.primary)
                        .padding(.horizontal, AppSpacing.regular)
                        .padding(.vertical, AppSpacing.xSmall)
                        .background(
                            Capsule(style: .continuous)
                                .fill(style.primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.xSmall)
                    .accessibilityLabel(actionTitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.88,
            strokeOpacity: 0.72,
            shadowOpacity: 0.026,
            shadowRadius: 14,
            shadowY: 6,
            darkGlowColor: style.primary
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next Action. \(nextAction.title). \(nextAction.message)")
    }

    private func perform(
        _ nextAction: DashboardNextAction
    ) {
        switch nextAction {
        case .bankSync:
            showsLinkedAccountsSetup = true

        case .suggestedUpdate,
             .paymentPlanNeedsMoney:
            navigation.selectedTab = 1

        case .upcomingNeedsMoney(let forecast):
            selectedExpense = forecast

        case .allClear:
            break
        }
    }

    private var planningReassuranceCard: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: CalderaCategoryStyle.style(for: .covered),
                size: 38,
                iconSize: 16
            )

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("You’re set for now.")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text("Your Upcoming Expenses are covered based on your current setup.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.88,
            strokeOpacity: 0.72,
            shadowOpacity: 0.026,
            shadowRadius: 14,
            shadowY: 6,
            darkGlowColor: CalderaCategoryStyle.style(for: .covered).primary
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You’re set for now. Your Upcoming Expenses are covered based on your current setup.")
    }

    private var protectedMetricCard: some View {
        Button {
            navigation.selectedTab = 1
        } label: {
            DashboardMetricCard {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                metricHeader(
                    title: "Set Aside",
                    style: CalderaCategoryStyle.style(for: .reserve)
                )

                Text(AppFormatters.currency(dashboardFinancialSummary.protectedMoney))
                    .font(.title3.bold())
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .monospacedDigit()

                Text(protectedMetricCaption)
                    .font(.caption)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

                CalderaProgressBar(
                    progress: protectedProgress,
                    colors: CalderaCategoryStyle.style(for: .reserve).gradient
                )

                Text("\(Int(protectedProgress * 100))% toward plans")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .reserve).primary)
            }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Set Aside")
    }

    private var upcomingExpenseMetricCard: some View {
        Button {
            navigation.selectedTab = 2
        } label: {
            DashboardMetricCard {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                metricHeader(
                    title: "Coming Up",
                    style: CalderaCategoryStyle.style(for: .upcomingExpense)
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(nextExpense?.event.name ?? "Nothing coming up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                    Text(nextExpense.map { AppFormatters.currency($0.event.amount) } ?? "You're clear")
                        .font(.title3.bold())
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .monospacedDigit()

                    Text(nextExpense.map { upcomingExpenseStatusText(for: $0) } ?? "Add an expense when you want it reflected in your plan.")
                        .font(.caption)
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                }

                Text("View all upcoming")
                    .font(.caption.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .upcomingExpense).primary)
            }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Timeline upcoming expenses")
    }

    private var goalsCard: some View {
        DashboardSectionCard(
            title: "Goals",
            style: CalderaCategoryStyle.style(for: .savingsGoal),
            seeAllAction: {
                navigation.selectedTab = 1
            },
            emptyTitle: "Nothing planned here yet",
            emptySubtitle: "Create a goal for something you want to set money aside for.",
            emptySystemImage: "target",
            rows: visibleGoals.map(goalRow)
        )
    }

    private var upcomingExpensesCard: some View {
        DashboardSectionCard(
            title: "Upcoming Expenses",
            style: CalderaCategoryStyle.style(for: .upcomingExpense),
            seeAllAction: {
                navigation.selectedTab = 2
            },
            emptyTitle: "Nothing planned here yet",
            emptySubtitle: "Add an upcoming expense when you want Caldera to help keep it visible.",
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
            style: CalderaCategoryStyle.style(for: .savingsGoal),
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
        let remainingAmount = remainingAmount(for: forecast)
        let trailing = remainingAmount <= 0.005
            ? "Covered"
            : "Still needs \(AppFormatters.currency(remainingAmount))"

        return DashboardRow(
            id: forecast.id,
            title: forecast.event.name,
            subtitle: dueTimingText(for: forecast.occurrenceDate),
            amount: AppFormatters.currency(forecast.event.amount),
            trailing: trailing,
            style: CalderaCategoryStyle.style(for: .upcomingExpense),
            trailingStyle: remainingAmount <= 0.005
                ? CalderaCategoryStyle.style(for: .covered)
                : CalderaCategoryStyle.style(for: .needsMoney),
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
        let remainingAmount = remainingAmount(for: forecast)
        let status = remainingAmount <= 0.005
            ? "Covered"
            : "Still needs \(AppFormatters.currency(remainingAmount))"

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

    private func remainingAmount(
        for forecast: ForecastEvent
    ) -> Double {
        max(
            forecast.event.amount - allocatedAmount(for: forecast),
            0
        )
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

    private func metricHeader(
        title: String,
        style: CalderaCategoryStyle
    ) -> some View {
        HStack(spacing: AppSpacing.small) {
            CalderaGradientIcon(
                style: style,
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

private struct DashboardMetricPair<Leading: View, Trailing: View>: View {

    let minimumColumnWidth: CGFloat
    let leading: Leading
    let trailing: Trailing

    @State private var equalizedHeight: CGFloat = 0

    init(
        minimumColumnWidth: CGFloat,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.minimumColumnWidth = minimumColumnWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                leading
                    .frame(minWidth: minimumColumnWidth)
                    .frame(maxWidth: .infinity)
                    .measureDashboardMetricCardHeight()
                    .frame(
                        minHeight: safeEqualizedHeight,
                        alignment: .top
                    )

                trailing
                    .frame(minWidth: minimumColumnWidth)
                    .frame(maxWidth: .infinity)
                    .measureDashboardMetricCardHeight()
                    .frame(
                        minHeight: safeEqualizedHeight,
                        alignment: .top
                    )
            }
            .onPreferenceChange(DashboardMetricCardHeightKey.self) { height in
                guard height.isFinite,
                      height > 0,
                      abs(height - equalizedHeight) > 0.5 else {
                    return
                }

                equalizedHeight = height
            }

            VStack(spacing: AppSpacing.medium) {
                leading
                trailing
            }
        }
    }

    private var safeEqualizedHeight: CGFloat? {
        guard equalizedHeight.isFinite,
              equalizedHeight > 0 else {
            return nil
        }

        return equalizedHeight
    }
}

private struct DashboardMetricCardHeightKey: PreferenceKey {

    static var defaultValue: CGFloat = 0

    static func reduce(
        value: inout CGFloat,
        nextValue: () -> CGFloat
    ) {
        let next = nextValue()
        guard next.isFinite,
              next > 0 else {
            return
        }

        value = max(value, next)
    }
}

private extension View {

    func measureDashboardMetricCardHeight() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DashboardMetricCardHeightKey.self,
                    value: safeDashboardMetricHeight(proxy.size.height)
                )
            }
        }
    }

    private func safeDashboardMetricHeight(
        _ height: CGFloat
    ) -> CGFloat {
        guard height.isFinite,
              height > 0 else {
            return 0
        }

        return height
    }
}

private struct DashboardMetricCard<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
            .padding(AppSpacing.regular)
            .calderaGlassCard(
                cornerRadius: 24,
                fillOpacity: 0.84,
                strokeOpacity: 0.68,
                shadowOpacity: 0.026,
                shadowRadius: 14,
                shadowY: 6
            )
    }
}

private struct DashboardSectionCard: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let style: CalderaCategoryStyle
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
                        .foregroundColor(style.primary)
                }
                .buttonStyle(.plain)
            }

            if rows.isEmpty {
                DashboardEmptyRow(
                    title: emptyTitle,
                    subtitle: emptySubtitle,
                    systemImage: emptySystemImage,
                    style: style
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
            fillOpacity: 0.84,
            strokeOpacity: 0.68,
            shadowOpacity: 0.026,
            shadowRadius: 14,
            shadowY: 6
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
                        style: row.style,
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
                            .foregroundColor(row.trailingStyle.primary)
                            .lineLimit(1)
                    }
                }

                CalderaProgressBar(
                    progress: row.progress,
                    colors: row.style.gradient
                )
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
    let style: CalderaCategoryStyle

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: style.gradient,
                size: 32,
                iconSize: 13
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
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: 20,
            fillOpacity: 0.78,
            strokeOpacity: 0.58,
            shadowOpacity: 0.025,
            shadowRadius: 12,
            shadowY: 5,
            darkGlowColor: style.primary
        )
        .accessibilityElement(children: .combine)
    }
}


private enum DashboardNextAction {

    case bankSync
    case suggestedUpdate
    case upcomingNeedsMoney(ForecastEvent)
    case paymentPlanNeedsMoney
    case allClear

    var title: String {
        switch self {
        case .bankSync:
            return "Check Bank Sync"

        case .suggestedUpdate:
            return "Review suggested update"

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

        case .suggestedUpdate:
            return "Caldera found card details that may help update a payment plan."

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

        case .suggestedUpdate:
            return "Review suggested update"

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
        case .bankSync:
            return CalderaCategoryStyle.style(for: .bankAccount)

        case .suggestedUpdate:
            return CalderaCategoryStyle.style(for: .debtPayoff)

        case .upcomingNeedsMoney,
             .paymentPlanNeedsMoney:
            return CalderaCategoryStyle.style(for: .needsMoney)

        case .allClear:
            return CalderaCategoryStyle.style(for: .covered)
        }
    }
}

private struct DashboardRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let amount: String
    let trailing: String
    let style: CalderaCategoryStyle
    var trailingStyle: CalderaCategoryStyle {
        trailingStyleOverride ?? style
    }
    let trailingStyleOverride: CalderaCategoryStyle?
    let progress: Double
    let action: (() -> Void)?

    init(
        id: String,
        title: String,
        subtitle: String,
        amount: String,
        trailing: String,
        style: CalderaCategoryStyle,
        trailingStyle: CalderaCategoryStyle? = nil,
        progress: Double,
        action: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.amount = amount
        self.trailing = trailing
        self.style = style
        self.trailingStyleOverride = trailingStyle
        self.progress = progress
        self.action = action
    }
}
