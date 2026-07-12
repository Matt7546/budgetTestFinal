#if DEBUG

import SwiftUI
import SwiftData

struct LabDashboardCardsPrototypeView: View {

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var plaid: PlaidService
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPersonalizationKeys.preferredName) private var preferredName = ""

    @Query private var events: [PlannerEvent]
    @Query private var allocations: [EventAllocation]
    @Query private var occurrenceStatuses: [ExpenseOccurrenceStatus]
    @Query private var debtPayoffBuckets: [DebtPayoffBucket]

    @State private var showsAvailableInsights = false

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
            upcomingExpensesSetAside: activeUpcomingSetAside,
            debtPaymentsSetAside: totalPaymentPlanSetAside
        )
    }

    private var displayedSafeToSpend: Double {
        canShowBankData ? dashboardFinancialSummary.safeToSpend : 0
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

    private var bankRefreshStatusText: String? {
        guard canShowBankData,
              hasLinkedBanks else {
            return nil
        }

        if plaid.isRefreshingPlaidData {
            return "Refreshing balances..."
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

    private var availableToSpendColor: Color {
        displayedSafeToSpend >= 0
            ? CalderaVisualStyle.primaryText(colorScheme)
            : CalderaCategoryStyle.style(for: .shortfall).primary
    }

    private var totalPaymentPlanSetAside: Double {
        debtPayoffBuckets.totalProtectedAmount
    }

    private var totalPaymentPlanTarget: Double {
        debtPayoffBuckets.reduce(0) {
            $0 + max($1.paymentTargetAmount, $1.protectedAmount)
        }
    }

    private var safeToSpendBeforeUpcomingAfterPaymentPlans: Double {
        baseFinancialSummary.safeToSpendBeforeUpcomingExpenses - totalPaymentPlanSetAside
    }

    private var inactiveOccurrenceIDs: Set<String> {
        ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: occurrenceStatuses
        )
    }

    private var baseForecastEvents: [ForecastEvent] {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: safeToSpendBeforeUpcomingAfterPaymentPlans,
            totalGoalAllocated: baseFinancialSummary.savingsGoalsSetAside,
            reserveBalance: baseFinancialSummary.reserve,
            includeFutureIncome: true,
            protectGoals: true,
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
        .forecastEvents
    }

    private var activeUpcomingSetAside: Double {
        FinancialSummaryCalculator.activeUpcomingExpensesSetAside(
            allocations: allocations,
            forecastEvents: baseForecastEvents
        )
    }

    private var forecastCalculator: PlannerForecastCalculator {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: safeToSpendBeforeUpcomingAfterPaymentPlans,
            totalGoalAllocated: baseFinancialSummary.savingsGoalsSetAside,
            reserveBalance: baseFinancialSummary.reserve,
            protectedEventAllocations: activeUpcomingSetAside,
            includeFutureIncome: true,
            protectGoals: true,
            allocatedAmountProvider: { forecast in
                allocatedAmount(for: forecast)
            },
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
    }

    private var upcomingExpenseForecasts: [ForecastEvent] {
        let today = Calendar.current.startOfDay(for: Date())

        return forecastCalculator.forecastEvents
            .filter { $0.event.type == .expense }
            .filter {
                Calendar.current.startOfDay(for: $0.occurrenceDate) >= today
            }
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

    private var nearestUpcomingExpense: ForecastEvent? {
        upcomingExpenseForecasts.first
    }

    private var firstUpcomingExpenseNeedingMoney: ForecastEvent? {
        upcomingExpenseForecasts.first {
            remainingAmount(for: $0) > 0.005
        }
    }

    private var sortedPaymentPlans: [DebtPayoffBucket] {
        debtPayoffBuckets.sorted {
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

    private var firstPaymentPlanNeedingMoney: DebtPayoffBucket? {
        sortedPaymentPlans.first { bucket in
            paymentPlanRemainingAmount(for: bucket) > 0.005
        }
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

    private var firstPaymentPlanWithSuggestedUpdate: DebtPayoffBucket? {
        sortedPaymentPlans.first {
            paymentPlanHasSuggestedUpdate($0)
        }
    }

    private var nextAction: LabDashboardNextAction {
        if !auth.isSignedIn || !hasLinkedBanks || hasBankRefreshWarning {
            return .bankSync
        }

        if firstPaymentPlanWithSuggestedUpdate != nil {
            return .suggestedUpdate
        }

        if firstUpcomingExpenseNeedingMoney != nil {
            return .needsMoney(
                title: "Still needs money",
                message: "One planned item needs more set aside."
            )
        }

        if firstPaymentPlanNeedingMoney != nil {
            return .needsMoney(
                title: "Still needs money",
                message: "One payment plan needs more set aside."
            )
        }

        return .allClear
    }

    private var totalSetAside: Double {
        dashboardFinancialSummary.protectedMoney
    }

    private var savingsGoalsCurrentAmount: Double {
        plaid.savingsGoals.totalSaved
    }

    private var savingsGoalsTargetAmount: Double {
        plaid.savingsGoals.totalTarget
    }

    private var savingsGoalsProgress: Double {
        guard savingsGoalsTargetAmount > 0 else {
            return 0
        }

        let value = savingsGoalsCurrentAmount / savingsGoalsTargetAmount
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0), 1)
    }

    private var savingsGoalsPercentText: String {
        guard savingsGoalsTargetAmount > 0 else {
            return ""
        }

        let value = savingsGoalsCurrentAmount / savingsGoalsTargetAmount
        guard value.isFinite else {
            return "0%"
        }

        return "\(Int((max(value, 0) * 100).rounded()))%"
    }

    var body: some View {
        AppScreen(
            usesNavigationStack: false,
            backgroundStyle: .page(.dashboard),
            contentSpacing: AppSpacing.medium
        ) {
            hero

            labMarker

            DashboardLabAtAGlanceCard(
                setAsideValue: AppFormatters.currency(totalSetAside),
                setAsideSubtitle: "Total set aside",
                upcomingValue: nextSevenDayUpcomingForecasts.isEmpty
                    ? "None"
                    : AppFormatters.currency(nextSevenDayUpcomingTotal),
                upcomingSubtitle: nextSevenDayUpcomingForecasts.isEmpty
                    ? "Next 7 days"
                    : "\(nextSevenDayUpcomingForecasts.count) due soon",
                paymentValue: debtPayoffBuckets.isEmpty
                    ? "None"
                    : AppFormatters.currency(totalPaymentPlanTarget),
                paymentSubtitle: paymentPlansDueSoonCount > 0
                    ? "\(paymentPlansDueSoonCount) due soon"
                    : "Active plans"
            )

            DashboardLabNextActionCard(
                action: nextAction,
                onTap: performNextAction
            )

            miniCardGrid
                .padding(.bottom, AppSpacing.floatingTabClearance + 144)
        }
        .navigationTitle("Dashboard Lab")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsAvailableInsights) {
            AvailableToSpendInsightsSheet(
                summary: dashboardFinancialSummary,
                canShowBankData: canShowBankData,
                hasLinkedAccounts: hasLinkedBanks,
                hasEligibleCashAccounts: !visibleBankAccounts.cashAccounts.isEmpty,
                hasIncludedCashAccounts: !financialSummaryAccounts.cashAccounts.isEmpty,
                bankSyncState: plaid.bankSyncRefreshState
            )
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.panel) {
            greetingBlock

            availableToSpendBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppSpacing.regular)
        .padding(.bottom, AppSpacing.small)
    }

    @ViewBuilder
    private var greetingBlock: some View {
        if let preferredDisplayName {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Text("\(greeting),")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

                Text(preferredDisplayName)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        } else {
            Text(greeting)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityLabel(greeting)
        }
    }

    private var availableToSpendBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.xxSmall) {
                Text("Available to Spend")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                ContextHelpButton(
                    title: "Available to Spend",
                    bodyText: "Available to Spend is your cash balance minus money you have set aside inside \(AppBrand.shortName).",
                    breakdownItems: [
                        "Cash Balance",
                        "- Cash Cushion",
                        "- Savings Goals",
                        "- Upcoming Expenses",
                        "- Payment Plans",
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
                .padding(.top, 2)

            if let bankRefreshStatusText {
                HStack(spacing: AppSpacing.xSmall) {
                    Image(systemName: bankRefreshStatusIcon)
                        .font(.caption.weight(.bold))
                        .foregroundColor(bankRefreshStatusColor)

                    Text(bankRefreshStatusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                showsAvailableInsights = true
            } label: {
                HStack(spacing: AppSpacing.xSmall) {
                    Text("View insights")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
                .padding(.horizontal, AppSpacing.regular)
                .padding(.vertical, AppSpacing.small)
                .background(
                    Capsule()
                        .fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.72))
                )
            }
            .buttonStyle(.plain)
            .padding(.top, AppSpacing.xxSmall)
        }
    }

    private var labMarker: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Image(systemName: "flask.fill")
                .font(.caption.weight(.bold))

            Text("Lab prototype")
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
        .padding(.top, -AppSpacing.small)
    }

    private var miniCardGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 142), spacing: AppSpacing.regular),
                GridItem(.flexible(minimum: 142), spacing: AppSpacing.regular)
            ],
            alignment: .leading,
            spacing: AppSpacing.regular
        ) {
            comingUpSoonCard
            paymentPlanCard
            whatChangedCard
            setAsideProgressCard
        }
    }

    private var comingUpSoonCard: some View {
        DashboardLabMiniCard(
            title: "Coming Up",
            actionTitle: nearestUpcomingExpense == nil ? nil : "Details",
            onAction: { navigation.selectedTab = 2 }
        ) {
            if let forecast = nearestUpcomingExpense {
                DashboardLabMiniIconValue(
                    systemImage: CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                    style: CalderaCategoryStyle.style(for: .upcomingExpense),
                    title: forecast.event.name,
                    subtitle: dueText(for: forecast.occurrenceDate),
                    value: AppFormatters.currency(forecast.event.amount),
                    badge: upcomingStatusText(for: forecast),
                    badgeStyle: remainingAmount(for: forecast) > 0.005
                        ? CalderaCategoryStyle.style(for: .needsMoney)
                        : CalderaCategoryStyle.style(for: .covered)
                )
            } else {
                DashboardLabMiniEmptyState(
                    title: "Nothing soon",
                    message: "No upcoming expenses yet."
                )
            }
        }
    }

    private var paymentPlanCard: some View {
        DashboardLabMiniCard(
            title: "Payment Plan",
            actionTitle: relevantPaymentPlan == nil ? nil : "Plan",
            onAction: openRelevantPaymentPlan
        ) {
            if let bucket = relevantPaymentPlan {
                DashboardLabMiniIconValue(
                    systemImage: CalderaCategoryStyle.style(for: .debtPayoff).icon,
                    style: CalderaCategoryStyle.style(for: .debtPayoff),
                    title: paymentPlanTitle(for: bucket),
                    subtitle: bucket.shouldDisplayDueDate
                        ? "Due \(AppFormatters.abbreviatedMonthDay(bucket.dueDate))"
                        : "Due date not set",
                    value: AppFormatters.currency(max(bucket.paymentTargetAmount, bucket.protectedAmount)),
                    badge: paymentPlanStatusText(for: bucket),
                    badgeStyle: paymentPlanRemainingAmount(for: bucket) > 0.005
                        ? CalderaCategoryStyle.style(for: .needsMoney)
                        : CalderaCategoryStyle.style(for: .covered)
                )
            } else {
                DashboardLabMiniEmptyState(
                    title: "No plans yet",
                    message: "Payment plans will appear here."
                )
            }
        }
    }

    private var whatChangedCard: some View {
        DashboardLabMiniCard(
            title: "What Changed",
            actionTitle: "Sync",
            onAction: { navigation.selectedTab = 3 }
        ) {
            if let summary = plaid.latestBankSyncChangeSummary {
                if let change = summary.changedAccounts.first {
                    DashboardLabMiniIconValue(
                        systemImage: "building.columns.fill",
                        style: CalderaCategoryStyle.style(for: .bankAccount),
                        title: change.accountLabel,
                        subtitle: "Updated \(summary.refreshedAt.formatted(date: .omitted, time: .shortened))",
                        value: change.delta >= 0
                            ? "+\(AppFormatters.currency(change.delta))"
                            : "-\(AppFormatters.currency(abs(change.delta)))",
                        valueStyle: change.delta >= 0
                            ? CalderaCategoryStyle.style(for: .covered).primary
                            : CalderaCategoryStyle.style(for: .needsMoney).primary,
                        badge: summary.changedAccounts.count > 1
                            ? "\(summary.changedAccounts.count) changes"
                            : "Changed",
                        badgeStyle: CalderaCategoryStyle.style(for: .bankAccount)
                    )
                } else {
                    DashboardLabMiniEmptyState(
                        title: "No major changes",
                        message: "Since the last refresh."
                    )
                }
            } else {
                DashboardLabMiniEmptyState(
                    title: "No summary yet",
                    message: "Refresh Bank Sync to compare balances."
                )
            }
        }
    }

    private var setAsideProgressCard: some View {
        DashboardLabMiniCard(
            title: "Savings Goals",
            actionTitle: "Goals",
            onAction: { navigation.openSavings() }
        ) {
            if plaid.savingsGoals.isEmpty || savingsGoalsTargetAmount <= 0.005 {
                DashboardLabGoalsProgressEmptyState()
            } else {
                DashboardLabGoalsProgressTile(
                    progress: savingsGoalsProgress,
                    percentText: savingsGoalsPercentText,
                    currentAmount: savingsGoalsCurrentAmount,
                    targetAmount: savingsGoalsTargetAmount
                )
            }
        }
    }

    private func performNextAction() {
        switch nextAction {
        case .bankSync:
            navigation.selectedTab = 3

        case .suggestedUpdate:
            if let bucket = firstPaymentPlanWithSuggestedUpdate {
                navigation.openSavingsEditDebtPayoff(bucket.id)
            } else {
                navigation.openSavings()
            }

        case .needsMoney:
            if let bucket = firstPaymentPlanNeedingMoney {
                navigation.openSavingsEditDebtPayoff(bucket.id)
            } else {
                navigation.selectedTab = 2
            }

        case .allClear:
            break
        }
    }

    private func openRelevantPaymentPlan() {
        guard let bucket = relevantPaymentPlan else {
            return
        }

        navigation.openSavingsEditDebtPayoff(bucket.id)
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

    private func dueText(
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

        if days == 0 {
            return "Due today"
        }

        if days == 1 {
            return "Due tomorrow"
        }

        if days > 1,
           days <= 30 {
            return "Due in \(days) days"
        }

        return "Due \(AppFormatters.abbreviatedMonthDay(date))"
    }

    private func upcomingStatusText(
        for forecast: ForecastEvent
    ) -> String {
        let remaining = remainingAmount(for: forecast)

        return remaining <= 0.005
            ? "Covered"
            : "Still needs \(AppFormatters.currency(remaining))"
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
        let remaining = paymentPlanRemainingAmount(for: bucket)

        return remaining <= 0.005
            ? "Covered"
            : "Still needs \(AppFormatters.currency(remaining))"
    }

    private func paymentPlanTitle(
        for bucket: DebtPayoffBucket
    ) -> String {
        let trimmed = bucket.accountName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if !trimmed.isEmpty {
            return trimmed
        }

        if let account = visibleBankAccounts.first(where: {
            $0.account_id == bucket.plaidAccountID
        }) {
            return account.name
        }

        return bucket.isLinkedCreditCard ? "Credit Card" : "Payment Plan"
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

        return abs(bucket.paymentTargetAmount - amount) >= 0.005
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

    private func parsedCardPaymentDueDate(
        _ value: String?
    ) -> Date? {
        guard let value,
              !value.isEmpty else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter.date(from: value)
    }
}

private enum LabDashboardNextAction {
    case bankSync
    case suggestedUpdate
    case needsMoney(title: String, message: String)
    case allClear

    var title: String {
        switch self {
        case .bankSync:
            return "Check Bank Sync"

        case .suggestedUpdate:
            return "Review suggested update"

        case .needsMoney(let title, _):
            return title

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

        case .needsMoney(_, let message):
            return message

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

        case .needsMoney:
            return "Set aside money"

        case .allClear:
            return nil
        }
    }

    var icon: String {
        switch self {
        case .bankSync:
            return "building.columns.fill"

        case .suggestedUpdate:
            return "creditcard.fill"

        case .needsMoney:
            return "calendar.badge.exclamationmark"

        case .allClear:
            return "checkmark.circle.fill"
        }
    }

    var style: CalderaCategoryStyle {
        switch self {
        case .bankSync:
            return CalderaCategoryStyle.style(for: .bankAccount)

        case .suggestedUpdate:
            return CalderaCategoryStyle.style(for: .debtPayoff)

        case .needsMoney:
            return CalderaCategoryStyle.style(for: .needsMoney)

        case .allClear:
            return CalderaCategoryStyle.style(for: .covered)
        }
    }

}

private enum DashboardLabCardLayout {
    static let widePadding: CGFloat = 22
    static let miniPadding: CGFloat = 16
    static let miniHeaderHeight: CGFloat = 18
    static let miniCardHeight: CGFloat = 180
    static let miniIconSize: CGFloat = 32
    static let atAGlanceIconSize: CGFloat = 30
}

private struct DashboardLabAtAGlanceCard: View {

    @Environment(\.colorScheme) private var colorScheme

    let setAsideValue: String
    let setAsideSubtitle: String
    let upcomingValue: String
    let upcomingSubtitle: String
    let paymentValue: String
    let paymentSubtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            DashboardLabCardHeader(title: "At a glance")

            HStack(alignment: .center, spacing: 0) {
                DashboardLabAtAGlanceMetric(
                    title: "Set Aside",
                    value: setAsideValue,
                    subtitle: setAsideSubtitle,
                    style: CalderaCategoryStyle.style(for: .reserve),
                    systemImage: "wallet.pass.fill"
                )

                DashboardLabDivider()

                DashboardLabAtAGlanceMetric(
                    title: "Upcoming",
                    value: upcomingValue,
                    subtitle: upcomingSubtitle,
                    style: CalderaCategoryStyle.style(for: .upcomingExpense),
                    systemImage: CalderaCategoryStyle.style(for: .upcomingExpense).icon
                )

                DashboardLabDivider()

                DashboardLabAtAGlanceMetric(
                    title: "Payments",
                    value: paymentValue,
                    subtitle: paymentSubtitle,
                    style: CalderaCategoryStyle.style(for: .debtPayoff),
                    systemImage: CalderaCategoryStyle.style(for: .debtPayoff).icon
                )
            }
        }
        .padding(DashboardLabCardLayout.widePadding)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.84,
            shadowOpacity: 0.045,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
        )
    }
}

