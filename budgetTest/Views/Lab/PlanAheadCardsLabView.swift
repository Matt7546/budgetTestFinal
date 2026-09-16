#if DEBUG
import SwiftData
import SwiftUI

/// Card-native Plan Ahead: the same planning stream as Timeline Lab, arranged
/// for dense date-by-date scanning rather than a continuous vertical spine.
struct PlanAheadCardsLabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var plaid: PlaidService
    @EnvironmentObject private var auth: AuthManager

    @Query private var events: [PlannerEvent]
    @Query private var allocations: [EventAllocation]
    @Query private var occurrenceStatuses: [ExpenseOccurrenceStatus]
    @Query private var debtPayoffBuckets: [DebtPayoffBucket]
    @Query private var paymentPlanCycles: [PaymentPlanCycle]
    @Query private var incomeSchedules: [IncomeSchedule]

    @State private var selectedAllocationForecast: ForecastEvent?
    @State private var pendingEventToEdit: ForecastEvent?
    @State private var selectedEvent: PlannerEvent?
    @State private var selectedEventForecast: ForecastEvent?
    @State private var scheduleToEdit: IncomeSchedule?
    @State private var selectedSummaryHorizon: LabPlanAheadCardsSummaryHorizon = .days30

    private let calendar = Calendar.current
    private let loadsVisualScenarioOnAppear: Bool

    init(loadsVisualScenarioOnAppear: Bool = true) {
        self.loadsVisualScenarioOnAppear = loadsVisualScenarioOnAppear
    }

    var body: some View {
        ZStack {
            LabPlanAheadCardsBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    hero
                    planningOutlook
                    if !pastDueItems.isEmpty { pastDueSection }
                    if upcomingFinancialItems.isEmpty { emptyState } else { obligationOverview }
                    if !expectedIncomeItems.isEmpty { incomingSection }
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.bottom, AppSpacing.floatingTabClearance)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Plan Ahead Cards Lab")
        .navigationBarTitleDisplayMode(.inline)
        .calderaTransparentNavigationSurface()
        .task(id: loadsVisualScenarioOnAppear) {
            guard loadsVisualScenarioOnAppear else { return }
            loadVisualScenario()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Load scenario", systemImage: "wand.and.stars") { loadVisualScenario() }
                    .accessibilityHint("Loads the Lab visual review scenario using real Plan Ahead models.")
            }
        }
        .sheet(item: $selectedAllocationForecast, onDismiss: presentPendingEventEditorIfNeeded) { forecast in
            EventAllocationDetailView(forecast: forecast) {
                pendingEventToEdit = forecast
                selectedAllocationForecast = nil
            }
        }
        .sheet(item: $selectedEvent, onDismiss: { selectedEventForecast = nil }) { event in
            PlannerEventEditorDestination(
                editingEvent: event,
                forecast: selectedEventForecast,
                onSaved: { _, _ in },
                onScheduleReset: {},
                onDeleted: { _ in }
            )
        }
        .sheet(item: $scheduleToEdit) { schedule in
            IncomeScheduleEditorView(ownerScopeID: schedule.ownerScopeID, editingSchedule: schedule)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text("PLAN AHEAD")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(AppColors.accent)
            Text(monthTitle)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.primaryText)
            Text("A funding overview for what is ahead.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(.top, AppSpacing.panel)
        .padding(.bottom, AppSpacing.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan Ahead Cards Lab. A funding overview for what is ahead. \(monthTitle).")
    }

    private var planningOutlook: some View {
        let presentation = summaryPresentation
        return VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLANNING OUTLOOK")
                        .font(.caption2.weight(.heavy))
                        .tracking(1)
                        .foregroundStyle(AppColors.accent)
                    Text(selectedSummaryHorizon.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                }
                Spacer(minLength: AppSpacing.small)
                Picker("Summary period", selection: $selectedSummaryHorizon) {
                    ForEach(LabPlanAheadCardsSummaryHorizon.allCases) { horizon in
                        Text(horizon.shortTitle).tag(horizon)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 118 : 136)
                .accessibilityLabel("Summary period")
                .accessibilityValue(selectedSummaryHorizon.title)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    metric("Due soon", presentation.dueSoonValue, AppColors.primaryText)
                    metric("Still needed", presentation.stillNeededValue, LabPlanAheadCardsPalette.attention)
                    metric("Covered", presentation.coveredValue, LabPlanAheadCardsPalette.covered)
                }
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    metric("Due soon", presentation.dueSoonValue, AppColors.primaryText)
                    HStack(spacing: AppSpacing.medium) {
                        metric("Still needed", presentation.stillNeededValue, LabPlanAheadCardsPalette.attention)
                        metric("Covered", presentation.coveredValue, LabPlanAheadCardsPalette.covered)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presentation.accessibilitySummary)
            Text(presentation.detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(AppSpacing.medium)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(AppColors.accent.opacity(0.09)))
        .overlay(alignment: .leading) {
            Capsule().fill(AppColors.accent.opacity(0.7)).frame(width: 3, height: 42)
                .padding(.leading, AppSpacing.xSmall)
        }
        .padding(.bottom, AppSpacing.medium)
    }

    private func metric(_ label: String, _ value: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SensitiveValueText(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(AppColors.secondaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pastDueSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                Text("Past Due").font(.title3.weight(.bold)).foregroundStyle(LabPlanAheadCardsPalette.pastDue)
                Text("\(pastDueItems.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LabPlanAheadCardsPalette.pastDue)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(LabPlanAheadCardsPalette.pastDue.opacity(0.13), in: Capsule())
                Spacer()
                Text("Needs attention").font(.caption.weight(.semibold)).foregroundStyle(LabPlanAheadCardsPalette.pastDue)
            }
            obligationGrid(items: pastDueItems, isPastDue: true)
        }
        .padding(.top, AppSpacing.medium)
        .padding(.bottom, AppSpacing.medium)
    }

    private var incomingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                Text("Incoming")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                Spacer()
                Text("Planning only")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppSpacing.small) {
                    ForEach(expectedIncomeItems) { item in
                        if case let .expectedIncome(schedule, date) = item {
                            LabPlanAheadIncomingCard(
                                schedule: schedule,
                                date: date,
                                onTap: { openIncome(schedule) }
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, AppSpacing.medium)
    }

    private var obligationOverview: some View {
        LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
            ForEach(upcomingMonths) { month in
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    HStack(spacing: AppSpacing.small) {
                        Text(month.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppColors.primaryText)
                        Rectangle()
                            .fill(AppColors.accent.opacity(0.22))
                            .frame(height: 1)
                    }
                    obligationGrid(items: month.items, isPastDue: false)
                }
            }
        }
        .padding(.top, AppSpacing.medium)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Nothing is scheduled after today.").font(.headline.weight(.semibold)).foregroundStyle(AppColors.primaryText)
            Text("Add an Upcoming Expense or Payment Plan in the main app to see it here.")
                .font(.subheadline).foregroundStyle(AppColors.secondaryText)
        }
        .padding(.top, AppSpacing.medium)
    }

    private func obligationGrid(items: [LabPlanAheadCardsItem], isPastDue: Bool) -> some View {
        LabPlanAheadCardsObligationGrid(
            items: items,
            allocationAmounts: allocationAmounts,
            accountByID: paymentPlanAccountByID,
            cycles: paymentPlanCycles,
            isPastDue: isPastDue,
            onExpenseTap: openExpense,
            onPaymentPlanTap: openPaymentPlan
        )
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

    private var inactiveOccurrenceIDs: Set<String> {
        ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: cardsOccurrenceStatuses
        )
    }

    private var expenseFundingComposition: UpcomingExpenseFundingComposition {
        UpcomingExpenseFundingComposition(
            events: cardsEvents,
            allocations: cardsAllocations,
            occurrenceStatuses: cardsOccurrenceStatuses
        )
    }

    private var forecastEvents: [ForecastEvent] {
        // The timeline needs the existing occurrence stream and durable funding
        // merge, not a second Available to Spend calculation. Per-event funding
        // remains sourced from the same allocation lookup used in Plan Ahead.
        expenseFundingComposition.forecastCalculator(
            events: cardsEvents,
            totalAvailable: 0,
            totalGoalAllocated: 0,
            reserveBalance: 0,
            includeFutureIncome: true,
            protectGoals: true,
            allocatedAmountProvider: { forecast in
                allocationAmounts.allocatedAmount(for: forecast)
            },
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
        .forecastEvents
    }

    private var unresolvedPastDueExpenseForecasts: [ForecastEvent] {
        ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
            from: forecastEvents,
            statuses: cardsOccurrenceStatuses
        )
    }

    private var upcomingExpenseForecasts: [ForecastEvent] {
        forecastEvents.filter {
            $0.event.type == .expense &&
                calendar.startOfDay(for: $0.occurrenceDate) >= startOfToday
        }
    }

    private var visiblePaymentPlans: [DebtPayoffBucket] {
        debtPayoffBuckets
            .filter { bucket in
                !loadsVisualScenarioOnAppear ||
                    LabPlanAheadTimelineFixture.contains(paymentPlan: bucket)
            }
            .filter { bucket in
                bucket.shouldDisplayDueDate &&
                    PlanAheadPaymentPlanWindow.isVisible(
                        paymentPlanID: bucket.id,
                        cycles: paymentPlanCycles
                    )
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var planAheadPaymentPlans: [PlanAheadPaymentPlan] {
        visiblePaymentPlans.map { bucket in
            PlanAheadPaymentPlan(
                bucket: bucket,
                dueDate: PlanAheadPaymentPlanWindow.effectiveDueDate(
                    bucketDueDate: bucket.dueDate,
                    activeCycle: PaymentPlanCycleStore.activeCycle(
                        for: bucket.id,
                        in: paymentPlanCycles
                    )
                )
            )
        }
    }

    private var pastDueItems: [LabPlanAheadCardsItem] {
        PlanAheadTimelineItems.pastDue(
            expenses: unresolvedPastDueExpenseForecasts,
            paymentPlans: planAheadPaymentPlans,
            startOfToday: startOfToday
        )
        .map(LabPlanAheadCardsItem.financial)
    }

    private var upcomingFinancialItems: [LabPlanAheadCardsItem] {
        PlanAheadTimelineItems.upcoming(
            expenses: upcomingExpenseForecasts,
            paymentPlans: planAheadPaymentPlans,
            startOfToday: startOfToday
        )
        .map(LabPlanAheadCardsItem.financial)
        .sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.id < rhs.id
        }
    }

    private var expectedIncomeItems: [LabPlanAheadCardsItem] {
        if let schedule = visibleIncomeSchedule,
           let date = IncomeScheduleCalendar.nextDisplayDate(for: schedule) {
            return [
                .expectedIncome(schedule: schedule, date: date)
            ]
        }
        return []
    }

    private var upcomingMonths: [LabPlanAheadCardsMonth] {
        Dictionary(grouping: upcomingFinancialItems) { item in
            calendar.dateComponents([.year, .month], from: item.date)
        }
        .compactMap { components, items in
            guard let date = calendar.date(from: components) else { return nil }
            return LabPlanAheadCardsMonth(date: date, items: items.sorted { $0.date < $1.date })
        }
        .sorted { $0.date < $1.date }
    }

    private var visibleIncomeSchedule: IncomeSchedule? {
        IncomeSchedulePhaseOnePolicy.visibleSchedule(
            from: loadsVisualScenarioOnAppear
                ? incomeSchedules.filter(LabPlanAheadTimelineFixture.contains)
                : incomeSchedules,
            ownerScopeID: IncomeScheduleOwnerScope.current(
                authenticatedUserID: auth.user?.id
            )
        )
    }

    private var allocationAmounts: EventAllocationAmountLookup {
        EventAllocationAmountLookup(allocations: cardsAllocations)
    }

    private var cardsEvents: [PlannerEvent] {
        loadsVisualScenarioOnAppear
            ? events.filter(LabPlanAheadTimelineFixture.contains)
            : events
    }

    private var cardsAllocations: [EventAllocation] {
        guard loadsVisualScenarioOnAppear else { return allocations }
        let fixtureEventIDs = Set(cardsEvents.map(\.id))
        return allocations.filter { fixtureEventIDs.contains($0.sourceEventID) }
    }

    private var cardsOccurrenceStatuses: [ExpenseOccurrenceStatus] {
        guard loadsVisualScenarioOnAppear else { return occurrenceStatuses }
        let fixtureEventIDs = Set(cardsEvents.map(\.id))
        return occurrenceStatuses.filter { fixtureEventIDs.contains($0.sourceEventID) }
    }

    private var paymentPlanAccountByID: [String: PlaidAccount] {
        Dictionary(
            uniqueKeysWithValues: plaid.accounts.deduplicatedForDisplayAndTotals.map {
                ($0.account_id, $0)
            }
        )
    }

    private var monthTitle: String {
        Date().formatted(.dateTime.month(.wide).year())
    }

    private var summaryPresentation: PlanAheadSummaryPresentation {
        let expenseEntries = upcomingExpenseForecasts
            .filter { isInSummaryHorizon($0.occurrenceDate) }
            .map { forecast in
            let allocated = min(
                max(allocationAmounts.allocatedAmount(for: forecast), 0),
                forecast.event.amount
            )
            return PlanAheadSummaryEntry(
                dueAmount: forecast.event.amount,
                coveredAmount: allocated,
                stillNeededAmount: max(forecast.event.amount - allocated, 0)
            )
        }
        let paymentEntries = planAheadPaymentPlans
            .filter { isInSummaryHorizon($0.dueDate) }
            .map { paymentPlan in
            let cycle = PaymentPlanCycleStore.activeCycle(
                for: paymentPlan.bucket.id,
                in: paymentPlanCycles
            )
            let display = DebtPayoffDisplayModel(
                bucket: paymentPlan.bucket,
                linkedAccount: paymentPlanAccountByID[paymentPlan.bucket.plaidAccountID],
                cycle: cycle
            )
            return PlanAheadSummaryEntry(
                dueAmount: display.plannedPaymentAmount,
                coveredAmount: display.coveredPaymentAmount,
                stillNeededAmount: display.remainingPaymentAmount
            )
        }

        return PlanAheadSummaryPresentation(
            entries: expenseEntries + paymentEntries,
            pastDueCount: pastDueItems.count
        )
    }

    private func isInSummaryHorizon(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard let end = calendar.date(
            byAdding: .day,
            value: selectedSummaryHorizon.dayCount,
            to: startOfToday
        ) else {
            return false
        }
        return day >= startOfToday && day < end
    }

    private func openExpense(_ forecast: ForecastEvent) {
        selectedAllocationForecast = forecast
    }

    private func loadVisualScenario() {
        LabPlanAheadTimelineFixture.load(
            into: modelContext,
            ownerScopeID: IncomeScheduleOwnerScope.current(
                authenticatedUserID: auth.user?.id
            ),
            events: events,
            allocations: allocations,
            paymentPlans: debtPayoffBuckets,
            cycles: paymentPlanCycles,
            incomeSchedules: incomeSchedules
        )
    }

    private func openPaymentPlan(_ paymentPlan: PlanAheadPaymentPlan) {
        let cycle = PaymentPlanCycleStore.activeCycle(
            for: paymentPlan.bucket.id,
            in: paymentPlanCycles
        )
        navigation.openSavingsEditDebtPayoff(
            paymentPlan.bucket.id,
            cycleID: cycle?.id
        )
    }

    private func openIncome(_ schedule: IncomeSchedule) {
        scheduleToEdit = schedule
    }

    private func presentPendingEventEditorIfNeeded() {
        guard let forecast = pendingEventToEdit else { return }
        pendingEventToEdit = nil
        selectedEventForecast = forecast
        selectedEvent = forecast.event
    }
}

