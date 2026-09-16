#if DEBUG
import SwiftData
import SwiftUI

/// A Lab-only composition that reuses Plan Ahead's live forecast and funding
/// models, while testing a more spatial, date-led reading of the plan.
struct LabPlanAheadTimelineView: View {

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
    @State private var selectedSummaryHorizon: LabPlanAheadSummaryHorizon = .days30

    private let calendar = Calendar.current
    private let loadsVisualScenarioOnAppear: Bool

    init(loadsVisualScenarioOnAppear: Bool = false) {
        self.loadsVisualScenarioOnAppear = loadsVisualScenarioOnAppear
    }

    var body: some View {
        ZStack {
            LabPlanAheadTimelineBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    timelineHero
                    planningSummary

                    if !pastDueItems.isEmpty {
                        pastDueSection
                    }

                    todayAnchor

                    if upcomingItems.isEmpty {
                        emptyTimeline
                    } else {
                        futureTimeline
                    }
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.bottom, AppSpacing.floatingTabClearance)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Plan Ahead Lab")
        .navigationBarTitleDisplayMode(.inline)
        .calderaTransparentNavigationSurface()
        .task(id: loadsVisualScenarioOnAppear) {
            guard loadsVisualScenarioOnAppear else { return }
            loadVisualScenario()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Load scenario", systemImage: "wand.and.stars") {
                    loadVisualScenario()
                }
                .accessibilityHint("Loads the Lab visual review scenario using real Plan Ahead models.")
            }
        }
        .sheet(
            item: $selectedAllocationForecast,
            onDismiss: presentPendingEventEditorIfNeeded
        ) { forecast in
            EventAllocationDetailView(forecast: forecast) {
                pendingEventToEdit = forecast
                selectedAllocationForecast = nil
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
                onSaved: { _, _ in },
                onScheduleReset: {},
                onDeleted: { _ in }
            )
        }
        .sheet(item: $scheduleToEdit) { schedule in
            IncomeScheduleEditorView(
                ownerScopeID: schedule.ownerScopeID,
                editingSchedule: schedule
            )
        }
    }

    private var timelineHero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text("PLAN AHEAD")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(AppColors.accent)

            Text(monthTitle)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Your financial future, laid out over time.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, AppSpacing.large)
        .padding(.bottom, AppSpacing.panel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan Ahead Lab. Your financial future laid out over time. \(monthTitle).")
    }

    private var pastDueSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("Past Due")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(LabPlanAheadPalette.pastDue)

                Text("\(pastDueItems.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LabPlanAheadPalette.pastDue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(LabPlanAheadPalette.pastDue.opacity(0.12), in: Capsule())
            }

            Text("Still open before today.")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.secondaryText)

            LabPlanAheadTimelineTrack(
                days: grouped(pastDueItems),
                allocationAmounts: allocationAmounts,
                accountByID: paymentPlanAccountByID,
                cycles: paymentPlanCycles,
                isPastDue: true,
                onExpenseTap: openExpense,
                onPaymentPlanTap: openPaymentPlan,
                onIncomeTap: openIncome
            )
        }
        .padding(.vertical, AppSpacing.card)
    }

    private var planningSummary: some View {
        let presentation = summaryPresentation

        return VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("PLANNING OUTLOOK")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(AppColors.accent)

                Spacer(minLength: AppSpacing.small)

                Picker("Summary period", selection: $selectedSummaryHorizon) {
                    ForEach(LabPlanAheadSummaryHorizon.allCases) { horizon in
                        Text(horizon.shortTitle).tag(horizon)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 136)
                .accessibilityLabel("Summary period")
                .accessibilityValue(selectedSummaryHorizon.title)
                .accessibilityHint("Choose 7, 30, or 90 days for the planning summary.")
            }

            Group {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppSpacing.large) {
                        planningMetric("Due soon", presentation.dueSoonValue)
                        planningMetric("Still needed", presentation.stillNeededValue)
                        planningMetric("Covered", presentation.coveredValue)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        planningMetric("Due soon", presentation.dueSoonValue)
                        HStack(spacing: AppSpacing.large) {
                            planningMetric("Still needed", presentation.stillNeededValue)
                            planningMetric("Covered", presentation.coveredValue)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Due soon, \(presentation.dueSoonValue). Still needed, \(presentation.stillNeededValue). Covered, \(presentation.coveredValue)."
            )
        }
        .padding(AppSpacing.medium)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.accent.opacity(0.075))
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppColors.accent.opacity(0.55))
                .frame(width: 2)
                .padding(.vertical, AppSpacing.medium)
        }
        .padding(.bottom, AppSpacing.small)
    }

    private func planningMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SensitiveValueText(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayAnchor: some View {
        HStack(alignment: .center, spacing: 0) {
            LabPlanAheadAxisMarker(color: AppColors.accent, diameter: 12)
                .frame(width: LabPlanAheadTimelineAxis.railWidth)
                .zIndex(1)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Text("Today · \(Date().formatted(.dateTime.weekday(.abbreviated).day()))")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppColors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    HStack(spacing: AppSpacing.medium) {
                        Rectangle()
                            .fill(AppColors.accent.opacity(0.35))
                            .frame(height: 1)

                        VStack(spacing: 2) {
                            Text("TODAY")
                                .font(.caption2.weight(.heavy))
                                .tracking(1)
                                .foregroundStyle(AppColors.accent)
                            Text(Date().formatted(.dateTime.weekday(.abbreviated).day()))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppColors.primaryText)
                        }
                        .padding(.horizontal, AppSpacing.small)

                        Rectangle()
                            .fill(AppColors.accent.opacity(0.35))
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(.vertical, AppSpacing.large)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today, \(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))")
    }

    private var futureTimeline: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("Ahead")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.primaryText)

            LabPlanAheadTimelineTrack(
                days: grouped(upcomingItems),
                allocationAmounts: allocationAmounts,
                accountByID: paymentPlanAccountByID,
                cycles: paymentPlanCycles,
                isPastDue: false,
                onExpenseTap: openExpense,
                onPaymentPlanTap: openPaymentPlan,
                onIncomeTap: openIncome
            )
        }
    }

    private var emptyTimeline: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Nothing is scheduled after today.")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
            Text("Add an Upcoming Expense or Payment Plan in the main app to see it here.")
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(.leading, LabPlanAheadTimelineAxis.railWidth)
        .padding(.top, AppSpacing.medium)
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

    private var inactiveOccurrenceIDs: Set<String> {
        ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: timelineOccurrenceStatuses
        )
    }

    private var expenseFundingComposition: UpcomingExpenseFundingComposition {
        UpcomingExpenseFundingComposition(
            events: timelineEvents,
            allocations: timelineAllocations,
            occurrenceStatuses: timelineOccurrenceStatuses
        )
    }

    private var forecastEvents: [ForecastEvent] {
        // The timeline needs the existing occurrence stream and durable funding
        // merge, not a second Available to Spend calculation. Per-event funding
        // remains sourced from the same allocation lookup used in Plan Ahead.
        expenseFundingComposition.forecastCalculator(
            events: timelineEvents,
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
            statuses: timelineOccurrenceStatuses
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

    private var pastDueItems: [LabPlanAheadTimelineItem] {
        PlanAheadTimelineItems.pastDue(
            expenses: unresolvedPastDueExpenseForecasts,
            paymentPlans: planAheadPaymentPlans,
            startOfToday: startOfToday
        )
        .map(LabPlanAheadTimelineItem.financial)
    }

    private var upcomingItems: [LabPlanAheadTimelineItem] {
        let financial = PlanAheadTimelineItems.upcoming(
            expenses: upcomingExpenseForecasts,
            paymentPlans: planAheadPaymentPlans,
            startOfToday: startOfToday
        )
        .map(LabPlanAheadTimelineItem.financial)

        let expectedIncome: [LabPlanAheadTimelineItem]
        if let schedule = visibleIncomeSchedule,
           let date = IncomeScheduleCalendar.nextDisplayDate(for: schedule) {
            expectedIncome = [
                .expectedIncome(schedule: schedule, date: date)
            ]
        } else {
            expectedIncome = []
        }

        return (financial + expectedIncome).sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }

            return lhs.id < rhs.id
        }
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
        EventAllocationAmountLookup(allocations: timelineAllocations)
    }

    private var timelineEvents: [PlannerEvent] {
        loadsVisualScenarioOnAppear
            ? events.filter(LabPlanAheadTimelineFixture.contains)
            : events
    }

    private var timelineAllocations: [EventAllocation] {
        guard loadsVisualScenarioOnAppear else { return allocations }
        let fixtureEventIDs = Set(timelineEvents.map(\.id))
        return allocations.filter { fixtureEventIDs.contains($0.sourceEventID) }
    }

    private var timelineOccurrenceStatuses: [ExpenseOccurrenceStatus] {
        guard loadsVisualScenarioOnAppear else { return occurrenceStatuses }
        let fixtureEventIDs = Set(timelineEvents.map(\.id))
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
            pastDueCount: 0
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

    private func grouped(
        _ items: [LabPlanAheadTimelineItem]
    ) -> [LabPlanAheadTimelineDay] {
        var groups: [LabPlanAheadTimelineDay] = []

        for item in items {
            let date = calendar.startOfDay(for: item.date)
            if let last = groups.indices.last,
               calendar.isDate(groups[last].date, inSameDayAs: date) {
                groups[last].items.append(item)
            } else {
                groups.append(.init(date: date, items: [item]))
            }
        }

        return groups
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

private struct LabPlanAheadTimelineDay: Identifiable {
    let date: Date
    var items: [LabPlanAheadTimelineItem]

    var id: Date { date }
}

private enum LabPlanAheadSummaryHorizon: Int, CaseIterable, Identifiable {
    case days7 = 7
    case days30 = 30
    case days90 = 90

    var id: Int { rawValue }
    var dayCount: Int { rawValue }
    var title: String { "Next \(rawValue) days" }
    var shortTitle: String { "\(rawValue)d" }
}

private enum LabPlanAheadTimelineAxis {
    /// The date rail leaves room for a distinct time axis and attachment line.
    static let railWidth: CGFloat = 50
    static let nodeDiameter: CGFloat = 14
    static let nodeGap: CGFloat = 7
    static let axisX: CGFloat = 44
    static let spineWidth: CGFloat = 3
    static let eventLeadingGap: CGFloat = 8
    static let monthLabelGap: CGFloat = 16
}

/// Every attachment shares this axis coordinate: date node, Today, and month
/// transition cannot drift apart as the screen adapts for Dynamic Type.
private struct LabPlanAheadAxisMarker: View {
    let color: Color
    let diameter: CGFloat

    var body: some View {
        Color.clear
            .frame(height: diameter)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(color)
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.82), lineWidth: 3)
                    }
                    .offset(x: LabPlanAheadTimelineAxis.axisX - diameter / 2)
            }
            .accessibilityHidden(true)
    }
}

