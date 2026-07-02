import SwiftUI
import SwiftData

struct PlannerView: View {

    @EnvironmentObject var summary: SummaryViewModel
    @EnvironmentObject private var navigation: AppNavigation

    @Query
    var events: [PlannerEvent]

    @Query
    var allocations: [EventAllocation]

    @Query
    var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @Query
    var debtPayoffBuckets: [DebtPayoffBucket]

    @State private var showAddEvent = false
    @State private var showPurchaseImpact = false
    @State private var selectedEvent: PlannerEvent?
    @State private var selectedAllocationForecast: ForecastEvent?

    var body: some View {

        NavigationStack {

            ZStack(alignment: .bottomTrailing) {
                CalderaPageBackground(
                    mood: .timeline,
                    isActive: navigation.selectedTab == 2
                )

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.screen
                    ) {
                        plannerHeader

                        availableCard

                        upcomingExpensesSection
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
                    .padding(.bottom, 120)
                }

                purchaseImpactButton
                    .padding(.trailing, AppSpacing.regular)
                    .padding(.bottom, AppSpacing.regular)
            }
            .optionalTopScrollFade(isEnabled: true)
        }
        .sheet(
            isPresented: $showAddEvent
        ) {

            AddPlannerEventView(
                editingEvent: nil
            )
        }
        .sheet(
            item: $selectedEvent
        ) { event in

            AddPlannerEventView(
                editingEvent: event
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
        .sheet(
            isPresented: $showPurchaseImpact
        ) {

            PurchaseImpactSheet(
                plannerAvailable: plannerAvailable,
                safeToSpend: safeToSpend,
                nextExpense: nextExpense
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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

    private var purchaseImpactButton: some View {
        Button {
            showPurchaseImpact = true
        } label: {
            Image(systemName: "cart.fill")
                .font(.title3.bold())
                .foregroundColor(.white)
                .frame(
                    width: 58,
                    height: 58
                )
                .background(
                    LinearGradient(
                        colors: CalderaVisualStyle.safeGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                }
                .shadow(
                    color: AppColors.accent.opacity(0.28),
                    radius: 20,
                    y: 12
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open purchase impact")
    }

    private var plannerHeader: some View {
        HStack(spacing: AppSpacing.medium) {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("Forecast")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

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

                Text("See how each upcoming event changes what remains available.")
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
                Text("Upcoming Expenses")
                    .font(.title3.bold())
                    .foregroundStyle(AppColors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !uniqueUpcomingExpenseForecasts.isEmpty {
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

            if forecastEvents.isEmpty {
                EmptyStateView(
                    systemImage: CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                    title: "No Upcoming Expenses yet",
                    description: "Add your first bill or recurring expense to see how it shapes Available to Spend over time.",
                    primaryActionTitle: "Add Upcoming Expense",
                    primaryAction: {
                        showAddEvent = true
                    },
                    secondaryText: "You can add paychecks later too, but expenses are the fastest way to understand what's coming up.",
                    color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
                )
            } else {
                VStack(spacing: AppSpacing.medium) {
                    ForEach(
                        forecastEvents.prefix(6)
                    ) { forecast in
                        PlannerEventRow(
                            event: forecast.event,
                            occurrenceDate: forecast.occurrenceDate,
                            projectedAvailable: projectedAvailable(
                                after: forecast
                            ),
                            currentSafeToSpend: safeToSpend,
                            allocatedAmount: allocatedAmount(
                                for: forecast
                            ),
                            usesCoverageAwareStatus: forecast.id == nextExpense?.id
                        ) {
                            selectedAllocationForecast = forecast
                        }
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
