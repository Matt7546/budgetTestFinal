import SwiftUI

struct DashboardCardsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let planStatusItems: [DashboardPlanStatusItem]
    let showsNextAction: Bool
    let nextAction: DashboardNextAction
    @Binding var isNextActionCollapsed: Bool
    let performNextAction: (DashboardNextAction) -> Void

    var body: some View {
        VStack(spacing: AppSpacing.regular) {
            if showsNextAction {
                nextActionCard
            }

            planStatusCard
        }
    }

    private var nextActionCard: some View {
        let presentation = DashboardNextActionPresentation.make(
            for: nextAction,
            isCollapsed: isNextActionCollapsed
        )

        return VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                Text("Next Action")
                    .font(.caption.weight(.bold))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )

                Spacer(minLength: AppSpacing.small)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isNextActionCollapsed.toggle()
                    }
                } label: {
                    HStack(spacing: AppSpacing.xxSmall) {
                        Text(presentation.toggleTitle)
                        Image(systemName: presentation.toggleSystemImage)
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundColor(nextAction.style.primary)
                    .padding(.horizontal, AppSpacing.small)
                    .padding(.vertical, AppSpacing.xSmall)
                    .background(
                        nextAction.style.primary.opacity(0.10),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(presentation.toggleTitle) Next Action"
                )
            }

            if presentation.isCollapsed {
                collapsedNextActionContent(presentation)
            } else {
                expandedNextActionContent(presentation)
            }
        }
        .padding(DashboardCardsLayout.widePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.84,
            shadowOpacity: 0.045,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: nextAction.style.primary
        )
        .accessibilityElement(children: .contain)
    }

    private func expandedNextActionContent(
        _ presentation: DashboardNextActionPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(nextAction.title)
                .font(.headline.weight(.bold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if presentation.showsExpandedMessage {
                SensitiveValueText(nextAction.message)
                    .font(.subheadline)
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            primaryNextActionButton(presentation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func collapsedNextActionContent(
        _ presentation: DashboardNextActionPresentation
    ) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(nextAction.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(
                        CalderaVisualStyle.primaryText(colorScheme)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                SensitiveValueText(presentation.compactMessage)
                    .font(.caption)
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            primaryNextActionButton(presentation)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func primaryNextActionButton(
        _ presentation: DashboardNextActionPresentation
    ) -> some View {
        if presentation.showsPrimaryAction,
           let actionTitle = nextAction.actionTitle {
            DashboardCardsCTAButton(
                title: actionTitle,
                color: nextAction.style.primary
            ) {
                performNextAction(nextAction)
            }
        }
    }

    private var planStatusCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("At a glance")
                .font(.headline.weight(.bold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

            planStatusMetrics
        }
        .padding(DashboardCardsLayout.compactPadding)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.84,
            shadowOpacity: 0.045,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var planStatusMetrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(Array(planStatusItems.enumerated()), id: \.element.id) {
                    index,
                    item in
                    if index > 0 {
                        Divider()
                    }

                    DashboardAtAGlanceMetric(item: item)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(planStatusItems.enumerated()), id: \.element.id) {
                    index,
                    item in
                    if index > 0 {
                        Rectangle()
                            .fill(AppColors.secondaryText.opacity(0.18))
                            .frame(
                                width: 1,
                                height: DashboardCardsLayout.metricDividerHeight
                            )
                            .padding(.horizontal, AppSpacing.xxSmall)
                    }

                    DashboardAtAGlanceMetric(item: item)
                }
            }
        }
    }
}

struct DashboardPlanStatusItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let style: CalderaCategoryStyle
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var accessibilityLabel: String {
        "\(title). \(value). \(detail)"
    }
}

private enum DashboardCardsLayout {
    static let widePadding: CGFloat = 22
    static let compactPadding: CGFloat = 20
    static let metricDividerHeight: CGFloat = 76
    static let metricMinimumHeight: CGFloat = 94
}

private struct DashboardAtAGlanceMetric: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: DashboardPlanStatusItem

    var body: some View {
        Button(action: item.action) {
            VStack(spacing: AppSpacing.xSmall) {
                CalderaGradientIcon(
                    systemImage: item.systemImage,
                    colors: item.style.gradient,
                    size: 30,
                    iconSize: 12
                )

                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                SensitiveValueText(item.value)
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)

                Text(item.detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(item.style.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: DashboardCardsLayout.metricMinimumHeight,
                alignment: .top
            )
            .padding(.horizontal, AppSpacing.xxSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .sensitiveAccessibilityLabel(item.accessibilityLabel)
        .accessibilityHint(item.actionTitle)
    }
}

private struct DashboardCardsCTAButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxSmall) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Image(systemName: "chevron.right")
            }
            .font(.footnote.weight(.bold))
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small)
            .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
