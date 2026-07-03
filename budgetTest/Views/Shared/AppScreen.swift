import SwiftUI

struct AppScreen<Content: View>: View {

    enum BackgroundStyle {
        case softAurora
        case staticGradient
    }

    private let usesNavigationStack: Bool
    private let backgroundStyle: BackgroundStyle
    private let contentPadding: Edge.Set
    private let contentSpacing: CGFloat
    private let showsTopScrollFade: Bool
    private let content: Content

    init(
        usesNavigationStack: Bool = true,
        backgroundStyle: BackgroundStyle = .softAurora,
        contentPadding: Edge.Set = .all,
        contentSpacing: CGFloat = AppSpacing.screen,
        showsTopScrollFade: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.usesNavigationStack = usesNavigationStack
        self.backgroundStyle = backgroundStyle
        self.contentPadding = contentPadding
        self.contentSpacing = contentSpacing
        self.showsTopScrollFade = showsTopScrollFade
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
            background

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: contentSpacing
                ) {
                    content
                }
                .padding(contentPadding)
                .dismissKeyboardOnBackgroundTap()
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnBackgroundTap()
        }
        .optionalTopScrollFade(
            isEnabled: showsTopScrollFade
        )
    }

    @ViewBuilder
    private var background: some View {
        switch backgroundStyle {
        case .softAurora:
            AppBackgroundView()

        case .staticGradient:
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

    @ViewBuilder
    func optionalTopScrollFade(
        isEnabled: Bool,
        height: CGFloat = 96
    ) -> some View {
        if isEnabled {
            topScrollFade(height: height)
        } else {
            self
        }
    }
}