private enum LabPlanAheadTimelineItem: Identifiable {
    case financial(PlanAheadTimelineItem)
    case expectedIncome(schedule: IncomeSchedule, date: Date)

    var id: String {
        switch self {
        case .financial(let item):
            return item.id
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

private struct LabPlanAheadTimelineTrack: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let days: [LabPlanAheadTimelineDay]
    let allocationAmounts: EventAllocationAmountLookup
    let accountByID: [String: PlaidAccount]
    let cycles: [PaymentPlanCycle]
    let isPastDue: Bool
    let onExpenseTap: (ForecastEvent) -> Void
    let onPaymentPlanTap: (PlanAheadPaymentPlan) -> Void
    let onIncomeTap: (IncomeSchedule) -> Void

    private let calendar = Calendar.current

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(days.indices, id: \.self) { index in
                let day = days[index]
                if index == 0 || !calendar.isDate(day.date, equalTo: days[index - 1].date, toGranularity: .month) {
                    monthTransition(day.date)
                }

                dayRow(day)
                    .padding(.bottom, AppSpacing.large)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(
                    (isPastDue ? LabPlanAheadPalette.pastDue : AppColors.accent)
                        .opacity(isPastDue ? 0.34 : 0.42)
                )
                .frame(width: LabPlanAheadTimelineAxis.spineWidth)
                .offset(
                    x: LabPlanAheadTimelineAxis.axisX
                        - LabPlanAheadTimelineAxis.spineWidth / 2
                )
                .padding(.vertical, 5)
                .allowsHitTesting(false)
        }
    }

    private func monthTransition(_ date: Date) -> some View {
        HStack(alignment: .center, spacing: 0) {
            LabPlanAheadAxisMarker(
                color: isPastDue ? LabPlanAheadPalette.pastDue : AppColors.accent,
                diameter: 8
            )
            .frame(width: LabPlanAheadTimelineAxis.railWidth)
            .zIndex(1)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(date.formatted(.dateTime.month(.abbreviated).year()))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppColors.primaryText)
                } else {
                    HStack(spacing: AppSpacing.small) {
                        Text(date.formatted(.dateTime.month(.wide).year()))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppColors.primaryText)
                        Rectangle()
                            .fill(AppColors.accent.opacity(0.22))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.leading, LabPlanAheadTimelineAxis.monthLabelGap)
        }
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.medium)
    }

    private func dayRow(_ day: LabPlanAheadTimelineDay) -> some View {
        HStack(alignment: .top, spacing: 0) {
            LabPlanAheadDateMarker(date: day.date, isPastDue: isPastDue)
                .frame(width: LabPlanAheadTimelineAxis.railWidth)
                .zIndex(1)

            VStack(spacing: AppSpacing.small) {
                ForEach(day.items) { item in
                    eventRow(item)
                }
            }
            .padding(.leading, LabPlanAheadTimelineAxis.eventLeadingGap)
        }
    }

    @ViewBuilder
    private func eventRow(_ item: LabPlanAheadTimelineItem) -> some View {
        switch item {
        case .financial(.upcomingExpense(let forecast)):
            LabPlanAheadExpenseRow(
                forecast: forecast,
                allocatedAmount: allocationAmounts.allocatedAmount(for: forecast),
                isPastDue: isPastDue,
                onTap: { onExpenseTap(forecast) }
            )
        case .financial(.paymentPlan(let paymentPlan)):
            LabPlanAheadPaymentPlanRow(
                paymentPlan: paymentPlan,
                cycle: PaymentPlanCycleStore.activeCycle(
                    for: paymentPlan.bucket.id,
                    in: cycles
                ),
                linkedAccount: accountByID[paymentPlan.bucket.plaidAccountID],
                onTap: { onPaymentPlanTap(paymentPlan) }
            )
        case .expectedIncome(let schedule, _):
            LabPlanAheadIncomeRow(schedule: schedule) {
                onIncomeTap(schedule)
            }
        }
    }
}

