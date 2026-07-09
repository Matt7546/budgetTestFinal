import SwiftUI

struct SavingsSectionShell<Content: View, Trailing: View>: View {

    let title: String
    let style: CalderaCategoryStyle
    let trailing: Trailing
    let content: Content

    init(
        title: String,
        style: CalderaCategoryStyle,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.style = style
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    style: style,
                    size: 34,
                    iconSize: 14
                )

                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)

                Spacer()

                trailing
            }

            content
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.72,
            shadowOpacity: 0.036,
            shadowRadius: 16,
            shadowY: 8
        )
    }
}

struct SavingsSeeAllLabel: View {

    var body: some View {
        Text("See all")
            .font(.caption2.weight(.bold))
            .foregroundColor(AppColors.accent)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.xxSmall)
            .background(
                Capsule(style: .continuous)
                    .fill(AppColors.accent.opacity(0.09))
            )
    }
}

struct SavingsQuickAddButton: View {

    let title: String
    let style: CalderaCategoryStyle
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: "plus")
                    .font(.caption2.weight(.bold))

                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(style.primary)
            .frame(minHeight: 36)
            .padding(.horizontal, AppSpacing.medium)
            .background(
                Capsule(style: .continuous)
                    .fill(style.primary.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        style.primary.opacity(0.12),
                        lineWidth: 1
                    )
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: AppRadii.button,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SavingsEmptyPreviewRow: View {

    let title: String
    let subtitle: String
    let style: CalderaCategoryStyle

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            CalderaGradientIcon(
                style: style,
                size: 32,
                iconSize: 13
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.78,
            strokeOpacity: 0.58,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: style.primary
        )
        .accessibilityElement(children: .combine)
    }
}

struct SavingsSetAsideExplanationRow: View {

    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            Image(systemName: "info.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
                .padding(.top, 1)

            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.74,
            strokeOpacity: 0.54,
            shadowOpacity: 0.0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
        )
    }
}

struct SavingsCompactRow: View {

    let title: String
    let subtitle: String
    let value: String
    let style: CalderaCategoryStyle
    let valueStyle: CalderaCategoryStyle?
    let progress: Double
    let showsProgress: Bool
    let rowAction: (() -> Void)?
    let accessorySystemImage: String?
    let accessoryAccessibilityLabel: String?
    let accessoryAction: (() -> Void)?

    init(
        title: String,
        subtitle: String,
        value: String,
        style: CalderaCategoryStyle,
        valueStyle: CalderaCategoryStyle? = nil,
        progress: Double,
        showsProgress: Bool = true,
        rowAction: (() -> Void)? = nil,
        accessorySystemImage: String? = nil,
        accessoryAccessibilityLabel: String? = nil,
        accessoryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.style = style
        self.valueStyle = valueStyle
        self.progress = progress
        self.showsProgress = showsProgress
        self.rowAction = rowAction
        self.accessorySystemImage = accessorySystemImage
        self.accessoryAccessibilityLabel = accessoryAccessibilityLabel
        self.accessoryAction = accessoryAction
    }

    var body: some View {
        VStack(spacing: AppSpacing.xSmall) {
            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: style,
                    size: 32,
                    iconSize: 13
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(
                        (valueStyle ?? style).primary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let accessorySystemImage,
                   let accessoryAction {
                    Button(
                        action: accessoryAction
                    ) {
                        Image(systemName: accessorySystemImage)
                            .font(.body.weight(.semibold))
                            .foregroundColor(style.primary)
                            .frame(
                                width: 32,
                                height: 32
                            )
                            .background(
                                Circle()
                                    .fill(style.primary.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        accessoryAccessibilityLabel ?? title
                    )
                }
            }

            if showsProgress {
                CalderaProgressBar(
                    progress: clampedProgressValue(progress),
                    colors: style.gradient
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            rowAction?()
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, showsProgress ? AppSpacing.small : AppSpacing.compact)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.80,
            strokeOpacity: 0.60,
            shadowOpacity: 0.012,
            shadowRadius: 8,
            shadowY: 3
        )
        .accessibilityElement(children: .combine)
    }
}
