import SwiftUI

struct SplashRootView<Content: View>: View {

    @State private var showsSplash = true

    private let content: Content

    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content

            if showsSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(
                nanoseconds: 2_500_000_000
            )

            withAnimation(
                .easeInOut(duration: 0.42)
            ) {
                showsSplash = false
            }
        }
    }
}

