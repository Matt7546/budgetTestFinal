import SwiftUI
import SwiftData

struct SavingsGoalsView: View {

    @EnvironmentObject private var plaid: PlaidService
    @EnvironmentObject private var navigation: AppNavigation

    @Query
    private var events: [PlannerEvent]

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

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

    @State private var activeGoalSheet: ActiveGoalSheet?
    @State private var reserveAmountText = ""
    @State private var selectedAllocationForecast: ForecastEvent?
    @State private var selectedEvent: PlannerEvent?

    private var totalSaved: Double {
        plaid.savingsGoals.totalSaved
    }

    private var protectedTotal: Double {
        plaid.reserveBalance + totalSaved
    }

    private var totalUpcomingExpenseAllocated: Double {
        upcomingExpenseAllocations.reduce(0) {
            $0 + $1.allocatedAmount
        }
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
        AppScreen {
            header

            summaryStrip

            reserveCard

            savingsGoalsSection

            upcomingExpensesSection
        }
        .navigationTitle("Savings")
        .navigationBarTitleDisplayMode(.inline)
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
        HStack(spacing: AppSpacing.small) {
            summaryPill(
                title: "Protected",
                value: AppFormatters.currency(protectedTotal),
                color: AppColors.protected
            )

            summaryPill(
                title: "Goals",
                value: AppFormatters.currency(totalSaved),
                color: AppColors.protected
            )

            summaryPill(
                title: "Expenses",
                value: AppFormatters.currency(totalUpcomingExpenseAllocated),
                color: AppColors.warning
            )
        }
    }

    private var reserveCard: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.medium) {
                IconBadge(
                    systemImage: "lock.shield.fill",
                    color: AppColors.protected,
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

                    Text("Money intentionally protected")
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
            .glassCard(
                cornerRadius: AppRadii.field,
                shadow: nil
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
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.protected.opacity(0.07),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: AppShadows.softPanelCompact
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
                    title: "Start your Savings Goals",
                    subtitle: "Create your first goal and keep it separate from everyday spending.",
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
                    subtitle: "Add an expense in Timeline to track what is coming next.",
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
                IconBadge(
                    systemImage: systemImage,
                    color: color,
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
    }

    private func summaryPill(
        title: String,
        value: String,
        color: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xxSmall) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.medium)
        .padding(.horizontal, AppSpacing.small)
        .glassCard(
            cornerRadius: AppRadii.field,
            shadow: nil
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
                : AppFormatters.currency(remainingAmount),
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
            IconBadge(
                systemImage: systemImage,
                color: color,
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
        .glassCard(
            cornerRadius: AppRadii.field,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    color.opacity(0.04),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: nil
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
                IconBadge(
                    systemImage: systemImage,
                    color: color,
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

            ProgressView(value: progress)
                .tint(color)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            rowAction?()
        }
        .padding(AppSpacing.medium)
        .glassCard(
            cornerRadius: AppRadii.field,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    color.opacity(0.04),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: nil
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

    private func progress(
        allocated: Double,
        amount: Double
    ) -> Double {
        guard amount > 0 else {
            return 0
        }

        return min(allocated / amount, 1)
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

    private var totalSaved: Double {
        plaid.savingsGoals.totalSaved
    }

    private var totalTarget: Double {
        plaid.savingsGoals.totalTarget
    }

    private var overallProgress: Double {
        guard totalTarget > 0 else { return 0 }
        return totalSaved / totalTarget
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
