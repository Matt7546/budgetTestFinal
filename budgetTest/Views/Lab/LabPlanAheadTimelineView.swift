#if DEBUG
import SwiftData
import SwiftUI

/// A Lab-only composition that reuses Plan Ahead's live forecast and funding
/// models, while testing a more spatial, date-led reading of the plan.
struct LabPlanAheadTimelineView: View {

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

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .timeline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    timelineHero

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
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(monthTitle)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(AppColors.accent)

            Text("Your financial future\nlaid out over time.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Plan Ahead Lab · Expenses, payment plans, and expected income in one continuous view.")
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
                    .foregroundStyle(CalderaCategoryStyle.style(for: .shortfall).primary)

                Text("\(pastDueItems.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CalderaCategoryStyle.style(for: .shortfall).primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(CalderaCategoryStyle.style(for: .shortfall).primary.opacity(0.12), in: Capsule())
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

    private var todayAnchor: some View {
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
            .padding(.vertical, 7)
            .background(AppColors.accent.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(AppColors.accent.opacity(0.32), lineWidth: 1)
            }

            Rectangle()
                .fill(AppColors.accent.opacity(0.35))
                .frame(height: 1)
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
        .padding(.leading, 58)
        .padding(.top, AppSpacing.medium)
    }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

    private var inactiveOccurrenceIDs: Set<String> {
        ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: occurrenceStatuses
        )
    }

    private var expenseFundingComposition: UpcomingExpenseFundingComposition {
        UpcomingExpenseFundingComposition(
            events: events,
            allocations: allocations,
            occurrenceStatuses: occurrenceStatuses
        )
    }

    private var forecastEvents: [ForecastEvent] {
        // The timeline needs the existing occurrence stream and durable funding
        // merge, not a second Available to Spend calculation. Per-event funding
        // remains sourced from the same allocation lookup used in Plan Ahead.
        expenseFundingComposition.forecastCalculator(
            events: events,
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
            statuses: occurrenceStatuses
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
            from: incomeSchedules,
            ownerScopeID: IncomeScheduleOwnerScope.current(
                authenticatedUserID: auth.user?.id
            )
        )
    }

    private var allocationAmounts: EventAllocationAmountLookup {
        EventAllocationAmountLookup(allocations: allocations)
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
                .fill(AppColors.accent.opacity(isPastDue ? 0.20 : 0.28))
                .frame(width: 2)
                .padding(.leading, 43)
                .padding(.vertical, 5)
                .allowsHitTesting(false)
        }
    }

    private func monthTransition(_ date: Date) -> some View {
        HStack(spacing: AppSpacing.small) {
            Text(date.formatted(.dateTime.month(.wide).year()))
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColors.primaryText)
            Rectangle()
                .fill(AppColors.secondaryText.opacity(0.18))
                .frame(height: 1)
        }
        .padding(.leading, 58)
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.medium)
    }

    private func dayRow(_ day: LabPlanAheadTimelineDay) -> some View {
        HStack(alignment: .top, spacing: 0) {
            LabPlanAheadDateMarker(date: day.date, isPastDue: isPastDue)
                .frame(width: 58)

            VStack(spacing: AppSpacing.small) {
                ForEach(day.items) { item in
                    eventRow(item)
                }
            }
            .padding(.leading, AppSpacing.small)
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
        HStack(spacing: AppSpacing.xSmall) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.secondaryText)
                Text(date.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
            }
            Circle()
                .fill(isPastDue ? CalderaCategoryStyle.style(for: .shortfall).primary : AppColors.accent)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.78), lineWidth: 3)
                }
        }
        .padding(.top, 14)
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
                ? CalderaCategoryStyle.style(for: .shortfall).primary
                : CalderaCategoryStyle.style(for: .upcomingExpense).primary,
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
                ? CalderaCategoryStyle.style(for: .covered).primary
                : CalderaCategoryStyle.style(for: .debtPayoff).primary,
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
            accent: CalderaCategoryStyle.style(for: .income).primary,
            systemImage: "arrow.down.circle.fill"
        )
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Edits expected income.")
    }
}

private struct LabPlanAheadEventSurface: View {
    let title: String
    let amount: String
    let type: String
    let status: String
    let detail: String
    let accent: Color
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: 24, height: 24)
                .background(accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(type.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(0.7)
                    .foregroundStyle(accent)

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
                .font(.headline.weight(.bold))
                .foregroundStyle(AppColors.primaryText)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(AppSpacing.medium)
        .background {
            RoundedRectangle(cornerRadius: AppRadii.field, style: .continuous)
                .fill(accent.opacity(0.055))
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, AppSpacing.medium)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadii.field, style: .continuous)
                .stroke(accent.opacity(0.16), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppRadii.field, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type), \(title), \(amount), \(status), \(detail)")
    }
}
#endif
