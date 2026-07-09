import SwiftUI

struct DashboardCardsSection: View {

    @Environment(\.colorScheme) private var colorScheme

    let setAsideMetric: DashboardCardsMetric
    let upcomingMetric: DashboardCardsMetric
    let paymentsMetric: DashboardCardsMetric
    let showsNextAction: Bool
    let nextAction: DashboardNextAction
    let performNextAction: (DashboardNextAction) -> Void
    let comingUp: DashboardCardsMiniItem?
    let paymentPlan: DashboardCardsMiniItem?
    let bankSyncChangeSummary: BankSyncChangeSummary?
    let openBankSync: () -> Void
    let goalsProgress: DashboardGoalsProgressSummary
    let openGoals: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.regular) {
            atAGlanceCard

            if showsNextAction {
                nextActionCard
            }

            miniCardGrid
        }
    }

    private var atAGlanceCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            DashboardCardsHeader(title: "At a glance")

            HStack(alignment: .center, spacing: 0) {
                DashboardCardsAtAGlanceMetric(metric: setAsideMetric)

                DashboardCardsDivider()

                DashboardCardsAtAGlanceMetric(metric: upcomingMetric)

                DashboardCardsDivider()

                DashboardCardsAtAGlanceMetric(metric: paymentsMetric)
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
        .accessibilityElement(children: .combine)
    }

    private var nextActionCard: some View {
        HStack(alignment: .top, spacing: AppSpacing.regular) {
            CalderaGradientIcon(
                systemImage: nextAction.icon,
                colors: nextAction.style.gradient,
                size: 46,
                iconSize: 18
            )

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                DashboardCardsSectionLabel("Next Action")

                Text(nextAction.title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(nextAction.message)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle = nextAction.actionTitle {
                    DashboardCardsCTAButton(
                        title: actionTitle,
                        color: nextAction.style.primary,
                        action: {
                            performNextAction(nextAction)
                        }
                    )
                    .padding(.top, AppSpacing.xSmall)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    private var miniCardGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 132), spacing: AppSpacing.regular),
                GridItem(.flexible(minimum: 132), spacing: AppSpacing.regular)
            ],
            alignment: .leading,
            spacing: AppSpacing.regular
        ) {
            comingUpCard
            paymentPlanCard
            whatChangedCard
            goalsProgressCard
        }
    }

    private var comingUpCard: some View {
        DashboardCardsMiniCard(
            title: "Coming Up",
            actionTitle: comingUp?.actionTitle,
            action: comingUp?.action
        ) {
            if let comingUp {
                DashboardCardsMiniIconValue(item: comingUp)
            } else {
                DashboardCardsMiniEmptyState(
                    title: "Nothing soon",
                    message: "No upcoming expenses yet."
                )
            }
        }
    }

    private var paymentPlanCard: some View {
        DashboardCardsMiniCard(
            title: "Payment Plan",
            actionTitle: paymentPlan?.actionTitle,
            action: paymentPlan?.action
        ) {
            if let paymentPlan {
                DashboardCardsMiniIconValue(item: paymentPlan)
            } else {
                DashboardCardsMiniEmptyState(
                    title: "No plans yet",
                    message: "Payment plans will appear here."
                )
            }
        }
    }

    private var whatChangedCard: some View {
        DashboardCardsMiniCard(
            title: "What Changed",
            actionTitle: "Sync",
            action: openBankSync
        ) {
            if let summary = bankSyncChangeSummary,
               let change = summary.changedAccounts.first {
                DashboardCardsMiniIconValue(
                    item: DashboardCardsMiniItem(
                        systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
                        style: CalderaCategoryStyle.style(for: .bankAccount),
                        title: change.accountLabel,
                        subtitle: "Updated \(summary.refreshedAt.formatted(date: .omitted, time: .shortened))",
                        value: change.delta >= 0
                            ? "+\(AppFormatters.currency(change.delta))"
                            : "-\(AppFormatters.currency(abs(change.delta)))",
                        valueStyle: change.delta >= 0
                            ? CalderaCategoryStyle.style(for: .covered).primary
                            : CalderaCategoryStyle.style(for: .needsMoney).primary,
                        badge: summary.changedAccounts.count > 1
                            ? "\(summary.changedAccounts.count) changes"
                            : "Changed",
                        badgeStyle: CalderaCategoryStyle.style(for: .bankAccount),
                        actionTitle: nil,
                        action: nil
                    )
                )
            } else if bankSyncChangeSummary != nil {
                DashboardCardsMiniEmptyState(
                    title: "No major changes",
                    message: "Since the last refresh."
                )
            } else {
                DashboardCardsMiniEmptyState(
                    title: "No summary yet",
                    message: "Connect or refresh Bank Sync to compare balances."
                )
            }
        }
    }

    private var goalsProgressCard: some View {
        DashboardCardsMiniCard(
            title: "Savings Goals",
            actionTitle: "Goals",
            action: openGoals
        ) {
            if goalsProgress.hasProgressTarget {
                DashboardCardsGoalsProgressTile(summary: goalsProgress)
            } else {
                DashboardCardsGoalsProgressEmptyState()
            }
        }
    }
}

struct DashboardCardsMetric {
    let title: String
    let value: String
    let subtitle: String
    let style: CalderaCategoryStyle
    let systemImage: String
}

struct DashboardCardsMiniItem {
    let systemImage: String
    let style: CalderaCategoryStyle
    let title: String
    let subtitle: String
    let value: String
    var valueStyle: Color? = nil
    let badge: String
    let badgeStyle: CalderaCategoryStyle
    let actionTitle: String?
    let action: (() -> Void)?
}

struct DashboardGoalsProgressSummary {
    let currentAmount: Double
    let targetAmount: Double
    let hasGoals: Bool

