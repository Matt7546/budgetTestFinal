#if DEBUG

import SwiftUI

struct ModularDashboardLabView: View {

    @State private var showsWidgetPicker = false
    @State private var configuredWidgets: [LabDashboardConfiguredWidget] = []

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.screen) {
                    LabDashboardAtAGlanceCard()
                    LabDashboardNextActionCard()

                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        HStack(spacing: AppSpacing.medium) {
                            Text("Your dashboard")
                                .font(.title3.weight(.bold))
                                .foregroundColor(AppColors.primaryText)

                            Spacer(minLength: AppSpacing.small)

                            Button {
                                showsWidgetPicker = true
                            } label: {
                                Label("Add widget", systemImage: "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(
                                        CalderaCategoryStyle.style(for: .safeToSpend).primary
                                    )
                                    .padding(.horizontal, AppSpacing.medium)
                                    .padding(.vertical, AppSpacing.small)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                CalderaCategoryStyle.style(for: .safeToSpend).primary
                                                    .opacity(0.12)
                                            )
                                    )
                                    .contentShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the Lab widget configuration flow")
                        }

                        LabDashboardWidgetGrid()
                    }

                    if !configuredWidgets.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.medium) {
                            Text("My widgets")
                                .font(.title3.weight(.bold))
                                .foregroundColor(AppColors.primaryText)

                            LabDashboardConfiguredWidgetCollection(
                                widgets: configuredWidgets
                            )
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.floatingTabClearance)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsWidgetPicker) {
            LabDashboardWidgetPickerSheet { widget in
                withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                    configuredWidgets.append(widget)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

enum LabDashboardWidgetSizing {
    static let tileHeight: CGFloat = 176
    static let tileSpacing = AppSpacing.medium
    static let tilePadding = AppSpacing.medium
}

private struct LabDashboardAtAGlanceCard: View {

    @Environment(\.colorScheme) private var colorScheme

    private let style = CalderaCategoryStyle.style(for: .safeToSpend)

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    style: style,
                    size: 38,
                    iconSize: 15
                )

                Text("At a glance")
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Spacer(minLength: AppSpacing.small)

                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(style.primary)
            }

            HStack(spacing: 0) {
                LabDashboardSummaryMetric(
                    title: "Cash",
                    value: "$4,680",
                    color: CalderaCategoryStyle.style(for: .bankAccount).primary
                )

                LabDashboardMetricDivider()

                LabDashboardSummaryMetric(
                    title: "Set Aside",
                    value: "$2,838",
                    color: CalderaCategoryStyle.style(for: .reserve).primary
                )

                LabDashboardMetricDivider()

                LabDashboardSummaryMetric(
                    title: "Available",
                    value: "$1,842",
                    color: style.primary
                )
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.72,
            shadowOpacity: colorScheme == .dark ? 0.14 : 0.04,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: style.primary
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("At a glance. Cash $4,680. Set Aside $2,838. Available to Spend $1,842.")
    }
}

private struct LabDashboardSummaryMetric: View {

    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: AppSpacing.xxSmall) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LabDashboardMetricDivider: View {

    var body: some View {
        Rectangle()
            .fill(AppColors.secondaryText.opacity(0.14))
            .frame(width: 1, height: 34)
            .padding(.horizontal, AppSpacing.small)
    }
}

private struct LabDashboardNextActionCard: View {

    @Environment(\.colorScheme) private var colorScheme

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.regular) {
            CalderaGradientIcon(
                systemImage: "creditcard.fill",
                colors: style.gradient,
                size: 48,
                iconSize: 18
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("NEXT ACTION")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(style.primary)

                Text("Set aside $249 for Platinum")
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)

                Text("Due Sep 1 · Statement balance")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: AppSpacing.xSmall)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(style.primary)
        }
        .padding(AppSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.72,
            shadowOpacity: colorScheme == .dark ? 0.14 : 0.04,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: style.primary
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next Action. Set aside $249 for Platinum. Due September 1, Statement balance.")
    }
}

