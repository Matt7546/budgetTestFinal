import SwiftUI

struct DashboardCardsSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let planStatusItems: [DashboardPlanStatusItem]
    let showsNextAction: Bool
    let nextAction: DashboardNextAction
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
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Next Action")
                .font(.caption2.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

            Text(nextAction.title)
                .font(.headline.weight(.bold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Text(nextAction.message)
                .font(.subheadline)
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle = nextAction.actionTitle {
                DashboardCardsCTAButton(
                    title: actionTitle,
                    color: nextAction.style.primary
                ) {
                    performNextAction(nextAction)
                }
            }
        }
        .padding(DashboardCardsLayout.widePadding)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.84,
            shadowOpacity: 0.045,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: nextAction.style.primary
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next Action. \(nextAction.title). \(nextAction.message)")
        .accessibilityHint(nextAction.actionTitle ?? "")
    }

    private var planStatusCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Plan status")
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text("Your Set Aside, Upcoming Expenses, and Payment Plans.")
                    .font(.subheadline)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(planStatusItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                    }

                    DashboardPlanStatusRow(item: item)
                }
            }
        }
        .padding(DashboardCardsLayout.widePadding)
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
}

private struct DashboardPlanStatusRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let item: DashboardPlanStatusItem

    var body: some View {
        Button(action: item.action) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(alignment: .top, spacing: AppSpacing.small) {
                    CalderaGradientIcon(
                        systemImage: item.systemImage,
                        colors: item.style.gradient,
                        size: 34,
                        iconSize: 14
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(item.detail)
                            .font(.caption)
                            .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                    Text(item.value)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: AppSpacing.small)

                    HStack(spacing: AppSpacing.xxSmall) {
                        Text(item.actionTitle)
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(item.style.primary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, AppSpacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
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