private struct DashboardLabAtAGlanceMetric: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String
    let subtitle: String
    let style: CalderaCategoryStyle
    let systemImage: String

    var body: some View {
        VStack(alignment: .center, spacing: AppSpacing.xSmall) {
            DashboardLabGradientIcon(
                systemImage: systemImage,
                style: style,
                size: DashboardLabCardLayout.atAGlanceIconSize,
                imageFont: .caption.weight(.bold),
                shadowRadius: 7
            )

            VStack(alignment: .center, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(value)
                    .font(.footnote.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
                    .monospacedDigit()

                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(style.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
        .padding(.horizontal, AppSpacing.xSmall)
    }
}

private struct DashboardLabDivider: View {

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 68)
            .padding(.horizontal, AppSpacing.xSmall)
    }
}

private struct DashboardLabNextActionCard: View {

    @Environment(\.colorScheme) private var colorScheme

    let action: LabDashboardNextAction
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.regular) {
            DashboardLabGradientIcon(
                systemImage: action.icon,
                style: action.style,
                size: 46,
                imageFont: .headline.weight(.bold),
                shadowRadius: 9
            )

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                DashboardLabSectionLabel("Next Action")

                Text(action.title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(action.message)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)

                if let actionTitle = action.actionTitle {
                    DashboardLabCTAButton(
                        title: actionTitle,
                        color: action.style.primary,
                        action: onTap
                    )
                    .padding(.top, AppSpacing.xSmall)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DashboardLabCardLayout.widePadding)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.84,
            shadowOpacity: 0.045,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: action.style.primary
        )
    }
}

