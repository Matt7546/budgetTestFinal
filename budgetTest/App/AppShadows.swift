import SwiftUI

struct AppShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    init(
        color: Color,
        radius: CGFloat,
        x: CGFloat = 0,
        y: CGFloat
    ) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

enum AppShadows {

    static let darkCard =
        AppShadow(
            color: AppColors.shadowSoft,
            radius: 20,
            y: 10
        )

    static let softCard =
        AppShadow(
            color: AppColors.shadowCompact,
            radius: 20,
            y: 10
        )

    static let softPanel =
        AppShadow(
            color: AppColors.shadowSoft,
            radius: 30,
            y: 15
        )

    static let softPanelCompact =
        AppShadow(
            color: AppColors.shadowCompact,
            radius: 20,
            y: 10
        )

    static let blueHero =
        AppShadow(
            color: AppColors.accent.opacity(0.08),
            radius: 20,
            y: 10
        )
}
