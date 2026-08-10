#if DEBUG

import SwiftUI

struct LabSetAsidePagerPrototypeView: View {
    @State private var selectedSection: LabSetAsideSection = .goals

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .savings)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.regular) {
                    header
                    sectionSelector

                    TabView(selection: $selectedSection) {
                        LabSetAsideUpcomingPage()
                            .tag(LabSetAsideSection.upcoming)

                        LabSetAsidePaymentsPage()
                            .tag(LabSetAsideSection.payments)

                        LabSetAsideGoalsPage()
                            .tag(LabSetAsideSection.goals)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 610)
                    .animation(
                        .easeInOut(duration: 0.22),
                        value: selectedSection
                    )

                    pageDots
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.floatingTabClearance)
            }
        }
        .navigationTitle("Set Aside Pager")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text("SET ASIDE")
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.secondaryText)

            Text("A calmer plan for what matters next.")
                .font(.title3.weight(.bold))
                .foregroundColor(AppColors.primaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var sectionSelector: some View {
        HStack(spacing: AppSpacing.small) {
            ForEach(LabSetAsideSection.allCases) { section in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        selectedSection = section
                    }
                } label: {
                    LabSetAsideSectionCard(
                        section: section,
                        isSelected: selectedSection == section
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(section.title)")
                .accessibilityAddTraits(
                    selectedSection == section ? .isSelected : []
                )
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Spacer()

            ForEach(LabSetAsideSection.allCases) { section in
                Capsule(style: .continuous)
                    .fill(
                        selectedSection == section
                            ? selectedSection.style.primary
                            : AppColors.secondaryText.opacity(0.22)
                    )
                    .frame(
                        width: selectedSection == section ? 18 : 6,
                        height: 6
                    )
                    .animation(.easeInOut(duration: 0.2), value: selectedSection)
            }

            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(selectedSection.title) page, \(selectedSection.pageIndex) of \(LabSetAsideSection.allCases.count)")
    }
}

private enum LabSetAsideSection: String, CaseIterable, Identifiable {
    case upcoming
    case payments
    case goals

    var id: Self { self }

    var title: String {
        switch self {
        case .upcoming:
            return "Upcoming"
        case .payments:
            return "Payments"
        case .goals:
            return "Goals"
        }
    }

    var icon: String {
        switch self {
        case .upcoming:
            return "calendar"
        case .payments:
            return "creditcard"
        case .goals:
            return "target"
        }
    }

    var style: CalderaCategoryStyle {
        switch self {
        case .upcoming:
            return CalderaCategoryStyle.style(for: .upcomingExpense)
        case .payments:
            return CalderaCategoryStyle.style(for: .debtPayoff)
        case .goals:
            return CalderaCategoryStyle.style(for: .savingsGoal)
        }
    }

    var pageIndex: Int {
        switch self {
        case .upcoming:
            return 1
        case .payments:
            return 2
        case .goals:
            return 3
        }
    }
}

private struct LabSetAsideSectionCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let section: LabSetAsideSection
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: section.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(isSelected ? .white : section.style.primary)

            Text(section.title)
                .font(.caption2.weight(.bold))
                .foregroundColor(
                    isSelected
                        ? .white
                        : AppColors.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background {
            RoundedRectangle(cornerRadius: AppRadii.field, style: .continuous)
                .fill(
                    isSelected
                        ? LinearGradient(
                            colors: section.style.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [
                                AppColors.glassOverlayWhite,
                                AppColors.glassOverlaySurface
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppRadii.field, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.white.opacity(colorScheme == .dark ? 0.22 : 0.34)
                        : AppColors.secondaryText.opacity(0.14),
                    lineWidth: 1
                )
        }
        .shadow(
            color: isSelected ? section.style.primary.opacity(0.20) : .clear,
            radius: 10,
            y: 5
        )
        .contentShape(RoundedRectangle(cornerRadius: AppRadii.field, style: .continuous))
    }
}

private struct LabSetAsideGoalsPage: View {
    private let style = CalderaCategoryStyle.style(for: .savingsGoal)

    private let goals = [
        LabSetAsideGoal(name: "Goal", saved: 525, target: 500),
        LabSetAsideGoal(name: "Goal", saved: 0, target: 500),
        LabSetAsideGoal(name: "Test 2", saved: 0, target: 750)
    ]

    private var totalSaved: Double {
        goals.reduce(0) { $0 + $1.saved }
    }

    private var totalTarget: Double {
        goals.reduce(0) { $0 + $1.target }
    }

    private var overallProgress: Double {
        guard totalTarget > 0 else {
            return 0
        }

        return min(max(totalSaved / totalTarget, 0), 1)
    }

    private var remaining: Double {
        max(totalTarget - totalSaved, 0)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                goalsHeader
                summaryCard

                ForEach(goals) { goal in
                    LabSetAsideGoalRow(goal: goal, style: style)
                }

                Button {
                    // This Lab surface intentionally has no production action.
                } label: {
                    Label("Create Savings Goal", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(style.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.medium)
                        .background(
                            Capsule(style: .continuous)
                                .fill(style.primary.opacity(0.12))
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(style.primary.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, AppSpacing.xxSmall)
                .accessibilityLabel("Create Savings Goal prototype")
            }
            .padding(.vertical, AppSpacing.xxSmall)
            .padding(.bottom, AppSpacing.medium)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var goalsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Savings Goals")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text("\(goals.count) active goals")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()

            Text("30% funded")
                .font(.caption.weight(.bold))
                .foregroundColor(style.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private var summaryCard: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("TOTAL SAVED")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppColors.secondaryText)

                Text(AppFormatters.currency(totalSaved))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("of \(AppFormatters.currency(totalTarget)) across your goals")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)

                HStack(spacing: AppSpacing.small) {
                    LabSetAsideMetric(
                        title: "Progress",
                        value: "\(Int((overallProgress * 100).rounded()))%"
                    )

                    LabSetAsideMetricDivider()

                    LabSetAsideMetric(
                        title: "Remaining",
                        value: AppFormatters.currency(remaining)
                    )
                }
                .padding(.top, AppSpacing.xxSmall)
            }

            Spacer(minLength: 0)

            LabSetAsideGoalsArc(
                progress: overallProgress,
                style: style
            )
            .frame(width: 126, height: 126)
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.70,
            shadowOpacity: 0.04,
            shadowRadius: 14,
            shadowY: 7,
            darkGlowColor: style.primary
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Savings Goals. \(AppFormatters.currency(totalSaved)) saved of \(AppFormatters.currency(totalTarget)). \(Int((overallProgress * 100).rounded())) percent funded. \(AppFormatters.currency(remaining)) remaining."
        )
    }
}

private struct LabSetAsideGoalsArc: View {
    let progress: Double
    let style: CalderaCategoryStyle

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(
                    style.primary.opacity(0.14),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.08, to: 0.08 + (0.84 * clampedProgress))
                .stroke(
                    LinearGradient(
                        colors: style.gradient,
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .shadow(color: style.primary.opacity(0.20), radius: 8, y: 4)

            VStack(spacing: 1) {
                Text("\(Int((clampedProgress * 100).rounded()))%")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()

                Text("toward goals")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((clampedProgress * 100).rounded())) percent toward all goals")
    }
}

private struct LabSetAsideMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)

            Text(value)
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct LabSetAsideMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.secondaryText.opacity(0.16))
            .frame(width: 1, height: 28)
    }
}