private struct DashboardLabMiniCard<Content: View>: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let actionTitle: String?
    let onAction: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            DashboardLabCardHeader(title: title)
            .frame(height: DashboardLabCardLayout.miniHeaderHeight, alignment: .top)

            content
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: AppSpacing.xSmall)

            if let actionTitle {
                HStack {
                    Spacer(minLength: AppSpacing.small)

                    DashboardLabInlineAction(
                        title: actionTitle,
                        action: onAction
                    )
                }
            }
        }
        .padding(DashboardLabCardLayout.miniPadding)
        .frame(maxWidth: .infinity, minHeight: DashboardLabCardLayout.miniCardHeight, maxHeight: DashboardLabCardLayout.miniCardHeight, alignment: .topLeading)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.82,
            shadowOpacity: 0.04,
            shadowRadius: 14,
            shadowY: 6,
            darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
        )
    }
}

private struct DashboardLabMiniIconValue: View {

    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let style: CalderaCategoryStyle
    let title: String
    let subtitle: String
    let value: String
    var valueStyle: Color? = nil
    let badge: String
    let badgeStyle: CalderaCategoryStyle

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            DashboardLabIconTitleBlock(
                systemImage: systemImage,
                style: style,
                title: title,
                subtitle: subtitle
            )

            DashboardLabAmountStatusBlock(
                value: value,
                valueStyle: valueStyle,
                badge: badge,
                badgeStyle: badgeStyle
            )
        }
    }
}

