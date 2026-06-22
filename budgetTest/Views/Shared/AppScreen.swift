import SwiftUI

struct AppScreen<Content: View>: View {

    private let usesNavigationStack: Bool
    private let contentPadding: Edge.Set
    private let contentSpacing: CGFloat
    private let content: Content

    init(
        usesNavigationStack: Bool = true,
        contentPadding: Edge.Set = .all,
        contentSpacing: CGFloat = AppSpacing.screen,
        @ViewBuilder content: () -> Content
    ) {
        self.usesNavigationStack = usesNavigationStack
        self.contentPadding = contentPadding
        self.contentSpacing = contentSpacing
        self.content = content()
    }

    var body: some View {
        if usesNavigationStack {
            NavigationStack {
                screenContent
            }
        } else {
            screenContent
        }
    }

    private var screenContent: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppColors.screenGradientTop,
                    AppColors.screenGradientBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: contentSpacing
                ) {
                    content
                }
                .padding(contentPadding)
            }
        }
        .topScrollFade()
    }
}

private struct TopScrollFade: View {

    let height: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(fadeMask)

            LinearGradient(
                colors: [
                    AppColors.screenGradientTop.opacity(0.92),
                    AppColors.screenGradientTop.opacity(0.52),
                    AppColors.screenGradientTop.opacity(0.16),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: height)
        .frame(
            maxHeight: .infinity,
            alignment: .top
        )
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    private var fadeMask: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.95),
                Color.black.opacity(0.65),
                Color.black.opacity(0.18),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct TopScrollFadeModifier: ViewModifier {

    let height: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            alignment: .top
        ) {
            TopScrollFade(height: height)
        }
    }
}

extension View {

    func topScrollFade(
        height: CGFloat = 96
    ) -> some View {
        modifier(
            TopScrollFadeModifier(
                height: height
            )
        )
    }
}