private struct LabPlanAheadCardsMonth: Identifiable {
    let date: Date
    let items: [LabPlanAheadCardsItem]
    var id: Date { date }
    var title: String {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
            ? "This month"
            : date.formatted(.dateTime.month(.wide).year())
    }
}

private enum LabPlanAheadCardsSummaryHorizon: Int, CaseIterable, Identifiable {
    case days7 = 7
    case days30 = 30
    case days90 = 90
    var id: Int { rawValue }
    var dayCount: Int { rawValue }
    var title: String { "Next \(rawValue) days" }
    var shortTitle: String { "\(rawValue)d" }
}

private enum LabPlanAheadCardsItem: Identifiable {
    case financial(PlanAheadTimelineItem)
    case expectedIncome(schedule: IncomeSchedule, date: Date)
    var id: String {
        switch self {
        case .financial(let item): return item.id
        case .expectedIncome(let schedule, let date):
            return "expected-income-\(schedule.id.uuidString)-\(IncomeScheduleCalendar.dateKey(for: date))"
        }
    }
    var date: Date {
        switch self {
        case .financial(let item): return item.dueDate
        case .expectedIncome(_, let date): return date
        }
    }
}

private struct LabPlanAheadCardsObligationGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let items: [LabPlanAheadCardsItem]
    let allocationAmounts: EventAllocationAmountLookup
    let accountByID: [String: PlaidAccount]
    let cycles: [PaymentPlanCycle]
    let isPastDue: Bool
    let onExpenseTap: (ForecastEvent) -> Void
    let onPaymentPlanTap: (PlanAheadPaymentPlan) -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.small) {
            ForEach(items) { item in
                card(for: item)
            }
        }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [
                GridItem(.flexible(), spacing: AppSpacing.small),
                GridItem(.flexible(), spacing: AppSpacing.small)
            ]
    }

    @ViewBuilder
    private func card(for item: LabPlanAheadCardsItem) -> some View {
        switch item {
        case .financial(.upcomingExpense(let forecast)):
            LabPlanAheadExpenseCard(
                forecast: forecast,
                date: item.date,
                allocatedAmount: allocationAmounts.allocatedAmount(for: forecast),
                isPastDue: isPastDue,
                onTap: { onExpenseTap(forecast) }
            )
        case .financial(.paymentPlan(let paymentPlan)):
            LabPlanAheadPaymentPlanCard(
                paymentPlan: paymentPlan,
                date: item.date,
                cycle: PaymentPlanCycleStore.activeCycle(for: paymentPlan.bucket.id, in: cycles),
                linkedAccount: accountByID[paymentPlan.bucket.plaidAccountID],
                isPastDue: isPastDue,
                onTap: { onPaymentPlanTap(paymentPlan) }
            )
        case .expectedIncome:
            EmptyView()
        }
    }
}

