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
                        LabSetAsidePlaceholderPage(section: .upcoming)
                            .tag(LabSetAsideSection.upcoming)

                        LabSetAsidePlaceholderPage(section: .payments)
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

private struct LabSetAsidePlaceholderPage: View {
    let section: LabSetAsideSection

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            Spacer(minLength: AppSpacing.medium)

            CalderaGradientIcon(
                style: section.style,
                size: 62,
                iconSize: 25
            )

            VStack(spacing: AppSpacing.xxSmall) {
                Text(section.title)
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text("Coming soon in this Lab prototype")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
            }

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("This section will use the same calm Set Aside language once its page design is ready.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(section.style.primary.opacity(0.16))
                    .frame(width: 124, height: 7)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AppColors.secondaryText.opacity(0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 7)
            }
            .padding(AppSpacing.card)
            .calderaGlassCard(
                cornerRadius: AppRadii.panel,
                fillOpacity: 0.82,
                strokeOpacity: 0.66,
                shadowOpacity: 0.03,
                shadowRadius: 12,
                shadowY: 6,
                darkGlowColor: section.style.primary
            )
            .padding(.horizontal, AppSpacing.small)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, AppSpacing.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title). Coming soon in this Lab prototype.")
    }
}

#endif