private struct LabSetAsideGoal: Identifiable {
    let name: String
    let saved: Double
    let target: Double

    var id: String { "\(name)-\(target)" }

    var progress: Double {
        guard target > 0 else {
            return 0
        }

        return min(max(saved / target, 0), 1)
    }

    var remaining: Double {
        max(target - saved, 0)
    }
}

private struct LabSetAsideGoalRow: View {
    let goal: LabSetAsideGoal
    let style: CalderaCategoryStyle

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .center, spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    style: style,
                    size: 34,
                    iconSize: 13
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Text("\(AppFormatters.currency(goal.saved)) saved of \(AppFormatters.currency(goal.target))")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }

                Spacer(minLength: AppSpacing.xSmall)

                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(Int((goal.progress * 100).rounded()))%")
                        .font(.caption.weight(.bold))
                        .foregroundColor(style.primary)
                        .monospacedDigit()

                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundColor(style.primary)
                        .frame(width: 24, height: 24)
                        .background(style.primary.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                }
            }

            CalderaProgressBar(progress: goal.progress, colors: style.gradient)
                .frame(height: 5)

            Text(
                goal.remaining == 0
                    ? "Goal funded"
                    : "\(AppFormatters.currency(goal.remaining)) remaining"
            )
            .font(.caption2.weight(.medium))
            .foregroundColor(
                goal.remaining == 0
                    ? CalderaCategoryStyle.style(for: .covered).primary
                    : AppColors.secondaryText
            )
            .monospacedDigit()
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.80,
            strokeOpacity: 0.60,
            shadowOpacity: 0.012,
            shadowRadius: 8,
            shadowY: 3
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(goal.name), \(AppFormatters.currency(goal.saved)) saved of \(AppFormatters.currency(goal.target)), \(Int((goal.progress * 100).rounded())) percent funded"
        )
    }
}

