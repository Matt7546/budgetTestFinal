import SwiftUI

struct AppScreen<Content: View>: View {

    enum BackgroundStyle {
        case softAurora
        case page(CalderaVisualMood)
        case staticGradient
        case editorModal(CalderaEditorMood)
    }

    private let usesNavigationStack: Bool
    private let backgroundStyle: BackgroundStyle
    private let contentPadding: Edge.Set
    private let contentSpacing: CGFloat
    private let content: Content

    init(
        usesNavigationStack: Bool = true,
        backgroundStyle: BackgroundStyle = .softAurora,
        contentPadding: Edge.Set = .all,
        contentSpacing: CGFloat = AppSpacing.screen,
        @ViewBuilder content: () -> Content
    ) {
        self.usesNavigationStack = usesNavigationStack
        self.backgroundStyle = backgroundStyle
        self.contentPadding = contentPadding
        self.contentSpacing = contentSpacing
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
    }

    @ViewBuilder
    private var background: some View {
        switch backgroundStyle {
        case .softAurora:
            AppBackgroundView()

        case .page(let mood):
            CalderaPageBackground(mood: mood)

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
