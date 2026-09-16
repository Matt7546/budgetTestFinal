import SwiftUI
import UIKit

struct PlanAheadAtmosphericBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.025, green: 0.045, blue: 0.10),
                        Color(red: 0.045, green: 0.08, blue: 0.16),
                        Color(red: 0.025, green: 0.04, blue: 0.09)
                    ]
                    : [
                        Color(red: 0.94, green: 0.97, blue: 1.00),
                        Color(red: 0.90, green: 0.94, blue: 0.99),
                        Color(red: 0.96, green: 0.98, blue: 1.00)
                    ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    AppColors.accent.opacity(colorScheme == .dark ? 0.18 : 0.10),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct PlanAheadPlanningOutlookView: View {
    @Binding var horizon: PlanAheadSummaryHorizon
    let presentation: PlanAheadSummaryPresentation
    let onReviewPastDue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLANNING OUTLOOK")
                        .font(.caption2.weight(.heavy))
                        .tracking(1)
                        .foregroundStyle(AppColors.accent)

                    Text(horizon.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                }

                Spacer(minLength: AppSpacing.small)

                Picker("Summary period", selection: $horizon) {
                    ForEach(PlanAheadSummaryHorizon.allCases) { option in
                        Text(option.shortTitle).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 136)
                .accessibilityLabel("Planning Outlook period")
                .accessibilityValue(horizon.title)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    metric("Due", presentation.dueSoonValue, AppColors.primaryText)
                    metric(
                        "Still Needed",
                        presentation.stillNeededValue,
                        PlanAheadVisualPalette.attention
                    )
                    metric(
                        "Covered",
                        presentation.coveredValue,
                        PlanAheadVisualPalette.covered
                    )
                }

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    metric("Due", presentation.dueSoonValue, AppColors.primaryText)
                    HStack(spacing: AppSpacing.medium) {
                        metric(
                            "Still Needed",
                            presentation.stillNeededValue,
                            PlanAheadVisualPalette.attention
                        )
                        metric(
                            "Covered",
                            presentation.coveredValue,
                            PlanAheadVisualPalette.covered
                        )
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .sensitiveAccessibilityLabel(presentation.accessibilitySummary)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                SensitiveValueText(presentation.detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AppSpacing.small)

                if presentation.pastDueCount > 0 {
                    Button("Review Past Due", action: onReviewPastDue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PlanAheadVisualPalette.pastDue)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(AppSpacing.medium)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.accent.opacity(0.09))
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(AppColors.accent.opacity(0.70))
                .frame(width: 3, height: 42)
                .padding(.leading, AppSpacing.xSmall)
        }
    }

    private func metric(
        _ label: String,
        _ value: String,
        _ color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SensitiveValueText(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlanAheadPresentationSelector: View {
    @Binding var selection: PlanAheadPresentationMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PlanAheadPresentationMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode == .cards ? "square.grid.2x2" : "list.bullet")
                        Text(mode.title)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        selection == mode
                            ? AppColors.primaryText
                            : AppColors.secondaryText
                    )
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.small)
                    .background {
                        if selection == mode {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.42))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(AppColors.accent.opacity(0.14), lineWidth: 1)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppColors.accent.opacity(0.08), in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan Ahead presentation")
    }
}

enum PlanAheadScrollAnchor: Hashable {
    case pastDue
}

struct PlanAheadListPresentation: View {
    let composition: PlanAheadProductionComposition
    let onSelect: (PlanAheadPresentedEvent) -> Void
    let onEditExpectedIncome: (PlanAheadExpectedIncomeUpdate) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .id(PlanAheadScrollAnchor.pastDue)

            if !composition.pastDueObligations.isEmpty {
                sectionHeader(
                    title: "Past Due",
                    count: composition.pastDueObligations.count,
                    color: PlanAheadVisualPalette.pastDue,
                    subtitle: "Still open before today."
                )
                .padding(.top, AppSpacing.medium)

                PlanAheadTimelineTrack(
                    days: composition.groupedPastDue(),
                    isPastDue: true,
                    onSelect: onSelect
                )
                .padding(.top, AppSpacing.medium)
            }

