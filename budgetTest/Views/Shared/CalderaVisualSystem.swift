import SwiftUI

enum CalderaVisualMood {
    case dashboard
    case savings
    case timeline
    case more
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let mood: CalderaVisualMood
    let isActive: Bool

    init(
        mood: CalderaVisualMood,
        isActive: Bool = true
    ) {
        self.mood = mood
        self.isActive = isActive
    }

    @State private var animate = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CalderaVisualStyle.background(mood, colorScheme)
                .ignoresSafeArea()

            switch mood {
            case .dashboard:
                dashboardBlobLayer

            case .savings:
                ambientLayer(
                    size: CGSize(width: 360, height: 320),
                    blur: 78,
                    opacity: colorScheme == .dark ? 0.42 : 0.34,
                    primaryOffset: CGSize(
                        width: animate ? 92 : 118,
                        height: animate ? 44 : 76
                    ),
                    secondaryColor: AppColors.accentSecondary,
                    secondaryOpacity: colorScheme == .dark ? 0.18 : 0.11,
                    secondarySize: 360,
                    secondaryBlur: 104,
                    secondaryOffset: CGSize(
                        width: animate ? -156 : -108,
                        height: animate ? 430 : 380
                    ),
                    duration: 16
                )

            case .timeline:
                ambientLayer(
                    size: CGSize(width: 390, height: 340),
                    blur: 82,
                    opacity: colorScheme == .dark ? 0.46 : 0.34,
                    primaryOffset: CGSize(
                        width: animate ? 116 : 78,
                        height: animate ? 36 : 84
                    ),
                    secondaryColor: AppColors.accent,
                    secondaryOpacity: colorScheme == .dark ? 0.18 : 0.10,
                    secondarySize: 420,
                    secondaryBlur: 118,
                    secondaryOffset: CGSize(
                        width: animate ? -150 : -98,
                        height: animate ? 430 : 365
                    ),
                    duration: 18
                )

            case .more:
                ambientLayer(
                    size: CGSize(width: 370, height: 330),
                    blur: 86,
                    opacity: colorScheme == .dark ? 0.42 : 0.30,
                    primaryOffset: CGSize(
                        width: animate ? 104 : 132,
                        height: animate ? 52 : 94
                    ),
                    secondaryColor: AppColors.protected,
                    secondaryOpacity: colorScheme == .dark ? 0.16 : 0.10,
                    secondarySize: 390,
                    secondaryBlur: 118,
                    secondaryOffset: CGSize(
                        width: animate ? -142 : -104,
                        height: animate ? 420 : 360
                    ),
                    duration: 17
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            updateAnimationState()
        }
        .onChange(of: isActive) { _, _ in
            updateAnimationState()
        }
        .onChange(of: scenePhase) { _, _ in
            updateAnimationState()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateAnimationState()
        }
    }

    private var shouldAnimate: Bool {
        isActive &&
        scenePhase == .active &&
        !reduceMotion
    }

    private var animationDuration: Double {
        switch mood {
        case .dashboard:
            return 8.5

        case .savings:
            return 16

        case .timeline:
            return 18

        case .more:
            return 17
        }
    }

    private func updateAnimationState() {
        if shouldAnimate {
            guard !animate else {
                return
            }

            withAnimation(
                .easeInOut(duration: animationDuration)
                    .repeatForever(autoreverses: true)
            ) {
                animate = true
            }
        } else {
            guard animate else {
                return
            }

            if reduceMotion || scenePhase != .active {
                var transaction = Transaction()
                transaction.animation = nil

                withTransaction(transaction) {
                    animate = false
                }
            } else {
                withAnimation(.easeOut(duration: 0.35)) {
                    animate = false
                }
            }
        }
    }