private struct LabDashboardWidgetGrid: View {

    var body: some View {
        VStack(spacing: LabDashboardWidgetSizing.tileSpacing) {
            LabAvailableToSpendWidget()

            LabDashboardTwoColumnRow {
                LabSetAsideWidget()
            } trailing: {
                LabSavingsGoalsWidget()
            }

            LabPaymentPlansWidget()

            LabDashboardTwoColumnRow {
                LabUpcomingExpensesWidget()
            } trailing: {
                LabNeedsAttentionWidget()
            }

            LabPlanAheadWidget()

            LabDashboardTwoColumnRow {
                LabBankSyncWidget()
            } trailing: {
                LabWhatChangedWidget()
            }

            LabQuickActionsWidget()
        }
    }
}

private struct LabDashboardTwoColumnRow<Leading: View, Trailing: View>: View {

    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: LabDashboardWidgetSizing.tileSpacing) {
            leading
                .frame(maxWidth: .infinity)

            trailing
                .frame(maxWidth: .infinity)
        }
    }
}

private struct LabDashboardWidgetTile<Content: View>: View {

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String
    let style: CalderaCategoryStyle
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        style: CalderaCategoryStyle,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    systemImage: systemImage,
                    colors: style.gradient,
                    size: 34,
                    iconSize: 13
                )

                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(LabDashboardWidgetSizing.tilePadding)
        .frame(maxWidth: .infinity)
        .frame(height: LabDashboardWidgetSizing.tileHeight, alignment: .topLeading)
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
}

private struct LabAvailableToSpendWidget: View {

    private let style = CalderaCategoryStyle.style(for: .safeToSpend)

