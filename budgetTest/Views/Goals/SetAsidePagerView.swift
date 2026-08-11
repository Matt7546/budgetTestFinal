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
            .animation(.easeInOut(duration: 0.22), value: selectedSection)

            pageDots
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sectionSelector: some View {
        HStack(spacing: AppSpacing.small) {
            ForEach(SetAsidePagerSection.allCases) { section in
                Button {
                    withAnimation(
                        .spring(response: 0.32, dampingFraction: 0.86)
                    ) {
                        selectedSection = section
                    }
                } label: {
                    SetAsidePagerSectionButton(
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
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: section.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(
                    isSelected ? .white : section.style.primary
                )

            Text(section.title)
                .font(.caption2.weight(.bold))
                .foregroundColor(
                    isSelected ? .white : AppColors.primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
        .shadow(
            color: isSelected
                ? section.style.primary.opacity(0.20)
                : .clear,
            radius: 10,
            y: 5
        )
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
            SetAsidePagerPageHeader(
                title: snapshot.title,
                countText: "\(snapshot.activeCount) active goal\(snapshot.activeCount == 1 ? "" : "s")",
                progress: snapshot.progress,
                style: style,
                seeAllAction: {
                    performDestination(snapshot.seeAllDestination)
                }
            )

            SetAsidePagerFundingSummaryCard(
                heading: "TOTAL SAVED",
                totalSetAside: snapshot.totalSaved,
                totalTarget: snapshot.totalTarget,
                targetDescription: "across your goals",
                progress: snapshot.progress,
                remaining: snapshot.remainingAmount,
                arcLabel: "toward goals",
                style: style,
                accessibilityLabel: snapshot.accessibilityLabel
            ) {
                EmptyView()
            }

            if snapshot.isEmpty {
                SetAsidePagerEmptyCard(
                    snapshot: snapshot.emptyState,
                    style: style,
                    systemImage: "target"
                )
            } else {
                ForEach(snapshot.rows) { row in
                    SetAsidePagerGoalRow(
                        row: row,
                        style: style
                    ) {
                        performDestination(row.contributeDestination)
                    }
                }
            }

            SetAsidePagerCreateButton(
                title: "Create Savings Goal",
                style: style,
                action: {
                    performDestination(snapshot.createDestination)
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
            SetAsidePagerPageHeader(
                title: snapshot.title,
                countText: "\(snapshot.activeCount) active payment plan\(snapshot.activeCount == 1 ? "" : "s")",
                progress: snapshot.progress,
                style: style,
                seeAllAction: {
                    performDestination(snapshot.seeAllDestination)
                }
            )

            SetAsidePagerFundingSummaryCard(
                heading: "TOTAL SET ASIDE",
                totalSetAside: snapshot.totalSetAside,
                totalTarget: snapshot.totalPlanned,
                targetDescription: "planned across payment plans",
                progress: snapshot.progress,
                remaining: snapshot.remainingAmount,
                arcLabel: "toward payments",
                style: style,
                accessibilityLabel: snapshot.accessibilityLabel
            ) {
                if !snapshot.segments.isEmpty {
                    SetAsidePagerPaymentSegments(
                        segments: snapshot.segments,
                        style: style
                    )
                }
            }

            if snapshot.isEmpty {
                SetAsidePagerEmptyCard(
                    snapshot: snapshot.emptyState,
                    style: style,
                    systemImage: "creditcard.fill"
                )
            } else {
                ForEach(snapshot.rows) { row in
                    SetAsidePagerFundingRow(
                        style: style,
                        systemImage: row.editor == .modernCard
                            ? "creditcard.fill"
                            : "banknote.fill",
                        title: row.title,
                        detail: "Due \(AppFormatters.abbreviatedMonthDay(row.dueDate)) · \(row.targetBasis)",
                        target: row.plannedAmount,
                        setAside: row.setAsideAmount,
                        remaining: row.remainingAmount,
                        progress: row.progress,
                        status: row.status,
                        accessibilityLabel: row.accessibilityLabel
                    ) {
                        performDestination(row.contributeDestination)
                    }
                }
            }

            SetAsidePagerCreateButton(
                title: "Create Payment Plan",
                style: style,
                action: {
                    performDestination(snapshot.createDestination)
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
            SetAsidePagerPageHeader(
                title: snapshot.title,
                countText: snapshot.summaryLabel,
                progress: snapshot.progress,
                style: style,
                seeAllAction: {
                    performDestination(snapshot.seeAllDestination)
                }
            )

            SetAsidePagerFundingSummaryCard(
                heading: "TOTAL SET ASIDE",
                totalSetAside: snapshot.totalSetAside,
                totalTarget: snapshot.totalNeeded,
                targetDescription: "needed for upcoming expenses",
                progress: snapshot.progress,
                remaining: snapshot.remainingAmount,
                arcLabel: "toward expenses",
                style: style,
                accessibilityLabel: snapshot.accessibilityLabel
            ) {
                EmptyView()
            }

            if snapshot.isEmpty {
                SetAsidePagerEmptyCard(
                    snapshot: snapshot.emptyState,
                    style: style,
                    systemImage: "calendar"
                )
            } else {
                ForEach(snapshot.rows) { row in
                    SetAsidePagerFundingRow(
                        style: style,
                        systemImage: "calendar",
                        title: row.title,
                        detail: "Due \(AppFormatters.abbreviatedMonthDay(row.occurrenceDate)) · \(row.recurrence)",
                        target: row.amountNeeded,
                        setAside: row.setAsideAmount,
                        remaining: row.remainingAmount,
                        progress: row.progress,
                        status: fundingStatus(
                            remaining: row.remainingAmount,
                            target: row.amountNeeded
                        ),
                        accessibilityLabel: row.accessibilityLabel
                    ) {
                        performDestination(row.contributeDestination)
                    }
                }
            }

            SetAsidePagerCreateButton(
                title: "Create Upcoming Expense",
                style: style,
                action: {
                    performDestination(snapshot.createDestination)
                }
            )
        }
        .accessibilityLabel(snapshot.accessibilityLabel)
    }

    private func fundingStatus(
        remaining: Double,
        target: Double
    ) -> String {
        if remaining <= 0.005 {
            return "Funded"
        }

        if remaining >= target - 0.005 {
            return "Not funded"
        }

        return "Needs \(AppFormatters.currency(remaining))"
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
        .scrollBounceBehavior(.basedOnSize)
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

private struct SetAsidePagerPageHeader: View {
    let title: String
    let countText: String
    let progress: Double
    let style: CalderaCategoryStyle
    let seeAllAction: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text(countText)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: AppSpacing.xSmall)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int((clampedProgressValue(progress) * 100).rounded()))% funded")
                    .font(.caption.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()

                Button(action: seeAllAction) {
                    HStack(spacing: 3) {
                        Text("See all")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(style.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all \(title)")
            }
        }
    }
}

private struct SetAsidePagerSummaryMetric: View {
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

private struct SetAsidePagerSummaryMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.secondaryText.opacity(0.16))
            .frame(width: 1, height: 28)
    }
}

private struct SetAsidePagerFundingSummaryCard<Supplement: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let heading: String
    let totalSetAside: Double
    let totalTarget: Double
    let targetDescription: String
    let progress: Double
    let remaining: Double
    let arcLabel: String
    let style: CalderaCategoryStyle
    let accessibilityLabel: String
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
        accessibilityLabel: String,
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
        self.accessibilityLabel = accessibilityLabel
        self.supplement = supplement()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            if dynamicTypeSize.isAccessibilitySize {
                verticalSummary
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalSummary
                    verticalSummary
                }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var horizontalSummary: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            summaryDetails
                .layoutPriority(1)

            Spacer(minLength: 0)

            progressArc
        }
    }

    private var verticalSummary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            summaryDetails

            progressArc
                .frame(maxWidth: .infinity)
        }
    }

    private var summaryDetails: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(heading)
                .font(.caption2.weight(.bold))
                .foregroundColor(AppColors.secondaryText)

            Text(AppFormatters.currency(totalSetAside))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(
                "of \(AppFormatters.currency(totalTarget)) " +
                    targetDescription
            )
            .font(.caption.weight(.medium))
            .foregroundColor(AppColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.small) {
                SetAsidePagerSummaryMetric(
                    title: "Progress",
                    value: "\(Int((clampedProgressValue(progress) * 100).rounded()))%"
                )

                SetAsidePagerSummaryMetricDivider()

                SetAsidePagerSummaryMetric(
                    title: "Remaining",
                    value: AppFormatters.currency(remaining)
                )
            }
            .padding(.top, AppSpacing.xxSmall)
        }
    }

    private var progressArc: some View {
        SetAsidePagerFundingArc(
            progress: progress,
            label: arcLabel,
            style: style
        )
        .frame(width: 116, height: 116)
    }
}

