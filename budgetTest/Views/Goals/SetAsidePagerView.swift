import SwiftUI

struct SetAsidePagerView: View {
    let snapshot: SetAsidePagerSnapshot
    let performDestination: (SetAsidePagerDestination) -> Void

    @State private var selectedSection: SetAsidePagerSection

    init(
        snapshot: SetAsidePagerSnapshot,
        initialSection: SetAsidePagerSection = .defaultSelection,
        performDestination: @escaping (SetAsidePagerDestination) -> Void
    ) {
        self.snapshot = snapshot
        self.performDestination = performDestination
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            sectionSelector
            pageDots

            TabView(selection: $selectedSection) {
                SetAsidePagerUpcomingPage(
                    snapshot: snapshot.upcomingExpenses,
                    performDestination: performDestination
                )
                .tag(SetAsidePagerSection.upcomingExpenses)

                SetAsidePagerPaymentsPage(
                    snapshot: snapshot.payments,
                    performDestination: performDestination
                )
                .tag(SetAsidePagerSection.paymentPlans)

                SetAsidePagerGoalsPage(
                    snapshot: snapshot.goals,
                    performDestination: performDestination
                )
                .tag(SetAsidePagerSection.savingsGoals)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sectionSelector: some View {
        HStack(spacing: AppSpacing.small) {
            ForEach(SetAsidePagerSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedSection = section
                    }
                } label: {
                    SetAsidePagerSectionButton(
                        section: section,
                        count: count(for: section),
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
            ForEach(SetAsidePagerSection.allCases) { section in
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
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedSection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(selectedSection.title) page, \(selectedSection.pageIndex) of \(SetAsidePagerSection.allCases.count)"
        )
    }

    private func count(
        for section: SetAsidePagerSection
    ) -> Int {
        switch section {
        case .upcomingExpenses:
            return snapshot.upcomingExpenses.allUpcomingOccurrenceCount
        case .paymentPlans:
            return snapshot.payments.activeCount
        case .savingsGoals:
            return snapshot.goals.activeCount
        }
    }
}

private extension SetAsidePagerSection {
    var title: String {
        switch self {
        case .upcomingExpenses:
            return "Upcoming"
        case .paymentPlans:
            return "Payments"
        case .savingsGoals:
            return "Goals"
        }
    }

    var systemImage: String {
        switch self {
        case .upcomingExpenses:
            return "calendar"
        case .paymentPlans:
            return "creditcard"
        case .savingsGoals:
            return "target"
        }
    }

    var style: CalderaCategoryStyle {
        switch self {
        case .upcomingExpenses:
            return CalderaCategoryStyle.style(for: .upcomingExpense)
        case .paymentPlans:
            return CalderaCategoryStyle.style(for: .debtPayoff)
        case .savingsGoals:
            return CalderaCategoryStyle.style(for: .savingsGoal)
        }
    }

    var pageIndex: Int {
        guard let index = Self.allCases.firstIndex(of: self) else {
            return 1
        }
        return index + 1
    }
}

private struct SetAsidePagerSectionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let section: SetAsidePagerSection
    let count: Int
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: section.systemImage)
                .font(.system(size: 14, weight: .bold))

            Text(section.title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .opacity(0.78)
        }
        .foregroundColor(isSelected ? .white : section.style.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background {
            RoundedRectangle(
                cornerRadius: AppRadii.field,
                style: .continuous
            )
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
            RoundedRectangle(
                cornerRadius: AppRadii.field,
                style: .continuous
            )
            .stroke(
                isSelected
                    ? Color.white.opacity(colorScheme == .dark ? 0.20 : 0.34)
                    : AppColors.secondaryText.opacity(0.14),
                lineWidth: 1
            )
        }
        .contentShape(
            RoundedRectangle(
                cornerRadius: AppRadii.field,
                style: .continuous
            )
        )
    }
}

private struct SetAsidePagerGoalsPage: View {
    let snapshot: SetAsidePagerGoalsSnapshot
    let performDestination: (SetAsidePagerDestination) -> Void

    private let style = CalderaCategoryStyle.style(for: .savingsGoal)

    var body: some View {
        SetAsidePagerPageScroll {
            SetAsidePagerSummaryCard(
                style: style,
                systemImage: "target",
                title: snapshot.title,
                primaryValue: AppFormatters.currency(snapshot.totalSaved),
                primaryLabel: "Total saved",
                progress: snapshot.progress,
                metrics: [
                    .init(label: "Active", value: "\(snapshot.activeCount)"),
                    .init(
                        label: "Target",
                        value: AppFormatters.currency(snapshot.totalTarget)
                    ),
                    .init(
                        label: "Remaining",
                        value: AppFormatters.currency(snapshot.remainingAmount)
                    )
                ]
            )

            if snapshot.isEmpty {
                SetAsidePagerEmptyCard(
                    snapshot: snapshot.emptyState,
                    style: style,
                    systemImage: "target"
                )
            } else {
                ForEach(snapshot.rows) { row in
                    SetAsidePagerItemButton(
                        style: style,
                        systemImage: "target",
                        title: row.title,
                        subtitle: "\(AppFormatters.currency(row.savedAmount)) saved of \(AppFormatters.currency(row.targetAmount))",
                        trailingValue: AppFormatters.currency(row.remainingAmount),
                        trailingLabel: "remaining",
                        progress: row.progress,
                        accessibilityLabel: row.accessibilityLabel
                    ) {
                        performDestination(row.contributeDestination)
                    }
                }
            }

            SetAsidePagerPageActions(
                createTitle: "Create Savings Goal",
                seeAllTitle: "See all Goals",
                style: style,
                createAction: {
                    performDestination(snapshot.createDestination)
                },
                seeAllAction: {
                    performDestination(snapshot.seeAllDestination)
                }
            )
        }
        .accessibilityLabel(snapshot.accessibilityLabel)
    }
}

private struct SetAsidePagerPaymentsPage: View {
    let snapshot: SetAsidePagerPaymentsSnapshot
    let performDestination: (SetAsidePagerDestination) -> Void

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    var body: some View {
        SetAsidePagerPageScroll {
            SetAsidePagerSummaryCard(
                style: style,
                systemImage: "creditcard.fill",
                title: snapshot.title,
                primaryValue: AppFormatters.currency(snapshot.totalSetAside),
                primaryLabel: "Set aside",
                progress: snapshot.progress,
                metrics: [
                    .init(label: "Active", value: "\(snapshot.activeCount)"),
                    .init(
                        label: "Planned",
                        value: AppFormatters.currency(snapshot.totalPlanned)
                    ),
                    .init(
                        label: "Remaining",
                        value: AppFormatters.currency(snapshot.remainingAmount)
                    )
                ],
                segments: snapshot.segments
            )

            if snapshot.isEmpty {
                SetAsidePagerEmptyCard(
                    snapshot: snapshot.emptyState,
                    style: style,
                    systemImage: "creditcard.fill"
                )
            } else {
                ForEach(snapshot.rows) { row in
                    SetAsidePagerItemButton(
                        style: style,
                        systemImage: row.editor == .modernCard
                            ? "creditcard.fill"
                            : "banknote.fill",
                        title: row.title,
                        subtitle: "Due \(AppFormatters.abbreviatedMonthDay(row.dueDate)) · \(row.targetBasis)",
                        trailingValue: AppFormatters.currency(row.remainingAmount),
                        trailingLabel: "remaining",
                        progress: row.progress,
                        accessibilityLabel: row.accessibilityLabel
                    ) {
                        performDestination(row.contributeDestination)
                    }
                }
            }

            SetAsidePagerPageActions(
                createTitle: "Create Payment Plan",
                seeAllTitle: "See all Payments",
                style: style,
                createAction: {
                    performDestination(snapshot.createDestination)
                },
                seeAllAction: {
                    performDestination(snapshot.seeAllDestination)
                }
            )
        }
        .accessibilityLabel(snapshot.accessibilityLabel)
    }
}

private struct SetAsidePagerUpcomingPage: View {
    let snapshot: SetAsidePagerUpcomingSnapshot
    let performDestination: (SetAsidePagerDestination) -> Void

    private let style = CalderaCategoryStyle.style(for: .upcomingExpense)

    var body: some View {
        SetAsidePagerPageScroll {
            SetAsidePagerSummaryCard(
                style: style,
                systemImage: "calendar",
                title: snapshot.title,
                primaryValue: AppFormatters.currency(snapshot.totalSetAside),
                primaryLabel: snapshot.summaryLabel,
                progress: snapshot.progress,
                metrics: [
                    .init(
                        label: "Upcoming",
                        value: "\(snapshot.allUpcomingOccurrenceCount)"
                    ),
                    .init(
                        label: "Needed",
                        value: AppFormatters.currency(snapshot.totalNeeded)
                    ),
                    .init(
                        label: "Remaining",
                        value: AppFormatters.currency(snapshot.remainingAmount)
                    )
                ]
            )

            if snapshot.isEmpty {
                SetAsidePagerEmptyCard(
                    snapshot: snapshot.emptyState,
                    style: style,
                    systemImage: "calendar"
                )
            } else {
                ForEach(snapshot.rows) { row in
                    SetAsidePagerItemButton(
                        style: style,
                        systemImage: "calendar",
                        title: row.title,
                        subtitle: "Due \(AppFormatters.abbreviatedMonthDay(row.occurrenceDate)) · \(row.recurrence)",
                        trailingValue: AppFormatters.currency(row.remainingAmount),
                        trailingLabel: "remaining",
                        progress: row.progress,
                        accessibilityLabel: row.accessibilityLabel
                    ) {
                        performDestination(row.contributeDestination)
                    }
                }
            }

            SetAsidePagerPageActions(
                createTitle: "Create Upcoming Expense",
                seeAllTitle: "See all Upcoming",
                style: style,
                createAction: {
                    performDestination(snapshot.createDestination)
                },
                seeAllAction: {
                    performDestination(snapshot.seeAllDestination)
                }
            )
        }
        .accessibilityLabel(snapshot.accessibilityLabel)
    }
}

private struct SetAsidePagerPageScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                content()
            }
            .padding(.vertical, AppSpacing.xxSmall)
            .padding(.bottom, AppSpacing.floatingTabClearance)
        }
        .scrollContentBackground(.hidden)
    }
}

struct SetAsidePagerCashCushionCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: SetAsidePagerCashCushionSnapshot
    let performDestination: (SetAsidePagerDestination) -> Void

    private let style = CalderaCategoryStyle.style(for: .reserve)

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: style,
                size: 36,
                iconSize: 15
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(snapshot.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(
                        CalderaVisualStyle.primaryText(colorScheme)
                    )

                Text("\(AppFormatters.currency(snapshot.currentAmount)) set aside")
                    .font(.headline.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: AppSpacing.xSmall)

            HStack(spacing: AppSpacing.xSmall) {
                if let useDestination = snapshot.useDestination {
                    adjustmentButton(
                        systemImage: "minus",
                        accessibilityLabel: "Use Cash Cushion"
                    ) {
                        performDestination(useDestination)
                    }
                }

                adjustmentButton(
                    systemImage: "plus",
                    accessibilityLabel: "Add to Cash Cushion"
                ) {
                    performDestination(snapshot.addDestination)
                }
            }
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.78,
            strokeOpacity: 0.58,
            shadowOpacity: 0.018,
            shadowRadius: 9,
            shadowY: 4,
            darkGlowColor: style.primary
        )
        .accessibilityElement(children: .contain)
    }

    private func adjustmentButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(style.primary)
                .frame(width: 34, height: 34)
                .background(style.primary.opacity(0.11), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private struct SetAsidePagerMetric: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

private struct SetAsidePagerSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let style: CalderaCategoryStyle
    let systemImage: String
    let title: String
    let primaryValue: String
    let primaryLabel: String
    let progress: Double
    let metrics: [SetAsidePagerMetric]
    var segments: [SetAsidePagerPaymentSegmentSnapshot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    systemImage: systemImage,
                    colors: style.gradient,
                    size: 36,
                    iconSize: 15
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundColor(
                            CalderaVisualStyle.primaryText(colorScheme)
                        )

                    Text(primaryLabel)
                        .font(.caption)
                        .foregroundColor(
                            CalderaVisualStyle.secondaryText(colorScheme)
                        )
                }

                Spacer(minLength: AppSpacing.small)

                Text(primaryValue)
                    .font(.title3.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if segments.isEmpty {
                CalderaProgressBar(
                    progress: progress,
                    colors: style.gradient
                )
                .frame(height: 8)
            } else {
                SetAsidePagerPaymentSegments(
                    segments: segments,
                    style: style
                )
            }

            HStack(alignment: .top, spacing: AppSpacing.small) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label)
                            .font(.caption2)
                            .foregroundColor(
                                CalderaVisualStyle.secondaryText(colorScheme)
                            )

                        Text(metric.value)
                            .font(.caption.weight(.bold))
                            .foregroundColor(
                                CalderaVisualStyle.primaryText(colorScheme)
                            )
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.82,
            strokeOpacity: 0.58,
            shadowOpacity: 0.025,
            shadowRadius: 12,
            shadowY: 5,
            darkGlowColor: style.primary
        )
    }
}

