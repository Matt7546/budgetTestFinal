//
//  ContentView.swift
//  budgetTest
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {

    @EnvironmentObject var plaid: PlaidService
    @EnvironmentObject var navigation: AppNavigation
    @SwiftUI.Environment(\.modelContext)
    private var swiftDataContext

    init() {

        let appearance = UITabBarAppearance()

        appearance.configureWithTransparentBackground()

        appearance.backgroundEffect = UIBlurEffect(
            style: .systemUltraThinMaterial
        )

        appearance.backgroundColor =
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 0.76)
                    : UIColor.white.withAlphaComponent(0.18)
            }

        appearance.shadowColor =
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.45, green: 0.62, blue: 0.90, alpha: 0.18)
                    : UIColor.black.withAlphaComponent(0.08)
            }

        appearance.stackedLayoutAppearance.selected.iconColor =
            UIColor(AppColors.accent)

        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(AppColors.accent)
        ]

        appearance.stackedLayoutAppearance.normal.iconColor =
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.66, green: 0.72, blue: 0.84, alpha: 1)
                    : UIColor(red: 0.26, green: 0.31, blue: 0.40, alpha: 1)
            }

        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.66, green: 0.72, blue: 0.84, alpha: 1)
                    : UIColor(red: 0.26, green: 0.31, blue: 0.40, alpha: 1)
            }
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {

        ZStack {
            rootBackground

            TabView(
                selection: $navigation.selectedTab
            ) {

                DashboardView()
                    .tabItem {
                        Label(
                            "Dashboard",
                            systemImage: "house.fill"
                        )
                    }
                    .tag(0)

                SavingsGoalsView()
                    .tabItem {
                        Label(
                            "Savings",
                            systemImage: "target"
                        )
                    }
                    .tag(1)

                PlannerView()
                    .tabItem {
                        Label(
                            "Timeline",
                            systemImage: "calendar"
                        )
                    }
                    .tag(2)

                LinkBankView()
                    .tabItem {
                        Label(
                            "Accounts",
                            systemImage: "building.columns.fill"
                        )
                    }
                    .tag(3)

                SettingsView()
                    .tabItem {
                        Label(
                            "Settings",
                            systemImage: "gearshape.fill"
                        )
                    }
                    .tag(4)
            }
            .tint(
                AppColors.tabTint
            )
        }
        .onAppear {
            plaid.configurePersistence(
                modelContext: swiftDataContext
            )
        }
    }

    @ViewBuilder
    private var rootBackground: some View {
        if navigation.selectedTab == 0 {
            AnimatedBackgroundView()
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [
                    AppColors.screenGradientTop,
                    AppColors.screenGradientBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    ContentViewPreview()
}

private struct ContentViewPreview: View {

    @StateObject private var plaid = PlaidService()
    @StateObject private var navigation = AppNavigation()

    var body: some View {
        ContentView()
            .environmentObject(plaid)
            .environmentObject(
                SummaryViewModel(
                    accountsPublisher: plaid.$accounts.eraseToAnyPublisher(),
                    goalsPublisher: plaid.$savingsGoals.eraseToAnyPublisher(),
                    reservePublisher: plaid.$reserveBalance.eraseToAnyPublisher()
                )
            )
            .environmentObject(navigation)
            .modelContainer(
                for: [
                    PlannerEvent.self,
                    EventAllocation.self,
                    ExpenseOccurrenceStatus.self,
                    SavingsGoalRecord.self,
                    ReserveSettings.self
                ],
                inMemory: true
            )
    }
}
