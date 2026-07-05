#if DEBUG

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ModularDashboardLabView: View {

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var plaid: PlaidService
    @Environment(\.colorScheme) private var colorScheme

    @Query
    private var events: [PlannerEvent]

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @Query
    private var debtPayoffBuckets: [DebtPayoffBucket]

    @State private var showsCustomizeDashboard = false
    @State private var showsAvailableInsights = false
    @State private var isEditingDashboard = false
    @State private var draggingTileID: ModularDashboardTileID?

    @AppStorage("lab.modularDashboard.tileOrder")
    private var tileOrderRaw = ""

    @AppStorage("lab.modularDashboard.hiddenTiles")
    private var hiddenTileIDsRaw = ""

    @AppStorage(AppPersonalizationKeys.preferredName)
    private var preferredName = ""

    private enum Layout {
        static let pageHorizontalPadding = AppSpacing.regular
        static let minimumTileWidth: CGFloat = 150
    }

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.screen
                ) {
                    focusedHero

                    tilesHeader

                    if visibleTileIDs.isEmpty {
                        emptyTilesCard
                    } else {
                        tileGrid
                    }

                    if isEditingDashboard {
                        editModeActions
                    }
                }
                .padding(.horizontal, Layout.pageHorizontalPadding)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.floatingTabClearance)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsCustomizeDashboard) {
            ModularDashboardCustomizeSheet(
                initialOrder: orderedTileIDs,
                initialHiddenTileIDs: hiddenTileIDs,
                onApply: { order, hidden in
                    setTileOrder(order)
                    setHiddenTileIDs(hidden)
                },
                onReset: resetTileLayout
            )
        }
        .sheet(isPresented: $showsAvailableInsights) {
            AvailableToSpendInsightsSheet(
                summary: dashboardFinancialSummary,
                canShowBankData: canShowBankData,
                hasBankAccounts: !visibleBankAccounts.isEmpty
            )
        }
    }

    private var focusedHero: some View {
        ModularDashboardFocusedHero(
            greeting: greeting,
            preferredDisplayName: preferredDisplayName,
            amount: AppFormatters.currency(displayedSafeToSpend),
            amountColor: displayedSafeToSpend < -0.005
                ? CalderaCategoryStyle.style(for: .shortfall).primary
                : CalderaVisualStyle.primaryText(colorScheme),
            subtitle: canShowBankData
                ? "Cash left after set-asides"
                : "Sign in to sync bank balances.",
            onViewInsights: {
                showsAvailableInsights = true
            }
        )
    }

    private var tilesHeader: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("Dashboard Tiles")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text("Two-column lab widgets you can show, hide, and reorder.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.small)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isEditingDashboard.toggle()
                    if !isEditingDashboard {
                        draggingTileID = nil
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.xSmall) {
                    Image(systemName: isEditingDashboard ? "checkmark" : "square.and.pencil")
                    Text(isEditingDashboard ? "Done" : "Edit Dashboard")
                }
                .font(.subheadline.weight(.bold))
                .foregroundColor(AppColors.primaryText)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.72))
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isEditingDashboard ? "Done editing dashboard" : "Edit dashboard")
        }
    }

    private var tileGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: Layout.minimumTileWidth,
                        maximum: 230
                    ),
                    spacing: AppSpacing.medium
                )
            ],
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            ForEach(visibleTileIDs) { tileID in
                editableTileCard(
                    tileID: tileID
                )
            }
        }
    }

    private var editModeActions: some View {
        HStack(spacing: AppSpacing.medium) {
            Button {
                showsCustomizeDashboard = true
            } label: {
                HStack(spacing: AppSpacing.xSmall) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                    Text(hiddenTileIDs.isEmpty ? "Customize" : "Add Tile")
                }
                .font(.subheadline.weight(.bold))
                .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.small)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            CalderaCategoryStyle.style(for: .safeToSpend).primary
                                .opacity(colorScheme == .dark ? 0.16 : 0.12)
                        )
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize dashboard tiles")

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    resetTileLayout()
                }
            } label: {
                HStack(spacing: AppSpacing.xSmall) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                }
                .font(.subheadline.weight(.bold))
                .foregroundColor(AppColors.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.small)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.72))
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset dashboard tiles")
        }
    }

    @ViewBuilder
    private func editableTileCard(
        tileID: ModularDashboardTileID
    ) -> some View {
        let card = ModularDashboardTileCard(
            tile: tileModel(for: tileID),
            isEditing: isEditingDashboard,
            jigglePhase: tileID.jiggleSeed,
            isDragging: draggingTileID == tileID,
            onRemove: {
                hideTile(tileID)
            }
        )

        if isEditingDashboard {
            card
                .onDrag {
                    draggingTileID = tileID
                    return NSItemProvider(
                        object: tileID.rawValue as NSString
                    )
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ModularDashboardTileDropDelegate(
                        targetTileID: tileID,
                        draggingTileID: $draggingTileID,
                        moveTile: moveTile
                    )
                )
        } else {
            card
        }
    }

    private var emptyTilesCard: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            IconBadge(
                systemImage: "square.grid.2x2.fill",
                color: CalderaCategoryStyle.style(for: .safeToSpend).primary,
                size: 46,
                iconSize: 18
            )

            Text("All tiles are hidden")
                .font(.headline)
                .foregroundColor(AppColors.primaryText)

            Text("Reset the lab layout to bring the default dashboard tiles back.")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button("Reset to Default") {
                resetTileLayout()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(AppSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
        )
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

    private var canShowBankData: Bool {
        !AppConfig.requiresAuthenticatedBankData || auth.isSignedIn
    }

    private var visibleBankAccounts: [PlaidAccount] {
        canShowBankData
            ? plaid.accounts.deduplicatedForDisplayAndTotals
            : []
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

    private var displayedSafeToSpend: Double {
        canShowBankData ? dashboardFinancialSummary.safeToSpend : 0
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

    private var sevenDayExpenseTotal: Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let endDate = calendar.date(byAdding: .day, value: 7, to: today) else {
            return 0
        }

        return upcomingExpenseForecasts
            .filter {
                $0.occurrenceDate <= endDate
            }
            .reduce(0) { total, forecast in
                total + forecast.event.amount
            }
    }

    private var needsSetAsideTotal: Double {
        let upcomingNeeds = upcomingExpenseForecasts.reduce(0) { total, forecast in
            let remainingAmount = max(
                forecast.event.amount - allocatedAmount(for: forecast),
                0
            )
            return total + remainingAmount
        }

        let debtNeeds = debtPayoffBuckets.reduce(0) { total, bucket in
            total + max(bucket.paymentTargetAmount - bucket.protectedAmount, 0)
        }

        return upcomingNeeds + debtNeeds
    }

    private var bankSyncValue: String {
        guard canShowBankData else {
            return "Sign in"
        }

        guard !visibleBankAccounts.isEmpty else {
            return "No accounts"
        }

        if plaid.isRefreshingPlaidData {
            return "Refreshing"
        }

        if let message = plaid.manualPlaidRefreshMessage?.lowercased(),
           message.contains("refresh failed") {
            return "Needs refresh"
        }

        return "Synced"
    }

    private var bankSyncSubtitle: String {
        guard canShowBankData else {
            return "Bank Sync required"
        }

        guard !visibleBankAccounts.isEmpty else {
            return "Connect accounts"
        }

        return plaid.accountsLastUpdatedText
    }

    private var orderedTileIDs: [ModularDashboardTileID] {
        let savedIDs = tileOrderRaw
            .split(separator: ",")
            .compactMap {
                ModularDashboardTileID(rawValue: String($0))
            }
        let savedSet = Set(savedIDs)
        let missingIDs = ModularDashboardTileID.allCases.filter {
            !savedSet.contains($0)
        }

        return savedIDs + missingIDs
    }

    private var hiddenTileIDs: Set<ModularDashboardTileID> {
        Set(
            hiddenTileIDsRaw
                .split(separator: ",")
                .compactMap {
                    ModularDashboardTileID(rawValue: String($0))
                }
        )
    }

    private var visibleTileIDs: [ModularDashboardTileID] {
        orderedTileIDs.filter {
            !hiddenTileIDs.contains($0)
        }
    }

    private func setTileOrder(
        _ order: [ModularDashboardTileID]
    ) {
        tileOrderRaw = order
            .map(\.rawValue)
            .joined(separator: ",")
    }

    private func setHiddenTileIDs(
        _ hidden: Set<ModularDashboardTileID>
    ) {
        hiddenTileIDsRaw = hidden
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }

    private func resetTileLayout() {
        tileOrderRaw = ""
        hiddenTileIDsRaw = ""
    }

    private func hideTile(
        _ tileID: ModularDashboardTileID
    ) {
        var hidden = hiddenTileIDs
        hidden.insert(tileID)

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            setHiddenTileIDs(hidden)
        }
    }

    private func moveTile(
        _ draggingTileID: ModularDashboardTileID,
        before targetTileID: ModularDashboardTileID
    ) {
        var reorderedVisibleTileIDs = visibleTileIDs

        guard let fromIndex = reorderedVisibleTileIDs.firstIndex(of: draggingTileID),
              let targetIndex = reorderedVisibleTileIDs.firstIndex(of: targetTileID),
              fromIndex != targetIndex else {
            return
        }

        let destination = targetIndex > fromIndex
            ? targetIndex + 1
            : targetIndex

        reorderedVisibleTileIDs.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: destination
        )

        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
            setTileOrder(
                mergedTileOrder(
                    withVisibleOrder: reorderedVisibleTileIDs
                )
            )
        }
    }

    private func mergedTileOrder(
        withVisibleOrder visibleOrder: [ModularDashboardTileID]
    ) -> [ModularDashboardTileID] {
        var mergedOrder: [ModularDashboardTileID] = []
        var visibleIterator = visibleOrder.makeIterator()

        for tileID in orderedTileIDs {
            if hiddenTileIDs.contains(tileID) {
                mergedOrder.append(tileID)
            } else if let nextVisibleTileID = visibleIterator.next() {
                mergedOrder.append(nextVisibleTileID)
            }
        }

        return mergedOrder
    }

    private func allocatedAmount(
        for forecast: ForecastEvent
    ) -> Double {
        allocations.first {
            $0.occurrenceID == forecast.occurrenceID
        }?
        .allocatedAmount ?? 0
    }

    private func tileModel(
        for tileID: ModularDashboardTileID
    ) -> ModularDashboardTileModel {
        switch tileID {
        case .cashBalance:
            return ModularDashboardTileModel(
                id: tileID,
                title: "Cash Balance",
                value: AppFormatters.currency(dashboardFinancialSummary.cash),
                subtitle: canShowBankData ? "Linked cash" : "Sign in for Bank Sync",
                style: CalderaCategoryStyle.style(for: .bankAccount),
                isPrototype: false
            )

        case .setAside:
            return ModularDashboardTileModel(
                id: tileID,
                title: "Set Aside",
                value: AppFormatters.currency(dashboardFinancialSummary.protectedMoney),
                subtitle: "Cushion, Goals, Expenses, Debt",
                style: CalderaCategoryStyle.style(for: .reserve),
                isPrototype: false
            )

        case .cashCushion:
            return ModularDashboardTileModel(
                id: tileID,
                title: "Cash Cushion",
                value: AppFormatters.currency(dashboardFinancialSummary.reserve),
                subtitle: "Flexible buffer",
                style: CalderaCategoryStyle.style(for: .reserve),
                isPrototype: false
            )

        case .needsSetAside:
            return ModularDashboardTileModel(
                id: tileID,
                title: "Needs Set Aside",
                value: AppFormatters.currency(needsSetAsideTotal),
                subtitle: "Prototype estimate",
                style: CalderaCategoryStyle.style(for: .needsMoney),
                isPrototype: true
            )

        case .nextExpense:
            return ModularDashboardTileModel(
                id: tileID,
                title: "Next Expense",
                value: nextExpense?.event.name ?? "None",
                subtitle: nextExpense.map {
                    "\(AppFormatters.currency($0.event.amount)) · \(AppFormatters.abbreviatedMonthDay($0.occurrenceDate))"
                } ?? "Nothing scheduled",
                style: CalderaCategoryStyle.style(for: .upcomingExpense),
                isPrototype: false
            )

        case .goals:
            return ModularDashboardTileModel(
                id: tileID,
                title: "Goals",
                value: AppFormatters.currency(dashboardFinancialSummary.savingsGoalsSetAside),
                subtitle: "\(plaid.savingsGoals.count) active",
                style: CalderaCategoryStyle.style(for: .savingsGoal),
                isPrototype: false
            )

        case .debtPayoff:
            return ModularDashboardTileModel(
                id: tileID,
                title: "Debt Payoff",
                value: AppFormatters.currency(totalDebtPayoffSetAside),
                subtitle: "\(debtPayoffBuckets.count) plan\(debtPayoffBuckets.count == 1 ? "" : "s")",
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                isPrototype: false
            )

        case .bankSync:
            return ModularDashboardTileModel(
                id: tileID,
                title: "Bank Sync",
                value: bankSyncValue,
                subtitle: bankSyncSubtitle,
                style: CalderaCategoryStyle.style(for: .bankAccount),
                isPrototype: false
            )

        case .sevenDayOutlook:
            return ModularDashboardTileModel(
                id: tileID,
                title: "7-Day Outlook",
                value: AppFormatters.currency(sevenDayExpenseTotal),
                subtitle: "Prototype total",
                style: CalderaCategoryStyle.style(for: .safeToSpend),
                isPrototype: true
            )
        }
    }
}