private struct SetAsidePagerPaymentSegments: View {
    let segments: [SetAsidePagerPaymentSegmentSnapshot]
    let style: CalderaCategoryStyle

    private var totalTarget: Double {
        segments.reduce(0) { $0 + max($1.targetAmount, 0) }
    }

    var body: some View {
        GeometryReader { proxy in
            let gap = CGFloat(max(segments.count - 1, 0)) * 3
            let width = max(proxy.size.width - gap, 0)

            HStack(spacing: 3) {
                ForEach(segments) { segment in
                    SetAsidePagerPaymentSegment(
                        progress: segment.progress,
                        style: style
                    )
                    .frame(
                        width: segmentWidth(
                            segment,
                            availableWidth: width
                        )
                    )
                }
            }
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }

    private func segmentWidth(
        _ segment: SetAsidePagerPaymentSegmentSnapshot,
        availableWidth: CGFloat
    ) -> CGFloat {
        guard totalTarget > 0 else {
            return 0
        }

        return availableWidth * CGFloat(
            max(segment.targetAmount, 0) / totalTarget
        )
    }
}

private struct SetAsidePagerPaymentSegment: View {
    @Environment(\.colorScheme) private var colorScheme

    let progress: Double
    let style: CalderaCategoryStyle

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CalderaVisualStyle.progressTrack(colorScheme))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: style.gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: proxy.size.width * CGFloat(
                            clampedProgressValue(progress)
                        )
                    )
            }
        }
    }
}

