//
//  ContentView.swift
//  budgetTest
//

import SwiftUI
import LinkKit

struct ContentView: View {

    @EnvironmentObject var plaid: PlaidService
    @EnvironmentObject var navigation: AppNavigation

    init() {

        let appearance = UITabBarAppearance()

        appearance.configureWithTransparentBackground()

        appearance.backgroundEffect = UIBlurEffect(
            style: .systemUltraThinMaterial
        )

        appearance.backgroundColor =
            UIColor.white.withAlphaComponent(0.15)

        appearance.stackedLayoutAppearance.selected.iconColor =
            UIColor.systemBlue

        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor.systemBlue
        ]

        appearance.stackedLayoutAppearance.normal.iconColor =
            UIColor.systemGray

        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.systemGray
        ]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {

        TabView(
            selection: $navigation.selectedTab
        ) {

            DashboardView()
                .tabItem {
                    Label(
                        "Home",
                        systemImage: "house.fill"
                    )
                }
                .tag(0)

            LinkBankView()
                .tabItem {
                    Label(
                        "Accounts",
                        systemImage: "building.columns.fill"
                    )
                }
                .tag(1)

            SavingsGoalsView()
                .tabItem {
                    Label(
                        "Goals",
                        systemImage: "target"
                    )
                }
                .tag(2)

            PlannerView()
                .tabItem {
                    Label(
                        "Planner",
                        systemImage: "calendar"
                    )
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label(
                        "Profile",
                        systemImage: "person.crop.circle.fill"
                    )
                }
                .tag(4)
        }
        .tint(
            Color(
                red: 0.35,
                green: 0.70,
                blue: 1.0
            )
        )
    }
}

#Preview {

    ContentView()
        .environmentObject(PlaidService())
        .environmentObject(AppNavigation())
}
