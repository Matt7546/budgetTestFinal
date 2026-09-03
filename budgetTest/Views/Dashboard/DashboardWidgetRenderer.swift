import SwiftUI

struct DashboardWidgetRenderer: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: DashboardWidgetSnapshot
    let size: DashboardWidgetTileSize
    let action: DashboardWidgetAction?
    let itemActions: [String: DashboardWidgetAction]
    let perform: (DashboardWidgetAction) -> Void

    private var style: CalderaCategoryStyle {
        CalderaCategoryStyle.style(for: snapshot.categoryRole)
    }

    var body: some View {
        Group {
            if let action {
                Button {
                    perform(action)
                } label: {
                    tile
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .sensitiveAccessibilityLabel(snapshot.accessibilityLabel)
                .accessibilityHint("Opens \(snapshot.title)")
            } else if !itemActions.isEmpty {
                tile
                    .accessibilityElement(children: .contain)
            } else {
                tile
                    .accessibilityElement(children: .ignore)
                    .sensitiveAccessibilityLabel(snapshot.accessibilityLabel)
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

            if action != nil || !itemActions.isEmpty {
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

                                SensitiveValueText(item.primaryValue)
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
                    SensitiveValueText(snapshot.primaryValue)
                        .font(.title2.weight(.bold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    SensitiveValueText(snapshot.status ?? snapshot.subtitle)
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
                SensitiveValueText(snapshot.primaryValue)
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)

                SensitiveValueText(snapshot.secondaryValue ?? snapshot.subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(size == .wide ? 2 : 3)
            }

            if size == .wide {
                Spacer(minLength: AppSpacing.medium)

                SensitiveValueText(snapshot.status ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(style.primary)
            }
        }
    }

    private var reviewUpdatesContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                SensitiveValueText(snapshot.primaryValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(style.primary)
                    .monospacedDigit()

                SensitiveValueText(snapshot.secondaryValue ?? "updates")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(2)
            }

            SensitiveValueText(snapshot.subtitle)
                .font(.caption2.weight(.medium))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .lineLimit(size == .wide ? 1 : 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savingsGoalContent: some View {
        Group {
            if size == .wide {
                wideSavingsGoalContent
            } else {
                HStack(alignment: .center, spacing: AppSpacing.medium) {
                    DashboardWidgetProgressRing(
                        progress: snapshot.progress ?? 0,
                        color: style.primary
                    )

                    savingsGoalValueBlock
                }
            }
        }
    }

    private var wideSavingsGoalContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                SensitiveValueText(snapshot.subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: AppSpacing.small)

                SensitiveValueText(snapshot.status ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(style.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                SensitiveValueText(snapshot.primaryValue)
                    .font(.title3.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if let secondaryValue = snapshot.secondaryValue {
                    SensitiveValueText(secondaryValue)
                        .font(.caption.weight(.medium))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .lineLimit(1)
                }
            }

            CalderaProgressBar(
                progress: snapshot.progress ?? 0,
                colors: style.gradient
            )
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savingsGoalValueBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            SensitiveValueText(snapshot.subtitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            SensitiveValueText(snapshot.primaryValue)
                .font(.headline.weight(.bold))
                .foregroundColor(style.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            if let secondaryValue = snapshot.secondaryValue {
                SensitiveValueText(secondaryValue)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(1)
            }
        }
    }

    private var fundedListContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                SensitiveValueText(snapshot.primaryValue)
                    .font(.title3.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)

                Spacer(minLength: AppSpacing.small)

                if let status = snapshot.status {
                    SensitiveValueText(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(style.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            DashboardWidgetSegmentedFundingBar(
                items: Array(snapshot.items.prefix(3)),
                fallbackProgress: snapshot.progress ?? 0,
                fundedColor: style.primary,
                primaryTextColor: CalderaVisualStyle.primaryText(colorScheme),
                actionForItem: { itemActions[$0.id] },
                perform: perform
            )
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

                    SensitiveValueText(item.primaryValue)
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
            SensitiveValueText(snapshot.primaryValue)
                .font(.title2.weight(.bold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            SensitiveValueText(snapshot.status ?? snapshot.subtitle)
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

private struct DashboardWidgetSegmentedFundingBar: View {
    let items: [DashboardWidgetItemSnapshot]
    let fallbackProgress: Double
    let fundedColor: Color
    let primaryTextColor: Color
    let actionForItem: (DashboardWidgetItemSnapshot) -> DashboardWidgetAction?
    let perform: (DashboardWidgetAction) -> Void

    private let segmentSpacing: CGFloat = 3

    private var segments: [DashboardWidgetItemSnapshot] {
        items.filter { item in
            let target = item.targetAmount ?? 0
            return target.isFinite && target > 0
        }
    }

    private var totalTarget: Double {
        segments.reduce(0) { total, item in
            total + max(item.targetAmount ?? 0, 0)
        }
    }

    var body: some View {
        Group {
            if segments.isEmpty || totalTarget <= 0 {
                CalderaProgressBar(
                    progress: clampedProgress(fallbackProgress),
                    colors: [fundedColor, fundedColor.opacity(0.72)]
                )
                .frame(height: 7)
            } else {
                GeometryReader { proxy in
                    let widths = segmentWidths(for: proxy.size.width)

                    HStack(alignment: .top, spacing: segmentSpacing) {
                        ForEach(segments.indices, id: \.self) { index in
                            segmentControl(
                                for: segments[index],
                                availableWidth: widths[index],
                                alignment: labelAlignment(for: index)
                            )
                            .frame(width: widths[index])
                        }
                    }
                }
                .frame(height: 39)
            }
        }
    }

    @ViewBuilder
    private func segmentControl(
        for item: DashboardWidgetItemSnapshot,
        availableWidth: CGFloat,
        alignment: Alignment
    ) -> some View {
        if let action = actionForItem(item) {
            Button {
                perform(action)
            } label: {
                segmentContent(
                    for: item,
                    availableWidth: availableWidth,
                    alignment: alignment
                )
            }
            .buttonStyle(.plain)
            .sensitiveAccessibilityLabel(item.accessibilityLabel)
            .accessibilityHint("Opens \(item.title)")
        } else {
            segmentContent(
                for: item,
                availableWidth: availableWidth,
                alignment: alignment
            )
        }
    }

    private func segmentContent(
        for item: DashboardWidgetItemSnapshot,
        availableWidth: CGFloat,
        alignment: Alignment
    ) -> some View {
        VStack(spacing: AppSpacing.xSmall) {
            fundingSegment(for: item)
                .frame(height: 8)

            segmentLabel(
                for: item,
                availableWidth: availableWidth
            )
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .contentShape(Rectangle())
    }

    private func fundingSegment(
        for item: DashboardWidgetItemSnapshot
    ) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppColors.secondaryText.opacity(0.18))

                Rectangle()
                    .fill(fundedColor)
                    .frame(width: proxy.size.width * fundingProgress(for: item))
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AppColors.secondaryText.opacity(0.14), lineWidth: 1)
            }
        }
    }

    private func segmentLabel(
        for item: DashboardWidgetItemSnapshot,
        availableWidth: CGFloat
    ) -> some View {
        Group {
            if availableWidth >= 66 {
                VStack(spacing: 1) {
                    Text(item.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(primaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    SensitiveValueText(item.primaryValue)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(fundedColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.60)
                }
            } else if availableWidth >= 38 {
                SensitiveValueText(item.primaryValue)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(fundedColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)
            } else {
                EmptyView()
            }
        }
    }

    private func segmentWidths(for totalWidth: CGFloat) -> [CGFloat] {
        let totalSpacing = segmentSpacing * CGFloat(max(segments.count - 1, 0))
        let availableWidth = max(totalWidth - totalSpacing, 0)

        return segments.map { item in
            availableWidth * (max(item.targetAmount ?? 0, 0) / totalTarget)
        }
    }

    private func fundingProgress(
        for item: DashboardWidgetItemSnapshot
    ) -> CGFloat {
        let target = max(item.targetAmount ?? 0, 0)
        guard target > 0 else {
            return 0
        }

        return CGFloat(clampedProgress((item.setAsideAmount ?? 0) / target))
    }

    private func labelAlignment(for index: Int) -> Alignment {
        if segments.count == 1 || index == segments.count - 1 {
            return .trailing
        }

        return index == 0 ? .leading : .center
    }

    private func clampedProgress(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0), 1)
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
