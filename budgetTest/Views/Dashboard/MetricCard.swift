import SwiftUI

struct MetricCard: View {

    let title: String
    let valueText: String
    let subtitle: String
    let systemImage: String
    let iconColor: Color
    let valueColor: Color

    init(
        title: String,
        value: Double,
        subtitle: String,
        systemImage: String,
        iconColor: Color,
        valueColor: Color = AppColors.primaryText
    ) {
        self.title = title
        self.valueText = AppFormatters.currency(
            value
        )
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.valueColor = valueColor
    }

    init(
        title: String,
        valueText: String,
        subtitle: String,
        systemImage: String,
        iconColor: Color,
        valueColor: Color = AppColors.primaryText
    ) {
        self.title = title
        self.valueText = valueText
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.valueColor = valueColor
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 6) {

            ZStack {

                Circle()
                    .fill(iconColor.opacity(0.14))
                    .frame(
                        width: 40,
                        height: 40
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                Color.white.opacity(0.45),
                                lineWidth: 1
                            )
                    }

                Image(systemName: systemImage)
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(valueText)
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.52)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(minHeight: 118, alignment: .topLeading)
        .dashboardGlassCard(
            cornerRadius: AppRadii.card,
            accent: iconColor,
            bloomOpacity: 0.10,
            borderOpacity: 0.70,
            shadow: AppShadows.softCard
        )
    }
}

private struct DashboardGlassCardModifier: ViewModifier {

    let cornerRadius: CGFloat
    let accent: Color
    let bloomOpacity: Double
    let borderOpacity: Double
    let shadow: AppShadow?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.34),
                                        Color.white.opacity(0.16),
                                        AppColors.glassOverlaySurface
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RadialGradient(
                            colors: [
                                accent.opacity(bloomOpacity),
                                accent.opacity(bloomOpacity * 0.42),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 210
                        )
                        .blendMode(.plusLighter)
                        .clipShape(
                            RoundedRectangle(cornerRadius: cornerRadius)
                        )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(borderOpacity),
                                AppColors.glassStroke.opacity(0.42),
                                accent.opacity(0.10),
                                Color.white.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: shadow?.color ?? .clear,
                radius: shadow?.radius ?? 0,
                x: shadow?.x ?? 0,
                y: shadow?.y ?? 0
            )
    }
}

extension View {

    func dashboardGlassCard(
        cornerRadius: CGFloat,
        accent: Color,
        bloomOpacity: Double,
        borderOpacity: Double,
        shadow: AppShadow?
    ) -> some View {
        modifier(
            DashboardGlassCardModifier(
                cornerRadius: cornerRadius,
                accent: accent,
                bloomOpacity: bloomOpacity,
                borderOpacity: borderOpacity,
                shadow: shadow
            )
        )
    }
}