private struct ModularDashboardFocusedHero: View {

    @Environment(\.colorScheme) private var colorScheme

    let greeting: String
    let preferredDisplayName: String?
    let amount: String
    let amountColor: Color
    let subtitle: String
    let onViewInsights: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.panel) {
            greetingBlock

            availableToSpendBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppSpacing.regular)
        .padding(.bottom, AppSpacing.screen)
        .frame(minHeight: 278, alignment: .topLeading)
    }

    @ViewBuilder
    private var greetingBlock: some View {
        if let preferredDisplayName {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Text("\(greeting),")
                    .font(.subheadline.weight(.medium))
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
                    bodyText: "Available to Spend is your cash balance minus money you’ve set aside inside Caldera.",
                    breakdownItems: [
                        "Cash Balance",
                        "− Cash Cushion",
                        "− Savings Goals",
                        "− Upcoming Expenses",
                        "− Debt Payoff",
                        "= Available to Spend"
                    ],
                    footnote: "Set-asides are virtual. Your money stays in your bank account, but Caldera treats it as unavailable for everyday spending."
                )
            }

            Text(amount)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(amountColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppSpacing.xSmall)

            Button {
                onViewInsights()
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
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, AppSpacing.medium)
            .accessibilityLabel("View Available to Spend insights")
        }
    }
}