private struct LabPlanAheadDateMarker: View {
    let date: Date
    let isPastDue: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(
                    width: LabPlanAheadTimelineAxis.axisX
                        - LabPlanAheadTimelineAxis.nodeDiameter / 2
                        - LabPlanAheadTimelineAxis.nodeGap,
                    alignment: .trailing
                )
                .padding(.top, 10)

            Circle()
                .fill(isPastDue ? LabPlanAheadPalette.pastDue : AppColors.accent)
                .frame(
                    width: LabPlanAheadTimelineAxis.nodeDiameter,
                    height: LabPlanAheadTimelineAxis.nodeDiameter
                )
                .overlay {
                    Circle().stroke(Color.white.opacity(0.82), lineWidth: 3)
                }
                .offset(
                    x: LabPlanAheadTimelineAxis.axisX
                        - LabPlanAheadTimelineAxis.nodeDiameter / 2,
                    y: 14
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        )
    }
}

private struct LabPlanAheadExpenseRow: View {
    let forecast: ForecastEvent
    let allocatedAmount: Double
    let isPastDue: Bool
    let onTap: () -> Void

    private var setAsideAmount: Double {
        min(max(allocatedAmount, 0), forecast.event.amount)
    }

    private var remainingAmount: Double {
        max(forecast.event.amount - setAsideAmount, 0)
    }

