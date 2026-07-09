import SwiftUI

enum CalderaVisualMood {
    case dashboard
    case savings
    case timeline
    case more
}

enum CalderaEditorMood {
    case general
    case savingsGoal
    case upcomingExpense
    case debtPayoff
}

enum CalderaFinanceSemanticRole {
    case safeToSpend
    case reserve
    case savingsGoal
    case upcomingExpense
    case debtPayoff
    case bankAccount
    case covered
    case needsMoney
    case shortfall
    case income
}

struct CalderaCategoryStyle {

    let role: CalderaFinanceSemanticRole
    let icon: String
    let primary: Color
    let gradient: [Color]

    static func style(
        for role: CalderaFinanceSemanticRole
    ) -> CalderaCategoryStyle {
        switch role {
        case .safeToSpend:
            return CalderaCategoryStyle(
                role: role,
                icon: "wallet.pass.fill",
                primary: Color(red: 0.24, green: 0.42, blue: 1.00),
                gradient: [
                    Color(red: 0.24, green: 0.42, blue: 1.00),
                    Color(red: 0.50, green: 0.24, blue: 1.00),
                    Color(red: 0.10, green: 0.78, blue: 1.00)
                ]
            )

        case .reserve:
            return CalderaCategoryStyle(
                role: role,
                icon: "lock.shield.fill",
                primary: Color(red: 0.36, green: 0.25, blue: 0.98),
                gradient: [
                    Color(red: 0.28, green: 0.24, blue: 0.92),
                    Color(red: 0.54, green: 0.30, blue: 1.00),
                    Color(red: 0.16, green: 0.56, blue: 1.00)
                ]
            )

        case .savingsGoal:
            return CalderaCategoryStyle(
                role: role,
                icon: "target",
                primary: Color(red: 0.72, green: 0.22, blue: 0.95),
                gradient: [
                    Color(red: 0.50, green: 0.22, blue: 1.00),
                    Color(red: 0.95, green: 0.20, blue: 0.78),
                    Color(red: 0.88, green: 0.36, blue: 1.00)
                ]
            )

        case .upcomingExpense:
            return CalderaCategoryStyle(
                role: role,
                icon: "calendar.badge.clock",
                primary: Color(red: 0.95, green: 0.45, blue: 0.10),
                gradient: [
                    Color(red: 1.00, green: 0.62, blue: 0.18),
                    Color(red: 0.98, green: 0.38, blue: 0.22),
                    Color(red: 0.92, green: 0.28, blue: 0.44)
                ]
            )

        case .debtPayoff:
            return CalderaCategoryStyle(
                role: role,
                icon: "creditcard.fill",
                primary: Color(red: 0.95, green: 0.24, blue: 0.30),
                gradient: [
                    Color(red: 1.00, green: 0.32, blue: 0.34),
                    Color(red: 0.98, green: 0.42, blue: 0.26),
                    Color(red: 0.84, green: 0.16, blue: 0.42)
                ]
            )

        case .bankAccount:
            return CalderaCategoryStyle(
                role: role,
                icon: "building.columns.fill",
                primary: Color(red: 0.08, green: 0.58, blue: 0.96),
                gradient: [
                    Color(red: 0.00, green: 0.72, blue: 1.00),
                    Color(red: 0.12, green: 0.48, blue: 1.00),
                    Color(red: 0.16, green: 0.88, blue: 0.94)
                ]
            )

        case .covered:
            return CalderaCategoryStyle(
                role: role,
                icon: "checkmark.circle.fill",
                primary: AppColors.spendable,
                gradient: [
                    AppColors.spendable,
                    Color(red: 0.20, green: 0.86, blue: 0.62)
                ]
            )

        case .needsMoney:
            return CalderaCategoryStyle(
                role: role,
                icon: "exclamationmark.triangle.fill",
                primary: AppColors.warning,
                gradient: [
                    AppColors.warning,
                    Color(red: 1.00, green: 0.64, blue: 0.18)
                ]
            )

        case .shortfall:
            return CalderaCategoryStyle(
                role: role,
                icon: "exclamationmark.octagon.fill",
                primary: AppColors.negative,
                gradient: [
                    AppColors.negative,
                    Color(red: 1.00, green: 0.30, blue: 0.46),
                    Color(red: 0.88, green: 0.16, blue: 0.36)
                ]
            )

        case .income:
            return CalderaCategoryStyle(
                role: role,
                icon: "arrow.down.circle.fill",
                primary: AppColors.spendable,
                gradient: [
                    AppColors.spendable,
                    AppColors.accentSecondary
                ]
            )
        }
    }
}