private enum ModularDashboardTileID: String, CaseIterable, Identifiable {
    case cashBalance
    case setAside
    case cashCushion
    case needsSetAside
    case nextExpense
    case goals
    case debtPayoff
    case bankSync
    case sevenDayOutlook

    var id: String {
        rawValue
    }

    var displayTitle: String {
        switch self {
        case .cashBalance:
            return "Cash Balance"

        case .setAside:
            return "Set Aside"

        case .cashCushion:
            return "Cash Cushion"

        case .needsSetAside:
            return "Needs Set Aside"

        case .nextExpense:
            return "Next Expense"

        case .goals:
            return "Goals"

        case .debtPayoff:
            return "Debt Payoff"

        case .bankSync:
            return "Bank Sync"

        case .sevenDayOutlook:
            return "7-Day Outlook"
        }
    }

    var jiggleSeed: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

private struct ModularDashboardTileModel: Identifiable {
    let id: ModularDashboardTileID
    let title: String
    let value: String
    let subtitle: String
    let style: CalderaCategoryStyle
    let isPrototype: Bool
}

private struct ModularDashboardTileCard: View {

    let tile: ModularDashboardTileModel
    let isEditing: Bool
    let jigglePhase: Int
    let isDragging: Bool
    let onRemove: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var jiggleForward = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            tileContent