            todayAnchor

            if let update = composition.expectedIncomeUpdate {
                PlanAheadExpectedIncomeUpdateCard(update: update) {
                    onEditExpectedIncome(update)
                }
                .padding(.leading, PlanAheadTimelineAxis.railWidth)
                .padding(.bottom, AppSpacing.large)
            }

            if composition.upcomingObligations.isEmpty && composition.incoming.isEmpty {
                emptyState
            } else {
                Text("Ahead")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                    .padding(.bottom, AppSpacing.medium)

                PlanAheadTimelineTrack(
                    days: composition.groupedUpcomingIncludingIncome(),
                    isPastDue: false,
                    onSelect: onSelect
                )
            }
        }
    }

    private func sectionHeader(
        title: String,
        count: Int,
        color: Color,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)

                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.13), in: Capsule())
            }

            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.secondaryText)
        }
    }

    private var todayAnchor: some View {
        HStack(alignment: .center, spacing: 0) {
            PlanAheadAxisMarker(color: AppColors.accent, diameter: 12)
                .frame(width: PlanAheadTimelineAxis.railWidth)
                .zIndex(1)

            HStack(spacing: AppSpacing.medium) {
                Rectangle()
                    .fill(AppColors.accent.opacity(0.35))
                    .frame(height: 1)

                VStack(spacing: 2) {
                    Text("TODAY")
                        .font(.caption2.weight(.heavy))
                        .tracking(1)
                        .foregroundStyle(AppColors.accent)
                    Text(Date().formatted(.dateTime.weekday(.abbreviated).day()))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.primaryText)
                }
                .padding(.horizontal, AppSpacing.small)

                Rectangle()
                    .fill(AppColors.accent.opacity(0.35))
                    .frame(height: 1)
            }
        }
        .padding(.vertical, AppSpacing.large)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Today, \(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))"
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("No Upcoming Expenses or Payment Plans are scheduled after today.")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
            Text("Add an Upcoming Expense or Payment Plan to keep it visible here.")
                .font(.subheadline)
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(.leading, PlanAheadTimelineAxis.railWidth)
        .padding(.top, AppSpacing.medium)
    }
}

struct PlanAheadCardsPresentation: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let composition: PlanAheadProductionComposition
    let today: Date
    let onSelect: (PlanAheadPresentedEvent) -> Void
    let onEditExpectedIncome: (PlanAheadExpectedIncomeUpdate) -> Void

    private let calendar = Calendar.current

    var body: some View {
        LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
            if !composition.pastDueObligations.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                        Text("Past Due")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(PlanAheadVisualPalette.pastDue)
                        Text("\(composition.pastDueObligations.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PlanAheadVisualPalette.pastDue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                PlanAheadVisualPalette.pastDue.opacity(0.13),
                                in: Capsule()
                            )
                        Spacer()
                        Text("Needs attention")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PlanAheadVisualPalette.pastDue)
                    }

                    obligationGrid(composition.pastDueObligations)
                }
            }

            if composition.upcomingObligations.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("No Upcoming Expenses or Payment Plans are scheduled after today.")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.primaryText)
                    Text("Add an Upcoming Expense or Payment Plan to keep it visible here.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.secondaryText)
                }
            } else {
                ForEach(composition.upcomingMonths(calendar: calendar)) { month in
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        HStack(spacing: AppSpacing.small) {
                            Text(month.title(relativeTo: today, calendar: calendar))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(AppColors.primaryText)
                            Rectangle()
                                .fill(AppColors.accent.opacity(0.22))
                                .frame(height: 1)
                        }

                        obligationGrid(month.items)
                    }
                }
            }

            if !composition.incoming.isEmpty || composition.expectedIncomeUpdate != nil {
                PlanAheadIncomingSection(
                    items: composition.incoming,
                    update: composition.expectedIncomeUpdate,
                    onSelect: onSelect,
                    onEditUpdate: onEditExpectedIncome
                )
            }
        }
    }

    private var columns: [GridItem] {
        if PlanAheadCardLayout.columnCount(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        ) == 1 {
            return [GridItem(.flexible())]
        }

        return [
            GridItem(.flexible(), spacing: AppSpacing.small),
            GridItem(.flexible(), spacing: AppSpacing.small)
        ]
    }

    private func obligationGrid(
        _ items: [PlanAheadPresentedEvent]
    ) -> some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.small) {
            ForEach(items) { item in
                PlanAheadObligationCard(item: item) {
                    onSelect(item)
                }
            }
        }
    }
}