struct CalderaPageBackground: View {

    @Environment(\.colorScheme) private var colorScheme

    let mood: CalderaVisualMood

    init(
        mood: CalderaVisualMood,
        isActive: Bool = true
    ) {
        self.mood = mood
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: baseGradientColors,
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    primaryAccent.opacity(colorScheme == .dark ? 0.30 : 0.27),
                    secondaryAccent.opacity(colorScheme == .dark ? 0.19 : 0.17),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 560
            )

            RadialGradient(
                colors: [
                    secondaryAccent.opacity(colorScheme == .dark ? 0.17 : 0.13),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 24,
                endRadius: 640
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var baseGradientColors: [Color] {
        let base = CalderaVisualStyle.background(mood, colorScheme)

        if colorScheme == .dark {
            return [
                base,
                primaryAccent.opacity(0.14),
                base,
                Color(red: 0.012, green: 0.018, blue: 0.045)
            ]
        }

        return [
            base,
            primaryAccent.opacity(0.15),
            secondaryAccent.opacity(0.10),
            base
        ]
    }

    private var primaryAccent: Color {
        switch mood {
        case .dashboard:
            return Color(red: 0.00, green: 0.72, blue: 1.00)

        case .savings:
            return Color(red: 0.58, green: 0.34, blue: 1.00)

        case .timeline:
            return Color(red: 1.00, green: 0.56, blue: 0.22)

        case .more:
            return Color(red: 0.38, green: 0.52, blue: 1.00)
        }
    }

    private var secondaryAccent: Color {
        switch mood {
        case .dashboard:
            return Color(red: 0.90, green: 0.20, blue: 0.96)

        case .savings:
            return Color(red: 0.92, green: 0.26, blue: 0.82)

        case .timeline:
            return Color(red: 0.86, green: 0.26, blue: 0.44)

        case .more:
            return Color(red: 0.56, green: 0.46, blue: 0.88)
        }
    }
}

struct CalderaModalBackground: View {

    @Environment(\.colorScheme) private var colorScheme

    let mood: CalderaEditorMood

    init(
        mood: CalderaEditorMood = .general
    ) {
        self.mood = mood
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: baseColors,
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    primaryColor.opacity(colorScheme == .dark ? 0.18 : 0.14),
                    secondaryColor.opacity(colorScheme == .dark ? 0.10 : 0.08),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    secondaryColor.opacity(colorScheme == .dark ? 0.09 : 0.065),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 24,
                endRadius: 600
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var baseColors: [Color] {
        let base = CalderaVisualStyle.background(.more, colorScheme)

        if colorScheme == .dark {
            return [
                base,
                primaryColor.opacity(0.14),
                base
            ]
        }

        return [
            base,
            primaryColor.opacity(0.09),
            base
        ]
    }

    private var primaryColor: Color {
        switch mood {
        case .general:
            return Color(red: 0.34, green: 0.48, blue: 1.00)

        case .savingsGoal:
            return Color(red: 0.52, green: 0.28, blue: 1.00)

        case .upcomingExpense:
            return Color(red: 1.00, green: 0.55, blue: 0.24)

        case .debtPayoff:
            return Color(red: 0.92, green: 0.30, blue: 0.44)
        }
    }

    private var secondaryColor: Color {
        switch mood {
        case .general:
            return Color(red: 0.58, green: 0.34, blue: 0.96)

        case .savingsGoal:
            return Color(red: 0.92, green: 0.30, blue: 0.82)

        case .upcomingExpense:
            return Color(red: 0.94, green: 0.30, blue: 0.46)

        case .debtPayoff:
            return Color(red: 0.72, green: 0.28, blue: 0.88)
        }
    }
}

enum CalderaPageChrome {
    static let horizontalPadding: CGFloat = AppSpacing.regular
    static let topContentPadding: CGFloat = AppSpacing.regular
    static let topFadeHeight: CGFloat = 116
    static let titleSize: CGFloat = 38
}

struct CalderaPageHeader: View {

    @Environment(\.colorScheme) private var colorScheme

    let eyebrow: String
    let title: String
    let subtitle: String?
    private let titleAccessory: AnyView
    private let trailing: AnyView

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.titleAccessory = AnyView(EmptyView())
        self.trailing = AnyView(EmptyView())
    }

    init<TitleAccessory: View>(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder titleAccessory: () -> TitleAccessory
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.titleAccessory = AnyView(titleAccessory())
        self.trailing = AnyView(EmptyView())
    }

    init<Trailing: View>(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.titleAccessory = AnyView(EmptyView())
        self.trailing = AnyView(trailing())
    }

    init<TitleAccessory: View, Trailing: View>(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder titleAccessory: () -> TitleAccessory,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.titleAccessory = AnyView(titleAccessory())
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(eyebrow)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

                HStack(alignment: .center, spacing: AppSpacing.xxSmall) {
                    Text(title)
                        .font(
                            .system(
                                size: CalderaPageChrome.titleSize,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    titleAccessory
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, AppSpacing.xxSmall)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .accessibilityElement(children: .contain)
    }
}

struct CalderaTopScrollFade: View {

    @Environment(\.colorScheme) private var colorScheme

    let mood: CalderaVisualMood
    let height: CGFloat

    init(
        mood: CalderaVisualMood,
        height: CGFloat = CalderaPageChrome.topFadeHeight
    ) {
        self.mood = mood
        self.height = height
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    CalderaVisualStyle.background(mood, colorScheme).opacity(0.96),
                    CalderaVisualStyle.background(mood, colorScheme).opacity(colorScheme == .dark ? 0.72 : 0.64),
                    CalderaVisualStyle.background(mood, colorScheme).opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .mask(
            LinearGradient(
                colors: [
                    Color.black,
                    Color.black.opacity(0.82),
                    Color.black.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

extension View {

    func calderaTopScrollFade(
        mood: CalderaVisualMood,
        height: CGFloat = CalderaPageChrome.topFadeHeight
    ) -> some View {
        overlay(alignment: .top) {
            CalderaTopScrollFade(
                mood: mood,
                height: height
            )
        }
    }
}

struct CalderaGradientIcon: View {

    let systemImage: String
    let colors: [Color]
    let size: CGFloat
    let iconSize: CGFloat

    init(
        systemImage: String,
        colors: [Color],
        size: CGFloat,
        iconSize: CGFloat
    ) {
        self.systemImage = systemImage
        self.colors = colors
        self.size = size
        self.iconSize = iconSize
    }

    init(
        style: CalderaCategoryStyle,
        size: CGFloat,
        iconSize: CGFloat
    ) {
        self.systemImage = style.icon
        self.colors = style.gradient
        self.size = size
        self.iconSize = iconSize
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .shadow(
                color: (colors.first ?? AppColors.accent).opacity(0.18),
                radius: 10,
                y: 5
            )
    }
}

struct CalderaProgressBar: View {

    @Environment(\.colorScheme) private var colorScheme

    let progress: Double
    let colors: [Color]

    private var clampedProgress: Double {
        guard progress.isFinite else {
            return 0
        }

        return min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(
                proxy.size.width.isFinite ? proxy.size.width : 0,
                0
            )
            let availableHeight = max(
                proxy.size.height.isFinite ? proxy.size.height : 0,
                0
            )
            let fillWidth = clampedProgress <= 0
                ? 0
                : min(
                    availableWidth,
                    max(
                        availableHeight,
                        availableWidth * clampedProgress
                    )
                )

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CalderaVisualStyle.progressTrack(colorScheme))

                if fillWidth > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: colors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(height: 8)
    }
}

struct CalderaGlassCardStyle: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let fillOpacity: Double
    let strokeOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let darkGlowColor: Color

    func body(content: Content) -> some View {
        let effectiveShadowOpacity = AppPerformanceSettings.disablesGlassCardShadows
            ? 0
            : shadowOpacity
        let darkGlowOpacity = colorScheme == .dark &&
            !AppPerformanceSettings.disablesDarkGlassGlow
            ? min(max(effectiveShadowOpacity * 1.75, 0), 0.08)
            : 0
        let darkGlowRadius: CGFloat = darkGlowOpacity > 0 ? 24 : 0
        let darkGlowY: CGFloat = darkGlowOpacity > 0 ? 9 : 0

        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(CalderaVisualStyle.cardFill(colorScheme, lightOpacity: fillOpacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: CalderaVisualStyle.cardHighlightColors(colorScheme),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        CalderaVisualStyle.cardStroke(colorScheme, lightOpacity: strokeOpacity),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: CalderaVisualStyle.cardShadow(colorScheme, lightOpacity: effectiveShadowOpacity),
                radius: AppPerformanceSettings.disablesGlassCardShadows ? 0 : shadowRadius,
                x: 0,
                y: AppPerformanceSettings.disablesGlassCardShadows ? 0 : shadowY
            )
            .shadow(
                color: darkGlowColor.opacity(darkGlowOpacity),
                radius: darkGlowRadius,
                x: 0,
                y: darkGlowY
            )
    }
}

extension View {

    func calderaGlassCard(
        cornerRadius: CGFloat,
        fillOpacity: Double = 0.88,
        strokeOpacity: Double = 0.74,
        shadowOpacity: Double = 0.04,
        shadowRadius: CGFloat = 18,
        shadowY: CGFloat = 8,
        darkGlowColor: Color = AppColors.accent
    ) -> some View {
        modifier(
            CalderaGlassCardStyle(
                cornerRadius: cornerRadius,
                fillOpacity: fillOpacity,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY,
                darkGlowColor: darkGlowColor
            )
        )
    }
}

enum CalderaVisualStyle {

    static let dashboardProgressGradient: [Color] = [
        Color(red: 0.52, green: 0.29, blue: 1.0),
        Color(red: 0.96, green: 0.31, blue: 0.70),
        Color(red: 0.22, green: 0.58, blue: 1.0)
    ]

    static let protectedGradient: [Color] = [
        Color(red: 0.34, green: 0.22, blue: 1.0),
        Color(red: 0.00, green: 0.76, blue: 1.0)
    ]

    static let safeGradient: [Color] = [
        Color(red: 0.17, green: 0.58, blue: 1.0),
        Color(red: 0.00, green: 0.82, blue: 1.0)
    ]

    static let expenseGradient: [Color] = [
        Color(red: 1.0, green: 0.54, blue: 0.20),
        Color(red: 0.95, green: 0.30, blue: 0.44)
    ]

    static func iconGradient(
        for color: Color
    ) -> [Color] {
        [
            color,
            AppColors.accentSecondary,
            AppColors.accent
        ]
    }

    static func background(
        _ mood: CalderaVisualMood,
        _ colorScheme: ColorScheme
    ) -> Color {
        switch mood {
        case .dashboard:
            return colorScheme == .dark
                ? Color(red: 0.025, green: 0.033, blue: 0.070)
                : Color(red: 0.965, green: 0.972, blue: 0.992)

        case .savings:
            return colorScheme == .dark
                ? Color(red: 0.018, green: 0.030, blue: 0.070)
                : Color(red: 0.965, green: 0.982, blue: 1.000)

        case .timeline:
            return colorScheme == .dark
                ? Color(red: 0.018, green: 0.028, blue: 0.070)
                : Color(red: 0.965, green: 0.978, blue: 1.000)

        case .more:
            return colorScheme == .dark
                ? Color(red: 0.020, green: 0.026, blue: 0.064)
                : Color(red: 0.970, green: 0.976, blue: 0.994)
        }
    }

    static func primaryText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.94, green: 0.96, blue: 1.00)
            : Color(red: 0.08, green: 0.11, blue: 0.20)
    }

    static func secondaryText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.68, green: 0.73, blue: 0.84)
            : Color(red: 0.47, green: 0.51, blue: 0.64)
    }

    static func tertiaryText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.76, green: 0.80, blue: 0.90)
            : Color(red: 0.42, green: 0.46, blue: 0.58)
    }

    static func cardFill(
        _ colorScheme: ColorScheme,
        lightOpacity: Double
    ) -> Color {
        colorScheme == .dark
            ? Color(red: 0.070, green: 0.086, blue: 0.145).opacity(0.76)
            : Color.white.opacity(min(lightOpacity + 0.035, 0.97))
    }

    static func cardStroke(
        _ colorScheme: ColorScheme,
        lightOpacity: Double
    ) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.17)
            : Color(red: 0.62, green: 0.68, blue: 0.84)
                .opacity(min(max(lightOpacity * 0.26, 0.12), 0.22))
    }