    private var isCovered: Bool { remainingAmount <= 0.005 }

    private var status: String {
        if isPastDue { return "Past Due" }
        return PlannerExpenseFundingStatus.resolve(
            isCovered: isCovered,
            remainingAmount: remainingAmount
        ).text
    }

    var body: some View {
        LabPlanAheadEventSurface(
            title: forecast.event.name,
            amount: AppFormatters.currency(forecast.event.amount),
            type: "Upcoming Expense",
            status: status,
            detail: "\(AppFormatters.currency(setAsideAmount)) set aside",
            accent: isPastDue
                ? LabPlanAheadPalette.pastDue
                : LabPlanAheadPalette.expense,
            systemImage: "calendar.badge.clock"
        )
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens this exact expense occurrence.")
    }
}

private struct LabPlanAheadPaymentPlanRow: View {
    let paymentPlan: PlanAheadPaymentPlan
    let cycle: PaymentPlanCycle?
    let linkedAccount: PlaidAccount?
    let onTap: () -> Void

    private var display: DebtPayoffDisplayModel {
        DebtPayoffDisplayModel(
            bucket: paymentPlan.bucket,
            linkedAccount: linkedAccount,
            cycle: cycle
        )
    }

    var body: some View {
        LabPlanAheadEventSurface(
            title: display.title,
            amount: display.plannedPaymentValue,
            type: "Payment Plan",
            status: display.presentationStatusValue,
            detail: "\(display.setAsideValue) set aside · \(display.remainingValue)",
            accent: display.presentationStatus.isReassuring
                ? LabPlanAheadPalette.payment
                : LabPlanAheadPalette.payment,
            systemImage: "creditcard.fill"
        )
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens this payment plan and its active payment cycle.")
    }
}