private struct DashboardLabMiniEmptyState: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(message)
                .font(.caption2.weight(.medium))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    }
}

private struct DashboardLabCardHeader: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var actionTitle: String? = nil
    var trailingSystemImage: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.small) {
            DashboardLabSectionLabel(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle,
               let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
                        .lineLimit(1)
                        .padding(.horizontal, AppSpacing.xSmall)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .frame(width: 24, height: 24)
            }
        }
    }
}

private struct DashboardLabSectionLabel: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.heavy))
            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }
}

private struct DashboardLabIconTitleBlock: View {

    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let style: CalderaCategoryStyle
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.small) {
            DashboardLabGradientIcon(
                systemImage: systemImage,
                style: style,
                size: DashboardLabCardLayout.miniIconSize,
                imageFont: .caption.weight(.bold),
                shadowRadius: 0
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DashboardLabAmountStatusBlock: View {

    @Environment(\.colorScheme) private var colorScheme

    let value: String
    let valueStyle: Color?
    let badge: String
    let badgeStyle: CalderaCategoryStyle

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(valueStyle ?? CalderaVisualStyle.primaryText(colorScheme))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            DashboardLabStatusBadge(
                text: badge,
                style: badgeStyle
            )
        }
        .padding(.top, 1)
    }
}

private struct DashboardLabStatusBadge: View {