private struct LabPlanAheadExpenseCard: View {
    let forecast: ForecastEvent
    let date: Date
    let allocatedAmount: Double
    let isPastDue: Bool
    let onTap: () -> Void

    private var setAside: Double { min(max(allocatedAmount, 0), forecast.event.amount) }
    private var remaining: Double { max(forecast.event.amount - setAside, 0) }
    private var covered: Bool { remaining <= 0.005 }

    var body: some View {
        LabPlanAheadEventCardSurface(
            title: forecast.event.name,
            amount: AppFormatters.currency(forecast.event.amount),
            type: "Upcoming Expense",
            timing: date.formatted(.dateTime.month(.abbreviated).day()),
            status: isPastDue ? "Past Due" : PlannerExpenseFundingStatus.resolve(isCovered: covered, remainingAmount: remaining).text,
            setAside: AppFormatters.currency(setAside),
            fundingDetail: fundingDetail,
            progress: forecast.event.amount > 0 ? setAside / forecast.event.amount : 0,
            accent: isPastDue ? LabPlanAheadCardsPalette.pastDue : LabPlanAheadCardsPalette.expense,
            systemImage: "calendar.badge.clock",
            onTap: onTap
        )
        .accessibilityHint("Opens this exact expense occurrence.")
    }

    private var fundingDetail: String {
        if covered { return "Covered" }
        if setAside > 0.005 {
            return "\(AppFormatters.wholeCurrency(setAside)) set aside · \(AppFormatters.wholeCurrency(remaining)) needed"
        }
        return "\(AppFormatters.wholeCurrency(remaining)) needed"
    }
}