    var body: some View {
        LabDashboardWidgetTile(
            title: "Available to Spend",
            systemImage: "sparkles",
            style: style
        ) {
            HStack(alignment: .bottom, spacing: AppSpacing.regular) {
                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("$1,842")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("After Set Aside")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(style.primary)

                    Text("Your planned money is already held back.")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: AppSpacing.medium)

                VStack(alignment: .trailing, spacing: AppSpacing.xxSmall) {
                    Text("+$120")
                        .font(.headline.weight(.bold))
                        .foregroundColor(CalderaCategoryStyle.style(for: .covered).primary)
                        .monospacedDigit()

                    Text("since last sync")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Available to Spend, $1,842 after Set Aside. Up $120 since last sync.")
    }
}

private struct LabSetAsideWidget: View {

    private let style = CalderaCategoryStyle.style(for: .reserve)

    var body: some View {
        LabDashboardWidgetTile(
            title: "Set Aside Total",
            systemImage: "wallet.pass.fill",
            style: style
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("$2,838")
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("held back")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                LabSetAsideSplitBar()

                Text("Goals · Upcoming · Plans")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Set Aside Total, $2,838 across goals, upcoming expenses, and payment plans.")
    }
}

private struct LabSetAsideSplitBar: View {

    private let parts: [(value: CGFloat, color: Color)] = [
        (0.48, CalderaCategoryStyle.style(for: .savingsGoal).primary),
        (0.29, CalderaCategoryStyle.style(for: .upcomingExpense).primary),
        (0.23, CalderaCategoryStyle.style(for: .debtPayoff).primary)
    ]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(parts.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(parts[index].color)
                        .frame(width: max((proxy.size.width - 6) * parts[index].value, 0))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private struct LabSavingsGoalsWidget: View {

    private let style = CalderaCategoryStyle.style(for: .savingsGoal)

    var body: some View {
        LabDashboardWidgetTile(
            title: "Savings Goals",
            systemImage: "target",
            style: style
        ) {
            HStack(spacing: AppSpacing.small) {
                LabProgressRing(
                    progress: 0.68,
                    color: style.primary
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("$3,400")
                        .font(.headline.weight(.bold))
                        .foregroundColor(AppColors.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("of $5,000")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("68% saved")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(style.primary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Savings Goals, $3,400 of $5,000, 68 percent saved.")
    }
}

private struct LabProgressRing: View {

    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.secondaryText.opacity(0.14), lineWidth: 7)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("68")
                .font(.caption.weight(.bold))
                .foregroundColor(color)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

private struct LabPaymentPlansWidget: View {

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    var body: some View {
        LabDashboardWidgetTile(
            title: "Payment Plans",
            systemImage: "creditcard.fill",
            style: style
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                HStack(alignment: .firstTextBaseline) {
                    Text("$835 of $1,586")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppColors.primaryText)
                        .monospacedDigit()

                    Spacer(minLength: AppSpacing.small)

                    Text("3 upcoming")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(style.primary)
                }

                LabDashboardPaymentSegments(
                    payments: LabDashboardPaymentSample.all,
                    color: style.primary
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Payment Plans. $835 of $1,586 set aside across three upcoming payments.")
    }
}

private struct LabDashboardPaymentSample: Identifiable {
    let name: String
    let target: Double
    let setAside: Double
    let due: String

    var id: String { name }

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(setAside / target, 0), 1)
    }

    static let all = [
        LabDashboardPaymentSample(name: "Amex", target: 384, setAside: 384, due: "Aug 13"),
        LabDashboardPaymentSample(name: "Platinum", target: 700, setAside: 451, due: "Sep 1"),
        LabDashboardPaymentSample(name: "Chase", target: 502, setAside: 0, due: "Sep 3")
    ]
}

private struct LabDashboardPaymentSegments: View {

    let payments: [LabDashboardPaymentSample]
    let color: Color

    private let spacing: CGFloat = 4

    private var totalTarget: Double {
        payments.reduce(0) { $0 + $1.target }
    }

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(totalWidth: proxy.size.width)

            HStack(alignment: .top, spacing: spacing) {
                ForEach(payments.indices, id: \.self) { index in
                    LabDashboardPaymentSegment(
                        payment: payments[index],
                        color: color
                    )
                    .frame(width: widths[index])
                }
            }
        }
        .frame(height: 70)
    }

    private func segmentWidths(totalWidth: CGFloat) -> [CGFloat] {
        let availableWidth = max(
            totalWidth - spacing * CGFloat(max(payments.count - 1, 0)),
            0
        )

        guard totalTarget > 0 else {
            return Array(repeating: 0, count: payments.count)
        }

        return payments.map { payment in
            availableWidth * payment.target / totalTarget
        }
    }
}

private struct LabDashboardPaymentSegment: View {

    let payment: LabDashboardPaymentSample
    let color: Color

    var body: some View {
        VStack(spacing: AppSpacing.xxSmall) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(AppColors.secondaryText.opacity(0.17))

                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: proxy.size.width * payment.progress)
                }
            }
            .frame(height: 9)

            Text(payment.name)
                .font(.caption2.weight(.bold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text("$\(Int(payment.target)) · \(payment.due)")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.56)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LabUpcomingExpensesWidget: View {

    private let style = CalderaCategoryStyle.style(for: .upcomingExpense)

    var body: some View {
        LabDashboardWidgetTile(
            title: "Upcoming Expenses",
            systemImage: style.icon,
            style: style
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Rent")
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)

                Text("$1,700")
                    .font(.title3.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()

                Text("Due Aug 1")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                LabDashboardProgressBar(progress: 0.66, color: style.primary)

                Text("$580 needed")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Upcoming Expense. Rent, $1,700 due August 1. $580 needed.")
    }
}

private struct LabNeedsAttentionWidget: View {

    private let style = CalderaCategoryStyle.style(for: .needsMoney)

    var body: some View {
        LabDashboardWidgetTile(
            title: "Needs Attention",
            systemImage: "bell.badge.fill",
            style: style
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("2")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()

                Text("items to review")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text("1 past due · 1 plan needs funding")
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Needs Attention. Two items to review. One past due and one payment plan needs funding.")
    }
}

private struct LabPlanAheadWidget: View {

    private let style = CalderaCategoryStyle.style(for: .bankAccount)

    private let items = [
        LabDashboardPlanItem(name: "Rent", date: "Aug 1", amount: "$1,700", color: CalderaCategoryStyle.style(for: .upcomingExpense).primary),
        LabDashboardPlanItem(name: "Amex Gold", date: "Aug 13", amount: "$384", color: CalderaCategoryStyle.style(for: .debtPayoff).primary),
        LabDashboardPlanItem(name: "Vacation", date: "Aug 14", amount: "$500", color: CalderaCategoryStyle.style(for: .savingsGoal).primary)
    ]

    var body: some View {
        LabDashboardWidgetTile(
            title: "Plan Ahead",
            systemImage: "calendar",
            style: style
        ) {
            VStack(spacing: AppSpacing.xxSmall) {
                ForEach(items) { item in
                    HStack(spacing: AppSpacing.small) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 7, height: 7)

                        Text(item.date)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 46, alignment: .leading)

                        Text(item.name)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: AppSpacing.small)

                        Text(item.amount)
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppColors.primaryText)
                            .monospacedDigit()
                    }
                    .frame(minHeight: 24)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan Ahead. Rent August 1, $1,700. Amex Gold August 13, $384. Vacation August 14, $500.")
    }
}

private struct LabDashboardPlanItem: Identifiable {
    let name: String
    let date: String
    let amount: String
    let color: Color

    var id: String { name }
}

private struct LabBankSyncWidget: View {

    private let style = CalderaCategoryStyle.style(for: .bankAccount)

    var body: some View {
        LabDashboardWidgetTile(
            title: "Bank Sync",
            systemImage: "building.columns.fill",
            style: style
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .covered).primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("4 accounts")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text("Refreshed 8 min ago")
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bank Sync is up to date. Four accounts refreshed eight minutes ago.")
    }
}

private struct LabWhatChangedWidget: View {

    private let style = CalderaCategoryStyle.style(for: .safeToSpend)

    var body: some View {
        LabDashboardWidgetTile(
            title: "What Changed",
            systemImage: "arrow.up.right",
            style: style
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("+$120")
                    .font(.title2.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .covered).primary)
                    .monospacedDigit()

                Text("Available to Spend")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)

                Text("since your last sync")
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What Changed. Available to Spend increased $120 since your last sync.")
    }
}

private struct LabQuickActionsWidget: View {

    private let style = CalderaCategoryStyle.style(for: .safeToSpend)

    var body: some View {
        LabDashboardWidgetTile(
            title: "Quick Actions",
            systemImage: "plus",
            style: style
        ) {
            HStack(spacing: AppSpacing.small) {
                LabDashboardQuickAction(
                    title: "Goal",
                    systemImage: "target",
                    color: CalderaCategoryStyle.style(for: .savingsGoal).primary
                )

                LabDashboardQuickAction(
                    title: "Expense",
                    systemImage: CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                    color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
                )

                LabDashboardQuickAction(
                    title: "Plan",
                    systemImage: "creditcard.fill",
                    color: CalderaCategoryStyle.style(for: .debtPayoff).primary
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LabDashboardQuickAction: View {

    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Button {
            // This Lab prototype intentionally has no production navigation.
        } label: {
            VStack(spacing: AppSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundColor(color)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(color.opacity(0.12))
                    )

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create \(title)")
        .accessibilityHint("Prototype only")
    }
}

private struct LabDashboardProgressBar: View {

    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(AppColors.secondaryText.opacity(0.16))

                Capsule(style: .continuous)
                    .fill(color)
                    .frame(
                        width: proxy.size.width * min(max(progress, 0), 1)
                    )
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

#endif
