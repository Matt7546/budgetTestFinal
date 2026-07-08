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
    @State private var pendingSuggestedExpenseDraft: PlannerEventDraft?
    @State private var pendingSuggestedExpenseID: String?
    @State private var showRecurringRecommendations = false
    @State private var queuedRecurringSuggestionForDraft: RecurringExpenseSuggestion?
    @AppStorage("caldera.recurringExpenseSuggestionStatuses")
    private var recurringSuggestionStatusData = "{}"
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

                        if hasRecurringRecommendationContent {
                            recurringExpenseRecommendationsEntryPoint
                        }

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
            isPresented: $showRecurringRecommendations,
            onDismiss: {
                presentQueuedRecurringSuggestionDraftIfNeeded()
            }
        ) {
            RecurringExpenseRecommendationsView(
                groups: recurringRecommendationGroups,
                onAddToPlanAhead: { suggestion in
                    queueRecurringSuggestionForDraft(suggestion)
                },
                onNotNow: { suggestion in
                    setRecurringSuggestionStatus(.dismissed, for: suggestion.id)
                },
                onReviewAgain: { suggestion in
                    setRecurringSuggestionStatus(.pending, for: suggestion.id)
                },
                onClose: {
                    showRecurringRecommendations = false
                }
            )
        }
        .sheet(
            isPresented: $showAddEvent,
            onDismiss: {
                pendingSuggestedExpenseDraft = nil
                pendingSuggestedExpenseID = nil
            }
        ) {

            AddPlannerEventView(
                editingEvent: nil,
                draft: pendingSuggestedExpenseDraft,
                onSaved: { type, isEditing in
                    markPendingRecurringSuggestionAddedIfNeeded(
                        type: type,
                        isEditing: isEditing
                    )
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
            presentNewExpense()
        }
    }

    private func presentNewExpense(
        draft: PlannerEventDraft? = nil,
        suggestionID: String? = nil
    ) {
        pendingSuggestedExpenseDraft = draft
        pendingSuggestedExpenseID = suggestionID
        showAddEvent = true
    }

    private func queueRecurringSuggestionForDraft(
        _ suggestion: RecurringExpenseSuggestion
    ) {
        queuedRecurringSuggestionForDraft = suggestion
        showRecurringRecommendations = false
    }

    private func presentQueuedRecurringSuggestionDraftIfNeeded() {
        guard let suggestion = queuedRecurringSuggestionForDraft else {
            return
        }

        queuedRecurringSuggestionForDraft = nil
        presentNewExpense(
            draft: suggestion.plannerDraft,
            suggestionID: suggestion.id
        )
    }

    private func markPendingRecurringSuggestionAddedIfNeeded(
        type: PlannerEventType,
        isEditing: Bool
    ) {
        guard type == .expense,
              !isEditing,
              let pendingSuggestedExpenseID else {
            return
        }

        setRecurringSuggestionStatus(
            .added,
            for: pendingSuggestedExpenseID
        )
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
                presentNewExpense()
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

    private var recurringExpenseSuggestions: [RecurringExpenseSuggestion] {
        RecurringExpenseSuggestionEngine.suggestions(
            transactions: plaid.transactions,
            existingEvents: events
        )
    }

    private var recurringSuggestionStatuses: [String: RecurringExpenseSuggestionStatus] {
        guard let data = recurringSuggestionStatusData.data(using: .utf8),
              let statuses = try? JSONDecoder().decode(
                [String: RecurringExpenseSuggestionStatus].self,
                from: data
              ) else {
            return [:]
        }

        return statuses
    }

    private var recurringRecommendationGroups: RecurringExpenseRecommendationGroups {
        RecurringExpenseRecommendationGroups(
            suggestions: recurringExpenseSuggestions,
            statuses: recurringSuggestionStatuses
        )
    }

    private var hasRecurringRecommendationContent: Bool {
        recurringRecommendationGroups.totalCount > 0
    }

    private var recurringExpenseRecommendationsEntryPoint: some View {
        let groups = recurringRecommendationGroups
        let needsReviewCount = groups.needsReview.count
        let historyCount = groups.added.count + groups.dismissed.count
        let detailText = needsReviewCount > 0
            ? "\(needsReviewCount) may help you plan ahead."
            : "Review suggestions you added or set aside for later."

        return Button {
            showRecurringRecommendations = true
        } label: {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: CalderaCategoryStyle.style(for: .upcomingExpense),
                    size: 44,
                    iconSize: 18
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("View recommended recurring expenses")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detailText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if historyCount > 0 {
                        Text("\(historyCount) reviewed")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.secondaryText.opacity(0.82))
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(AppSpacing.card)
            .calderaGlassCard(
                cornerRadius: AppRadii.card,
                fillOpacity: 0.86,
                strokeOpacity: 0.68,
                shadowOpacity: 0.025,
                shadowRadius: 14,
                shadowY: 7,
                darkGlowColor: CalderaCategoryStyle.style(for: .upcomingExpense).primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View recommended recurring expenses")
    }

    private func setRecurringSuggestionStatus(
        _ status: RecurringExpenseSuggestionStatus,
        for suggestionID: String
    ) {
        var statuses = recurringSuggestionStatuses

        switch status {
        case .pending:
            statuses.removeValue(forKey: suggestionID)
        case .added, .dismissed:
            statuses[suggestionID] = status
        }

        guard let data = try? JSONEncoder().encode(statuses),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }

        recurringSuggestionStatusData = encoded
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
                        presentNewExpense()
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
                    presentNewExpense()
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
                    presentNewExpense()
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
                        linkedAccount: paymentPlanAccountByID[bucket.plaidAccountID],
                        isPastDue: Calendar.current.startOfDay(for: bucket.dueDate) < startOfToday
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

    private var visiblePaymentPlans: [DebtPayoffBucket] {
        debtPayoffBuckets
            .filter { bucket in
                bucket.shouldDisplayDueDate
            }
            .sorted {
                $0.dueDate < $1.dueDate
            }
    }

    private var paymentPlanTimelineGroups: [PaymentPlanTimelineGroup] {
        [
            PaymentPlanTimelineGroup(
                id: "payment-past-due",
                title: "Past Due",
                subtitle: "Past their due date",
                paymentPlans: visiblePaymentPlans.filter {
                    Calendar.current.startOfDay(for: $0.dueDate) < startOfToday
                }
            ),
            PaymentPlanTimelineGroup(
                id: "payment-due-soon",
                title: "Due Soon",
                subtitle: "Next 7 days",
                paymentPlans: visiblePaymentPlans.filter {
                    let dueDay = Calendar.current.startOfDay(for: $0.dueDate)
                    return dueDay >= startOfToday &&
                        dueDay <= nextSevenDaysEnd
                }
            ),
            PaymentPlanTimelineGroup(
                id: "payment-coming-up",
                title: "Coming Up",
                subtitle: "Next 30 days",
                paymentPlans: visiblePaymentPlans.filter {
                    let dueDay = Calendar.current.startOfDay(for: $0.dueDate)
                    return dueDay > nextSevenDaysEnd &&
                        dueDay <= nextThirtyDaysEnd
                }
            ),
            PaymentPlanTimelineGroup(
                id: "payment-later",
                title: "Later",
                subtitle: "Beyond 30 days",
                paymentPlans: visiblePaymentPlans.filter {
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

private enum RecurringExpenseSuggestionStatus: String, Codable {
    case pending
    case added
    case dismissed
}

private struct RecurringExpenseRecommendationGroups {
    let needsReview: [RecurringExpenseSuggestion]
    let added: [RecurringExpenseSuggestion]
    let dismissed: [RecurringExpenseSuggestion]

    var totalCount: Int {
        needsReview.count + added.count + dismissed.count
    }

    init(
        suggestions: [RecurringExpenseSuggestion],
        statuses: [String: RecurringExpenseSuggestionStatus]
    ) {
        var needsReview = [RecurringExpenseSuggestion]()
        var added = [RecurringExpenseSuggestion]()
        var dismissed = [RecurringExpenseSuggestion]()

        for suggestion in suggestions {
            let status = statuses[suggestion.id] ?? .pending

            if suggestion.isAlreadyInPlan || status == .added {
                added.append(suggestion)
            } else if status == .dismissed {
                dismissed.append(suggestion)
            } else {
                needsReview.append(suggestion)
            }
        }

        self.needsReview = needsReview
        self.added = added
        self.dismissed = dismissed
    }
}

private struct RecurringExpenseSuggestion: Identifiable {
    let id: String
    let merchantName: String
    let normalizedName: String
    let amount: Double
    let nextDueDate: Date
    let dayOfMonth: Int
    let occurrenceCount: Int
    let isAlreadyInPlan: Bool

    var bodyText: String {
        "\(merchantName) looks monthly around the \(dayText) for about \(AppFormatters.currency(amount))."
    }

    var plannerDraft: PlannerEventDraft {
        PlannerEventDraft(
            name: merchantName,
            amount: amount,
            date: nextDueDate,
            type: .expense,
            frequency: .monthly,
            accentColorID: nil
        )
    }

    private var dayText: String {
        Self.ordinalFormatter.string(
            from: NSNumber(value: dayOfMonth)
        ) ?? "\(dayOfMonth)"
    }

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}

private struct RecurringExpenseRecommendationsView: View {
    let groups: RecurringExpenseRecommendationGroups
    let onAddToPlanAhead: (RecurringExpenseSuggestion) -> Void
    let onNotNow: (RecurringExpenseSuggestion) -> Void
    let onReviewAgain: (RecurringExpenseSuggestion) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .timeline)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.screen) {
                        header

                        if !groups.needsReview.isEmpty {
                            recommendationSection(
                                title: "Needs review",
                                subtitle: "Patterns Caldera found that may help you plan ahead.",
                                suggestions: groups.needsReview,
                                mode: .needsReview
                            )
                        }

                        if !groups.added.isEmpty {
                            recommendationSection(
                                title: "Added to Plan Ahead",
                                subtitle: "Already represented in Upcoming Expenses.",
                                suggestions: groups.added,
                                mode: .added
                            )
                        }

                        if !groups.dismissed.isEmpty {
                            recommendationSection(
                                title: "Not now",
                                subtitle: "Suggestions you set aside for later.",
                                suggestions: groups.dismissed,
                                mode: .dismissed
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
                    .padding(.bottom, AppSpacing.floatingTabClearance)
                }
                .scrollContentBackground(.hidden)
            }
            .calderaTransparentNavigationSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onClose()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text("Recommended recurring expenses")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Caldera found patterns that may help you plan ahead. Nothing is added unless you choose it.")
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func recommendationSection(
        title: String,
        subtitle: String,
        suggestions: [RecurringExpenseSuggestion],
        mode: RecurringRecommendationCardMode
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(AppColors.primaryText)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppSpacing.medium) {
                ForEach(suggestions) { suggestion in
                    recommendationCard(
                        suggestion,
                        mode: mode
                    )
                }
            }
        }
    }

    private func recommendationCard(
        _ suggestion: RecurringExpenseSuggestion,
        mode: RecurringRecommendationCardMode
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: CalderaCategoryStyle.style(for: .upcomingExpense),
                size: 44,
                iconSize: 18
            )

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Suggested upcoming expense")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(suggestion.bodyText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if mode == .added {
                    statusPill("Already in Plan Ahead")
                }

                switch mode {
                case .needsReview:
                    HStack(spacing: AppSpacing.small) {
                        Button {
                            onAddToPlanAhead(suggestion)
                        } label: {
                            Text("Add to Plan Ahead")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, AppSpacing.medium)
                                .padding(.vertical, AppSpacing.xSmall)
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

                        Button {
                            onNotNow(suggestion)
                        } label: {
                            Text("Not now")
                                .font(.caption.weight(.bold))
                                .foregroundColor(AppColors.secondaryText)
                                .padding(.horizontal, AppSpacing.medium)
                                .padding(.vertical, AppSpacing.xSmall)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppColors.secondaryText.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, AppSpacing.xxSmall)

                case .added:
                    EmptyView()

                case .dismissed:
                    Button {
                        onReviewAgain(suggestion)
                    } label: {
                        Text("Review again")
                            .font(.caption.weight(.bold))
                            .foregroundColor(CalderaCategoryStyle.style(for: .upcomingExpense).primary)
                            .padding(.horizontal, AppSpacing.medium)
                            .padding(.vertical, AppSpacing.xSmall)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CalderaCategoryStyle.style(for: .upcomingExpense).primary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.xxSmall)
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
            darkGlowColor: CalderaCategoryStyle.style(for: .upcomingExpense).primary
        )
    }

    private func statusPill(
        _ title: String
    ) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundColor(CalderaCategoryStyle.style(for: .covered).primary)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.xxSmall)
            .background(
                Capsule(style: .continuous)
                    .fill(CalderaCategoryStyle.style(for: .covered).primary.opacity(0.12))
            )
    }
}

private enum RecurringRecommendationCardMode {
    case needsReview
    case added
    case dismissed
}

private enum RecurringExpenseSuggestionEngine {
    private struct CandidateTransaction {
        let rawName: String
        let normalizedName: String
        let amount: Double
        let date: Date
    }

    static func suggestions(
        transactions: [PlaidTransaction],
        existingEvents: [PlannerEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RecurringExpenseSuggestion] {
        let candidates = transactions.compactMap { transaction -> CandidateTransaction? in
            guard transaction.amount > 0.01,
                  let date = transactionDateFormatter.date(from: transaction.date),
                  !shouldIgnoreTransactionName(transaction.name) else {
                return nil
            }

            let normalizedName = normalizedMerchantName(transaction.name)

            guard !normalizedName.isEmpty else {
                return nil
            }

            return CandidateTransaction(
                rawName: transaction.name,
                normalizedName: normalizedName,
                amount: transaction.amount,
                date: calendar.startOfDay(for: date)
            )
        }

        let groupedCandidates = Dictionary(
            grouping: candidates,
            by: \.normalizedName
        )

        return groupedCandidates.compactMap { normalizedName, group in
            suggestion(
                normalizedName: normalizedName,
                candidates: group,
                existingEvents: existingEvents,
                now: now,
                calendar: calendar
            )
        }
        .sorted { first, second in
            if calendar.isDate(first.nextDueDate, inSameDayAs: second.nextDueDate) {
                return first.merchantName < second.merchantName
            }

            return first.nextDueDate < second.nextDueDate
        }
    }

    private static func suggestion(
        normalizedName: String,
        candidates: [CandidateTransaction],
        existingEvents: [PlannerEvent],
        now: Date,
        calendar: Calendar
    ) -> RecurringExpenseSuggestion? {
        let occurrences = uniqueDailyOccurrences(
            candidates,
            calendar: calendar
        )
        .sorted { $0.date < $1.date }

        guard occurrences.count >= 3,
              hasMonthlyCadence(occurrences, calendar: calendar) else {
            return nil
        }

        let amounts = occurrences.map(\.amount)
        let suggestedAmount = median(amounts)

        guard amounts.allSatisfy({ amount in
            amountsAreSimilar(
                amount,
                suggestedAmount
            )
        }) else {
            return nil
        }

        guard let latestOccurrence = occurrences.last,
              let nextDueDate = nextMonthlyDate(
                after: latestOccurrence.date,
                now: now,
                calendar: calendar
              ) else {
            return nil
        }

        let alreadyInPlan = isAlreadyRepresented(
            normalizedName: normalizedName,
            amount: suggestedAmount,
            nextDueDate: nextDueDate,
            existingEvents: existingEvents,
            calendar: calendar
        )
        let dayOfMonth = calendar.component(
            .day,
            from: nextDueDate
        )
        let id = [
            normalizedName,
            "monthly",
            String(Int((suggestedAmount * 100).rounded())),
            String(dayOfMonth)
        ]
        .joined(separator: "|")

        return RecurringExpenseSuggestion(
            id: id,
            merchantName: displayName(from: latestOccurrence.rawName),
            normalizedName: normalizedName,
            amount: suggestedAmount,
            nextDueDate: nextDueDate,
            dayOfMonth: dayOfMonth,
            occurrenceCount: occurrences.count,
            isAlreadyInPlan: alreadyInPlan
        )
    }

    private static func uniqueDailyOccurrences(
        _ candidates: [CandidateTransaction],
        calendar: Calendar
    ) -> [CandidateTransaction] {
        candidates
            .sorted { first, second in
                if calendar.isDate(first.date, inSameDayAs: second.date) {
                    return first.amount > second.amount
                }

                return first.date < second.date
            }
            .reduce(into: [CandidateTransaction]()) { result, candidate in
                guard !result.contains(where: {
                    calendar.isDate($0.date, inSameDayAs: candidate.date)
                }) else {
                    return
                }

                result.append(candidate)
            }
    }

    private static func hasMonthlyCadence(
        _ occurrences: [CandidateTransaction],
        calendar: Calendar
    ) -> Bool {
        guard occurrences.count >= 3 else {
            return false
        }

        let intervals = zip(
            occurrences.dropLast(),
            occurrences.dropFirst()
        )
        .compactMap { previous, next in
            calendar.dateComponents(
                [.day],
                from: previous.date,
                to: next.date
            ).day
        }

        guard intervals.count == occurrences.count - 1 else {
            return false
        }

        return intervals.allSatisfy { interval in
            (24...38).contains(interval)
        }
    }

    private static func amountsAreSimilar(
        _ lhs: Double,
        _ rhs: Double
    ) -> Bool {
        abs(lhs - rhs) <= max(
            5,
            rhs * 0.15
        )
    }

    private static func isAlreadyRepresented(
        normalizedName: String,
        amount: Double,
        nextDueDate: Date,
        existingEvents: [PlannerEvent],
        calendar: Calendar
    ) -> Bool {
        existingEvents
            .filter { $0.type == .expense }
            .contains { event in
                let eventName = normalizedMerchantName(event.name)

                guard !eventName.isEmpty else {
                    return false
                }

                let nameMatches = eventName == normalizedName ||
                    eventName.contains(normalizedName) ||
                    normalizedName.contains(eventName)
                let amountMatches = amountsAreSimilar(
                    event.amount,
                    amount
                )
                let cadenceMatches = event.frequency == .monthly ||
                    dueDaysAreClose(
                        calendar.component(.day, from: event.date),
                        calendar.component(.day, from: nextDueDate)
                    )

                return nameMatches && amountMatches && cadenceMatches
            }
    }

    private static func dueDaysAreClose(
        _ lhs: Int,
        _ rhs: Int
    ) -> Bool {
        let distance = abs(lhs - rhs)
        return min(
            distance,
            31 - distance
        ) <= 4
    }

    private static func nextMonthlyDate(
        after latestDate: Date,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        var nextDate = calendar.date(
            byAdding: .month,
            value: 1,
            to: latestDate
        )
        let today = calendar.startOfDay(for: now)
        var attempts = 0

        while let candidate = nextDate,
              candidate < today,
              attempts < 12 {
            nextDate = calendar.date(
                byAdding: .month,
                value: 1,
                to: candidate
            )
            attempts += 1
        }

        return nextDate
    }

    private static func median(
        _ values: [Double]
    ) -> Double {
        let sortedValues = values.sorted()
        let middleIndex = sortedValues.count / 2

        if sortedValues.count.isMultiple(of: 2) {
            return (
                sortedValues[middleIndex - 1] + sortedValues[middleIndex]
            ) / 2
        }

        return sortedValues[middleIndex]
    }

    private static func normalizedMerchantName(
        _ value: String
    ) -> String {
        value
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9]+",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\b\\d+\\b",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayName(
        from value: String
    ) -> String {
        let cleaned = value
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return "Upcoming expense"
        }

        if cleaned == cleaned.uppercased() {
            return cleaned.localizedCapitalized
        }

        return cleaned
    }

    private static func shouldIgnoreTransactionName(
        _ name: String
    ) -> Bool {
        let value = name.lowercased()
        let ignoredFragments = [
            "refund",
            "deposit",
            "payroll",
            "salary",
            "transfer",
            "venmo",
            "zelle",
            "cash app"
        ]

        if ignoredFragments.contains(where: { value.contains($0) }) {
            return true
        }

        let paymentFragments = [
            "payment",
            "pymt"
        ]
        let accountPaymentFragments = [
            "amex",
            "american express",
            "capital one",
            "card",
            "cardmember",
            "chase",
            "citi",
            "credit",
            "discover",
            "loan",
            "mastercard",
            "visa"
        ]

        return paymentFragments.contains(where: { value.contains($0) }) &&
            accountPaymentFragments.contains(where: { value.contains($0) })
    }

    private static let transactionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
    let isPastDue: Bool
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

        if isCovered {
            return isPastDue ? "Past due · Covered" : "Covered"
        }

        return isPastDue
            ? "Past due · Still needs \(AppFormatters.currency(remainingAmount))"
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