private struct LabPlanAheadPaymentPlanCard: View {
    let paymentPlan: PlanAheadPaymentPlan
    let date: Date
    let cycle: PaymentPlanCycle?
    let linkedAccount: PlaidAccount?
    let isPastDue: Bool
    let onTap: () -> Void
    private var display: DebtPayoffDisplayModel {
        DebtPayoffDisplayModel(bucket: paymentPlan.bucket, linkedAccount: linkedAccount, cycle: cycle)
    }

    var body: some View {
        LabPlanAheadEventCardSurface(
            title: display.title,
            amount: display.plannedPaymentValue,
            type: "Payment Plan",
            timing: date.formatted(.dateTime.month(.abbreviated).day()),
            status: isPastDue ? "Past Due" : display.presentationStatusValue,
            setAside: display.setAsideValue,
            fundingDetail: fundingDetail,
            progress: display.plannedPaymentAmount > 0
                ? display.coveredPaymentAmount / display.plannedPaymentAmount
                : 0,
            accent: isPastDue ? LabPlanAheadCardsPalette.pastDue : LabPlanAheadCardsPalette.payment,
            systemImage: "creditcard.fill",
            onTap: onTap
        )
        .accessibilityHint("Opens this payment plan and its active payment cycle.")
    }

    private var fundingDetail: String {
        if display.remainingPaymentAmount <= 0.005 { return "Covered" }
        if display.coveredPaymentAmount > 0.005 {
            return "\(AppFormatters.wholeCurrency(display.coveredPaymentAmount)) set aside · \(AppFormatters.wholeCurrency(display.remainingPaymentAmount)) needed"
        }
        return "\(AppFormatters.wholeCurrency(display.remainingPaymentAmount)) needed"
    }
}

private struct LabPlanAheadIncomingCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let schedule: IncomeSchedule
    let date: Date
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(LabPlanAheadCardsPalette.income)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXPECTED INCOME")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.6)
                        .foregroundStyle(LabPlanAheadCardsPalette.income)
                    Text(schedule.sourceLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.primaryText)
                    Text("Doesn’t increase spendable cash until deposit.")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: AppSpacing.small)
                VStack(alignment: .trailing, spacing: 2) {
                    SensitiveValueText(AppFormatters.currency(schedule.takeHomeAmount))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppColors.primaryText)
                        .monospacedDigit()
                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LabPlanAheadCardsPalette.income)
                }
            }
            .frame(width: 310, alignment: .leading)
            .padding(AppSpacing.medium)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.50))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LabPlanAheadCardsPalette.income.opacity(colorScheme == .dark ? 0.22 : 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expected income, \(schedule.sourceLabel), \(AppFormatters.currency(schedule.takeHomeAmount)), \(date.formatted(.dateTime.month(.wide).day())). Does not increase spendable cash until deposit.")
        .accessibilityHint("Edits expected income.")
    }
}

private struct LabPlanAheadEventCardSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let amount: String
    let type: String
    let timing: String
    let status: String
    let setAside: String
    let fundingDetail: String
    let progress: Double
    let accent: Color
    let systemImage: String
    let onTap: () -> Void

    private var visualFundingDetail: String {
        status == "Past Due" ? "Past due · " + fundingDetail : fundingDetail
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: AppSpacing.small) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                        .background(accent.opacity(0.13), in: Circle())
                    Text(title)
                        .font(dynamicTypeSize.isAccessibilitySize ? .title3.weight(.semibold) : .headline.weight(.semibold))
                        .foregroundStyle(AppColors.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .firstTextBaseline) {
                    SensitiveValueText(amount)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppColors.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: AppSpacing.xSmall)
                    Text(timing.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(0.65)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(accent)
                    Text(visualFundingDetail)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 128, alignment: .leading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.46))
            }
            .overlay(alignment: .leading) {
                Capsule().fill(accent.opacity(0.80)).frame(width: 3, height: 26)
                    .padding(.leading, AppSpacing.xSmall)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(accent.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type), \(title), due \(timing), \(amount), \(setAside) set aside, \(fundingDetail), \(status)")
        .accessibilityAddTraits(.isButton)
    }
}

private enum LabPlanAheadCardsPalette {
    static let expense = AppColors.accent
    static let payment = Color(red: 0.26, green: 0.32, blue: 0.76)
    static let income = Color(red: 0.02, green: 0.49, blue: 0.43)
    static let covered = Color(red: 0.02, green: 0.49, blue: 0.43)
    static let attention = Color(red: 0.82, green: 0.38, blue: 0.10)
    static let pastDue = AppColors.warning
}

private struct LabPlanAheadCardsBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.025, green: 0.045, blue: 0.10), Color(red: 0.045, green: 0.08, blue: 0.16), Color(red: 0.025, green: 0.04, blue: 0.09)]
                    : [Color(red: 0.94, green: 0.97, blue: 1.00), Color(red: 0.90, green: 0.94, blue: 0.99), Color(red: 0.96, green: 0.98, blue: 1.00)],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [AppColors.accent.opacity(colorScheme == .dark ? 0.18 : 0.10), .clear],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
#endif
