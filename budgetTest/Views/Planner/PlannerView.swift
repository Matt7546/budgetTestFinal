import SwiftUI
import SwiftData

struct PlannerView: View {

    @EnvironmentObject var summary: SummaryViewModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var plaid: PlaidService

    @Query
    var events: [PlannerEvent]

    @Query
    var allocations: [EventAllocation]

    @Query
    var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @Query
    var debtPayoffBuckets: [DebtPayoffBucket]

    @State private var showAddEvent = false
    @State private var selectedEvent: PlannerEvent?
    @State private var selectedAllocationForecast: ForecastEvent?
    @State private var confirmationMessage: String?
    @State private var confirmationID = UUID()

    var body: some View {

        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .timeline)

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.screen
                    ) {
                        plannerHeader

                        nextThirtyDaysSummary

                        timelineInsightCard

                        if !paymentPlanTimelineGroups.isEmpty {
                            paymentPlansSection
                        }

                        upcomingExpensesSection
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
                    .padding(.bottom, AppSpacing.floatingTabClearance)
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .calderaTransparentNavigationSurface()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calderaConfirmationOverlay(message: confirmationMessage)
        .sheet(
            isPresented: $showAddEvent
        ) {

            AddPlannerEventView(
                editingEvent: nil,
                onSaved: { type, isEditing in
                    showPlannerEventConfirmation(
                        type: type,
                        isEditing: isEditing
                    )
                }
            )
        }
        .sheet(
            item: $selectedEvent
        ) { event in

            AddPlannerEventView(
                editingEvent: event,
                onSaved: { type, isEditing in
                    showPlannerEventConfirmation(
                        type: type,
                        isEditing: isEditing
                    )
                },
                onDeleted: { type in
                    showConfirmation(
                        type == .expense
                            ? "Upcoming Expense deleted."
                            : "Income deleted."
                    )
                }
            )
        }
        .sheet(
            item: $selectedAllocationForecast
        ) { forecast in

            EventAllocationDetailView(
                forecast: forecast
            ) {
                selectedAllocationForecast = nil
                selectedEvent = forecast.event
            }
        }
        .onAppear {
            consumeSetupNavigationRequests()
        }
        .onChange(of: navigation.shouldCreateUpcomingExpense) { _, _ in
            consumeSetupNavigationRequests()
        }
    }

    private func consumeSetupNavigationRequests() {
        if navigation.shouldCreateUpcomingExpense {
            navigation.shouldCreateUpcomingExpense = false
            showAddEvent = true
        }
    }

    private func showPlannerEventConfirmation(
        type: PlannerEventType,
        isEditing: Bool
    ) {
        switch type {
        case .expense:
            showConfirmation(
                isEditing
                    ? "Upcoming Expense updated."
                    : "Upcoming Expense added to your plan."
            )

        case .income:
            showConfirmation(
                isEditing
                    ? "Income updated."
                    : "Income added to your timeline."
            )
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

    private var plannerHeader: some View {
        HStack(spacing: AppSpacing.medium) {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("Plan Ahead")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                HStack(alignment: .center, spacing: AppSpacing.xxSmall) {
                    Text("Timeline")
                        .font(
                            .system(
                                size: 40,
                                weight: .bold
                            )
                        )
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    ContextHelpButton(
                        title: "Timeline",
                        bodyText: "Timeline shows expenses and payments coming up so you can see what still needs money set aside before the date arrives.",
                        footnote: "It helps you plan ahead before money leaves your account."
                    )
                }

                Text("See what's due soon, what is set aside, and what still needs money.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showAddEvent = true
            } label: {
                CalderaGradientIcon(
                    systemImage: "plus",
                    colors: CalderaVisualStyle.safeGradient,
                    size: 46,
                    iconSize: 19
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add upcoming event")
        }
    }

    private var upcomingExpensesSection: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.small) {
                Text("Coming Up")
                    .font(.title3.bold())
                    .foregroundStyle(AppColors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !upcomingExpenseForecasts.isEmpty {
                    NavigationLink {
                        AllTimelineExpensesView()
                    } label: {
                        Text("See all")
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppColors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all upcoming expenses")
                }
            }

            if upcomingExpenseForecasts.isEmpty {
                EmptyStateView(
                    systemImage: CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                    title: "Nothing planned here yet",
                    description: "Add an upcoming expense when you want Caldera to help keep it visible.",
                    primaryActionTitle: "Add Expense",
                    primaryAction: {
                        showAddEvent = true
                    },
                    color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
                )
            } else {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.large
                ) {
                    ForEach(timelineForecastGroups) { group in
                        timelineGroupSection(group)
                    }
                }
            }
        }
    }


    private var paymentPlansSection: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Payment Plans")
                    .font(.title3.bold())
                    .foregroundStyle(AppColors.primaryText)

                Text("Payments with due dates that may need money set aside.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(
                alignment: .leading,
                spacing: AppSpacing.large
            ) {
                ForEach(paymentPlanTimelineGroups) { group in
                    paymentPlanGroupSection(group)
                }
            }
        }
    }

    private var nextThirtyDaysSummary: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: CalderaCategoryStyle.style(for: .upcomingExpense),
                    size: 48,
                    iconSize: 20
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Next 30 Days")
                        .font(.title2.weight(.bold))
                        .foregroundColor(AppColors.primaryText)

                    Text("What is coming up and what still needs money.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppSpacing.small)
            }

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: 104,
                            maximum: 180
                        ),
                        spacing: AppSpacing.small
                    )
                ],
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                forecastMetric(
                    value: AppFormatters.currency(nextThirtyUpcomingTotal),
                    label: "upcoming",
                    style: CalderaCategoryStyle.style(for: .upcomingExpense)
                )

                forecastMetric(
                    value: AppFormatters.currency(nextThirtySetAsideTotal),
                    label: "set aside",
                    style: CalderaCategoryStyle.style(for: .covered)
                )

                forecastMetric(
                    value: AppFormatters.currency(nextThirtyNeededTotal),
                    label: "still needed",
                    style: nextThirtyNeededTotal <= currencyTolerance
                        ? CalderaCategoryStyle.style(for: .covered)
                        : CalderaCategoryStyle.style(for: .needsMoney)
                )
            }

            HStack(spacing: AppSpacing.small) {
                Button {
                    showAddEvent = true
                } label: {
                    HStack(spacing: AppSpacing.xSmall) {
                        Image(systemName: "plus")
                        Text("Add Expense")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.small)
                    .background(
                        LinearGradient(
                            colors: CalderaCategoryStyle.style(for: .upcomingExpense).gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule(style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Upcoming Expense")

                if !upcomingExpenseForecasts.isEmpty {
                    NavigationLink {
                        AllTimelineExpensesView()
                    } label: {
                        Text("See All")
                            .font(.caption.weight(.bold))
                            .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
                            .padding(.horizontal, AppSpacing.medium)
                            .padding(.vertical, AppSpacing.small)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CalderaCategoryStyle.style(for: .safeToSpend).primary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all upcoming expenses")
                }
            }
            .padding(.top, AppSpacing.xSmall)
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.hero,
            fillOpacity: 0.90,
            strokeOpacity: 0.76,
            shadowOpacity: 0.04,
            shadowRadius: 18,
            shadowY: 9,
            darkGlowColor: CalderaCategoryStyle.style(for: .upcomingExpense).primary
        )
    }

    @ViewBuilder
    private var timelineInsightCard: some View {
        if let forecast = firstUnderfundedForecast {
            let isBeyondNextThirtyDays = Calendar.current.startOfDay(
                for: forecast.occurrenceDate
            ) > nextThirtyDaysEnd

            timelineInsight(
                title: isBeyondNextThirtyDays ? "Looking ahead" : "Still needs money",
                message: "\(forecast.event.name) still needs \(AppFormatters.currency(remainingAmount(for: forecast))) by \(AppFormatters.abbreviatedMonthDay(forecast.occurrenceDate)).",
                style: CalderaCategoryStyle.style(for: .needsMoney),
                actionTitle: "Set Aside",
                action: {
                    selectedAllocationForecast = forecast
                }
            )
        } else if let coveredUntilDate {
            timelineInsight(
                title: "Covered until \(AppFormatters.abbreviatedMonthDay(coveredUntilDate))",
                message: "You have enough set aside for expenses due before then.",
                style: CalderaCategoryStyle.style(for: .covered),
                actionTitle: nil,
                action: nil
            )
        } else {
            timelineInsight(
                title: "Nothing needs attention",
                message: "Add Upcoming Expenses to see what needs money set aside before each due date.",
                style: CalderaCategoryStyle.style(for: .safeToSpend),
                actionTitle: "Add Expense",
                action: {
                    showAddEvent = true
                }
            )
        }
    }

    private func timelineInsight(
        title: String,
        message: String,
        style: CalderaCategoryStyle,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: style,
                size: 44,
                iconSize: 18
            )

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle,
                   let action {
                    Button(actionTitle) {
                        action()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(style.primary)
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.xSmall)
                    .background(
                        Capsule(style: .continuous)
                            .fill(style.primary.opacity(0.12))
                    )
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.xSmall)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.86,
            strokeOpacity: 0.68,
            shadowOpacity: 0.025,
            shadowRadius: 14,
            shadowY: 7,
            darkGlowColor: style.primary
        )
    }

    private func forecastMetric(
        value: String,
        label: String,
        style: CalderaCategoryStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundColor(style.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.medium)
        .background(
            RoundedRectangle(
                cornerRadius: AppRadii.control,
                style: .continuous
            )
            .fill(Color.white.opacity(0.16))
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: AppRadii.control,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.30), lineWidth: 1)
        }
    }

    private func timelineGroupSection(
        _ group: TimelineForecastGroup
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(group.title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text(group.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
            }

            VStack(spacing: AppSpacing.medium) {
                ForEach(group.forecasts) { forecast in
                    PlannerEventRow(
                        event: forecast.event,
                        occurrenceDate: forecast.occurrenceDate,
                        allocatedAmount: allocatedAmount(
                            for: forecast
                        )
                    ) {
                        selectedAllocationForecast = forecast
                    }
                }
            }
        }
    }


    private func paymentPlanGroupSection(
        _ group: PaymentPlanTimelineGroup
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(group.title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text(group.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
            }

            VStack(spacing: AppSpacing.medium) {
                ForEach(group.paymentPlans) { bucket in
                    PaymentPlanTimelineRow(
                        bucket: bucket,
                        linkedAccount: paymentPlanAccountByID[bucket.plaidAccountID]
                    ) {
                        navigation.openSavingsEditDebtPayoff(bucket.id)
                    }
                }
            }
        }
    }

    func allocation(
        for forecast: ForecastEvent
    ) -> EventAllocation? {
        allocations.first {
            $0.occurrenceID == forecast.occurrenceID
        }
    }

    func allocatedAmount(
        for forecast: ForecastEvent
    ) -> Double {
        allocation(
            for: forecast
        )?
        .allocatedAmount ?? 0
    }

    private var currencyTolerance: Double {
        0.005
    }

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var nextSevenDaysEnd: Date {
        Calendar.current.date(
            byAdding: .day,
            value: 7,
            to: startOfToday
        ) ?? startOfToday
    }

    private var nextThirtyDaysEnd: Date {
        Calendar.current.date(
            byAdding: .day,
            value: 30,
            to: startOfToday
        ) ?? startOfToday
    }

    private var upcomingExpenseForecasts: [ForecastEvent] {
        forecastEvents
            .filter {
                $0.event.type == .expense
            }
            .filter {
                Calendar.current.startOfDay(for: $0.occurrenceDate) >= startOfToday
            }
    }

    private var nextThirtyDayForecasts: [ForecastEvent] {
        upcomingExpenseForecasts.filter {
            Calendar.current.startOfDay(for: $0.occurrenceDate) <= nextThirtyDaysEnd
        }
    }

    private var nextThirtyUpcomingTotal: Double {
        nextThirtyDayForecasts.reduce(0) { total, forecast in
            total + forecast.event.amount
        }
    }

    private var nextThirtySetAsideTotal: Double {
        nextThirtyDayForecasts.reduce(0) { total, forecast in
            total + setAsideAmount(for: forecast)
        }
    }

    private var nextThirtyNeededTotal: Double {
        nextThirtyDayForecasts.reduce(0) { total, forecast in
            total + remainingAmount(for: forecast)
        }
    }

    private var firstUnderfundedForecast: ForecastEvent? {
        upcomingExpenseForecasts.first {
            remainingAmount(for: $0) > currencyTolerance
        }
    }

    private var coveredUntilDate: Date? {
        var lastCoveredDate: Date?

        for forecast in upcomingExpenseForecasts {
            guard remainingAmount(for: forecast) <= currencyTolerance else {
                break
            }

            lastCoveredDate = forecast.occurrenceDate
        }

        return lastCoveredDate
    }

    private var timelineForecastGroups: [TimelineForecastGroup] {
        [
            TimelineForecastGroup(
                id: "due-soon",
                title: "Due Soon",
                subtitle: "Next 7 days",
                forecasts: upcomingExpenseForecasts.filter {
                    Calendar.current.startOfDay(for: $0.occurrenceDate) <= nextSevenDaysEnd
                }
            ),
            TimelineForecastGroup(
                id: "coming-up",
                title: "Coming Up",
                subtitle: "Next 30 days",
                forecasts: upcomingExpenseForecasts.filter {
                    let occurrenceDay = Calendar.current.startOfDay(for: $0.occurrenceDate)
                    return occurrenceDay > nextSevenDaysEnd &&
                        occurrenceDay <= nextThirtyDaysEnd
                }
            ),
            TimelineForecastGroup(
                id: "later",
                title: "Later",
                subtitle: "Beyond 30 days",
                forecasts: upcomingExpenseForecasts.filter {
                    Calendar.current.startOfDay(for: $0.occurrenceDate) > nextThirtyDaysEnd
                }
            )
        ]
        .filter {
            !$0.forecasts.isEmpty
        }
    }

    private func setAsideAmount(
        for forecast: ForecastEvent
    ) -> Double {
        min(
            max(allocatedAmount(for: forecast), 0),
            forecast.event.amount
        )
    }

    private func remainingAmount(
        for forecast: ForecastEvent
    ) -> Double {
        max(
            forecast.event.amount - setAsideAmount(for: forecast),
            0
        )
    }

    private var paymentPlanAccountByID: [String: PlaidAccount] {
        Dictionary(
            uniqueKeysWithValues: plaid.accounts.deduplicatedForDisplayAndTotals.map {
                ($0.account_id, $0)
            }
        )
    }

    private var upcomingPaymentPlans: [DebtPayoffBucket] {
        debtPayoffBuckets
            .filter { bucket in
                bucket.shouldDisplayDueDate &&
                    Calendar.current.startOfDay(for: bucket.dueDate) >= startOfToday
            }
            .sorted {
                $0.dueDate < $1.dueDate
            }
    }

    private var paymentPlanTimelineGroups: [PaymentPlanTimelineGroup] {
        [
            PaymentPlanTimelineGroup(
                id: "payment-due-soon",
                title: "Due Soon",
                subtitle: "Next 7 days",
                paymentPlans: upcomingPaymentPlans.filter {
                    Calendar.current.startOfDay(for: $0.dueDate) <= nextSevenDaysEnd
                }
            ),
            PaymentPlanTimelineGroup(
                id: "payment-coming-up",
                title: "Coming Up",
                subtitle: "Next 30 days",
                paymentPlans: upcomingPaymentPlans.filter {
                    let dueDay = Calendar.current.startOfDay(for: $0.dueDate)
                    return dueDay > nextSevenDaysEnd &&
                        dueDay <= nextThirtyDaysEnd
                }
            ),
            PaymentPlanTimelineGroup(
                id: "payment-later",
                title: "Later",
                subtitle: "Beyond 30 days",
                paymentPlans: upcomingPaymentPlans.filter {
                    Calendar.current.startOfDay(for: $0.dueDate) > nextThirtyDaysEnd
                }
            )
        ]
        .filter {
            !$0.paymentPlans.isEmpty
        }
    }

    private var uniqueUpcomingExpenseForecasts: [ForecastEvent] {
        var seenEventIDs = Set<UUID>()

        return forecastEvents
            .filter {
                $0.event.type == .expense
            }
            .filter { forecast in
                seenEventIDs.insert(forecast.event.id).inserted
            }
    }
}

