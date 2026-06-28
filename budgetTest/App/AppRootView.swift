import SwiftUI

struct AppRootView: View {

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var plaid: PlaidService

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
        .onOpenURL { url in
            plaid.handleOAuthRedirect(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else {
                return
            }

            plaid.handleOAuthRedirect(url)
        }
        .onChange(of: auth.isSignedIn) { _, isSignedIn in
            Task { @MainActor in
                plaid.handleAuthenticationStateChanged(
                    isSignedIn: isSignedIn
                )
            }
        }
        .task {
            await plaid.handleAuthenticationStateChanged(
                isSignedIn: auth.isSignedIn
            )
        }
    }
}