private struct PlanAheadIncomingSection: View {
    let items: [PlanAheadPresentedEvent]
    let update: PlanAheadExpectedIncomeUpdate?
    let onSelect: (PlanAheadPresentedEvent) -> Void
    let onEditUpdate: (PlanAheadExpectedIncomeUpdate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                Text("Incoming")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                Spacer()
                Text("Planning only")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)
            }

            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: AppSpacing.small) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(PlanAheadVisualPalette.income)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("EXPECTED INCOME")
                                .font(.caption2.weight(.heavy))
                                .tracking(0.6)
                                .foregroundStyle(PlanAheadVisualPalette.income)
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.primaryText)
                            Text("Not included in Available to Spend until it arrives.")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(AppColors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: AppSpacing.small)

                        VStack(alignment: .trailing, spacing: 2) {
                            SensitiveValueText(item.amountValue)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppColors.primaryText)
                                .monospacedDigit()
                            Text(item.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(PlanAheadVisualPalette.income)
                        }
                    }
                    .padding(AppSpacing.medium)
                    .background {
                        PlanAheadTintedSurface(
                            accent: PlanAheadVisualPalette.income,
                            cornerRadius: 18
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .sensitiveAccessibilityLabel(
                    "Expected income, \(item.title), \(item.amountValue), \(item.date.formatted(.dateTime.month(.wide).day())). Planning only. Not included in Available to Spend until it arrives."
                )
                .accessibilityHint("Edits expected income.")
            }

            if let update {
                PlanAheadExpectedIncomeUpdateCard(update: update) {
                    onEditUpdate(update)
                }
            }
        }
    }
}

private struct PlanAheadExpectedIncomeUpdateCard: View {
    let update: PlanAheadExpectedIncomeUpdate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PlanAheadVisualPalette.income)
                    .frame(width: 28, height: 28)
                    .background(
                        PlanAheadVisualPalette.income.opacity(0.13),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("EXPECTED INCOME")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.6)
                        .foregroundStyle(PlanAheadVisualPalette.income)

                    Text(update.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(update.statusValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PlanAheadVisualPalette.income)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(update.detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Planning only · Not included in Available to Spend.")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.medium)
            .background {
                PlanAheadTintedSurface(
                    accent: PlanAheadVisualPalette.income,
                    cornerRadius: 18
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Expected income, \(update.title). \(update.statusValue). \(update.detail) Planning only. Not included in Available to Spend."
        )
        .accessibilityHint("Edits expected income.")
    }
}

private enum PlanAheadTimelineAxis {
    static let railWidth: CGFloat = 50
    static let nodeDiameter: CGFloat = 14
    static let nodeGap: CGFloat = 7
    static let axisX: CGFloat = 44
    static let spineWidth: CGFloat = 3
    static let eventLeadingGap: CGFloat = 8
    static let monthLabelGap: CGFloat = 16
}

private struct PlanAheadAxisMarker: View {
    let color: Color
    let diameter: CGFloat

    var body: some View {
        Color.clear
            .frame(height: diameter)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(color)
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.82), lineWidth: 3)
                    }
                    .offset(x: PlanAheadTimelineAxis.axisX - diameter / 2)
            }
            .accessibilityHidden(true)
    }
}

