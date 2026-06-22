import SwiftUI

struct AppRootView: View {

    @AppStorage("hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    @AppStorage("appearanceMode")
    private var appearanceMode = AppearanceMode.system.rawValue

    private var selectedAppearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .animation(
            .easeInOut(duration: 0.25),
            value: hasCompletedOnboarding
        )
        .preferredColorScheme(
            selectedAppearance.colorScheme
        )
    }
}
