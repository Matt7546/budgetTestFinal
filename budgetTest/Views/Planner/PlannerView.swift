import SwiftUI
import SwiftData

struct PlannerView: View {


@EnvironmentObject var summary: SummaryViewModel

@Query
var events: [PlannerEvent]

@State private var showAddEvent = false
@State private var selectedEvent: PlannerEvent?

@AppStorage("includeFutureIncome")
var includeFutureIncome = true

@AppStorage("protectGoals")
var protectGoals = true

var body: some View {

    NavigationStack {

        ZStack {

            LinearGradient(
                colors: [
                    Color(
                        red: 0.96,
                        green: 0.97,
                        blue: 1.00
                    ),
                    Color(
                        red: 0.92,
                        green: 0.95,
                        blue: 0.99
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {

                VStack(
                    alignment: .leading,
                    spacing: 24
                ) {

                    HStack(alignment: .center) {

                        Text("Planner")
                            .font(.system(size: 42, weight: .bold))

                        Spacer()

                        HStack(spacing: 8) {

                            Button {

                                includeFutureIncome.toggle()

                            } label: {

                                Text(
                                    includeFutureIncome
                                    ? "Forecast"
                                    : "Current"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    includeFutureIncome
                                    ? .blue
                                    : .primary
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            includeFutureIncome
                                            ? Color.blue.opacity(0.12)
                                            : Color.gray.opacity(0.10)
                                        )
                                )
                            }

                            Button {

                                protectGoals.toggle()

                            } label: {

                                Text(
                                    protectGoals
                                    ? "Protected"
                                    : "Available"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    protectGoals
                                    ? .green
                                    : .orange
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            protectGoals
                                            ? Color.green.opacity(0.12)
                                            : Color.orange.opacity(0.12)
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 16) {

                
                    availableCard

                    plannerSummaryCard
                    
                    }
                    .padding(.horizontal)

                    Text("Upcoming Events")
                        .font(
                            .system(
                                size: 24,
                                weight: .bold
                            )
                        )
                        .padding(.horizontal)

                    VStack(
                        spacing: 12
                    ) {

                        if forecastEvents.isEmpty {

                            ContentUnavailableView(
                                "No Events",
                                systemImage: "calendar"
                            )

                        } else {

                            ForEach(
                                forecastEvents.prefix(6)
                            ) { forecast in

                                PlannerEventRow(
                                    event: forecast.event,
                                    occurrenceDate: forecast.occurrenceDate,
                                    projectedAvailable: projectedAvailable(
                                        for: forecast.event
                                    )
                                ) {

                                    selectedEvent = forecast.event
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
   
        .toolbar {

            ToolbarItem(
                placement: .topBarTrailing
            ) {

                Button {

                    showAddEvent = true

                } label: {

                    Image(
                        systemName: "plus"
                    )
                }
            }
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
}

}
