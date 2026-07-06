import SwiftUI

struct AppScreen<Content: View>: View {

    enum BackgroundStyle {
        case softAurora
        case staticGradient
        case editorModal(CalderaEditorMood)
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
            .calderaTransparentNavigationSurface()
        } else {
            screenContent
                .calderaTransparentNavigationSurface()
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
            .scrollContentBackground(.hidden)
            .dismissKeyboardOnBackgroundTap()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

        case .editorModal(let mood):
            CalderaModalBackground(mood: mood)
        }
    }
}

extension View {

    func calderaTransparentNavigationSurface() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
    }
}

private struct TopScrollFade: View {

    let height: CGFloat

    var body: some View {
        Color.clear
        .frame(height: height)
        .frame(
            maxHeight: .infinity,
            alignment: .top
        )
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
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
