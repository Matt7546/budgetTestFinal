import SwiftUI

struct DashboardView: View {

    @EnvironmentObject var plaid: PlaidService
@EnvironmentObject var summary: SummaryViewModel
@EnvironmentObject var navigation: AppNavigation

@State private var showAccounts = true
@State private var showGoals = true
    @State private var showNetWorthSnapshot = false
    @State private var showAvailableSnapshot = false

private var greeting: String {

    let hour = Calendar.current.component(
        .hour,
        from: Date()
    )

    switch hour {

    case 5..<12:
        return "Good Morning"

    case 12..<17:
        return "Good Afternoon"

    default:
        return "Good Evening"
    }
}

var body: some View {

    ZStack {

        AnimatedBackgroundView()

        ScrollView {

            VStack(alignment: .leading, spacing: 24) {

                HStack(alignment: .top) {

                    VStack(alignment: .leading, spacing: 6) {

                        Text(greeting)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Matthew")
                            .font(
                                .system(
                                    size: 38,
                                    weight: .bold
                                )
                            )
                            .foregroundColor(
                                Color(
                                    red: 0.10,
                                    green: 0.14,
                                    blue: 0.22
                                )
                            )

                        Text(
                            Date.now.formatted(
                                .dateTime
                                    .weekday(.wide)
                                    .month()
                                    .day()
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    ZStack {

                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 60, height: 60)

                        Circle()
                            .stroke(
                                Color.white.opacity(0.8),
                                lineWidth: 1
                            )
                            .frame(width: 60, height: 60)

                        Text("MT")
                            .font(.headline.bold())
                            .foregroundColor(
                                Color(
                                    red: 0.10,
                                    green: 0.14,
                                    blue: 0.22
                                )
                            )
                    }
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.25),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                Button {
                    showNetWorthSnapshot = true
                } label: {
                    summaryCard
                }
                .buttonStyle(.plain)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 12
                ) {

                    Button {

                        navigation.selectedTab = 1
                        navigation.expandChecking = true
                        navigation.expandSavings = true

                    } label: {

                        MetricCard(
                            title: "Cash",
                            value: summary.totalCash
                        )
                    }
                    .buttonStyle(.plain)

                    Button {

                        navigation.selectedTab = 1
                        navigation.expandCredit = true
                        navigation.expandLoans = true

                    } label: {

                        MetricCard(
                            title: "Debt",
                            value: summary.totalDebt
                        )
                    }
                    .buttonStyle(.plain)

                    Button {

                        navigation.selectedTab = 2

                    } label: {

                        MetricCard(
                            title: "Goals",
                            value: summary.totalGoalAllocated
                        )
                    }
                    .buttonStyle(.plain)

                    Button {

                        showAvailableSnapshot = true

                    } label: {

                        MetricCard(
                            title: "Available",
                            value: summary.totalAvailable
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                SectionHeader(
                    title: "Accounts",
                    isExpanded: $showAccounts
                )

                if showAccounts {

                    VStack(spacing: 12) {

                        ForEach(plaid.accounts) { acct in
                            WalletAccountCard(account: acct)
                        }
                    }
                    .transition(
                        .opacity.combined(
                            with: .slide
                        )
                    )
                }

                if !plaid.savingsGoals.isEmpty {

                    SectionHeader(
                        title: "Goals Overview",
                        isExpanded: $showGoals
                    )

                    if showGoals {

                        VStack(spacing: 12) {

                            ForEach(plaid.savingsGoals) { goal in
                                GoalPreviewCard(goal: goal)
                            }
                        }
                        .transition(
                            .opacity.combined(
                                with: .slide
                            )
                        )
                    }
                }
            }
            .padding()
        }
    }
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showNetWorthSnapshot) {
        NetWorthSnapshotView()
            .environmentObject(plaid)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showAvailableSnapshot) {
        FinancialSnapshotView()
            .environmentObject(plaid)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}

private var summaryCard: some View {

    let netWorth = summary.totalNetWorth

    return VStack(
        alignment: .leading,
        spacing: 18
    ) {

        Text("Net Worth")
            .font(.subheadline)
            .foregroundColor(
                Color(
                    red: 0.45,
                    green: 0.50,
                    blue: 0.60
                )
            )

        Text(
            netWorth,
            format: .currency(code: "USD")
        
        )
        .font(
            .system(
                size: 48,
                weight: .bold
            )
        )
        .foregroundColor(
            Color(
                red: 0.10,
                green: 0.14,
                blue: 0.22
            )
        )

        HStack {

            Label(
                "Available",
                systemImage: "arrow.up.right"
            )
            .foregroundColor(
                Color(
                    red: 0.20,
                    green: 0.75,
                    blue: 0.45
                )
            )

            Spacer()

            Text("Tap for Details")
                .foregroundColor(
                    Color(
                        red: 0.45,
                        green: 0.50,
                        blue: 0.60
                    )
                )
        }
    }
    .padding(28)
    .frame(
        maxWidth: .infinity,
        alignment: .leading
    )
    .background(
        RoundedRectangle(
            cornerRadius: 30
        )
        .fill(.ultraThinMaterial)
    )
    .overlay(
        RoundedRectangle(
            cornerRadius: 30
        )
        .fill(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.20),
                    Color.cyan.opacity(0.08),
                    Color.green.opacity(0.05),
                    Color.blue.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    )
    .overlay(
        RoundedRectangle(
            cornerRadius: 30
        )
        .stroke(
            Color.white.opacity(0.85),
            lineWidth: 1
        )
    )
    .shadow(
        color: .black.opacity(0.05),
        radius: 30,
        y: 15
    )
}


}
