import SwiftUI

struct SettingsSection<Content: View>: View {

    let title: String
    let systemImage: String
    let color: Color
    let content: Content

    init(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    systemImage: systemImage,
                    colors: CalderaVisualStyle.iconGradient(for: color),
                    size: 34,
                    iconSize: 14
                )

                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
            }

            VStack(
                alignment: .leading,
                spacing: AppSpacing.medium
            ) {
                content
            }
        }
        .padding(AppSpacing.card)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.72,
            shadowOpacity: 0.036,
            shadowRadius: 16,
            shadowY: 8,
            darkGlowColor: color
        )
    }
}

struct SettingsInfoRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color

    var body: some View {
        SettingsRowShell(
            title: title,
            description: description,
            systemImage: systemImage,
            color: color
        )
    }
}

struct SettingsNavigationRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: CalderaVisualStyle.iconGradient(for: color),
                size: 34,
                iconSize: 14
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.small)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.secondaryText.opacity(0.65))
        }
        .contentShape(Rectangle())
    }
}

struct SettingsExternalLinkRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(
                alignment: .center,
                spacing: AppSpacing.medium
            ) {
                SettingsRowShell(
                    title: title,
                    description: description,
                    systemImage: systemImage,
                    color: color
                )

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.secondaryText.opacity(0.65))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsValueRow: View {

    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            SettingsRowShell(
                title: title,
                description: nil,
                systemImage: systemImage,
                color: color
            )

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
        }
    }
}

struct SettingsRefreshStatusRow: View {

    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: CalderaVisualStyle.iconGradient(for: color),
                size: 34,
                iconSize: 14
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: 0.76,
            strokeOpacity: 0.62,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: color
        )
    }
}

struct SettingsPlaceholderRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            SettingsRowShell(
                title: title,
                description: description,
                systemImage: systemImage,
                color: color
            )

            Text("Coming Soon")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AppColors.secondaryText.opacity(0.10))
                )
        }
        .opacity(0.82)
    }
}

private struct SettingsRowShell: View {

    let title: String
    let description: String?
    let systemImage: String
    let color: Color

    init(
        title: String,
        description: String?,
        systemImage: String,
        color: Color
    ) {
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: CalderaVisualStyle.iconGradient(for: color),
                size: 34,
                iconSize: 14
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}
