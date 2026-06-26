import SwiftUI
import SwiftData

struct PlannerView: View {

    @EnvironmentObject var summary: SummaryViewModel

    @Query
    var events: [PlannerEvent]

    @Query
    var allocations: [EventAllocation]

    @Query
    var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @State private var showAddEvent = false
    @State private var showPurchaseImpact = false
    @State private var selectedEvent: PlannerEvent?
    @State private var selectedAllocationForecast: ForecastEvent?

    var body: some View {

        NavigationStack {

            ZStack(alignment: .bottomTrailing) {
                AppScreen(
                    usesNavigationStack: false,
                    contentPadding: .vertical
                ) {

                    plannerHeader
                        .padding(.horizontal)

                    availableCard
                    .padding(.horizontal)

                    VStack(
                        spacing: 12
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
                                systemImage: "calendar.badge.exclamationmark",
                                title: "Plan ahead with confidence",
                                description: "Add your first bill, paycheck, or recurring event to see what your money needs to cover.",
                                primaryActionTitle: "Add Event",
                                primaryAction: {
                                    showAddEvent = true
                                },
                                color: AppColors.warning
                            )

                        } else {

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
                    .padding(.horizontal)
                }

                purchaseImpactButton
                    .padding(.trailing, AppSpacing.regular)
                    .padding(.bottom, AppSpacing.regular)
            }
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
                        colors: [
                            AppColors.primaryButtonStart,
                            AppColors.primaryButtonEnd
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .shadow(
                    color: AppColors.accent.opacity(0.25),
                    radius: 18,
                    y: 10
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open purchase impact")
    }

    private var plannerHeader: some View {
        HStack(spacing: AppSpacing.medium) {
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
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showAddEvent = true
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
            .accessibilityLabel("Add upcoming event")
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
