import SwiftUI
import SwiftData

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

    private var baseFinancialSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: visibleBankAccounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance
        )
    }

    private var totalSaved: Double {
        baseFinancialSummary.savingsGoalsSetAside
    }

    private var protectedTotal: Double {
        FinancialSummaryCalculator.calculate(
            accounts: visibleBankAccounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance,
            upcomingExpensesSetAside: totalUpcomingExpenseAllocated,
            debtPaymentsSetAside: totalDebtPayoffSetAside
        )
        .protectedMoney
    }

    private var totalUpcomingExpenseAllocated: Double {
        upcomingExpenseAllocations.reduce(0) {
            $0 + $1.allocatedAmount
        }
    }

    private var totalDebtPayoffSetAside: Double {
        debtPayoffBuckets.totalProtectedAmount
    }

    private var protectedSummaryCaption: String {
        totalDebtPayoffSetAside > 0
            ? "Reserve, goals, expenses, and debt payoff"
            : "Reserve, goals, and upcoming expenses"
    }

    private var debtAccounts: [PlaidAccount] {
        visibleBankAccounts.debtAccounts
    }

    private var canShowBankData: Bool {
        !AppConfig.requiresAuthenticatedBankData || auth.isSignedIn
    }

    private var visibleBankAccounts: [PlaidAccount] {
        canShowBankData ? plaid.accounts : []
    }

    private var sortedDebtPayoffBuckets: [DebtPayoffBucket] {
        debtPayoffBuckets.sorted {
            $0.dueDate < $1.dueDate
        }
    }

    private var visibleDebtPayoffBuckets: [DebtPayoffBucket] {
        Array(
            sortedDebtPayoffBuckets.prefix(3)
        )
    }

    private var upcomingExpenseForecasts: [ForecastEvent] {
        let startOfToday = Calendar.current.startOfDay(for: Date())

        return forecastEvents
            .filter {
                $0.event.type == .expense
            }
            .filter {
                Calendar.current.startOfDay(for: $0.occurrenceDate) >= startOfToday
            }
    }

    private var visibleUpcomingExpenseForecasts: [ForecastEvent] {
        Array(
            upcomingExpenseForecasts
                .prefix(3)
        )
    }

    private var visibleSavingsGoals: [SavingsGoal] {
        let pinnedGoals = plaid.savingsGoals.filter(\.isPinned)

        if !pinnedGoals.isEmpty {
            return pinnedGoals
        }

        return Array(
            plaid.savingsGoals.prefix(3)
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
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .savings)

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.screen
                    ) {
                        header

                        summaryStrip

                        reserveCard

                        savingsGoalsSection

                        upcomingExpensesSection

                        debtPayoffSection
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
        .sheet(item: $activeDebtPayoffSheet) { sheet in
            switch sheet {
            case .create:
                DebtPayoffBucketEditorView(
                    debtAccounts: debtAccounts,
                    bucket: nil,
                    onSave: saveDebtPayoffBucket
                )

            case .edit(let bucket):
                DebtPayoffBucketEditorView(
                    debtAccounts: debtAccounts,
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
    }

    private var header: some View {
        HStack(
            alignment: .top,
            spacing: AppSpacing.medium
        ) {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                Text("Protection")
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

            Spacer()

            Button {
                createSavingsGoal()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(AppColors.accent)
                    .frame(
                        width: 46,
                        height: 46
                    )
                    .background(
                        Circle()
                            .fill(AppColors.accent.opacity(0.12))
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                AppColors.glassSubtleHighlight,
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create savings goal")
        }
    }

    private var summaryStrip: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.regular
        ) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    systemImage: "lock.shield.fill",
                    colors: CalderaVisualStyle.protectedGradient,
                    size: 42,
                    iconSize: 18
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Total Protected")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.secondaryText)

                    Text(AppFormatters.currency(protectedTotal))
                        .font(.title2.bold())
                        .foregroundColor(AppColors.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(protectedSummaryCaption)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: AppSpacing.small) {
                summaryAmount(
                    title: "Reserve",
                    value: plaid.reserveBalance,
                    color: AppColors.protected
                )

                summaryAmount(
                    title: "Goals",
                    value: totalSaved,
                    color: AppColors.protected
                )

                summaryAmount(
                    title: "Expenses",
                    value: totalUpcomingExpenseAllocated,
                    color: AppColors.warning
                )

                if totalDebtPayoffSetAside > 0 {
                    summaryAmount(
                        title: "Debt",
                        value: totalDebtPayoffSetAside,
                        color: AppColors.obligation
                    )
                }
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            shadowOpacity: 0.045,
            shadowRadius: 18,
            shadowY: 8
        )
    }

    private var reserveCard: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    systemImage: "lock.shield.fill",
                    colors: CalderaVisualStyle.protectedGradient,
                    size: 42,
                    iconSize: 18
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Savings Reserve")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)

                    Text("Cash held back from everyday spending")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                Text(AppFormatters.currency(plaid.reserveBalance))
                    .font(.title2.bold())
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            TextField(
                "Amount",
                text: $reserveAmountText
            )
            .keyboardType(.decimalPad)
            .keyboardDismissToolbar()
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.medium)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.76,
                strokeOpacity: 0.62,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0
            )
            .accessibilityLabel("Savings reserve amount")

            HStack(spacing: AppSpacing.medium) {
                SecondaryButton(
                    "Subtract",
                    systemImage: "minus.circle",
                    cornerRadius: AppRadii.button,
                    fillsWidth: true,
                    action: subtractFromReserve
                )
                .disabled(!canAdjustReserve)
                .opacity(canAdjustReserve ? 1.0 : 0.6)
                .accessibilityLabel("Subtract from Savings Reserve")

                PrimaryButton(
                    "Add",
                    systemImage: "plus.circle.fill",
                    trailingSystemImage: nil,
                    cornerRadius: AppRadii.button,
                    isDisabled: !canAdjustReserve,
                    fillsWidth: true,
                    action: addToReserve
                )
                .accessibilityLabel("Add to Savings Reserve")
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            shadowOpacity: 0.045,
            shadowRadius: 18,
            shadowY: 8
        )
    }

    private var savingsGoalsSection: some View {
        redesignSection(
            title: "Savings Goals",
            systemImage: "target",
            color: AppColors.protected,
            trailing: savingsGoalsSeeAllButton
        ) {
            if plaid.savingsGoals.isEmpty {
                emptyRedesignRow(
                    title: "No savings goals yet",
                    subtitle: "Create a goal to set aside cash for something specific.",
                    systemImage: "target",
                    color: AppColors.protected,
                    actionTitle: "Create Goal",
                    action: createSavingsGoal
                )
            } else {
                VStack(spacing: AppSpacing.small) {
                    ForEach(visibleSavingsGoals) { goal in
                        savingsGoalRow(goal)
                    }
                }
            }
        }
    }

    private var savingsGoalsSeeAllButton: AnyView {
        guard !plaid.savingsGoals.isEmpty else {
            return AnyView(EmptyView())
        }

        return AnyView(
            NavigationLink {
                AllSavingsGoalsView()
                    .environmentObject(plaid)
            } label: {
                Text("See all")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all savings goals")
        )
    }

    private var upcomingExpensesSection: some View {
        redesignSection(
            title: "Upcoming Expenses",
            systemImage: "calendar.badge.exclamationmark",
            color: AppColors.warning,
            trailing: upcomingExpensesSeeAllButton
        ) {
            if upcomingExpenseForecasts.isEmpty {
                emptyRedesignRow(
                    title: "No upcoming expenses",
                    subtitle: "Add bills in Timeline to protect cash before they are due.",
                    systemImage: "calendar.badge.exclamationmark",
                    color: AppColors.warning
                )
            } else {
                VStack(spacing: AppSpacing.small) {
                    ForEach(visibleUpcomingExpenseForecasts) { forecast in
                        upcomingExpenseRow(forecast)
                    }
                }
            }
        }
    }

    private var upcomingExpensesSeeAllButton: AnyView {
        guard !upcomingExpenseForecasts.isEmpty else {
            return AnyView(EmptyView())
        }

        return AnyView(
            Button {
                navigation.selectedTab = 2
            } label: {
                Text("See all")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all upcoming expenses")
        )
    }

    private var debtPayoffSection: some View {
        redesignSection(
            title: "Debt Payoff",
            systemImage: "creditcard.fill",
            color: AppColors.obligation,
            trailing: debtPayoffAddButton
        ) {
            if debtPayoffBuckets.isEmpty {
                emptyRedesignRow(
                    title: "No debt payoff set aside",
                    subtitle: "Set aside money toward upcoming debt payments without reducing the balance yet.",
                    systemImage: "creditcard.fill",
                    color: AppColors.obligation,
                    actionTitle: debtAccounts.isEmpty ? nil : "Create",
                    action: debtAccounts.isEmpty ? nil : {
                        activeDebtPayoffSheet = .create
                    }
                )
            } else {
                VStack(spacing: AppSpacing.small) {
                    ForEach(visibleDebtPayoffBuckets) { bucket in
                        debtPayoffRow(bucket)
                    }
                }
            }
        }
    }

    private var debtPayoffAddButton: AnyView {
        guard !debtAccounts.isEmpty else {
            return AnyView(EmptyView())
        }

        return AnyView(
            Button {
                activeDebtPayoffSheet = .create
            } label: {
                Text("New")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create debt payoff bucket")
        )
    }

    private func redesignSection<Content: View>(
        title: String,
        systemImage: String,
        color: Color,
        trailing: AnyView = AnyView(EmptyView()),
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    systemImage: systemImage,
                    colors: CalderaVisualStyle.iconGradient(for: color),
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

    private func summaryAmount(
        title: String,
        value: Double,
        color: Color
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)

            Text(AppFormatters.currency(value))
                .font(.caption.weight(.bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.small)
        .padding(.horizontal, AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.72,
            strokeOpacity: 0.58,
            shadowOpacity: 0.0,
            shadowRadius: 0,
            shadowY: 0
        )
    }

    private func savingsGoalRow(
        _ goal: SavingsGoal
    ) -> some View {
        compactRedesignRow(
            title: goal.name.isEmpty ? "Untitled Savings Goal" : goal.name,
            subtitle: "\(AppFormatters.currency(goal.currentAmount)) saved of \(AppFormatters.currency(goal.targetAmount))",
            value: "\(Int(goal.progress * 100))%",
            systemImage: "target",
            color: AppColors.protected,
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
        _ forecast: ForecastEvent
    ) -> some View {
        let allocatedAmount = allocatedAmount(
            for: forecast
        )

        let remainingAmount = max(
            forecast.event.amount - allocatedAmount,
            0
        )

        return compactRedesignRow(
            title: forecast.event.name,
            subtitle: "\(AppFormatters.abbreviatedMonthDay(forecast.occurrenceDate)) · \(AppFormatters.currency(allocatedAmount)) set aside",
            value: remainingAmount <= 0
                ? "Covered"
                : "Needs \(AppFormatters.currency(remainingAmount))",
            systemImage: "calendar.badge.exclamationmark",
            color: remainingAmount <= 0
                ? AppColors.spendable
                : AppColors.warning,
            progress: progress(
                allocated: allocatedAmount,
                amount: forecast.event.amount
            ),
            rowAction: {
                selectedAllocationForecast = forecast
            }
        )
    }

    private func debtPayoffRow(
        _ bucket: DebtPayoffBucket
    ) -> some View {
        let account = debtAccount(
            for: bucket
        )
        let balance = account?.debtBalanceValue ?? 0
        let targetAmount = debtPayoffTargetAmount(
            for: bucket,
            balance: balance
        )
        let dueDate = AppFormatters.abbreviatedMonthDay(
            bucket.dueDate
        )
        let institution = account?.institution_name ?? bucket.institutionName
        let subtitlePrefix = institution.map {
            "\($0) · "
        } ?? ""

        return compactRedesignRow(
            title: account?.name ?? bucket.accountName,
            subtitle: "\(subtitlePrefix)Due \(dueDate) · \(AppFormatters.currency(bucket.protectedAmount)) set aside",
            value: "\(AppFormatters.currency(balance)) balance",
            systemImage: account?.isLoanGroupAccount == true
                ? "building.columns.fill"
                : "creditcard.fill",
            color: AppColors.obligation,
            progress: progress(
                allocated: bucket.protectedAmount,
                amount: targetAmount
            ),
            rowAction: {
                activeDebtPayoffSheet = .edit(bucket)
            },
            accessorySystemImage: "plus.circle.fill",
            accessoryAccessibilityLabel: "Edit debt payoff for \(bucket.accountName)",
            accessoryAction: {
                activeDebtPayoffSheet = .edit(bucket)
            }
        )
    }

    private func debtAccount(
        for bucket: DebtPayoffBucket
    ) -> PlaidAccount? {
        debtAccounts.first {
            $0.account_id == bucket.plaidAccountID
        }
    }

    private func debtPayoffTargetAmount(
        for bucket: DebtPayoffBucket,
        balance: Double
    ) -> Double {
        if bucket.paymentTargetAmount > 0 {
            return bucket.paymentTargetAmount
        }

        return max(balance, bucket.protectedAmount)
    }

    private func allocatedAmount(
        for forecast: ForecastEvent
    ) -> Double {
        guard let allocation = allocations.first(
            where: {
                $0.occurrenceID == forecast.occurrenceID
            }
        ) else {
            return 0
        }

        return min(
            max(allocation.allocatedAmount, 0),
            forecast.event.amount
        )
    }

    private func emptyRedesignRow(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: CalderaVisualStyle.iconGradient(for: color),
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

            if let actionTitle,
               let action {
                Button(
                    actionTitle,
                    action: action
                )
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.accent)
                .buttonStyle(.plain)
            }
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

    private func compactRedesignRow(
        title: String,
        subtitle: String,
        value: String,
        systemImage: String,
        color: Color,
        progress: Double,
        rowAction: (() -> Void)? = nil,
        accessorySystemImage: String? = nil,
        accessoryAccessibilityLabel: String? = nil,
        accessoryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    systemImage: systemImage,
                    colors: CalderaVisualStyle.iconGradient(for: color),
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
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let accessorySystemImage,
                   let accessoryAction {
                    Button(
                        action: accessoryAction
                    ) {
                        Image(systemName: accessorySystemImage)
                            .font(.body.weight(.semibold))
                            .foregroundColor(AppColors.accent)
                            .frame(
                                width: 32,
                                height: 32
                            )
                            .background(
                                Circle()
                                    .fill(AppColors.accent.opacity(0.10))
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
                colors: CalderaVisualStyle.iconGradient(for: color)
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            rowAction?()
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
        guard let account = debtAccounts.first(
            where: {
                $0.account_id == draft.plaidAccountID
            }
        ) else {
            return
        }

        modelContext.insert(
            DebtPayoffBucket(
                plaidAccountID: account.account_id,
                accountName: account.name,
                institutionName: account.institution_name,
                dueDate: draft.dueDate,
                paymentTargetAmount: draft.paymentTargetAmount,
                protectedAmount: draft.protectedAmount
            )
        )

        saveDebtPayoffContext()
    }

    private func updateDebtPayoffBucket(
        _ bucket: DebtPayoffBucket,
        draft: DebtPayoffBucketDraft
    ) {
        guard let account = debtAccounts.first(
            where: {
                $0.account_id == draft.plaidAccountID
            }
        ) else {
            return
        }

        bucket.plaidAccountID = account.account_id
        bucket.accountName = account.name
        bucket.institutionName = account.institution_name
        bucket.dueDate = draft.dueDate
        bucket.paymentTargetAmount = draft.paymentTargetAmount
        bucket.protectedAmount = draft.protectedAmount
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
            accounts: plaid.accounts,
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

            Text("Protection")
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