    static func cardShadow(
        _ colorScheme: ColorScheme,
        lightOpacity: Double
    ) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.31)
            : Color(red: 0.14, green: 0.20, blue: 0.38)
                .opacity(min(max(lightOpacity * 1.25, 0.018), 0.065))
    }

    static func cardHighlightColors(
        _ colorScheme: ColorScheme
    ) -> [Color] {
        colorScheme == .dark
            ? [
                Color.white.opacity(0.11),
                Color.white.opacity(0.03)
            ]
            : [
                Color.white.opacity(0.35),
                Color.white.opacity(0.10)
            ]
    }

    static func progressTrack(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color(red: 0.88, green: 0.91, blue: 0.96)
    }

    static func ambientBlobColors(
        _ mood: CalderaVisualMood,
        _ colorScheme: ColorScheme
    ) -> [Color] {
        switch mood {
        case .dashboard:
            if colorScheme == .dark {
                return [
                    Color(red: 0.19, green: 0.02, blue: 0.50),
                    Color(red: 0.78, green: 0.04, blue: 0.88),
                    Color(red: 0.48, green: 0.10, blue: 1.00),
                    Color(red: 0.06, green: 0.24, blue: 1.00),
                    Color(red: 0.00, green: 0.82, blue: 1.00),
                    Color(red: 0.62, green: 0.07, blue: 0.98),
                    Color(red: 0.19, green: 0.02, blue: 0.50)
                ]
            }

            return [
                Color(red: 0.34, green: 0.04, blue: 0.82),
                Color(red: 0.95, green: 0.08, blue: 0.72),
                Color(red: 0.48, green: 0.12, blue: 1.00),
                Color(red: 0.08, green: 0.30, blue: 1.00),
                Color(red: 0.00, green: 0.76, blue: 1.00),
                Color(red: 0.50, green: 0.08, blue: 0.94),
                Color(red: 0.34, green: 0.04, blue: 0.82)
            ]

        case .savings:
            if colorScheme == .dark {
                return [
                    Color(red: 0.08, green: 0.18, blue: 0.72),
                    Color(red: 0.24, green: 0.10, blue: 0.84),
                    Color(red: 0.00, green: 0.76, blue: 1.00),
                    Color(red: 0.64, green: 0.18, blue: 0.96),
                    Color(red: 0.08, green: 0.18, blue: 0.72)
                ]
            }

            return [
                Color(red: 0.20, green: 0.56, blue: 1.00),
                Color(red: 0.48, green: 0.24, blue: 1.00),
                Color(red: 0.00, green: 0.80, blue: 1.00),
                Color(red: 0.86, green: 0.32, blue: 0.92),
                Color(red: 0.20, green: 0.56, blue: 1.00)
            ]

        case .timeline:
            if colorScheme == .dark {
                return [
                    Color(red: 0.62, green: 0.20, blue: 0.16),
                    Color(red: 0.98, green: 0.46, blue: 0.18),
                    Color(red: 0.78, green: 0.16, blue: 0.40),
                    Color(red: 0.48, green: 0.18, blue: 0.96),
                    Color(red: 0.62, green: 0.20, blue: 0.16)
                ]
            }

            return [
                Color(red: 1.00, green: 0.56, blue: 0.20),
                Color(red: 0.96, green: 0.32, blue: 0.28),
                Color(red: 0.88, green: 0.26, blue: 0.62),
                Color(red: 0.52, green: 0.28, blue: 1.00),
                Color(red: 1.00, green: 0.56, blue: 0.20)
            ]

        case .more:
            if colorScheme == .dark {
                return [
                    Color(red: 0.12, green: 0.10, blue: 0.58),
                    Color(red: 0.48, green: 0.14, blue: 0.92),
                    Color(red: 0.00, green: 0.70, blue: 1.00),
                    Color(red: 0.74, green: 0.20, blue: 0.92),
                    Color(red: 0.12, green: 0.10, blue: 0.58)
                ]
            }

            return [
                Color(red: 0.34, green: 0.42, blue: 1.00),
                Color(red: 0.56, green: 0.28, blue: 1.00),
                Color(red: 0.00, green: 0.76, blue: 1.00),
                Color(red: 0.90, green: 0.34, blue: 0.90),
                Color(red: 0.34, green: 0.42, blue: 1.00)
            ]
        }
    }

    static func dashboardMagentaOverlayColors(_ colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 1.00, green: 0.08, blue: 0.82).opacity(0.72),
                Color(red: 0.48, green: 0.08, blue: 1.00).opacity(0.46),
                Color.clear
            ]
        }

        return [
            Color(red: 0.98, green: 0.08, blue: 0.72).opacity(0.62),
            Color(red: 0.46, green: 0.10, blue: 1.00).opacity(0.35),
            Color.clear
        ]
    }

    static func dashboardCyanOverlayColors(_ colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.00, green: 0.90, blue: 1.00).opacity(0.56),
                Color(red: 0.08, green: 0.26, blue: 1.00).opacity(0.42),
                Color.clear
            ]
        }

        return [
            Color(red: 0.00, green: 0.82, blue: 1.00).opacity(0.46),
            Color(red: 0.08, green: 0.24, blue: 1.00).opacity(0.30),
            Color.clear
        ]
    }
}
