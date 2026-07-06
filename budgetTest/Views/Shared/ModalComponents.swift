import SwiftUI
import UIKit

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

struct CalderaEditorFormCard<Content: View>: View {

    let title: String?
    let systemImage: String?
    let color: Color
    let content: Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
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
            if let title,
               let systemImage {
                FormSectionHeader(
                    title: title,
                    systemImage: systemImage,
                    color: color
                )
            } else if let title {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
            }

            content
        }
        .calderaEditorPanel(color: color)
    }
}

struct CalderaTextEntryField: View {

    let title: String
    let subtitle: String?
    let placeholder: String
    let text: Binding<String>
    let keyboardType: UIKeyboardType
    let color: Color
    let accessibilityLabel: String

    init(
        title: String,
        subtitle: String? = nil,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        color: Color = AppColors.accent,
        accessibilityLabel: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.placeholder = placeholder
        self.text = text
        self.keyboardType = keyboardType
        self.color = color
        self.accessibilityLabel = accessibilityLabel ?? title
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xSmall
        ) {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TextField(
                placeholder,
                text: text
            )
            .keyboardType(keyboardType)
            .textInputAutocapitalization(.words)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small)
            .frame(minHeight: 52)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.88,
                strokeOpacity: 0.70,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: color
            )
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

extension View {

    func calderaEditorPanel(
        color: Color
    ) -> some View {
        padding(AppSpacing.card)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .calderaGlassCard(
                cornerRadius: AppRadii.panel,
                fillOpacity: 0.90,
                strokeOpacity: 0.76,
                shadowOpacity: 0.032,
                shadowRadius: 14,
                shadowY: 6,
                darkGlowColor: color
            )
    }
}
