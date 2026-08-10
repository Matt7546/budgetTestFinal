#if DEBUG

import SwiftUI

enum LabDashboardWidgetSizing {
    static let tileHeight: CGFloat = 176
    static let tileSpacing = AppSpacing.medium
    static let tilePadding = AppSpacing.medium
    static let headerHeight: CGFloat = 34
    static let contentSpacing = AppSpacing.medium
}

struct LabDashboardWidgetManagementActions {
    let edit: () -> Void
    let remove: () -> Void
}

struct LabDashboardWidgetGrid: View {
    let widgets: [LabDashboardWidgetInstance]
    let addWidget: () -> Void
    let editWidget: (LabDashboardWidgetInstance) -> Void
    let removeWidget: (LabDashboardWidgetInstance) -> Void

    private var rows: [LabDashboardWidgetRow] {
        LabDashboardWidgetRow.makeRows(from: widgets)
    }

    var body: some View {
        VStack(spacing: LabDashboardWidgetSizing.tileSpacing) {
            if rows.isEmpty {
                LabDashboardEmptyWidgetGrid(addWidget: addWidget)
            } else {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: LabDashboardWidgetRow) -> some View {
        switch row.content {
        case let .wide(widget):
            renderer(for: widget)

        case let .squares(leading, trailing):
            HStack(alignment: .top, spacing: LabDashboardWidgetSizing.tileSpacing) {
                renderer(for: leading)
                    .frame(maxWidth: .infinity)

                if let trailing {
                    renderer(for: trailing)
                        .frame(maxWidth: .infinity)
                } else {
                    LabDashboardAddWidgetTile(action: addWidget)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func renderer(
        for widget: LabDashboardWidgetInstance
    ) -> some View {
        LabDashboardWidgetRenderer(
            widget: widget,
            managementActions: LabDashboardWidgetManagementActions(
                edit: { editWidget(widget) },
                remove: { removeWidget(widget) }
            )
        )
    }
}

private struct LabDashboardWidgetRow: Identifiable {
    enum Content {
        case wide(LabDashboardWidgetInstance)
        case squares(LabDashboardWidgetInstance, LabDashboardWidgetInstance?)
    }

    let id: String
    let content: Content

    static func makeRows(
        from widgets: [LabDashboardWidgetInstance]
    ) -> [LabDashboardWidgetRow] {
        var rows: [LabDashboardWidgetRow] = []
        var pendingSquare: LabDashboardWidgetInstance?

        for widget in widgets {
            switch widget.size {
            case .wide:
                if let pendingSquare {
                    rows.append(
                        LabDashboardWidgetRow(
                            id: pendingSquare.id.uuidString,
                            content: .squares(pendingSquare, nil)
                        )
                    )
                }

                pendingSquare = nil
                rows.append(
                    LabDashboardWidgetRow(
                        id: widget.id.uuidString,
                        content: .wide(widget)
                    )
                )

            case .square:
                if let leading = pendingSquare {
                    rows.append(
                        LabDashboardWidgetRow(
                            id: "\(leading.id.uuidString)-\(widget.id.uuidString)",
                            content: .squares(leading, widget)
                        )
                    )
                    pendingSquare = nil
                } else {
                    pendingSquare = widget
                }
            }
        }

        if let pendingSquare {
            rows.append(
                LabDashboardWidgetRow(
                    id: pendingSquare.id.uuidString,
                    content: .squares(pendingSquare, nil)
                )
            )
        }

        return rows
    }
}

private struct LabDashboardEmptyWidgetGrid: View {
    let addWidget: () -> Void

    var body: some View {
        Button(action: addWidget) {
            VStack(spacing: AppSpacing.small) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2.weight(.semibold))

                Text("Add your first widget")
                    .font(.subheadline.weight(.bold))

                Text("Choose one focused answer for this dashboard.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .calderaGlassCard(cornerRadius: AppRadii.card)
        }
        .buttonStyle(.plain)
    }
}

private struct LabDashboardAddWidgetTile: View {
    let action: () -> Void

    private let style = CalderaCategoryStyle.style(for: .safeToSpend)

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.small) {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(style.primary.opacity(0.12)))

                Text("Add widget")
                    .font(.caption.weight(.bold))
            }
            .foregroundColor(style.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: LabDashboardWidgetSizing.tileHeight)
            .calderaGlassCard(
                cornerRadius: AppRadii.card,
                fillOpacity: 0.56,
                strokeOpacity: 0.56,
                shadowOpacity: 0.02,
                darkGlowColor: style.primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Lab widget configuration flow")
    }
}

struct LabDashboardWidgetRenderer: View {
    let widget: LabDashboardWidgetInstance
    var managementActions: LabDashboardWidgetManagementActions?

    private var definition: LabDashboardWidgetDefinition {
        widget.definition
    }

    var body: some View {
        LabDashboardWidgetTile(
            title: definition.displayName,
            systemImage: definition.systemImage,
            style: definition.style,
            managementActions: managementActions
        ) {
            widgetContent
        }
    }

    @ViewBuilder
    private var widgetContent: some View {
        switch widget.type {
        case .availableToSpend:
            LabAvailableToSpendWidgetContent()
        case .setAside:
            LabSetAsideWidgetContent()
        case .paymentPlans:
            if widget.size == .wide {
                LabPaymentPlansWideContent()
            } else {
                LabPaymentPlanSquareContent(sampleID: widget.sampleID)
            }
        case .upcomingExpenses:
            if widget.size == .wide {
                LabUpcomingExpensesWideContent()
            } else {
                LabUpcomingExpenseSquareContent(sampleID: widget.sampleID)
            }
        case .savingsGoal:
            LabSavingsGoalSquareContent(sampleID: widget.sampleID)
        case .planAhead:
            LabPlanAheadWideContent()
        case .reviewUpdates:
            LabReviewUpdatesSquareContent()
        case .bankSync:
            LabBankSyncSquareContent()
        }
    }
}

private struct LabDashboardWidgetTile<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String
    let style: CalderaCategoryStyle
    let managementActions: LabDashboardWidgetManagementActions?
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        style: CalderaCategoryStyle,
        managementActions: LabDashboardWidgetManagementActions? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.managementActions = managementActions
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LabDashboardWidgetSizing.contentSpacing) {
            LabDashboardWidgetHeader(
                title: title,
                systemImage: systemImage,
                style: style,
                managementActions: managementActions
            )
            .frame(height: LabDashboardWidgetSizing.headerHeight)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

private struct LabDashboardWidgetHeader: View {
    let title: String
    let systemImage: String
    let style: CalderaCategoryStyle
    let managementActions: LabDashboardWidgetManagementActions?

    var body: some View {
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
                .minimumScaleFactor(0.70)

            Spacer(minLength: 0)

            if let managementActions {
                Menu {
                    Button(action: managementActions.edit) {
                        Label("Edit widget", systemImage: "slider.horizontal.3")
                    }

                    Button(role: .destructive, action: managementActions.remove) {
                        Label("Remove widget", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Widget options")
            }
        }
    }
}

private struct LabAvailableToSpendWidgetContent: View {
    private let style = CalderaCategoryStyle.style(for: .safeToSpend)

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.regular) {
            VStack(alignment: .leading, spacing: 3) {
                Text("$1,842")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("After Set Aside")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(style.primary)

                Text("Planned money is already held back.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: AppSpacing.medium)

            Rectangle()
                .fill(AppColors.secondaryText.opacity(0.14))
                .frame(width: 1, height: 52)

            VStack(alignment: .trailing, spacing: 3) {
                Text("Since sync")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)

                Text("+$120")
                    .font(.title3.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .covered).primary)
                    .monospacedDigit()

                Text("Available to Spend")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Available to Spend, $1,842 after Set Aside. Up $120 since last sync.")
    }
}

private struct LabSetAsideWidgetContent: View {
    private let style = CalderaCategoryStyle.style(for: .reserve)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                Text("$2,838")
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("held back")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(style.primary)
            }

            LabSetAsideSplitBar()

            HStack(spacing: AppSpacing.xSmall) {
                LabSetAsideLegend(
                    title: "Goals",
                    color: CalderaCategoryStyle.style(for: .savingsGoal).primary
                )
                LabSetAsideLegend(
                    title: "Upcoming",
                    color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
                )
                LabSetAsideLegend(
                    title: "Plans",
                    color: CalderaCategoryStyle.style(for: .debtPayoff).primary
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Set Aside, $2,838 across goals, upcoming expenses, and payment plans.")
    }
}

private struct LabSetAsideLegend: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
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

private struct LabPaymentPlanSnapshot: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let target: Double
    let setAside: Double
    let targetLabel: String
    let setAsideLabel: String
    let neededLabel: String
    let due: String

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(setAside / target, 0), 1)
    }

    static let platinum = LabPaymentPlanSnapshot(
        id: "payment.platinum",
        name: "Platinum Card®",
        shortName: "Platinum",
        target: 700,
        setAside: 451,
        targetLabel: "$700",
        setAsideLabel: "$451",
        neededLabel: "$249 needed",
        due: "Sep 1"
    )

    static let amex = LabPaymentPlanSnapshot(
        id: "payment.amex",
        name: "American Express Gold Card",
        shortName: "Amex",
        target: 384,
        setAside: 384,
        targetLabel: "$384",
        setAsideLabel: "$384",
        neededLabel: "Funded",
        due: "Aug 13"
    )

    static let chase = LabPaymentPlanSnapshot(
        id: "payment.chase",
        name: "Chase Freedom",
        shortName: "Chase",
        target: 502,
        setAside: 0,
        targetLabel: "$502",
        setAsideLabel: "$0",
        neededLabel: "$502 needed",
        due: "Sep 3"
    )

    static let nextThree = [amex, platinum, chase]

    static func sample(id: String?) -> LabPaymentPlanSnapshot {
        id == amex.id ? amex : platinum
    }
}

private struct LabPaymentPlanSquareContent: View {
    let sampleID: String?

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    private var plan: LabPaymentPlanSnapshot {
        LabPaymentPlanSnapshot.sample(id: sampleID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(plan.name)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text("\(plan.setAsideLabel) of \(plan.targetLabel)")
                .font(.title3.weight(.bold))
                .foregroundColor(style.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            LabDashboardProgressBar(progress: plan.progress, color: style.primary)

            HStack(spacing: AppSpacing.xSmall) {
                Text("Due \(plan.due)")
                Spacer(minLength: 0)
                Text(plan.neededLabel)
                    .foregroundColor(style.primary)
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(AppColors.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.64)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LabPaymentPlansWideContent: View {
    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("$835 of $1,586")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()

                Spacer(minLength: AppSpacing.small)

                Text("Next 3 payments")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(style.primary)
            }

            LabPaymentPlanSegments(
                payments: LabPaymentPlanSnapshot.nextThree,
                color: style.primary
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Payment Plans. $835 of $1,586 set aside across the next three payments.")
    }
}

private struct LabPaymentPlanSegments: View {
    let payments: [LabPaymentPlanSnapshot]
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
                    LabPaymentPlanSegment(
                        payment: payments[index],
                        color: color
                    )
                    .frame(width: widths[index])
                }
            }
        }
        .frame(height: 54)
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

private struct LabPaymentPlanSegment: View {
    let payment: LabPaymentPlanSnapshot
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 3) {
                GeometryReader { barProxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(AppColors.secondaryText.opacity(0.17))

                        Capsule(style: .continuous)
                            .fill(color)
                            .frame(width: barProxy.size.width * payment.progress)
                    }
                }
                .frame(height: 9)

                Text(payment.shortName)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                if proxy.size.width >= 68 {
                    Text(payment.due)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(payment.name), \(payment.setAsideLabel) of \(payment.targetLabel) set aside, due \(payment.due)"
        )
    }
}

private struct LabUpcomingExpenseSnapshot: Identifiable {
    let id: String
    let name: String
    let target: Double
    let setAside: Double
    let targetLabel: String
    let setAsideLabel: String
    let neededLabel: String
    let due: String

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(setAside / target, 0), 1)
    }

    static let rent = LabUpcomingExpenseSnapshot(
        id: "expense.rent",
        name: "Rent",
        target: 1_700,
        setAside: 1_120,
        targetLabel: "$1,700",
        setAsideLabel: "$1,120",
        neededLabel: "$580",
        due: "Aug 1"
    )

    static let insurance = LabUpcomingExpenseSnapshot(
        id: "expense.insurance",
        name: "Insurance",
        target: 240,
        setAside: 180,
        targetLabel: "$240",
        setAsideLabel: "$180",
        neededLabel: "$60",
        due: "Aug 8"
    )

    static let phone = LabUpcomingExpenseSnapshot(
        id: "expense.phone",
        name: "Phone Bill",
        target: 95,
        setAside: 80,
        targetLabel: "$95",
        setAsideLabel: "$80",
        neededLabel: "$15",
        due: "Aug 12"
    )

    static let nextThree = [rent, insurance, phone]

    static func sample(id: String?) -> LabUpcomingExpenseSnapshot {
        switch id {
        case insurance.id:
            return insurance
        case phone.id:
            return phone
        default:
            return rent
        }
    }
}

private struct LabUpcomingExpenseSquareContent: View {
    let sampleID: String?