private struct PlanAheadTimelineTrack: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let days: [PlanAheadPresentedDay]
    let isPastDue: Bool
    let onSelect: (PlanAheadPresentedEvent) -> Void

    private let calendar = Calendar.current

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if index == 0 || !calendar.isDate(
                    day.date,
                    equalTo: days[index - 1].date,
                    toGranularity: .month
                ) {
                    monthTransition(day.date)
                }

                dayRow(day)
                    .padding(.bottom, AppSpacing.large)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(
                    (isPastDue ? PlanAheadVisualPalette.pastDue : AppColors.accent)
                        .opacity(isPastDue ? 0.34 : 0.42)
                )
                .frame(width: PlanAheadTimelineAxis.spineWidth)
                .offset(
                    x: PlanAheadTimelineAxis.axisX
                        - PlanAheadTimelineAxis.spineWidth / 2
                )
                .padding(.vertical, 5)
                .allowsHitTesting(false)
        }
    }

    private func monthTransition(_ date: Date) -> some View {
        HStack(alignment: .center, spacing: 0) {
            PlanAheadAxisMarker(
                color: isPastDue ? PlanAheadVisualPalette.pastDue : AppColors.accent,
                diameter: 8
            )
            .frame(width: PlanAheadTimelineAxis.railWidth)
            .zIndex(1)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(date.formatted(.dateTime.month(.abbreviated).year()))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppColors.primaryText)
                } else {
                    HStack(spacing: AppSpacing.small) {
                        Text(date.formatted(.dateTime.month(.wide).year()))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppColors.primaryText)
                        Rectangle()
                            .fill(AppColors.accent.opacity(0.22))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.leading, PlanAheadTimelineAxis.monthLabelGap)
        }
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.medium)
    }

    private func dayRow(_ day: PlanAheadPresentedDay) -> some View {
        HStack(alignment: .top, spacing: 0) {
            PlanAheadDateMarker(date: day.date, isPastDue: isPastDue)
                .frame(width: PlanAheadTimelineAxis.railWidth)
                .zIndex(1)

            VStack(spacing: AppSpacing.small) {
                ForEach(day.items) { item in
                    PlanAheadTimelineEventRow(item: item) {
                        onSelect(item)
                    }
                }
            }
            .padding(.leading, PlanAheadTimelineAxis.eventLeadingGap)
        }
    }
}

private struct PlanAheadDateMarker: View {
    let date: Date
    let isPastDue: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(
                    width: PlanAheadTimelineAxis.axisX
                        - PlanAheadTimelineAxis.nodeDiameter / 2
                        - PlanAheadTimelineAxis.nodeGap,
                    alignment: .trailing
                )
                .padding(.top, 10)

            Circle()
                .fill(isPastDue ? PlanAheadVisualPalette.pastDue : AppColors.accent)
                .frame(
                    width: PlanAheadTimelineAxis.nodeDiameter,
                    height: PlanAheadTimelineAxis.nodeDiameter
                )
                .overlay {
                    Circle().stroke(Color.white.opacity(0.82), lineWidth: 3)
                }
                .offset(
                    x: PlanAheadTimelineAxis.axisX
                        - PlanAheadTimelineAxis.nodeDiameter / 2,
                    y: 14
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        )
    }
}

private struct PlanAheadTimelineEventRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: PlanAheadPresentedEvent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityContent
                } else {
                    compactContent
                }
            }
            .padding(AppSpacing.medium)
            .background {
                PlanAheadTintedSurface(accent: accent, cornerRadius: 18)
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(accent.opacity(0.85))
                    .frame(width: 3, height: 18)
                    .padding(.leading, AppSpacing.xSmall)
                    .padding(.top, AppSpacing.medium)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .sensitiveAccessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                eventIcon
                typeLabel

                Spacer(minLength: AppSpacing.xSmall)

                SensitiveValueText(item.amountValue)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text(item.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            SensitiveValueText(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                eventIcon
                typeLabel
                Spacer(minLength: 0)
                SensitiveValueText(item.amountValue)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppColors.primaryText)
                    .monospacedDigit()
            }
            Text(item.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            SensitiveValueText(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var eventIcon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(accent)
            .frame(width: 24, height: 24)
            .background(accent.opacity(0.12), in: Circle())
    }

    private var typeLabel: some View {
        Text(item.typeTitle.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.7)
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var detail: String {
        if item.kind == .expectedIncome {
            return "Planning estimate · Not included in Available to Spend until it arrives."
        }

        let funding = item.funding?.statusLine ?? item.statusValue
        return item.isPastDue ? "Past Due · \(funding)" : funding
    }

    private var accent: Color {
        PlanAheadVisualPalette.accent(for: item)
    }

    private var systemImage: String {
        switch item.kind {
        case .upcomingExpense: return "calendar.badge.clock"
        case .paymentPlan: return "creditcard.fill"
        case .expectedIncome: return "arrow.down.circle.fill"
        }
    }

    private var accessibilityLabel: String {
        "\(item.typeTitle), \(item.title), \(item.amountValue), due \(item.date.formatted(.dateTime.month(.wide).day().year())), \(detail)"
    }

    private var accessibilityHint: String {
        switch item.kind {
        case .upcomingExpense: return "Opens this exact expense occurrence."
        case .paymentPlan: return "Opens this payment plan and its active payment cycle."
        case .expectedIncome: return "Edits expected income."
        }
    }
}

private struct PlanAheadObligationCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: PlanAheadPresentedEvent
    let onTap: () -> Void

    private var funding: PlanAheadFundingPresentation? { item.funding }
    private var accent: Color { PlanAheadVisualPalette.accent(for: item) }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: AppSpacing.small) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                        .background(accent.opacity(0.13), in: Circle())

                    Text(item.title)
                        .font(
                            dynamicTypeSize.isAccessibilitySize
                                ? .title3.weight(.semibold)
                                : .headline.weight(.semibold)
                        )
                        .foregroundStyle(AppColors.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .firstTextBaseline) {
                    SensitiveValueText(item.amountValue)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppColors.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: AppSpacing.xSmall)
                    Text(item.date.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(0.65)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: min(max(funding?.progress ?? 0, 0), 1))
                        .tint(accent)

                    SensitiveValueText(statusLine)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 128,
                alignment: .leading
            )
            .padding(12)
            .background {
                PlanAheadTintedSurface(accent: accent, cornerRadius: 20)
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(accent.opacity(0.80))
                    .frame(width: 3, height: 26)
                    .padding(.leading, AppSpacing.xSmall)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .sensitiveAccessibilityLabel(
            "\(item.typeTitle), \(item.title), due \(item.date.formatted(.dateTime.month(.wide).day().year())), \(item.amountValue), \(statusLine)"
        )
        .accessibilityHint(
            item.kind == .paymentPlan
                ? "Opens this payment plan and its active payment cycle."
                : "Opens this exact expense occurrence."
        )
    }

    private var statusLine: String {
        let value = funding?.statusLine ?? item.statusValue
        return item.isPastDue ? "Past due · \(value)" : value
    }

    private var systemImage: String {
        item.kind == .paymentPlan ? "creditcard.fill" : "calendar.badge.clock"
    }
}

private struct PlanAheadTintedSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    let accent: Color
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                colorScheme == .dark
                    ? Color.white.opacity(0.065)
                    : Color.white.opacity(0.46)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        accent.opacity(colorScheme == .dark ? 0.18 : 0.12),
                        lineWidth: 1
                    )
            }
    }
}

enum PlanAheadVisualPalette {
    static let expense = AppColors.accent
    static let payment = adaptive(
        light: UIColor(red: 0.26, green: 0.32, blue: 0.76, alpha: 1),
        dark: UIColor(red: 0.62, green: 0.69, blue: 1.00, alpha: 1)
    )
    static let income = adaptive(
        light: UIColor(red: 0.02, green: 0.49, blue: 0.43, alpha: 1),
        dark: UIColor(red: 0.38, green: 0.90, blue: 0.78, alpha: 1)
    )
    static let covered = income
    static let attention = Color(red: 0.82, green: 0.38, blue: 0.10)
    static let pastDue = AppColors.warning

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }

    static func accent(for item: PlanAheadPresentedEvent) -> Color {
        if item.isPastDue { return pastDue }
        switch item.kind {
        case .upcomingExpense: return expense
        case .paymentPlan: return payment
        case .expectedIncome: return income
        }
    }
}
