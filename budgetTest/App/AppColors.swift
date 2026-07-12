import SwiftUI
import UIKit

enum AppColors {

    private static func adaptive(
        light: UIColor,
        dark: UIColor
    ) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? dark
                    : light
            }
        )
    }

    static let card =
        adaptive(
            light: UIColor(red: 0.10, green: 0.11, blue: 0.18, alpha: 1),
            dark: UIColor(red: 0.06, green: 0.08, blue: 0.16, alpha: 1)
        )

    static let textPrimary =
        adaptive(
            light: UIColor(red: 0.10, green: 0.14, blue: 0.22, alpha: 1),
            dark: UIColor(red: 0.96, green: 0.98, blue: 1.00, alpha: 1)
        )

    static let textSecondary =
        adaptive(
            light: UIColor(red: 0.45, green: 0.50, blue: 0.60, alpha: 1),
            dark: UIColor(red: 0.63, green: 0.70, blue: 0.82, alpha: 1)
        )

    static let screenGradientTop =
        adaptive(
            light: UIColor(red: 0.96, green: 0.97, blue: 1.00, alpha: 1),
            dark: UIColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1)
        )

    static let screenGradientBottom =
        adaptive(
            light: UIColor(red: 0.92, green: 0.95, blue: 0.99, alpha: 1),
            dark: UIColor(red: 0.06, green: 0.10, blue: 0.21, alpha: 1)
        )

    static let ink =
        textPrimary

    static let mutedInk =
        textSecondary

    static let accent =
        adaptive(
            light: UIColor.systemBlue,
            dark: UIColor(red: 0.30, green: 0.72, blue: 1.00, alpha: 1)
        )

    static let accentSecondary =
        adaptive(
            light: UIColor.systemCyan,
            dark: UIColor(red: 0.32, green: 0.93, blue: 1.00, alpha: 1)
        )

    static let positive =
        adaptive(
            light: UIColor.systemGreen,
            dark: UIColor(red: 0.25, green: 0.95, blue: 0.55, alpha: 1)
        )

    static let negative =
        adaptive(
            light: UIColor.systemRed,
            dark: UIColor(red: 1.00, green: 0.38, blue: 0.44, alpha: 1)
        )

    static let warning =
        adaptive(
            light: UIColor.systemOrange,
            dark: UIColor(red: 1.00, green: 0.65, blue: 0.24, alpha: 1)
        )

    static let savings =
        adaptive(
            light: UIColor.systemPurple,
            dark: UIColor(red: 0.78, green: 0.48, blue: 1.00, alpha: 1)
        )

    static let cash = positive

    static let liability = negative

    static let protected = savings

    static let spendable = cash

    static let obligation = liability

    static let primaryText = ink

    static let secondaryText = mutedInk

    static let glassStroke =
        adaptive(
            light: UIColor.white.withAlphaComponent(0.85),
            dark: UIColor(red: 0.65, green: 0.82, blue: 1.00, alpha: 0.34)
        )

    static let glassOverlayWhite =
        adaptive(
            light: UIColor.white.withAlphaComponent(0.20),
            dark: UIColor(red: 0.18, green: 0.28, blue: 0.48, alpha: 0.22)
        )

    static let glassOverlayCyan =
        adaptive(
            light: UIColor.cyan.withAlphaComponent(0.08),
            dark: UIColor(red: 0.20, green: 0.80, blue: 1.00, alpha: 0.14)
        )

    static let glassOverlayGreen =
        positive.opacity(0.05)

    static let glassOverlayProtected =
        protected.opacity(0.06)

    static let glassOverlayBlue =
        accent.opacity(0.08)

    static let glassOverlaySurface =
        adaptive(
            light: UIColor.white.withAlphaComponent(0.08),
            dark: UIColor(red: 0.08, green: 0.13, blue: 0.26, alpha: 0.18)
        )

    static let glassHighlight =
        adaptive(
            light: UIColor.white.withAlphaComponent(0.75),
            dark: UIColor(red: 0.58, green: 0.78, blue: 1.00, alpha: 0.40)
        )

    static let glassSubtleHighlight =
        adaptive(
            light: UIColor.white.withAlphaComponent(0.45),
            dark: UIColor(red: 0.44, green: 0.62, blue: 0.90, alpha: 0.24)
        )

    static let shadowSoft =
        adaptive(
            light: UIColor.black.withAlphaComponent(0.05),
            dark: UIColor(red: 0.12, green: 0.28, blue: 0.56, alpha: 0.22)
        )

    static let shadowCompact =
        adaptive(
            light: UIColor.black.withAlphaComponent(0.04),
            dark: UIColor(red: 0.12, green: 0.28, blue: 0.56, alpha: 0.16)
        )

    static let primaryButtonStart = accent

    static let primaryButtonEnd = accentSecondary

    static let tabTint =
        adaptive(
            light: UIColor(red: 0.35, green: 0.70, blue: 1.0, alpha: 1),
            dark: UIColor(red: 0.34, green: 0.78, blue: 1.0, alpha: 1)
        )
}