    let text: String
    let style: CalderaCategoryStyle

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundColor(style.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(style.primary.opacity(0.13))
            )
    }
}

private struct DashboardLabGoalsProgressTile: View {

    @Environment(\.colorScheme) private var colorScheme

    let progress: Double
    let percentText: String
    let currentAmount: Double
    let targetAmount: Double

    private var style: CalderaCategoryStyle {
        CalderaCategoryStyle.style(for: .savingsGoal)
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.small) {
            DashboardLabProgressRing(
                progress: progress,
                percentText: percentText,
                style: style
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(AppFormatters.currency(currentAmount))
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("of \(AppFormatters.currency(targetAmount))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("toward goals")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(style.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
    }
}

private struct DashboardLabGoalsProgressEmptyState: View {

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.small) {
            ZStack {
                Circle()
                    .stroke(
                        CalderaCategoryStyle.style(for: .savingsGoal).primary.opacity(0.18),
                        lineWidth: 8
                    )
                    .frame(width: 58, height: 58)

                Image(systemName: "flag.fill")
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .savingsGoal).primary)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("No goals yet")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(1)

                Text("Create a goal to track progress.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
    }
}

private struct DashboardLabProgressRing: View {

    @Environment(\.colorScheme) private var colorScheme

    let progress: Double
    let percentText: String
    let style: CalderaCategoryStyle

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    style.primary.opacity(colorScheme == .dark ? 0.18 : 0.14),
                    lineWidth: 8
                )

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: style.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            Text(percentText)
                .font(.caption.weight(.bold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: 60, height: 60)
        .accessibilityLabel("Savings Goals progress")
        .accessibilityValue(percentText)
    }
}

private struct DashboardLabInlineAction: View {

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxSmall) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.heavy))
            }
            .font(.caption.weight(.bold))
            .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.xSmall)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardLabCTAButton: View {

    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.heavy))
            }
            .font(.footnote.weight(.bold))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.xSmall)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardLabGradientIcon: View {

    let systemImage: String
    let style: CalderaCategoryStyle
    let size: CGFloat
    let imageFont: Font
    let shadowRadius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: style.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(
                    color: style.primary.opacity(shadowRadius > 0 ? 0.24 : 0),
                    radius: shadowRadius,
                    y: shadowRadius > 0 ? 4 : 0
                )

            Image(systemName: systemImage)
                .font(imageFont)
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

#endif
