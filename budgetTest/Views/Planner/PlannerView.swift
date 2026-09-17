import SwiftUI
import SwiftData

private enum PlannerReviewUpdatesDestination {
    case reviewUpdate(ReviewUpdateDestination)
    case recurringRecommendationHistory
}

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

    @Query
    var incomeSchedules: [IncomeSchedule]

    @State private var showNewExpenseCreate = false
    @State private var showAddEvent = false
    @State private var selectedEvent: PlannerEvent?
    @State private var selectedEventForecast: ForecastEvent?
    @State private var selectedAllocationForecast: ForecastEvent?
    @State private var pendingEventToEdit: ForecastEvent?
    @State private var planAheadPresentationNavigation =
        PlanAheadPresentationNavigationState()
    @State private var selectedSummaryHorizon: PlanAheadSummaryHorizon = .days30
    @State private var scheduleToEdit: IncomeSchedule?
    @State private var pendingSuggestedExpenseDraft: PlannerEventDraft?
    @State private var pendingSuggestedExpense: RecurringExpenseSuggestion?
    @State private var showRecurringRecommendations = false
    @State private var showReviewUpdates = false
    @State private var queuedRecurringSuggestionForDraft: RecurringExpenseSuggestion?
    @State private var pendingReviewDestination:
        PlannerReviewUpdatesDestination?
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
                PlanAheadAtmosphericBackground()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(
                            alignment: .leading,
                            spacing: AppSpacing.screen
                        ) {
                            plannerHeader

                            PlanAheadPlanningOutlookView(
                                horizon: $selectedSummaryHorizon,
                                presentation: planAheadSummaryPresentation,
                                onReviewPastDue: focusPastDue
                            )

                            HStack {
                                PlanAheadPresentationSelector(
                                    selection: $planAheadPresentationNavigation.selectedMode
                                )
                                Spacer(minLength: 0)
                            }

                            if hasReviewUpdatesContent {
                                reviewUpdatesEntryPoint
                            }

                            switch planAheadPresentationNavigation.selectedMode {
                            case .cards:
                                PlanAheadCardsPresentation(
                                    composition: planAheadComposition,
                                    today: startOfToday,
                                    onSelect: openPlanAheadEvent,
                                    onEditExpectedIncome: openExpectedIncomeUpdate
                                )

                            case .list:
                                PlanAheadListPresentation(
                                    composition: planAheadComposition,
                                    onSelect: openPlanAheadEvent,
                                    onEditExpectedIncome: openExpectedIncomeUpdate
                                )
                            }

                            if !legacyIncomeEvents.isEmpty {
                                LegacyIncomePlannerEventsSection(
                                    events: legacyIncomeEvents,
                                    onSelect: { event in
                                        selectedEventForecast = nil
                                        selectedEvent = event
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical)
                        .padding(.bottom, AppSpacing.floatingTabClearance)
                    }
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(
                        of: planAheadPresentationNavigation.pastDueFocusRequestID
                    ) { _, requestID in
                        guard requestID > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(
                                PlanAheadScrollAnchor.pastDue,
                                anchor: .top
                            )
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsPinnedEmptyAddExpenseAction {
                    pinnedEmptyAddExpenseAction
                }
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
                recurringRecommendationHistory:
                    reviewedRecurringRecommendationHistory,
                showsBankConfidenceBanner:
                    ReviewUpdatesBankConfidence.shouldShowBanner(
                        hasBankRefreshWarning:
                            plaid.bankSyncRefreshState.balanceNeedsAttention
                    ),
                onSelect: { item in
                    pendingReviewDestination = .reviewUpdate(
                        item.destination
                    )
                    showReviewUpdates = false
                },
                onOpenRecurringRecommendationHistory: {
                    pendingReviewDestination =
                        .recurringRecommendationHistory
                    showReviewUpdates = false
                },
                onOpenBankSync: {
                    showReviewUpdates = false
                    navigation.openBankSync()
                },
                onClose: {
                    showReviewUpdates = false
                }
            )
        }
        .sheet(
            isPresented: $showNewExpenseCreate
        ) {
            NewUpcomingExpenseCreateView {
                showPlannerEventConfirmation(
                    type: .expense,
                    isEditing: false
                )
            }
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
            item: $selectedEvent,
            onDismiss: {
                selectedEventForecast = nil
            }
        ) { event in

            PlannerEventEditorDestination(
                editingEvent: event,
                forecast: selectedEventForecast,
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
                            ? "Bill deleted."
                            : "Income deleted."
                    )
                }
            )
        }
        .sheet(
            item: $selectedAllocationForecast,
            onDismiss: {
                guard let forecast = pendingEventToEdit else {
                    return
                }

                pendingEventToEdit = nil
                selectedEventForecast = forecast
                selectedEvent = forecast.event
            }
        ) { forecast in

            EventAllocationDetailView(
                forecast: forecast
            ) {
                pendingEventToEdit = forecast
                selectedAllocationForecast = nil
            }
        }
        .sheet(item: $scheduleToEdit) { schedule in
            IncomeScheduleEditorView(
                ownerScopeID: schedule.ownerScopeID,
                editingSchedule: schedule
            )
        }
        .onAppear {
            consumeSetupNavigationRequests()
            consumeUpcomingExpenseEditRequest()
            consumeReviewNavigationRequest()
            reloadRecurringRecommendationHistory()
        }
        .onChange(of: navigation.shouldCreateUpcomingExpense) { _, _ in
            consumeSetupNavigationRequests()
        }
        .onChange(of: navigation.recurringRecommendationToReviewID) { _, _ in
            consumeReviewNavigationRequest()
        }
        .onChange(of: navigation.upcomingExpenseToEditRequest) { _, _ in
            consumeUpcomingExpenseEditRequest()
        }
        .onChange(of: navigation.shouldOpenReviewUpdates) { _, _ in
            consumeReviewNavigationRequest()
        }
        .onChange(of: navigation.shouldOpenPlanAheadPastDue) { _, _ in
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
        if navigation.shouldOpenReviewUpdates {
            navigation.shouldOpenReviewUpdates = false

            if hasReviewUpdatesContent {
                showReviewUpdates = true
            }
        }

        if navigation.shouldOpenPlanAheadPastDue {
            navigation.shouldOpenPlanAheadPastDue = false
            focusPastDue()
        }

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

    private func consumeUpcomingExpenseEditRequest() {
        guard let request = navigation.upcomingExpenseToEditRequest else {
            return
        }

        navigation.upcomingExpenseToEditRequest = nil

        guard let forecast = forecastEvents.first(where: {
            $0.event.id == request.eventID &&
                $0.occurrenceID == request.occurrenceID &&
                $0.event.type == .expense
        }) else {
            return
        }

        selectedEventForecast = forecast
        selectedEvent = forecast.event
    }

    private func presentNewExpense(
        draft: PlannerEventDraft? = nil,
        suggestion: RecurringExpenseSuggestion? = nil
    ) {
        guard draft != nil || suggestion != nil else {
            showNewExpenseCreate = true
            return
        }

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
        case .recurringRecommendationHistory:
            guard reviewedRecurringRecommendationHistory.isAvailable else {
                return
            }

            focusedRecurringRecommendationID = nil
            showRecurringRecommendations = true

        case .reviewUpdate(let reviewDestination):
            presentReviewUpdateDestination(reviewDestination)
        }
    }

    private func presentReviewUpdateDestination(
        _ destination: ReviewUpdateDestination
    ) {
        switch destination {
        case .upcomingExpense(let forecast):
            guard unresolvedPastDueExpenseForecasts.contains(where: {
                $0.occurrenceID == forecast.occurrenceID
            }) else {
                return
            }

            selectedAllocationForecast = forecast

        case .pastDuePaymentPlan:
            navigation.openPlanAheadPastDue()

        case .likelyPostedCardPayment(let candidate):
            navigation.openSavingsEditDebtPayoff(
                candidate.paymentPlanID,
                cycleID: candidate.cycleID
            )

        case .paymentPlanUpdate(let update):
            navigation.openSavingsEditDebtPayoff(
                update.paymentPlanID,
                providerReview: update
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
                    ? "Bill updated."
                    : "Bill added to your plan."
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
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("PLAN AHEAD")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.accent)

                Text(Date().formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your financial future, laid out over time.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.small)

            HStack(spacing: AppSpacing.xSmall) {
                ContextHelpButton(
                    title: "Plan Ahead",
                    bodyText: "Plan Ahead shows expenses and payments coming up so you can see what still needs money set aside before the date arrives.",
                    footnote: "It helps you plan ahead before money leaves your account."
                )

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
        .padding(.top, AppSpacing.small)
        .accessibilityElement(children: .contain)
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

    private var incomeScheduleOwnerScope: String {
        IncomeScheduleOwnerScope.current(
            authenticatedUserID: auth.user?.id
        )
    }

    private var reviewUpdateItems: [ReviewUpdateItem] {
        ReviewUpdateSourceAssembler.make(
            .init(
                pastDueExpenses: unresolvedPastDueExpenseForecasts,
                pastDuePaymentPlans: pastDuePaymentPlans.map(\.bucket),
                likelyPostedCardPayments: likelyPostedCardPaymentCandidates,
                paymentPlans: visiblePaymentPlans,
                cardPaymentDetails: plaid.cardPaymentDetails,
                cardPaymentDetailsRefreshState:
                    plaid.cardPaymentDetailsRefreshState,
                lastSuccessfulCardPaymentDetailsRefresh:
                    plaid.lastSuccessfulCardPaymentDetailsRefresh,
                recurringRecommendations: recurringRecommendationGroups.needsReview
            )
        )
    }

    private var reviewedRecurringRecommendationHistory:
        ReviewUpdatesRecurringRecommendationHistory {
        ReviewUpdatesRecurringRecommendationHistory(
            groups: recurringRecommendationGroups
        )
    }

    private var hasReviewUpdatesContent: Bool {
        !reviewUpdateItems.isEmpty ||
            reviewedRecurringRecommendationHistory.isAvailable
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
        let detail: String

        if count == 0 {
            detail = "Review recurring recommendations you already handled."
        } else if count == 1 {
            detail = "1 item is ready to review."
        } else {
            detail = "\(count) items are ready to review."
        }

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

    private var showsPinnedEmptyAddExpenseAction: Bool {
        planAheadComposition.upcomingObligations.isEmpty
    }

    private var pinnedEmptyAddExpenseAction: some View {
        PrimaryButton(
            "Add Expense",
            systemImage: "plus",
            trailingSystemImage: nil,
            fillsWidth: true
        ) {
            presentNewExpense()
        }
        .accessibilityIdentifier("plan-ahead-empty-add-expense")
        .padding(.horizontal, AppSpacing.regular)
        .padding(.top, AppSpacing.medium)
        .padding(.bottom, AppSpacing.small)
        .background(.ultraThinMaterial)
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

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
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

    private var pastDuePaymentPlans: [PlanAheadPaymentPlan] {
        planAheadPaymentPlans.filter {
            PlanAheadPaymentPlanWindow.isPastDue(
                dueDate: $0.dueDate,
                startOfToday: startOfToday
            )
        }
    }

    private var upcomingChronologicalItems: [PlanAheadTimelineItem] {
        PlanAheadTimelineItems.upcoming(
            expenses: upcomingExpenseForecasts,
            paymentPlans: planAheadPaymentPlans,
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

    private var visibleIncomeSchedule: IncomeSchedule? {
        IncomeSchedulePhaseOnePolicy.visibleSchedule(
            from: incomeSchedules,
            ownerScopeID: incomeScheduleOwnerScope
        )
    }

    private var planAheadComposition: PlanAheadProductionComposition {
        PlanAheadProductionCompositionBuilder.make(
            pastDueItems: pastDueChronologicalItems,
            upcomingItems: upcomingChronologicalItems,
            allocationAmounts: EventAllocationAmountLookup(
                allocations: allocations
            ),
            accountByID: paymentPlanAccountByID,
            cycles: paymentPlanCycles,
            expectedIncomeSchedule: visibleIncomeSchedule,
            today: startOfToday
        )
    }

    private func openPlanAheadEvent(_ item: PlanAheadPresentedEvent) {
        switch item.source {
        case .upcomingExpense(let forecast):
            selectedAllocationForecast = forecast

        case .paymentPlan(let paymentPlan, let cycle):
            navigation.openSavingsEditDebtPayoff(
                paymentPlan.bucket.id,
                cycleID: cycle?.id
            )

        case .expectedIncome(let schedule, _):
            scheduleToEdit = schedule
        }
    }

    private func openExpectedIncomeUpdate(
        _ update: PlanAheadExpectedIncomeUpdate
    ) {
        scheduleToEdit = update.schedule
    }

    private func focusPastDue() {
        planAheadPresentationNavigation.requestPastDueFocus()
    }

    private var planAheadSummaryPresentation: PlanAheadSummaryPresentation {
        planAheadComposition.summary(
            for: selectedSummaryHorizon,
            today: startOfToday
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
                    PlanAheadPaymentPlanWindow.isVisible(
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



private struct PaymentPlanTimelineRow: View {

    let bucket: DebtPayoffBucket
    let cycle: PaymentPlanCycle?
    let linkedAccount: PlaidAccount?
    let paymentCandidate: PaymentPlanPaymentCandidate?
    let action: () -> Void

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    private var display: DebtPayoffDisplayModel {
        DebtPayoffDisplayModel(
            bucket: bucket,
            linkedAccount: linkedAccount,
            cycle: cycle
        )
    }

    private var statusColor: Color {
        display.presentationStatus.isReassuring
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
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Credit or Loan")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(style.primary)
                                .padding(.horizontal, AppSpacing.xSmall)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(style.primary.opacity(0.12))
                                )
                        }

                        Text(display.presentationStatusValue)
                            .font(.caption)
                            .foregroundColor(statusColor)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(display.dueDateValue)
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    VStack(
                        alignment: .trailing,
                        spacing: 6
                    ) {
                        SensitiveValueText(display.plannedPaymentValue)
                            .font(.headline.bold())
                            .foregroundColor(style.primary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)

                        Text(display.plannedPaymentMeaningValue)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .multilineTextAlignment(.trailing)
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

                amountSummary

                Text("Next: \(display.nextActionValue)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(statusColor)
                    .fixedSize(horizontal: false, vertical: true)

                if let paymentCandidate {
                    HStack(alignment: .top, spacing: AppSpacing.small) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundColor(
                                CalderaCategoryStyle.style(for: .covered).primary
                            )

                        SensitiveValueText(
                            PossiblePaymentReviewPresentation.compactDetail(
                                for: paymentCandidate
                            )
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
        .sensitiveAccessibilityLabel(
            paymentCandidate == nil
                ? display.accessibilitySummary
                : "\(display.accessibilitySummary). A possible card payment is ready to review."
        )
        .accessibilityHint(
            paymentCandidate == nil
                ? "Opens this Credit or Loan."
                : "Opens this Credit or Loan to review the possible card payment."
        )
    }

    private var amountSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.small) {
                amountValue(
                    title: "Set aside",
                    value: display.setAsideValue
                )

                amountValue(
                    title: "Still needed",
                    value: display.remainingValue
                )
            }

            VStack(spacing: AppSpacing.xSmall) {
                amountValue(
                    title: "Set aside",
                    value: display.setAsideValue
                )

                amountValue(
                    title: "Still needed",
                    value: display.remainingValue
                )
            }
        }
    }

    private func amountValue(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)

            SensitiveValueText(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.small)
        .background(
            RoundedRectangle(
                cornerRadius: AppRadii.field,
                style: .continuous
            )
            .fill(style.primary.opacity(0.07))
        )
    }
}
