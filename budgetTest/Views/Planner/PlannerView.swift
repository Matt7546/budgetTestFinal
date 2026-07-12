import SwiftUI
import SwiftData

struct PlannerView: View {

    @EnvironmentObject var summary: SummaryViewModel
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var plaid: PlaidService
    @EnvironmentObject private var auth: AuthManager

    @Query
    var events: [PlannerEvent]

    @Query
    var allocations: [EventAllocation]

    @Query
    var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @Query
    var debtPayoffBuckets: [DebtPayoffBucket]

    @Query
    var paymentPlanCycles: [PaymentPlanCycle]

    @State private var showAddEvent = false
    @State private var selectedEvent: PlannerEvent?
    @State private var selectedAllocationForecast: ForecastEvent?
    @State private var selectedTimelineTab: TimelineTab = .upcoming
    @State private var pendingSuggestedExpenseDraft: PlannerEventDraft?
    @State private var pendingSuggestedExpense: RecurringExpenseSuggestion?
    @State private var showRecurringRecommendations = false
    @State private var showReviewUpdates = false
    @State private var queuedRecurringSuggestionForDraft: RecurringExpenseSuggestion?
    @State private var pendingReviewDestination: ReviewUpdateDestination?
    @State private var focusedRecurringRecommendationID: String?
    @State private var recurringRecommendationHistory =
        [String: RecurringExpenseRecommendationHistoryRecord]()
    @State private var confirmationMessage: String?
    @State private var confirmationID = UUID()

    private let recurringRecommendationHistoryStore =
        RecurringExpenseRecommendationHistoryStore()

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

                        timelineTabSelector

                        if !reviewUpdateItems.isEmpty {
                            reviewUpdatesEntryPoint
                        }

                        if hasPastDueItems,
                           unresolvedPastDueExpenseForecasts.isEmpty,
                           selectedTimelineTab == .upcoming {
                            pastDueReviewAlert
                        }