            if isEditing {
                removeButton
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(isDragging ? 1.045 : 1)
        .rotationEffect(
            .degrees(
                isEditing
                    ? (jiggleForward ? jiggleAmplitude : -jiggleAmplitude)
                    : 0
            )
        )
        .animation(
            .spring(response: 0.22, dampingFraction: 0.82),
            value: isDragging
        )
        .onAppear {
            updateJiggleState()
        }
        .onChange(of: isEditing) { _, _ in
            updateJiggleState()
        }
    }

    private var tileContent: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            HStack(
                alignment: .top,
                spacing: AppSpacing.small
            ) {
                CalderaGradientIcon(
                    systemImage: tile.style.icon,
                    colors: tile.style.gradient,
                    size: 42,
                    iconSize: 16
                )

                Spacer(minLength: AppSpacing.xSmall)

                if tile.isPrototype {
                    Text("Lab")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(tile.style.primary)
                        .padding(.horizontal, AppSpacing.xSmall)
                        .padding(.vertical, AppSpacing.xxSmall)
                        .background(
                            Capsule(style: .continuous)
                                .fill(tile.style.primary.opacity(0.12))
                        )
                }
            }

            Spacer(minLength: AppSpacing.xxSmall)

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(tile.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)

                Text(tile.value)
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)