private struct TimelineForecastGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let forecasts: [ForecastEvent]
}


private struct PaymentPlanTimelineGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let paymentPlans: [DebtPayoffBucket]
}

private struct PaymentPlanTimelineRow: View {

    let bucket: DebtPayoffBucket
    let linkedAccount: PlaidAccount?
    let action: () -> Void

    private let currencyTolerance = 0.005
    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    private var display: DebtPayoffDisplayModel {
        DebtPayoffDisplayModel(
            bucket: bucket,
            linkedAccount: linkedAccount
        )
    }

    private var paymentTarget: Double {
        max(
            bucket.isLinkedCreditCard
                ? bucket.paymentTargetAmount
                : bucket.monthlyPayment ?? bucket.paymentTargetAmount,
            0
        )
    }

    private var setAsideAmount: Double {
        min(
            max(bucket.protectedAmount, 0),
            paymentTarget
        )
    }

    private var remainingAmount: Double {
        max(
            paymentTarget - setAsideAmount,
            0
        )
    }

    private var isCovered: Bool {
        paymentTarget > currencyTolerance &&
            remainingAmount <= currencyTolerance
    }

    private var progress: Double {
        guard paymentTarget > currencyTolerance else {
            return 0
        }

        return clampedProgressValue(setAsideAmount / paymentTarget)
    }

