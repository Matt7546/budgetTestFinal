import SwiftUI

struct ModalHeaderView: View {

    let eyebrow: String
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            IconBadge(
                systemImage: systemImage,
                color: color,
                size: 56,
                iconSize: 22
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)

                Text(title)
                    .font(
                        .system(
                            size: 32,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

struct GlassFormCard<Content: View>: View {

    let color: Color
    let content: Content

    init(
        color: Color = AppColors.accent,
        @ViewBuilder content: () -> Content
    ) {
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            content
        }
        .padding(AppSpacing.card)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    color.opacity(0.05),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: AppShadows.softPanelCompact
        )
    }
}

struct FormSectionHeader: View {

    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            IconBadge(
                systemImage: systemImage,
                color: color,
                size: 34,
                iconSize: 14
            )

            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.primaryText)
        }
    }
}