private struct LabSetAsidePaymentsPage: View {
    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    private let payments = [
        LabSetAsideFundingItem(
            title: "Amex Gold",
            target: 384,
            setAside: 384,
            detail: "Due Aug 13 · Statement balance",
            shortTitle: "Amex",
            status: "Funded"
        ),
        LabSetAsideFundingItem(
            title: "Platinum",
            target: 700,
            setAside: 451,
            detail: "Due Sep 1 · Statement balance",
            shortTitle: "Platinum",
            status: "Partly funded"
        ),
        LabSetAsideFundingItem(
            title: "Chase",
            target: 502,
            setAside: 0,
            detail: "Due Sep 3 · Statement balance",
            shortTitle: "Chase",
            status: "Not funded"
        )
    ]

    private var totalSetAside: Double {
        payments.reduce(0) { $0 + $1.setAside }
    }

    private var totalPlanned: Double {
        payments.reduce(0) { $0 + $1.target }
    }

    private var remaining: Double {
        max(totalPlanned - totalSetAside, 0)
    }

    private var progress: Double {
        guard totalPlanned > 0 else {
            return 0
        }

        return min(max(totalSetAside / totalPlanned, 0), 1)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                LabSetAsideFundingPageHeader(
                    title: "Payment Plans",
                    countText: "\(payments.count) active payment plans",
                    progressText: "\(Int((progress * 100).rounded()))% funded",
                    style: style
                )

                LabSetAsideFundingSummaryCard(
                    heading: "TOTAL SET ASIDE",
                    totalSetAside: totalSetAside,
                    totalTarget: totalPlanned,
                    targetDescription: "planned across payment plans",
                    progress: progress,
                    remaining: remaining,
                    arcLabel: "toward payments",
                    style: style
                ) {
                    LabSetAsidePaymentSegments(
                        payments: payments,
                        style: style
                    )
                }

                ForEach(payments) { payment in
                    LabSetAsideFundingRow(
                        item: payment,
                        style: style
                    )
                }

                LabSetAsideCreateButton(
                    title: "Create Payment Plan",
                    style: style
                )
            }
            .padding(.vertical, AppSpacing.xxSmall)
            .padding(.bottom, AppSpacing.medium)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct LabSetAsideUpcomingPage: View {
    private let style = CalderaCategoryStyle.style(for: .upcomingExpense)

    private let expenses = [
        LabSetAsideFundingItem(
            title: "Rent",
            target: 900,
            setAside: 300,
            detail: "Due Aug 1 · Monthly",
            shortTitle: "Rent",
            status: "Needs $600"
        ),
        LabSetAsideFundingItem(
            title: "Insurance",
            target: 180,
            setAside: 120,
            detail: "Due Aug 5 · Monthly",
            shortTitle: "Insurance",
            status: "Needs $60"
        ),
        LabSetAsideFundingItem(
            title: "Phone Bill",
            target: 140,
            setAside: 0,
            detail: "Due Aug 9 · Monthly",
            shortTitle: "Phone",
            status: "Not funded"
        )
    ]

    private var totalSetAside: Double {
        expenses.reduce(0) { $0 + $1.setAside }
    }

    private var totalNeeded: Double {
        expenses.reduce(0) { $0 + $1.target }
    }

    private var remaining: Double {
        max(totalNeeded - totalSetAside, 0)
    }

    private var progress: Double {
        guard totalNeeded > 0 else {
            return 0
        }

        return min(max(totalSetAside / totalNeeded, 0), 1)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                LabSetAsideFundingPageHeader(
                    title: "Upcoming Expenses",
                    countText: "\(expenses.count) upcoming expenses",
                    progressText: "\(Int((progress * 100).rounded()))% funded",
                    style: style
                )

                LabSetAsideFundingSummaryCard(
                    heading: "TOTAL SET ASIDE",
                    totalSetAside: totalSetAside,
                    totalTarget: totalNeeded,
                    targetDescription: "needed for upcoming expenses",
                    progress: progress,
                    remaining: remaining,
                    arcLabel: "toward expenses",
                    style: style
                ) {
                    EmptyView()
                }

                ForEach(expenses) { expense in
                    LabSetAsideFundingRow(
                        item: expense,
                        style: style
                    )
                }

                LabSetAsideCreateButton(
                    title: "Create Upcoming Expense",
                    style: style
                )
            }
            .padding(.vertical, AppSpacing.xxSmall)
            .padding(.bottom, AppSpacing.medium)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct LabSetAsideFundingItem: Identifiable {
    let title: String
    let target: Double
    let setAside: Double
    let detail: String
    let shortTitle: String
    let status: String

    var id: String { title }

    var progress: Double {
        guard target > 0 else {
            return 0
        }

        return min(max(setAside / target, 0), 1)
    }

    var remaining: Double {
        max(target - setAside, 0)
    }

    var isFunded: Bool {
        progress == 1
    }
}

private struct LabSetAsideFundingPageHeader: View {
    let title: String
    let countText: String
    let progressText: String
    let style: CalderaCategoryStyle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text(countText)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()

            Text(progressText)
                .font(.caption.weight(.bold))
                .foregroundColor(style.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LabSetAsideFundingSummaryCard<Supplement: View>: View {
    let heading: String
    let totalSetAside: Double
    let totalTarget: Double
    let targetDescription: String
    let progress: Double
    let remaining: Double
    let arcLabel: String
    let style: CalderaCategoryStyle
    private let supplement: Supplement

    init(
        heading: String,
        totalSetAside: Double,
        totalTarget: Double,
        targetDescription: String,
        progress: Double,
        remaining: Double,
        arcLabel: String,
        style: CalderaCategoryStyle,
        @ViewBuilder supplement: () -> Supplement
    ) {
        self.heading = heading
        self.totalSetAside = totalSetAside
        self.totalTarget = totalTarget
        self.targetDescription = targetDescription
        self.progress = progress
        self.remaining = remaining
        self.arcLabel = arcLabel
        self.style = style
        self.supplement = supplement()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(heading)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppColors.secondaryText)

                    Text(AppFormatters.currency(totalSetAside))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("of \(AppFormatters.currency(totalTarget)) \(targetDescription)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(2)

                    HStack(spacing: AppSpacing.small) {
                        LabSetAsideMetric(
                            title: "Progress",
                            value: "\(Int((progress * 100).rounded()))%"
                        )

                        LabSetAsideMetricDivider()

                        LabSetAsideMetric(
                            title: "Remaining",
                            value: AppFormatters.currency(remaining)
                        )
                    }
                    .padding(.top, AppSpacing.xxSmall)
                }

                Spacer(minLength: 0)

                LabSetAsideFundingArc(
                    progress: progress,
                    label: arcLabel,
                    style: style
                )
                .frame(width: 116, height: 116)
            }

            supplement
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.70,
            shadowOpacity: 0.04,
            shadowRadius: 14,
            shadowY: 7,
            darkGlowColor: style.primary
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(heading). \(AppFormatters.currency(totalSetAside)) set aside of \(AppFormatters.currency(totalTarget)). \(Int((progress * 100).rounded())) percent funded. \(AppFormatters.currency(remaining)) remaining."
        )
    }
}

private struct LabSetAsideFundingArc: View {
    let progress: Double
    let label: String
    let style: CalderaCategoryStyle

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(
                    style.primary.opacity(0.14),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.08, to: 0.08 + (0.84 * clampedProgress))
                .stroke(
                    LinearGradient(
                        colors: style.gradient,
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .shadow(color: style.primary.opacity(0.20), radius: 8, y: 4)

            VStack(spacing: 1) {
                Text("\(Int((clampedProgress * 100).rounded()))%")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()

                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((clampedProgress * 100).rounded())) percent \(label)")
    }
}

private struct LabSetAsidePaymentSegments: View {
    let payments: [LabSetAsideFundingItem]
    let style: CalderaCategoryStyle

