import SwiftUI
import SwiftData

struct AllTimelineExpensesView: View {

    @EnvironmentObject private var navigation: AppNavigation

    @Query
    private var events: [PlannerEvent]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @State private var showAddEvent = false
    @State private var selectedEvent: PlannerEvent?
    @State private var confirmationMessage: String?
    @State private var confirmationID = UUID()

    private var forecasts: [ForecastEvent] {
        var seenEventIDs = Set<UUID>()

        return PlannerForecastCalculator(
            events: events,
            totalAvailable: 0,
            totalGoalAllocated: 0,
            includeFutureIncome: true,
            protectGoals: true,
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
        .forecastEvents
        .filter {
            $0.event.type == .expense
        }
        .filter { forecast in
            seenEventIDs.insert(forecast.event.id).inserted
        }
    }

    private var inactiveOccurrenceIDs: Set<String> {
        ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: occurrenceStatuses
        )
    }

    var body: some View {
        ZStack {
            CalderaPageBackground(
                mood: .timeline,
                isActive: navigation.selectedTab == 2
            )

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.screen
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.small
                    ) {
                        Text("Timeline")
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)

                        Text("Upcoming Expenses")
                            .font(
                                .system(
                                    size: 34,
                                    weight: .bold
                                )
                            )
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text("Your Upcoming Expenses, shown by next due date.")
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if forecasts.isEmpty {
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
                        VStack(spacing: AppSpacing.small) {
                            ForEach(forecasts) { forecast in
                                expenseRow(forecast)
                            }
                        }
                    }
                }
                .padding(.all)
                .padding(.bottom, AppSpacing.emptyState)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Upcoming Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .calderaTransparentNavigationSurface()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddEvent = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(AppColors.accent)
                }
                .accessibilityLabel("Add upcoming expense")
            }
        }
        .calderaConfirmationOverlay(message: confirmationMessage)
        .sheet(isPresented: $showAddEvent) {
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
        .sheet(item: $selectedEvent) { event in
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

    private func expenseRow(
        _ forecast: ForecastEvent
    ) -> some View {
        Button {
            selectedEvent = forecast.event
        } label: {
            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: CalderaCategoryStyle.style(for: .upcomingExpense),
                    size: 38,
                    iconSize: 16
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(forecast.event.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Text(subtitle(for: forecast))
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: AppSpacing.small)

                Text(AppFormatters.currency(forecast.event.amount))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .upcomingExpense).primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.65))
            }
        }
        .buttonStyle(.plain)
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.84,
            strokeOpacity: 0.66,
            shadowOpacity: 0.025,
            shadowRadius: 12,
            shadowY: 5
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Edit \(forecast.event.name)")
    }

    private func subtitle(
        for forecast: ForecastEvent
    ) -> String {
        let dateText = AppFormatters.abbreviatedMonthDay(
            forecast.occurrenceDate
        )

        if forecast.event.frequency == .once {
            return "Due \(dateText)"
        }

        return "Next \(dateText) · \(forecast.event.frequency.rawValue)"
    }
}