    var hasProgressTarget: Bool {
        hasGoals && targetAmount > 0.005
    }

    var progress: Double {
        guard targetAmount > 0 else {
            return 0
        }

        let value = currentAmount / targetAmount
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0), 1)
    }

    var percentText: String {
        guard targetAmount > 0 else {
            return ""
        }

        let value = currentAmount / targetAmount
        guard value.isFinite else {
            return "0%"
        }

        return "\(Int((max(value, 0) * 100).rounded()))%"
    }
}

private enum DashboardCardsLayout {
    static let widePadding: CGFloat = 22
    static let miniPadding: CGFloat = 16
    static let miniHeaderHeight: CGFloat = 18
    static let miniCardHeight: CGFloat = 180
    static let miniIconSize: CGFloat = 32
    static let atAGlanceIconSize: CGFloat = 30
}

private struct DashboardCardsAtAGlanceMetric: View {

    @Environment(\.colorScheme) private var colorScheme

    let metric: DashboardCardsMetric

    var body: some View {
        VStack(alignment: .center, spacing: AppSpacing.xSmall) {
            CalderaGradientIcon(
                systemImage: metric.systemImage,
                colors: metric.style.gradient,
                size: DashboardCardsLayout.atAGlanceIconSize,
                iconSize: 12
            )

            VStack(alignment: .center, spacing: 2) {
                Text(metric.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(metric.value)
                    .font(.footnote.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
                    .monospacedDigit()

                Text(metric.subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(metric.style.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
        .padding(.horizontal, AppSpacing.xSmall)
    }
}

private struct DashboardCardsDivider: View {

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 68)
            .padding(.horizontal, AppSpacing.xSmall)
    }
}

private struct DashboardCardsMiniCard<Content: View>: View {

    let title: String
    let actionTitle: String?
    let action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            DashboardCardsHeader(title: title)
                .frame(height: DashboardCardsLayout.miniHeaderHeight, alignment: .top)

            content
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: AppSpacing.xSmall)

            if let actionTitle,
               let action {
                HStack {
                    Spacer(minLength: AppSpacing.small)

                    DashboardCardsInlineAction(
                        title: actionTitle,
                        action: action
                    )
                }
            }
        }
        .padding(DashboardCardsLayout.miniPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: DashboardCardsLayout.miniCardHeight,
            maxHeight: DashboardCardsLayout.miniCardHeight,
            alignment: .topLeading
        )
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.82,
            shadowOpacity: 0.04,
            shadowRadius: 14,
            shadowY: 6,
            darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
        )
    }
}

private struct DashboardCardsMiniIconValue: View {

    @Environment(\.colorScheme) private var colorScheme

    let item: DashboardCardsMiniItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .center, spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    systemImage: item.systemImage,
                    colors: item.style.gradient,
                    size: DashboardCardsLayout.miniIconSize,
                    iconSize: 13
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(item.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(item.value)
                    .font(.title3.weight(.bold))
                    .foregroundColor(item.valueStyle ?? CalderaVisualStyle.primaryText(colorScheme))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                DashboardCardsStatusBadge(
                    text: item.badge,
                    style: item.badgeStyle
                )
            }
            .padding(.top, 1)
        }
    }
}

private struct DashboardCardsMiniEmptyState: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(message)
                .font(.caption2.weight(.medium))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
    }
}

private struct DashboardCardsGoalsProgressTile: View {

    @Environment(\.colorScheme) private var colorScheme
    let summary: DashboardGoalsProgressSummary

    private var style: CalderaCategoryStyle {
        CalderaCategoryStyle.style(for: .savingsGoal)
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.small) {
            DashboardCardsProgressRing(
                progress: summary.progress,
                percentText: summary.percentText,
                style: style
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(AppFormatters.currency(summary.currentAmount))
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("of \(AppFormatters.currency(summary.targetAmount))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("toward goals")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(style.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
    }
}

private struct DashboardCardsGoalsProgressEmptyState: View {

    @Environment(\.colorScheme) private var colorScheme

    private let style = CalderaCategoryStyle.style(for: .savingsGoal)

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.small) {
            ZStack {
                Circle()
                    .stroke(style.primary.opacity(0.18), lineWidth: 8)
                    .frame(width: 58, height: 58)

                Image(systemName: "flag.fill")
                    .font(.headline.weight(.bold))
                    .foregroundColor(style.primary)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("No goals yet")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(1)

                Text("Create a goal to track progress.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
    }
}

private struct DashboardCardsProgressRing: View {

    @Environment(\.colorScheme) private var colorScheme
    let progress: Double
    let percentText: String
    let style: CalderaCategoryStyle

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    style.primary.opacity(colorScheme == .dark ? 0.18 : 0.14),
                    lineWidth: 8
                )

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: style.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(percentText)
                .font(.caption.weight(.bold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: 60, height: 60)
        .accessibilityLabel("Savings Goals progress")
        .accessibilityValue(percentText)
    }
}

private struct DashboardCardsHeader: View {

    let title: String

    var body: some View {
        DashboardCardsSectionLabel(title)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardCardsSectionLabel: View {

    @Environment(\.colorScheme) private var colorScheme
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.heavy))
            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }
}

private struct DashboardCardsStatusBadge: View {

    let text: String
    let style: CalderaCategoryStyle

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundColor(style.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(style.primary.opacity(0.13))
            )
    }
}

private struct DashboardCardsInlineAction: View {

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxSmall) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.heavy))
            }
            .font(.caption.weight(.bold))
            .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.xSmall)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardCardsCTAButton: View {

    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.heavy))
            }
            .font(.footnote.weight(.bold))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.xSmall)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}