private struct LabPlanAheadIncomeRow: View {
    let schedule: IncomeSchedule
    let onTap: () -> Void

    var body: some View {
        LabPlanAheadEventSurface(
            title: schedule.sourceLabel,
            amount: AppFormatters.currency(schedule.takeHomeAmount),
            type: "Expected Income",
            status: "Planning estimate",
            detail: "Not included in Available to Spend until it arrives.",
            accent: LabPlanAheadPalette.income,
            systemImage: "arrow.down.circle.fill"
        )
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Edits expected income.")
    }
}

private struct LabPlanAheadEventSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let amount: String
    let type: String
    let status: String
    let detail: String
    let accent: Color
    let systemImage: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityContent
            } else {
                compactContent
            }
        }
        .padding(AppSpacing.medium)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.055)
                        : Color.white.opacity(0.48)
                )
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accent.opacity(0.85))
                .frame(width: 3, height: 18)
                .padding(.leading, AppSpacing.xSmall)
                .padding(.top, AppSpacing.medium)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type), \(title), \(amount), \(status), \(detail)")
    }

    private var compactContent: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            eventIcon

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                eventTypeLabel

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)

                Text("\(status) · \(detail)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.xSmall)

            SensitiveValueText(amount)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.primaryText)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                eventIcon
                eventTypeLabel
                Spacer(minLength: 0)
                SensitiveValueText(amount)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(status) · \(detail)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var eventIcon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(accent)
            .frame(width: 24, height: 24)
            .background(accent.opacity(0.12), in: Circle())
    }

    private var eventTypeLabel: some View {
        Text(type.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .default))
            .tracking(0.7)
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

private enum LabPlanAheadPalette {
    static let expense = AppColors.accent
    static let payment = Color(red: 0.26, green: 0.32, blue: 0.76)
    static let income = Color(red: 0.02, green: 0.49, blue: 0.43)
    static let pastDue = AppColors.warning
}

private struct LabPlanAheadTimelineBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.025, green: 0.045, blue: 0.10),
                        Color(red: 0.045, green: 0.08, blue: 0.16),
                        Color(red: 0.025, green: 0.04, blue: 0.09)
                    ]
                    : [
                        Color(red: 0.94, green: 0.97, blue: 1.00),
                        Color(red: 0.90, green: 0.94, blue: 0.99),
                        Color(red: 0.96, green: 0.98, blue: 1.00)
                    ],
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