    private var statusText: String {
        guard paymentTarget > currencyTolerance else {
            return "Payment target needed"
        }

        return isCovered
            ? "Covered"
            : "Still needs \(AppFormatters.currency(remainingAmount))"
    }

    private var statusColor: Color {
        isCovered
            ? CalderaCategoryStyle.style(for: .covered).primary
            : CalderaCategoryStyle.style(for: .needsMoney).primary
    }

    private var monthText: String {
        AppFormatters.abbreviatedMonth(bucket.dueDate).uppercased()
    }

    private var dayText: String {
        AppFormatters.day(bucket.dueDate)
    }

    var body: some View {
        Button {
            action()
        } label: {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.medium
            ) {
                HStack(spacing: AppSpacing.medium) {
                    VStack(spacing: 2) {
                        Text(monthText)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColors.secondaryText)

                        Text(dayText)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColors.primaryText)
                    }
                    .frame(width: 50)
                    .padding(.vertical, AppSpacing.small)
                    .calderaGlassCard(
                        cornerRadius: 18,
                        fillOpacity: 0.70,
                        strokeOpacity: 0.54,
                        shadowOpacity: 0,
                        shadowRadius: 0,
                        shadowY: 0
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        Text(display.title)
                            .font(.headline)
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)

                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(statusColor)
                            .lineLimit(2)

                        Text("Payment plan · Due \(AppFormatters.abbreviatedMonthDay(bucket.dueDate))")
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    VStack(
                        alignment: .trailing,
                        spacing: 6
                    ) {
                        Text(AppFormatters.currency(paymentTarget))
                            .font(.headline.bold())
                            .foregroundColor(style.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text("target")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(AppColors.secondaryText.opacity(0.10))
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        AppColors.glassSubtleHighlight.opacity(0.45),
                                        lineWidth: 1
                                    )
                            }
                    }
                }

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.small
                ) {
                    CalderaProgressBar(
                        progress: progress,
                        colors: [
                            style.primary,
                            CalderaCategoryStyle.style(for: .covered).primary,
                            CalderaCategoryStyle.style(for: .safeToSpend).primary
                        ]
                    )

                    HStack(alignment: .firstTextBaseline) {
                        Text("\(AppFormatters.currency(setAsideAmount)) set aside of \(AppFormatters.currency(paymentTarget))")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer()

                        Text(statusText)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(statusColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
            .padding(20)
            .calderaGlassCard(
                cornerRadius: 28,
                fillOpacity: 0.86,
                strokeOpacity: 0.72,
                shadowOpacity: 0.038,
                shadowRadius: 18,
                shadowY: 9,
                darkGlowColor: style.primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(display.title), payment plan, due \(AppFormatters.abbreviatedMonthDay(bucket.dueDate)), \(statusText)"
        )
    }
}