private struct SetAsidePagerItemButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let style: CalderaCategoryStyle
    let systemImage: String
    let title: String
    let subtitle: String
    let trailingValue: String
    let trailingLabel: String
    let progress: Double
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.small) {
                HStack(spacing: AppSpacing.small) {
                    CalderaGradientIcon(
                        systemImage: systemImage,
                        colors: style.gradient,
                        size: 32,
                        iconSize: 13
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(
                                CalderaVisualStyle.primaryText(colorScheme)
                            )
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(
                                CalderaVisualStyle.secondaryText(colorScheme)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }

                    Spacer(minLength: AppSpacing.xSmall)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(trailingValue)
                            .font(.caption.weight(.bold))
                            .foregroundColor(style.primary)
                            .monospacedDigit()

                        Text(trailingLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(
                                CalderaVisualStyle.secondaryText(colorScheme)
                            )
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(style.primary.opacity(0.72))
                }

                CalderaProgressBar(
                    progress: progress,
                    colors: style.gradient
                )
                .frame(height: 5)
            }
            .padding(AppSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.76,
                strokeOpacity: 0.52,
                shadowOpacity: 0.015,
                shadowRadius: 8,
                shadowY: 3,
                darkGlowColor: style.primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens Set Aside update")
    }
}

private struct SetAsidePagerEmptyCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: SetAsidePagerEmptyStateSnapshot
    let style: CalderaCategoryStyle
    let systemImage: String

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: style.gradient,
                size: 34,
                iconSize: 14
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(snapshot.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(
                        CalderaVisualStyle.primaryText(colorScheme)
                    )

                Text(snapshot.detail)
                    .font(.caption)
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.74,
            strokeOpacity: 0.50,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: style.primary
        )
    }
}

private struct SetAsidePagerPageActions: View {
    let createTitle: String
    let seeAllTitle: String
    let style: CalderaCategoryStyle
    let createAction: () -> Void
    let seeAllAction: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.small) {
                seeAllButton
                createButton
            }

            VStack(spacing: AppSpacing.small) {
                createButton
                seeAllButton
            }
        }
        .padding(.top, AppSpacing.xSmall)
    }

    private var createButton: some View {
        Button(action: createAction) {
            Label(createTitle, systemImage: "plus")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
                .background(
                    LinearGradient(
                        colors: style.gradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var seeAllButton: some View {
        Button(action: seeAllAction) {
            HStack(spacing: AppSpacing.xxSmall) {
                Text(seeAllTitle)
                Image(systemName: "chevron.right")
            }
            .font(.caption.weight(.bold))
            .foregroundColor(style.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small)
            .background(style.primary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