    private let segmentSpacing: CGFloat = 3

    private var totalTarget: Double {
        payments.reduce(0) { $0 + $1.target }
    }

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(for: max(proxy.size.width, 1))

            VStack(spacing: 5) {
                HStack(spacing: segmentSpacing) {
                    ForEach(payments.indices, id: \.self) { index in
                        segment(for: payments[index])
                            .frame(width: widths[index], height: 9)
                    }
                }

                HStack(spacing: segmentSpacing) {
                    ForEach(payments.indices, id: \.self) { index in
                        label(for: payments[index], index: index)
                            .frame(
                                width: widths[index],
                                alignment: alignment(for: index)
                            )
                    }
                }
            }
        }
        .frame(height: 46)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            payments.map { payment in
                "\(payment.title), \(AppFormatters.currency(payment.target)) planned, \(AppFormatters.currency(payment.setAside)) set aside"
            }
            .joined(separator: ". ")
        )
    }

    private func segment(
        for payment: LabSetAsideFundingItem
    ) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AppColors.secondaryText.opacity(0.18))

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: style.gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * payment.progress)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AppColors.secondaryText.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func label(
        for payment: LabSetAsideFundingItem,
        index: Int
    ) -> some View {
        VStack(spacing: 1) {
            Text(AppFormatters.currency(payment.target))
                .font(.caption2.weight(.bold))
                .foregroundColor(style.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(payment.shortTitle)
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .multilineTextAlignment(textAlignment(for: index))
    }

    private func segmentWidths(for fullWidth: CGFloat) -> [CGFloat] {
        let totalSpacing = segmentSpacing * CGFloat(max(payments.count - 1, 0))
        let availableWidth = max(fullWidth - totalSpacing, 0)

        return payments.map { payment in
            guard totalTarget > 0 else {
                return 0
            }

            return availableWidth * (payment.target / totalTarget)
        }
    }

    private func alignment(for index: Int) -> Alignment {
        if payments.count == 1 || index == payments.count - 1 {
            return .trailing
        }

        return index == 0 ? .leading : .center
    }

    private func textAlignment(for index: Int) -> TextAlignment {
        if payments.count == 1 || index == payments.count - 1 {
            return .trailing
        }

        return index == 0 ? .leading : .center
    }
}

private struct LabSetAsideFundingRow: View {
    let item: LabSetAsideFundingItem
    let style: CalderaCategoryStyle

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .center, spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    style: style,
                    size: 34,
                    iconSize: 13
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Text(item.detail)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: AppSpacing.xSmall)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppFormatters.currency(item.target))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(style.primary)
                        .monospacedDigit()

                    Text(item.status)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(
                            item.isFunded
                                ? CalderaCategoryStyle.style(for: .covered).primary
                                : AppColors.secondaryText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            HStack(spacing: AppSpacing.small) {
                Text("\(AppFormatters.currency(item.setAside)) set aside")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .monospacedDigit()

                Spacer(minLength: AppSpacing.small)

                Text("\(AppFormatters.currency(item.remaining)) needed")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .monospacedDigit()
            }

            CalderaProgressBar(progress: item.progress, colors: style.gradient)
                .frame(height: 5)
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.80,
            strokeOpacity: 0.60,
            shadowOpacity: 0.012,
            shadowRadius: 8,
            shadowY: 3
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.title), \(item.status), \(AppFormatters.currency(item.target)), \(AppFormatters.currency(item.setAside)) set aside, \(AppFormatters.currency(item.remaining)) needed"
        )
    }
}

private struct LabSetAsideCreateButton: View {
    let title: String
    let style: CalderaCategoryStyle

    var body: some View {
        Button {
            // This Lab surface intentionally has no production action.
        } label: {
            Label(title, systemImage: "plus")
                .font(.subheadline.weight(.bold))
                .foregroundColor(style.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.medium)
                .background(
                    Capsule(style: .continuous)
                        .fill(style.primary.opacity(0.12))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(style.primary.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .padding(.top, AppSpacing.xxSmall)
        .accessibilityLabel("\(title) prototype")
    }
}

#endif