                        if selectedTimelineTab == .upcoming {
                            nextThirtyDaysSummary

                            if hasRecurringRecommendationContent,
                               !hasPendingRecurringRecommendations {
                                recurringExpenseRecommendationsEntryPoint
                            }

                            upcomingExpensesSection
                        } else {
                            pastDueTimelineContent
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
                    .padding(.bottom, AppSpacing.floatingTabClearance)
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .calderaTopScrollFade(mood: .timeline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Plan Ahead")
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calderaConfirmationOverlay(message: confirmationMessage)
        .sheet(
            isPresented: $showRecurringRecommendations,
            onDismiss: {
                focusedRecurringRecommendationID = nil
                presentQueuedRecurringSuggestionDraftIfNeeded()
            }
        ) {
            RecurringExpenseRecommendationsView(
                groups: recurringRecommendationGroups,
                focusedSuggestionID: focusedRecurringRecommendationID,
                onAddToPlanAhead: { item in
                    guard let suggestion = currentRecurringSuggestion(
                        matching: item
                    ) else {
                        return
                    }

                    queueRecurringSuggestionForDraft(suggestion)
                },
                onNotNow: { item in
                    guard let suggestion = currentRecurringSuggestion(
                        matching: item
                    ) else {
                        return
                    }

                    recordRecurringSuggestion(
                        suggestion,
                        status: .dismissed,
                        plannerEventID: nil
                    )
                },
                onReviewAgain: { item in
                    guard currentRecurringSuggestion(matching: item) != nil,
                          auth.isSignedIn,
                          let userID = auth.user?.id else {
                        return
                    }

                    recurringRecommendationHistoryStore.removeDecision(
                        stableID: item.historyID,
                        for: userID
                    )
                    reloadRecurringRecommendationHistory()
                },
                onClose: {
                    showRecurringRecommendations = false
                }
            )
        }
        .sheet(
            isPresented: $showReviewUpdates,
            onDismiss: {
                presentPendingReviewDestinationIfNeeded()
            }
        ) {
            ReviewUpdatesView(
                items: reviewUpdateItems,
                onSelect: { item in
                    pendingReviewDestination = item.destination
                    showReviewUpdates = false
                },
                onClose: {
                    showReviewUpdates = false
                }
            )
        }
        .sheet(
            isPresented: $showAddEvent,
            onDismiss: {
                pendingSuggestedExpenseDraft = nil
                pendingSuggestedExpense = nil
            }
        ) {

            AddPlannerEventView(
                editingEvent: nil,
                draft: pendingSuggestedExpenseDraft,
                onSaved: { type, isEditing in
                    showPlannerEventConfirmation(
                        type: type,
                        isEditing: isEditing
                    )
                },
                onCreatedEventPersisted:
                    recurringSuggestionPersistenceHandler
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
                onScheduleReset: {
                    showConfirmation(
                        "Expense updated. Set-aside tracking was reset for the new schedule."
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
            consumeReviewNavigationRequest()
            reloadRecurringRecommendationHistory()
        }
        .onChange(of: navigation.shouldCreateUpcomingExpense) { _, _ in
            consumeSetupNavigationRequests()
        }
        .onChange(of: navigation.recurringRecommendationToReviewID) { _, _ in
            consumeReviewNavigationRequest()
        }
        .onChange(of: auth.user?.id) { _, _ in
            pendingSuggestedExpense = nil
            queuedRecurringSuggestionForDraft = nil
            reloadRecurringRecommendationHistory()
        }
        .onChange(of: auth.isSignedIn) { _, isSignedIn in
            guard isSignedIn else {
                recurringRecommendationHistory = [:]
                pendingSuggestedExpense = nil
                queuedRecurringSuggestionForDraft = nil
                return
            }

            reloadRecurringRecommendationHistory()
        }
    }

    private func consumeSetupNavigationRequests() {
        if navigation.shouldCreateUpcomingExpense {
            navigation.shouldCreateUpcomingExpense = false
            presentNewExpense()
        }
    }

    private func consumeReviewNavigationRequest() {
        guard let historyID = navigation.recurringRecommendationToReviewID else {
            return
        }

        navigation.recurringRecommendationToReviewID = nil

        guard recurringRecommendationGroups.needsReview.contains(where: {
            $0.historyID == historyID && $0.hasCurrentEvidence
        }) else {
            return
        }

        focusedRecurringRecommendationID = historyID
        showRecurringRecommendations = true
    }

    private func presentNewExpense(
        draft: PlannerEventDraft? = nil,
        suggestion: RecurringExpenseSuggestion? = nil
    ) {
        pendingSuggestedExpenseDraft = draft
        pendingSuggestedExpense = suggestion
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
            suggestion: suggestion
        )
    }

    private func presentPendingReviewDestinationIfNeeded() {
        guard let destination = pendingReviewDestination else {
            return
        }

        pendingReviewDestination = nil

        switch destination {
        case .upcomingExpense(let forecast):
            guard unresolvedPastDueExpenseForecasts.contains(where: {
                $0.occurrenceID == forecast.occurrenceID
            }) else {
                return
            }

            selectedAllocationForecast = forecast

        case .likelyPostedCardPayment(let candidate):
            navigation.openSavingsEditDebtPayoff(
                candidate.paymentPlanID
            )

        case .paymentPlanUpdate(let paymentPlanID):
            navigation.openSavingsEditDebtPayoff(
                paymentPlanID
            )

        case .recurringExpenseRecommendation(let historyID):
            guard recurringRecommendationGroups.needsReview.contains(where: {
                $0.historyID == historyID && $0.hasCurrentEvidence
            }) else {
                return
            }

            focusedRecurringRecommendationID = historyID
            showRecurringRecommendations = true
        }
    }

    private func markPendingRecurringSuggestionAddedIfNeeded(
        plannerEventID: UUID
    ) {
        guard let pendingSuggestedExpense else {
            return
        }

        recordRecurringSuggestion(
            pendingSuggestedExpense,
            status: .added,
            plannerEventID: plannerEventID
        )
    }

    private var recurringSuggestionPersistenceHandler: ((UUID) -> Void)? {
        guard pendingSuggestedExpense != nil else {
            return nil
        }

        return { eventID in
            markPendingRecurringSuggestionAddedIfNeeded(
                plannerEventID: eventID
            )
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
                    : "Income added to Plan Ahead."
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
        CalderaPageHeader(
            eyebrow: "Plan Ahead",
            title: "Plan Ahead",
            subtitle: "See what's due soon, what is set aside, and what still needs money.",
            titleAccessory: {
                ContextHelpButton(
                    title: "Plan Ahead",
                    bodyText: "Plan Ahead shows expenses and payments coming up so you can see what still needs money set aside before the date arrives.",
                    footnote: "It helps you plan ahead before money leaves your account."
                )
            },
            trailing: {
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
        )
    }

    private var timelineTabSelector: some View {
        HStack(spacing: 4) {
            ForEach(TimelineTab.allCases) { tab in
                Button {
                    selectedTimelineTab = tab
                } label: {
                    Text(tab.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(
                            selectedTimelineTab == tab
                                ? AppColors.primaryText
                                : AppColors.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.small)
                        .background {
                            Capsule(style: .continuous)
                                .fill(
                                    selectedTimelineTab == tab
                                        ? Color.white.opacity(0.48)
                                        : Color.clear
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    selectedTimelineTab == tab ? .isSelected : []
                )
            }
        }
        .padding(4)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.16))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan Ahead view")
    }

    private var pastDueReviewAlert: some View {
        Button {
            selectedTimelineTab = .pastDue
        } label: {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: CalderaCategoryStyle.style(for: .needsMoney),
                    size: 42,
                    iconSize: 17
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(pastDueAlertTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text(pastDueAlertDetail)
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text("Review")
                    .font(.caption.weight(.bold))
                    .foregroundColor(
                        CalderaCategoryStyle.style(for: .needsMoney).primary
                    )
            }
            .padding(AppSpacing.card)
            .calderaGlassCard(
                cornerRadius: AppRadii.card,
                fillOpacity: 0.86,
                strokeOpacity: 0.68,
                shadowOpacity: 0.025,
                shadowRadius: 14,
                shadowY: 7,
                darkGlowColor: CalderaCategoryStyle.style(for: .needsMoney).primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pastDueAlertTitle). Review past due items.")
    }

    private var pastDueTimelineContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.screen) {
            if pastDueChronologicalItems.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: "Nothing past due",
                    description: "You're up to date here.",
                    color: CalderaCategoryStyle.style(for: .covered).primary
                )
            } else {
                timelineListHeader(
                    title: "Past Due",
                    subtitle: "Expenses and payment plans that still need review."
                )
                chronologicalTimelineList(pastDueChronologicalItems)
            }
        }
    }

    private var recurringExpenseSuggestions: [RecurringExpenseSuggestion] {
        RecurringExpenseSuggestionEngine.suggestions(
            transactions: plaid.transactions,
            existingEvents: events,
            snapshotMetadata: plaid.transactionSnapshotMetadata,
            automationIsEligible: plaid.transactionAutomationIsEligible
        )
    }

    private var recurringRecommendationGroups: RecurringExpenseRecommendationGroups {
        RecurringExpenseRecommendationGroups(
            suggestions: recurringExpenseSuggestions,
            history: activeRecurringRecommendationHistory,
            existingExpenseIDs: Set(
                events
                    .filter { $0.type == .expense }
                    .map(\.id)
            )
        )
    }

    private var activeRecurringRecommendationHistory:
        [String: RecurringExpenseRecommendationHistoryRecord] {
        guard auth.isSignedIn,
              let userID = auth.user?.id else {
            return [:]
        }

        let activeScope =
            RecurringExpenseRecommendationIdentity.userScope(
                userID: userID
            )

        return recurringRecommendationHistory.filter {
            $0.value.userScope == activeScope
        }
    }

    private var hasRecurringRecommendationContent: Bool {
        recurringRecommendationGroups.totalCount > 0
    }

    private var hasPendingRecurringRecommendations: Bool {
        !recurringRecommendationGroups.needsReview.isEmpty
    }

    private var reviewUpdateItems: [ReviewUpdateItem] {
        ReviewUpdateItems.make(
            pastDueExpenses: unresolvedPastDueExpenseForecasts,
            likelyPostedCardPayments: likelyPostedCardPaymentCandidates,
            paymentPlanUpdates: PaymentPlanReviewUpdates.updates(
                paymentPlans: visiblePaymentPlans,
                cardPaymentDetails: plaid.cardPaymentDetails
            ),
            recurringRecommendations: recurringRecommendationGroups.needsReview
        )
    }

    private var likelyPostedCardPaymentCandidates:
        [PaymentPlanPaymentCandidate] {
        visiblePaymentPlans.compactMap { bucket in
            guard let cycle = PaymentPlanCycleStore.activeCycle(
                for: bucket.id,
                in: paymentPlanCycles
            ) else {
                return nil
            }

            return plaid.likelyPostedCardPayment(
                for: bucket,
                cycle: cycle
            )
        }
    }

    private var reviewUpdatesEntryPoint: some View {
        let count = reviewUpdateItems.count
        let detail = count == 1
            ? "1 item is ready to review."
            : "\(count) items are ready to review."

        return Button {
            showReviewUpdates = true
        } label: {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: CalderaCategoryStyle.style(for: .debtPayoff),
                    size: 44,
                    iconSize: 18
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Review Updates")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
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
                darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Review Updates. \(detail)"
        )
    }

    private var recurringExpenseRecommendationsEntryPoint: some View {
        let groups = recurringRecommendationGroups
        let needsReviewCount = groups.needsReview.count
        let historyCount = groups.added.count + groups.dismissed.count +
            groups.noLongerInPlan.count
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

    private func recordRecurringSuggestion(
        _ suggestion: RecurringExpenseSuggestion,
        status: RecurringExpenseSuggestionStatus,
        plannerEventID: UUID?
    ) {
        guard auth.isSignedIn,
              let userID = auth.user?.id else {
            return
        }

        recurringRecommendationHistoryStore.record(
            suggestion,
            status: status,
            plannerEventID: plannerEventID,
            for: userID
        )
        reloadRecurringRecommendationHistory()
    }

    private func currentRecurringSuggestion(
        matching item: RecurringExpenseRecommendationItem
    ) -> RecurringExpenseSuggestion? {
        guard auth.isSignedIn,
              let itemSuggestion = item.suggestion else {
            return nil
        }

        return recurringExpenseSuggestions.first {
            $0.id == itemSuggestion.id &&
                $0.historyID == itemSuggestion.historyID
        }
    }

    private func reloadRecurringRecommendationHistory() {
        recurringRecommendationHistory =
            recurringRecommendationHistoryStore.records(
                for: auth.user?.id
            )
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
            }

            Text("Upcoming Expenses and Payment Plans in date order.")
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if upcomingChronologicalItems.isEmpty {
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
                chronologicalTimelineList(upcomingChronologicalItems)
            }

            if !legacyIncomeEvents.isEmpty {
                LegacyIncomePlannerEventsSection(
                    events: legacyIncomeEvents,
                    onSelect: { event in
                        selectedEvent = event
                    }
                )
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

    private func timelineListHeader(
        title: String,
        subtitle: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(AppColors.primaryText)

            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chronologicalTimelineList(
        _ items: [PlanAheadTimelineItem]
    ) -> some View {
        VStack(spacing: AppSpacing.medium) {
            ForEach(items) { item in
                switch item {
                case .upcomingExpense(let forecast):
                    PlannerEventRow(
                        event: forecast.event,
                        occurrenceDate: forecast.occurrenceDate,
                        allocatedAmount: allocatedAmount(for: forecast)
                    ) {
                        selectedAllocationForecast = forecast
                    }

                case .paymentPlan(let bucket):
                    let cycle = PaymentPlanCycleStore.activeCycle(
                        for: bucket.id,
                        in: paymentPlanCycles
                    )
                    PaymentPlanTimelineRow(
                        bucket: bucket,
                        cycle: cycle,
                        linkedAccount: paymentPlanAccountByID[bucket.plaidAccountID],
                        isPastDue: Calendar.current.startOfDay(for: bucket.dueDate) < startOfToday,
                        paymentCandidate: cycle.flatMap {
                            plaid.likelyPostedCardPayment(
                                for: bucket,
                                cycle: $0
                            )
                        }
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

    private var legacyIncomeEvents: [PlannerEvent] {
        PlannerEventManagement.legacyIncomeEvents(
            from: events
        )
    }

    private var pastDueUpcomingExpenseForecasts: [ForecastEvent] {
        unresolvedPastDueExpenseForecasts
    }

    private var unresolvedPastDueExpenseForecasts: [ForecastEvent] {
        ExpenseOccurrenceLifecycleResolver.unresolvedPastDueForecasts(
            from: forecastEvents,
            statuses: occurrenceStatuses
        )
    }

    private var pastDuePaymentPlans: [DebtPayoffBucket] {
        visiblePaymentPlans.filter {
            Calendar.current.startOfDay(for: $0.dueDate) < startOfToday
        }
    }

    private var upcomingChronologicalItems: [PlanAheadTimelineItem] {
        PlanAheadTimelineItems.upcoming(
            expenses: upcomingExpenseForecasts,
            paymentPlans: visiblePaymentPlans,
            startOfToday: startOfToday
        )
    }

    private var pastDueChronologicalItems: [PlanAheadTimelineItem] {
        PlanAheadTimelineItems.pastDue(
            expenses: pastDueUpcomingExpenseForecasts,
            paymentPlans: pastDuePaymentPlans,
            startOfToday: startOfToday
        )
    }

    private var hasPastDueItems: Bool {
        !pastDueUpcomingExpenseForecasts.isEmpty ||
            !pastDuePaymentPlans.isEmpty
    }

    private var pastDueItemCount: Int {
        pastDueUpcomingExpenseForecasts.count + pastDuePaymentPlans.count
    }

    private var pastDueAlertTitle: String {
        pastDueItemCount == 1
            ? "1 item is past due"
            : "\(pastDueItemCount) items need review"
    }

    private var pastDueAlertDetail: String {
        if !pastDueUpcomingExpenseForecasts.isEmpty {
            return "Some money may still be set aside until you mark these expenses paid or skip them."
        }

        return "Review these payment plans to keep your plan current."
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
                bucket.shouldDisplayDueDate &&
                    PaymentPlanCycleStore.isActiveOrLegacy(
                        paymentPlanID: bucket.id,
                        cycles: paymentPlanCycles
                    )
            }
            .sorted {
                $0.dueDate < $1.dueDate
            }
    }

}

private enum TimelineTab: String, CaseIterable, Identifiable {
    case upcoming
    case pastDue

    var id: Self { self }

    var title: String {
        switch self {
        case .upcoming:
            return "Upcoming"
        case .pastDue:
            return "Past Due"
        }
    }
}



enum PlanAheadTimelineItem: Identifiable {
    case upcomingExpense(ForecastEvent)
    case paymentPlan(DebtPayoffBucket)

    var id: String {
        switch self {
        case .upcomingExpense(let forecast):
            return "expense-\(forecast.occurrenceID)"
        case .paymentPlan(let bucket):
            return "payment-plan-\(bucket.id.uuidString)"
        }
    }

    var dueDate: Date {
        switch self {
        case .upcomingExpense(let forecast):
            return forecast.occurrenceDate
        case .paymentPlan(let bucket):
            return bucket.dueDate
        }
    }

    fileprivate var typeSortOrder: Int {
        switch self {
        case .upcomingExpense:
            return 0
        case .paymentPlan:
            return 1
        }
    }

    fileprivate var titleForSort: String {
        switch self {
        case .upcomingExpense(let forecast):
            return forecast.event.name
        case .paymentPlan(let bucket):
            return bucket.accountName
        }
    }
}

enum PlanAheadTimelineItems {

    static func upcoming(
        expenses: [ForecastEvent],
        paymentPlans: [DebtPayoffBucket],
        startOfToday: Date,
        calendar: Calendar = .current
    ) -> [PlanAheadTimelineItem] {
        sorted(
            expenses: expenses.filter {
                calendar.startOfDay(for: $0.occurrenceDate) >= startOfToday
            },
            paymentPlans: paymentPlans.filter {
                calendar.startOfDay(for: $0.dueDate) >= startOfToday
            },
            calendar: calendar
        )
    }

    static func pastDue(
        expenses: [ForecastEvent],
        paymentPlans: [DebtPayoffBucket],
        startOfToday: Date,
        calendar: Calendar = .current
    ) -> [PlanAheadTimelineItem] {
        sorted(
            expenses: expenses.filter {
                calendar.startOfDay(for: $0.occurrenceDate) < startOfToday
            },
            paymentPlans: paymentPlans.filter {
                calendar.startOfDay(for: $0.dueDate) < startOfToday
            },
            calendar: calendar
        )
    }

    private static func sorted(
        expenses: [ForecastEvent],
        paymentPlans: [DebtPayoffBucket],
        calendar: Calendar
    ) -> [PlanAheadTimelineItem] {
        (expenses.map(PlanAheadTimelineItem.upcomingExpense) +
            paymentPlans.map(PlanAheadTimelineItem.paymentPlan))
            .sorted { lhs, rhs in
                let leftDate = calendar.startOfDay(for: lhs.dueDate)
                let rightDate = calendar.startOfDay(for: rhs.dueDate)

                if leftDate != rightDate {
                    return leftDate < rightDate
                }

                if lhs.typeSortOrder != rhs.typeSortOrder {
                    return lhs.typeSortOrder < rhs.typeSortOrder
                }

                let titleOrder = lhs.titleForSort.localizedCaseInsensitiveCompare(
                    rhs.titleForSort
                )

                if titleOrder != .orderedSame {
                    return titleOrder == .orderedAscending
                }

                return lhs.id < rhs.id
            }
    }
}

private struct PaymentPlanTimelineRow: View {

    let bucket: DebtPayoffBucket
    let cycle: PaymentPlanCycle?
    let linkedAccount: PlaidAccount?
    let isPastDue: Bool
    let paymentCandidate: PaymentPlanPaymentCandidate?
    let action: () -> Void

    private let currencyTolerance = 0.005
    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    private var display: DebtPayoffDisplayModel {
        DebtPayoffDisplayModel(
            bucket: bucket,
            linkedAccount: linkedAccount,
            cycle: cycle
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
                        HStack(spacing: AppSpacing.xSmall) {
                            Text(display.title)
                                .font(.headline)
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)

                            Text("Payment Plan")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(style.primary)
                                .padding(.horizontal, AppSpacing.xSmall)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(style.primary.opacity(0.12))
                                )
                        }

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

                if let paymentCandidate {
                    HStack(alignment: .top, spacing: AppSpacing.small) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundColor(
                                CalderaCategoryStyle.style(for: .covered).primary
                            )

                        Text(
                            "A payment of \(AppFormatters.currency(paymentCandidate.amount)) dated \(AppFormatters.abbreviatedMonthDay(paymentCandidate.postedDate)) may have posted after your last Bank Sync."
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: AppSpacing.xSmall)

                        HStack(spacing: 3) {
                            Text("Review payment")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(style.primary)
                    }
                    .padding(.top, AppSpacing.xxSmall)
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
            paymentCandidate == nil
                ? "\(display.title), payment plan, due \(AppFormatters.abbreviatedMonthDay(bucket.dueDate)), \(statusText)"
                : "\(display.title), payment plan, due \(AppFormatters.abbreviatedMonthDay(bucket.dueDate)), \(statusText). A possible card payment is ready to review."
        )
        .accessibilityHint(
            paymentCandidate == nil
                ? "Opens this payment plan."
                : "Opens this payment plan to review the possible card payment."
        )
    }
}
