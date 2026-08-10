import SwiftUI

struct DashboardWidgetRenderer: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: DashboardWidgetSnapshot
    let size: DashboardWidgetTileSize
    let action: (() -> Void)?

    private var style: CalderaCategoryStyle {
        CalderaCategoryStyle.style(for: snapshot.categoryRole)
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    tile
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.accessibilityLabel)
                .accessibilityHint("Opens (snapshot.title)")
            } else {
                tile
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(snapshot.accessibilityLabel)
            }
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            header
                .frame(height: 34)

            content
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .center
                )
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(
            RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous)
        )
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.86,
            strokeOpacity: 0.70,
            shadowOpacity: colorScheme == .dark ? 0.12 : 0.035,
            shadowRadius: 13,
            shadowY: 7,
            darkGlowColor: style.primary
        )
    }

    private var header: some View {
        HStack(spacing: AppSpacing.small) {
            CalderaGradientIcon(
                systemImage: style.icon,
                colors: style.gradient,
                size: 34,
                iconSize: 13
            )

            Text(snapshot.title)
                .font(.caption.weight(.bold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Spacer(minLength: 0)

            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(style.primary.opacity(0.82))
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot.kind {
        case .setAside:
            setAsideContent

        case .bankSync:
            bankSyncContent

        case .reviewUpdates:
            reviewUpdatesContent

        case .savingsGoal:
            savingsGoalContent

        case .upcomingExpenses,
             .paymentPlans:
            fundedListContent

        case .planAhead:
            planAheadContent
        }
    }

    private var setAsideContent: some View {
        Group {
            if size == .wide {
                HStack(alignment: .center, spacing: AppSpacing.regular) {
                    primaryValueBlock
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(AppColors.secondaryText.opacity(0.14))
                        .frame(width: 1, height: 58)

                    VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                        ForEach(snapshot.items.prefix(3)) { item in
                            HStack(spacing: AppSpacing.small) {
                                Text(item.title)
                                    .lineLimit(1)

                                Spacer(minLength: AppSpacing.small)

                                Text(item.primaryValue)
                                    .monospacedDigit()
                            }
                            .font(.caption2.weight(.semibold))
                        }
                    }
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(snapshot.primaryValue)
                        .font(.title2.weight(.bold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(snapshot.status ?? snapshot.subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(style.primary)
                        .lineLimit(2)

                    HStack(spacing: 3) {
                        ForEach(Array(snapshot.items.prefix(4))) { item in
                            Capsule(style: .continuous)
                                .fill(color(for: item.id))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 7)
                    .padding(.top, AppSpacing.xSmall)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private var bankSyncContent: some View {
        HStack(alignment: .center, spacing: AppSpacing.small) {
            Image(systemName: bankSyncStatusIcon)
                .font(.title2.weight(.bold))
                .foregroundColor(bankSyncStatusColor)

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(snapshot.primaryValue)
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)

                Text(snapshot.secondaryValue ?? snapshot.subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(size == .wide ? 2 : 3)
            }

            if size == .wide {
                Spacer(minLength: AppSpacing.medium)

                Text(snapshot.status ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(style.primary)
            }
        }
    }

    private var reviewUpdatesContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                Text(snapshot.primaryValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(style.primary)
                    .monospacedDigit()

                Text(snapshot.secondaryValue ?? "updates")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(2)
            }

            Text(snapshot.subtitle)
                .font(.caption2.weight(.medium))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .lineLimit(size == .wide ? 1 : 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savingsGoalContent: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            DashboardWidgetProgressRing(
                progress: snapshot.progress ?? 0,
                color: style.primary
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(snapshot.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Text(snapshot.primaryValue)
                    .font(.headline.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if let secondaryValue = snapshot.secondaryValue {
                    Text(secondaryValue)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .lineLimit(1)
                }
            }

            if size == .wide {
                Spacer(minLength: AppSpacing.medium)

                Text(snapshot.status ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(style.primary)
            }
        }
    }

    private var fundedListContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                Text(snapshot.primaryValue)
                    .font(.title3.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)

                Spacer(minLength: AppSpacing.small)

                if let status = snapshot.status {
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(style.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            if let progress = snapshot.progress {
                CalderaProgressBar(
                    progress: progress,
                    colors: style.gradient
                )
                .frame(height: 7)
            }

            HStack(alignment: .top, spacing: AppSpacing.small) {
                ForEach(snapshot.items.prefix(3)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                            .lineLimit(1)

                        Text(item.primaryValue)
                            .font(.caption.weight(.bold))
                            .foregroundColor(style.primary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.66)

                        Text(item.context)
                            .font(.caption2)
                            .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var planAheadContent: some View {
        VStack(spacing: AppSpacing.xxSmall) {
            ForEach(snapshot.items.prefix(3)) { item in
                HStack(spacing: AppSpacing.small) {
                    Circle()
                        .fill(style.primary)
                        .frame(width: 7, height: 7)

                    Text(item.context)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .frame(width: 44, alignment: .leading)

                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .lineLimit(1)

                    Spacer(minLength: AppSpacing.small)

                    Text(item.primaryValue)
                        .font(.caption.weight(.bold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(minHeight: 23)
            }
        }
    }

    private var primaryValueBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text(snapshot.primaryValue)
                .font(.title2.weight(.bold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(snapshot.status ?? snapshot.subtitle)
                .font(.caption2.weight(.semibold))
                .foregroundColor(style.primary)
                .lineLimit(2)
        }
    }

    private var bankSyncStatusIcon: String {
        switch snapshot.contentState {
        case .empty:
            return "link.badge.plus"
        case .content:
            return snapshot.primaryValue == "Up to date"
                ? "checkmark.circle.fill"
                : "clock.arrow.circlepath"
        case .hidden:
            return "circle"
        }
    }

    private var bankSyncStatusColor: Color {
        snapshot.primaryValue == "Up to date"
            ? CalderaCategoryStyle.style(for: .covered).primary
            : style.primary
    }

    private func color(
        for itemID: String
    ) -> Color {
        switch itemID {
        case "savings-goals":
            return CalderaCategoryStyle.style(for: .savingsGoal).primary
        case "upcoming-expenses":
            return CalderaCategoryStyle.style(for: .upcomingExpense).primary
        case "payment-plans":
            return CalderaCategoryStyle.style(for: .debtPayoff).primary
        default:
            return style.primary.opacity(0.72)
        }
    }
}

private struct DashboardWidgetProgressRing: View {
    let progress: Double
    let color: Color

    private var clampedProgress: Double {
        guard progress.isFinite else {
            return 0
        }

        return min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.secondaryText.opacity(0.14), lineWidth: 7)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(
                clampedProgress,
                format: .percent.precision(.fractionLength(0))
            )
            .font(.caption.weight(.bold))
            .foregroundColor(color)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}