    private let style = CalderaCategoryStyle.style(for: .upcomingExpense)

    private var expense: LabUpcomingExpenseSnapshot {
        LabUpcomingExpenseSnapshot.sample(id: sampleID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(expense.name)
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)

                Spacer(minLength: AppSpacing.xSmall)

                Text(expense.due)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(style.primary)
            }

            Text(expense.targetLabel)
                .font(.title3.weight(.bold))
                .foregroundColor(style.primary)
                .monospacedDigit()

            LabDashboardProgressBar(progress: expense.progress, color: style.primary)

            HStack(spacing: AppSpacing.xSmall) {
                Text("\(expense.setAsideLabel) set aside")
                Spacer(minLength: 0)
                Text("\(expense.neededLabel) needed")
                    .foregroundColor(style.primary)
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(AppColors.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.60)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LabUpcomingExpensesWideContent: View {
    private let style = CalderaCategoryStyle.style(for: .upcomingExpense)

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.regular) {
            VStack(alignment: .leading, spacing: 3) {
                Text("$655")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()

                Text("needed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text("across next 3")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
            }

            Rectangle()
                .fill(AppColors.secondaryText.opacity(0.14))
                .frame(width: 1, height: 68)

            VStack(spacing: 5) {
                ForEach(LabUpcomingExpenseSnapshot.nextThree) { expense in
                    HStack(spacing: AppSpacing.small) {
                        Circle()
                            .fill(style.primary)
                            .frame(width: 6, height: 6)

                        Text(expense.name)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: AppSpacing.small)

                        Text(expense.due)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(AppColors.secondaryText)

                        Text(expense.neededLabel)
                            .font(.caption.weight(.bold))
                            .foregroundColor(style.primary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next three Upcoming Expenses need $655 total.")
    }
}

private struct LabSavingsGoalSnapshot {
    let name: String
    let savedLabel: String
    let targetLabel: String
    let progress: Double

    static func sample(id: String?) -> LabSavingsGoalSnapshot {
        switch id {
        case "goal.emergency":
            return LabSavingsGoalSnapshot(
                name: "Emergency Fund",
                savedLabel: "$7,600",
                targetLabel: "$10,000",
                progress: 0.76
            )
        case "goal.car":
            return LabSavingsGoalSnapshot(
                name: "New Car",
                savedLabel: "$4,400",
                targetLabel: "$20,000",
                progress: 0.22
            )
        default:
            return LabSavingsGoalSnapshot(
                name: "Vacation",
                savedLabel: "$3,400",
                targetLabel: "$5,000",
                progress: 0.68
            )
        }
    }
}

private struct LabSavingsGoalSquareContent: View {
    let sampleID: String?

    private let style = CalderaCategoryStyle.style(for: .savingsGoal)

    private var goal: LabSavingsGoalSnapshot {
        LabSavingsGoalSnapshot.sample(id: sampleID)
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            LabDashboardProgressRing(progress: goal.progress, color: style.primary)

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(goal.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(goal.savedLabel)
                    .font(.headline.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("of \(goal.targetLabel)")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LabDashboardProgressRing: View {
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

            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption.weight(.bold))
                .foregroundColor(color)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

private struct LabPlanAheadWideContent: View {
    private let items = [
        LabDashboardPlanItem(
            name: "Rent",
            date: "Aug 1",
            amount: "$1,700",
            color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
        ),
        LabDashboardPlanItem(
            name: "Amex Gold",
            date: "Aug 13",
            amount: "$384",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ),
        LabDashboardPlanItem(
            name: "Vacation",
            date: "Aug 14",
            amount: "$500",
            color: CalderaCategoryStyle.style(for: .savingsGoal).primary
        )
    ]

    var body: some View {
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
        .accessibilityElement(children: .combine)
    }
}

private struct LabDashboardPlanItem: Identifiable {
    let name: String
    let date: String
    let amount: String
    let color: Color

    var id: String { name }
}

private struct LabReviewUpdatesSquareContent: View {
    private let style = CalderaCategoryStyle.style(for: .needsMoney)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                Text("2")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()

                Text("updates to review")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)
            }

            Text("Review past-due rent first")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Review Updates. Two updates to review. Review past-due rent first.")
    }
}

private struct LabBankSyncSquareContent: View {
    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.small) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2.weight(.bold))
                .foregroundColor(CalderaCategoryStyle.style(for: .covered).primary)

            VStack(alignment: .leading, spacing: 3) {
                Text("Up to date")
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)

                Text("4 accounts · 8 min ago")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bank Sync is up to date. Four accounts refreshed eight minutes ago.")
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
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

#endif