    private var dashboardBlobLayer: some View {
        ZStack(alignment: .topTrailing) {
            dashboardBlob
                .frame(width: 340, height: 360)
                .scaleEffect(1.0 + (animate ? 0.08 : -0.03))
                .rotationEffect(.degrees(animate ? 10 : -7))
                .blur(radius: 38)
                .opacity(colorScheme == .dark ? 0.98 : 0.94)
                .offset(
                    x: 112 + (animate ? 12 : -8),
                    y: 72 + (animate ? -10 : 8)
                )
                .blendMode(.normal)

            dashboardBlob
                .frame(width: 430, height: 380)
                .scaleEffect(1.02 + (animate ? -0.03 : 0.05))
                .rotationEffect(.degrees(animate ? -8 : 6))
                .blur(radius: 72)
                .opacity(colorScheme == .dark ? 0.28 : 0.18)
                .offset(
                    x: -48 + (animate ? -10 : 8),
                    y: 230 + (animate ? 8 : -8)
                )
                .blendMode(.normal)
        }
    }

    private var dashboardBlob: some View {
        ZStack {
            Ellipse()
                .fill(
                    AngularGradient(
                        colors: CalderaVisualStyle.ambientBlobColors(.dashboard, colorScheme),
                        center: .center,
                        angle: .degrees(animate ? 210 : 30)
                    )
                )
                .opacity(0.98)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: CalderaVisualStyle.dashboardMagentaOverlayColors(colorScheme),
                        center: .topTrailing,
                        startRadius: 18,
                        endRadius: 210
                    )
                )
                .scaleEffect(x: 1.12, y: 0.88)
                .offset(x: 24, y: -10)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: CalderaVisualStyle.dashboardCyanOverlayColors(colorScheme),
                        center: .bottomLeading,
                        startRadius: 22,
                        endRadius: 220
                    )
                )
                .offset(x: -42, y: 32)
        }
        .saturation(colorScheme == .dark ? 1.72 : 1.55)
        .contrast(colorScheme == .dark ? 1.24 : 1.18)
    }

    private func ambientLayer(
        size: CGSize,
        blur: CGFloat,
        opacity: Double,
        primaryOffset: CGSize,
        secondaryColor: Color,
        secondaryOpacity: Double,
        secondarySize: CGFloat,
        secondaryBlur: CGFloat,
        secondaryOffset: CGSize,
        duration: Double
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Ellipse()
                .fill(
                    AngularGradient(
                        colors: CalderaVisualStyle.ambientBlobColors(mood, colorScheme),
                        center: .center,
                        angle: .degrees(animate ? 190 : 25)
                    )
                )
                .frame(width: size.width, height: size.height)
                .blur(radius: blur)
                .opacity(opacity)
                .offset(primaryOffset)
                .scaleEffect(animate ? 1.08 : 0.98)

            Circle()
                .fill(secondaryColor.opacity(secondaryOpacity))
                .frame(width: secondarySize, height: secondarySize)
                .blur(radius: secondaryBlur)
                .offset(secondaryOffset)
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
        GeometryReader { geometry in
            let width = max(geometry.size.width * clampedProgress, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CalderaVisualStyle.progressTrack(colorScheme))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
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
                color: CalderaVisualStyle.cardShadow(colorScheme, lightOpacity: shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .shadow(
                color: colorScheme == .dark
                    ? darkGlowColor.opacity(0.08)
                    : Color.clear,
                radius: colorScheme == .dark ? 24 : 0,
                x: 0,
                y: colorScheme == .dark ? 9 : 0
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
            : Color.white.opacity(lightOpacity)
    }

    static func cardStroke(
        _ colorScheme: ColorScheme,
        lightOpacity: Double
    ) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.17)
            : Color.white.opacity(lightOpacity)
    }

    static func cardShadow(
        _ colorScheme: ColorScheme,
        lightOpacity: Double
    ) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.31)
            : Color.black.opacity(lightOpacity)
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
                    Color(red: 0.05, green: 0.22, blue: 0.78),
                    Color(red: 0.00, green: 0.82, blue: 1.00),
                    Color(red: 0.26, green: 0.12, blue: 0.92),
                    Color(red: 0.72, green: 0.18, blue: 0.96),
                    Color(red: 0.05, green: 0.22, blue: 0.78)
                ]
            }

            return [
                Color(red: 0.16, green: 0.54, blue: 1.00),
                Color(red: 0.00, green: 0.78, blue: 1.00),
                Color(red: 0.44, green: 0.28, blue: 1.00),
                Color(red: 0.86, green: 0.30, blue: 0.90),
                Color(red: 0.16, green: 0.54, blue: 1.00)
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