private struct SetAsidePagerFundingArc: View {
    let progress: Double
    let label: String
    let style: CalderaCategoryStyle

    private var clampedProgress: Double {
        clampedProgressValue(progress)
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
                .shadow(
                    color: style.primary.opacity(0.20),
                    radius: 8,
                    y: 4
                )

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
        .accessibilityLabel(
            "\(Int((clampedProgress * 100).rounded())) percent \(label)"
        )
    }
}

private struct SetAsidePagerPaymentSegments: View {
    let segments: [SetAsidePagerPaymentSegmentSnapshot]
    let style: CalderaCategoryStyle

    private let segmentSpacing: CGFloat = 3

    private var totalTarget: Double {
        segments.reduce(0) { $0 + max($1.targetAmount, 0) }
    }

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(for: max(proxy.size.width, 1))

            VStack(spacing: 5) {
                HStack(spacing: segmentSpacing) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        SetAsidePagerPaymentSegment(
                            progress: segment.progress,
                            style: style
                        )
                        .frame(width: widths[index], height: 9)
                    }
                }

                HStack(spacing: segmentSpacing) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        label(for: segment, index: index)
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
            segments.map { segment in
                "\(segment.title), \(AppFormatters.currency(segment.targetAmount)) planned, \(AppFormatters.currency(segment.setAsideAmount)) set aside"
            }
            .joined(separator: ". ")
        )
    }

    private func label(
        for segment: SetAsidePagerPaymentSegmentSnapshot,
        index: Int
    ) -> some View {
        VStack(spacing: 1) {
            Text(AppFormatters.currency(segment.targetAmount))
                .font(.caption2.weight(.bold))
                .foregroundColor(style.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(segment.title)
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .multilineTextAlignment(textAlignment(for: index))
    }

    private func segmentWidths(for fullWidth: CGFloat) -> [CGFloat] {
        let totalSpacing = segmentSpacing * CGFloat(max(segments.count - 1, 0))
        let availableWidth = max(fullWidth - totalSpacing, 0)

        guard totalTarget > 0 else {
            let equalWidth = segments.isEmpty
                ? 0
                : availableWidth / CGFloat(segments.count)
            return Array(repeating: equalWidth, count: segments.count)
        }

        return segments.map { segment in
            availableWidth * CGFloat(
                max(segment.targetAmount, 0) / totalTarget
            )
        }
    }

    private func alignment(for index: Int) -> Alignment {
        guard segments.count > 1 else {
            return .center
        }

        if index == segments.count - 1 {
            return .trailing
        }

        return index == 0 ? .leading : .center
    }

    private func textAlignment(for index: Int) -> TextAlignment {
        guard segments.count > 1 else {
            return .center
        }

        if index == segments.count - 1 {
            return .trailing
        }

        return index == 0 ? .leading : .center
    }
}

private struct SetAsidePagerPaymentSegment: View {
    @Environment(\.colorScheme) private var colorScheme

    let progress: Double
    let style: CalderaCategoryStyle

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(CalderaVisualStyle.progressTrack(colorScheme))

                RoundedRectangle(cornerRadius: 4, style: .continuous)
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
            .clipShape(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        AppColors.secondaryText.opacity(0.12),
                        lineWidth: 1
                    )
            }
        }
    }
}