                Text(tile.subtitle)
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.88,
            strokeOpacity: 0.72,
            shadowOpacity: 0.035,
            shadowRadius: 14,
            shadowY: 8,
            darkGlowColor: tile.style.primary
        )
        .accessibilityElement(children: .combine)
    }

    private var removeButton: some View {
        Button {
            onRemove()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        Color.white.opacity(
                            colorScheme == .dark ? 0.18 : 0.92
                        )
                    )
                    .frame(width: 28, height: 28)
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12),
                        radius: 8,
                        y: 4
                    )

                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 10, y: -10)
        .accessibilityLabel("Hide \(tile.title) tile")
    }

    private var jiggleAmplitude: Double {
        let direction = jigglePhase.isMultiple(of: 2) ? 1.0 : -1.0
        let magnitude = 0.8 + Double(jigglePhase % 3) * 0.22

        return direction * magnitude
    }

    private var jiggleDuration: Double {
        0.13 + Double(jigglePhase % 4) * 0.012
    }

    private func updateJiggleState() {
        guard isEditing else {
            withAnimation(.easeOut(duration: 0.12)) {
                jiggleForward = false
            }
            return
        }

        jiggleForward = false
        let delay = Double(jigglePhase % 5) * 0.035

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isEditing else {
                return
            }

            withAnimation(
                .easeInOut(duration: jiggleDuration)
                    .repeatForever(autoreverses: true)
            ) {
                jiggleForward = true
            }
        }
    }
}

private struct ModularDashboardTileDropDelegate: DropDelegate {

    let targetTileID: ModularDashboardTileID
    @Binding var draggingTileID: ModularDashboardTileID?
    let moveTile: (ModularDashboardTileID, ModularDashboardTileID) -> Void

    func dropEntered(
        info: DropInfo
    ) {
        guard let draggingTileID,
              draggingTileID != targetTileID else {
            return
        }

        moveTile(
            draggingTileID,
            targetTileID
        )
    }

    func dropUpdated(
        info: DropInfo
    ) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(
        info: DropInfo
    ) -> Bool {
        draggingTileID = nil
        return true
    }

    func dropExited(
        info: DropInfo
    ) {
        // The grid reorders on entry. Nothing to clean up until the drop completes.
    }
}

private struct ModularDashboardCustomizeSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var localOrder: [ModularDashboardTileID]
    @State private var localHiddenTileIDs: Set<ModularDashboardTileID>

    let onApply: ([ModularDashboardTileID], Set<ModularDashboardTileID>) -> Void
    let onReset: () -> Void

    init(
        initialOrder: [ModularDashboardTileID],
        initialHiddenTileIDs: Set<ModularDashboardTileID>,
        onApply: @escaping ([ModularDashboardTileID], Set<ModularDashboardTileID>) -> Void,
        onReset: @escaping () -> Void
    ) {
        _localOrder = State(initialValue: initialOrder)
        _localHiddenTileIDs = State(initialValue: initialHiddenTileIDs)
        self.onApply = onApply
        self.onReset = onReset
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .more)

                List {
                    Section {
                        ForEach(localOrder) { tileID in
                            Toggle(
                                isOn: Binding(
                                    get: {
                                        !localHiddenTileIDs.contains(tileID)
                                    },
                                    set: { isVisible in
                                        if isVisible {
                                            localHiddenTileIDs.remove(tileID)
                                        } else {
                                            localHiddenTileIDs.insert(tileID)
                                        }
                                    }
                                )
                            ) {
                                Text(tileID.displayTitle)
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .onMove { source, destination in
                            localOrder.move(
                                fromOffsets: source,
                                toOffset: destination
                            )
                        }
                    } header: {
                        Text("Show, hide, and reorder")
                    } footer: {
                        Text("This is DEBUG-only prototype state stored locally under lab.modularDashboard.")
                    }

                    Section {
                        Button(role: .destructive) {
                            localOrder = ModularDashboardTileID.allCases
                            localHiddenTileIDs = []
                            onReset()
                        } label: {
                            Text("Reset to Default")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Customize Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onApply(
                            localOrder,
                            localHiddenTileIDs
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#endif