private struct SetAsidePagerGoalRow: View {
    let row: SetAsidePagerGoalRowSnapshot
    let style: CalderaCategoryStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                HStack(alignment: .center, spacing: AppSpacing.small) {
                    CalderaGradientIcon(
                        style: style,
                        size: 34,
                        iconSize: 13
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)

                        Text("\(AppFormatters.currency(row.savedAmount)) saved of \(AppFormatters.currency(row.targetAmount))")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(AppColors.secondaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                    }

                    Spacer(minLength: AppSpacing.xSmall)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(Int((clampedProgressValue(row.progress) * 100).rounded()))%")
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

                CalderaProgressBar(
                    progress: row.progress,
                    colors: style.gradient
                )
                .frame(height: 5)

                Text(
                    row.remainingAmount <= 0.005
                        ? "Goal funded"
                        : "\(AppFormatters.currency(row.remainingAmount)) remaining"
                )
                .font(.caption2.weight(.medium))
                .foregroundColor(
                    row.remainingAmount <= 0.005
                        ? CalderaCategoryStyle.style(for: .covered).primary
                        : AppColors.secondaryText
                )
                .monospacedDigit()
            }
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.80,
                strokeOpacity: 0.60,
                shadowOpacity: 0.012,
                shadowRadius: 8,
                shadowY: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityHint("Opens Set Aside update")
    }
}

private struct SetAsidePagerFundingRow: View {
    let style: CalderaCategoryStyle
    let systemImage: String
    let title: String
    let detail: String
    let target: Double
    let setAside: Double
    let remaining: Double
    let progress: Double
    let status: String
    let accessibilityLabel: String
    let action: () -> Void

    private var isFunded: Bool {
        remaining <= 0.005
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                HStack(alignment: .center, spacing: AppSpacing.small) {
                    CalderaGradientIcon(
                        systemImage: systemImage,
                        colors: style.gradient,
                        size: 34,
                        iconSize: 13
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)

                        Text(detail)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer(minLength: AppSpacing.xSmall)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(AppFormatters.currency(target))
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(style.primary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(status)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(
                                isFunded
                                    ? CalderaCategoryStyle.style(for: .covered).primary
                                    : AppColors.secondaryText
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }

                HStack(spacing: AppSpacing.small) {
                    Text("\(AppFormatters.currency(setAside)) set aside")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .monospacedDigit()

                    Spacer(minLength: AppSpacing.small)

                    Text("\(AppFormatters.currency(remaining)) needed")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .monospacedDigit()
                }

                CalderaProgressBar(progress: progress, colors: style.gradient)
                    .frame(height: 5)
            }
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.80,
                strokeOpacity: 0.60,
                shadowOpacity: 0.012,
                shadowRadius: 8,
                shadowY: 3
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

private struct SetAsidePagerCreateButton: View {
    let title: String
    let style: CalderaCategoryStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .padding(.top, AppSpacing.xSmall)
        .accessibilityLabel(title)
    }
}
