#if DEBUG

import SwiftUI

struct LabDashboardConfiguredWidget: Identifiable {
    let id: UUID
    let type: LabDashboardWidgetType
    let size: LabDashboardWidgetSize
    let sample: LabDashboardWidgetSample?

    init(
        id: UUID = UUID(),
        type: LabDashboardWidgetType,
        size: LabDashboardWidgetSize,
        sample: LabDashboardWidgetSample?
    ) {
        self.id = id
        self.type = type
        self.size = size
        self.sample = sample
    }
}

enum LabDashboardWidgetSize: String, CaseIterable, Identifiable {
    case square
    case wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square:
            return "Square"
        case .wide:
            return "Wide"
        }
    }

    var systemImage: String {
        switch self {
        case .square:
            return "square"
        case .wide:
            return "rectangle"
        }
    }
}

enum LabDashboardWidgetType: String, CaseIterable, Identifiable {
    case availableToSpend
    case setAsideTotal
    case paymentPlanProgress
    case upcomingExpense
    case savingsGoalProgress
    case planAhead
    case needsAttention
    case bankSync
    case whatChanged
    case quickActions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .availableToSpend:
            return "Available to Spend"
        case .setAsideTotal:
            return "Set Aside Total"
        case .paymentPlanProgress:
            return "Payment Plan Progress"
        case .upcomingExpense:
            return "Upcoming Expense"
        case .savingsGoalProgress:
            return "Savings Goal Progress"
        case .planAhead:
            return "Plan Ahead"
        case .needsAttention:
            return "Needs Attention"
        case .bankSync:
            return "Bank Sync"
        case .whatChanged:
            return "What Changed"
        case .quickActions:
            return "Quick Actions"
        }
    }

    var summary: String {
        switch self {
        case .availableToSpend:
            return "Your main spending answer"
        case .setAsideTotal:
            return "Money held back by purpose"
        case .paymentPlanProgress:
            return "One card or the next three plans"
        case .upcomingExpense:
            return "One bill or the next three expenses"
        case .savingsGoalProgress:
            return "Progress toward one savings goal"
        case .planAhead:
            return "The next three dated items"
        case .needsAttention:
            return "A calm count of items to review"
        case .bankSync:
            return "Data freshness and account status"
        case .whatChanged:
            return "A short balance-change summary"
        case .quickActions:
            return "Create planning items quickly"
        }
    }

    var systemImage: String {
        switch self {
        case .availableToSpend:
            return "sparkles"
        case .setAsideTotal:
            return "wallet.pass.fill"
        case .paymentPlanProgress:
            return "creditcard.fill"
        case .upcomingExpense:
            return CalderaCategoryStyle.style(for: .upcomingExpense).icon
        case .savingsGoalProgress:
            return "target"
        case .planAhead:
            return "calendar"
        case .needsAttention:
            return "bell.badge.fill"
        case .bankSync:
            return "building.columns.fill"
        case .whatChanged:
            return "arrow.up.right"
        case .quickActions:
            return "plus"
        }
    }

    var style: CalderaCategoryStyle {
        switch self {
        case .availableToSpend, .whatChanged, .quickActions:
            return CalderaCategoryStyle.style(for: .safeToSpend)
        case .setAsideTotal:
            return CalderaCategoryStyle.style(for: .reserve)
        case .paymentPlanProgress:
            return CalderaCategoryStyle.style(for: .debtPayoff)
        case .upcomingExpense:
            return CalderaCategoryStyle.style(for: .upcomingExpense)
        case .savingsGoalProgress:
            return CalderaCategoryStyle.style(for: .savingsGoal)
        case .planAhead, .bankSync:
            return CalderaCategoryStyle.style(for: .bankAccount)
        case .needsAttention:
            return CalderaCategoryStyle.style(for: .needsMoney)
        }
    }

    var samples: [LabDashboardWidgetSample] {
        switch self {
        case .paymentPlanProgress:
            return [
                LabDashboardWidgetSample(
                    id: "payment.platinum",
                    title: "Platinum Card®",
                    subtitle: "$451 of $700 set aside"
                ),
                LabDashboardWidgetSample(
                    id: "payment.amex",
                    title: "American Express Gold Card",
                    subtitle: "$384 of $384 set aside"
                ),
                LabDashboardWidgetSample(
                    id: "payment.nextThree",
                    title: "Next 3 Payment Plans",
                    subtitle: "$835 of $1,586 set aside"
                )
            ]

        case .savingsGoalProgress:
            return [
                LabDashboardWidgetSample(
                    id: "goal.emergency",
                    title: "Emergency Fund",
                    subtitle: "$7,600 of $10,000"
                ),
                LabDashboardWidgetSample(
                    id: "goal.vacation",
                    title: "Vacation",
                    subtitle: "$3,400 of $5,000"
                ),
                LabDashboardWidgetSample(
                    id: "goal.car",
                    title: "New Car",
                    subtitle: "$4,400 of $20,000"
                )
            ]

        case .upcomingExpense:
            return [
                LabDashboardWidgetSample(
                    id: "expense.rent",
                    title: "Rent",
                    subtitle: "$1,120 of $1,700 set aside"
                ),
                LabDashboardWidgetSample(
                    id: "expense.insurance",
                    title: "Insurance",
                    subtitle: "$180 of $240 set aside"
                ),
                LabDashboardWidgetSample(
                    id: "expense.phone",
                    title: "Phone Bill",
                    subtitle: "$80 of $95 set aside"
                ),
                LabDashboardWidgetSample(
                    id: "expense.nextThree",
                    title: "Next 3 Upcoming Expenses",
                    subtitle: "$1,380 of $2,035 set aside"
                )
            ]

        default:
            return []
        }
    }
}

struct LabDashboardWidgetSample: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

struct LabDashboardWidgetPickerSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: LabDashboardWidgetPickerStep = .type
    @State private var selectedType: LabDashboardWidgetType = .availableToSpend
    @State private var selectedSize: LabDashboardWidgetSize = .wide
    @State private var selectedSample: LabDashboardWidgetSample?

    let onAdd: (LabDashboardConfiguredWidget) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .dashboard)

                VStack(spacing: AppSpacing.regular) {
                    stepIndicator
                    stepContent
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.bottom, AppSpacing.regular)
            }
            .navigationTitle(step.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .type ? "Cancel" : "Back") {
                        moveBack()
                    }
                }
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: AppSpacing.xSmall) {
            ForEach(LabDashboardWidgetPickerStep.allCases) { candidate in
                Capsule(style: .continuous)
                    .fill(
                        candidate.rawValue <= step.rawValue
                            ? selectedType.style.primary
                            : AppColors.secondaryText.opacity(0.16)
                    )
                    .frame(height: 4)
            }
        }
        .padding(.top, AppSpacing.xSmall)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .type:
            widgetTypeStep
        case .size:
            widgetSizeStep
        case .sample:
            widgetSampleStep
        case .preview:
            widgetPreviewStep
        }
    }

    private var widgetTypeStep: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.small) {
                ForEach(LabDashboardWidgetType.allCases) { type in
                    Button {
                        selectedType = type
                        selectedSample = type.samples.first
                        step = .size
                    } label: {
                        HStack(spacing: AppSpacing.medium) {
                            CalderaGradientIcon(
                                systemImage: type.systemImage,
                                colors: type.style.gradient,
                                size: 40,
                                iconSize: 15
                            )

                            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                                Text(type.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(AppColors.primaryText)

                                Text(type.summary)
                                    .font(.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: AppSpacing.small)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(type.style.primary)
                        }
                        .padding(AppSpacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous)
                                .fill(
                                    Color.white.opacity(
                                        colorScheme == .dark ? 0.08 : 0.72
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous)
                                        .stroke(
                                            Color.white.opacity(
                                                colorScheme == .dark ? 0.12 : 0.78
                                            ),
                                            lineWidth: 1
                                        )
                                }
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, AppSpacing.xSmall)
        }
    }

    private var widgetSizeStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.screen) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(selectedType.title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text("Choose how much dashboard space this widget uses.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
            }

            HStack(alignment: .top, spacing: AppSpacing.medium) {
                ForEach(LabDashboardWidgetSize.allCases) { size in
                    Button {
                        selectedSize = size
                        step = selectedType.samples.isEmpty ? .preview : .sample
                    } label: {
                        VStack(spacing: AppSpacing.medium) {
                            Image(systemName: size.systemImage)
                                .font(.system(size: size == .square ? 42 : 52, weight: .medium))
                                .foregroundColor(selectedType.style.primary)
                                .frame(height: 58)

                            Text(size.title)
                                .font(.headline.weight(.bold))
                                .foregroundColor(AppColors.primaryText)

                            Text(size == .square ? "One column" : "Two columns")
                                .font(.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(AppSpacing.card)
                        .frame(maxWidth: .infinity)
                        .calderaGlassCard(
                            cornerRadius: AppRadii.card,
                            darkGlowColor: selectedType.style.primary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, AppSpacing.screen)
    }

    private var widgetSampleStep: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Choose information")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text("Select what this \(selectedType.title) widget displays.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.top, AppSpacing.medium)

            ScrollView {
                LazyVStack(spacing: AppSpacing.small) {
                    ForEach(selectedType.samples) { sample in
                        Button {
                            selectedSample = sample
                            step = .preview
                        } label: {
                            HStack(spacing: AppSpacing.medium) {
                                Image(systemName: selectedType.systemImage)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(selectedType.style.primary)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(selectedType.style.primary.opacity(0.12))
                                    )

                                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                                    Text(sample.title)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(AppColors.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.78)

                                    Text(sample.subtitle)
                                        .font(.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.78)
                                }

                                Spacer(minLength: AppSpacing.small)

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(selectedType.style.primary)
                            }
                            .padding(AppSpacing.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadii.card, style: .continuous)
                                    .fill(
                                        Color.white.opacity(
                                            colorScheme == .dark ? 0.08 : 0.72
                                        )
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var widgetPreviewStep: some View {
        VStack(spacing: AppSpacing.screen) {
            VStack(spacing: AppSpacing.xxSmall) {
                Text("Preview")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text(selectedSize.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(selectedType.style.primary)
            }
            .padding(.top, AppSpacing.medium)

            Spacer(minLength: AppSpacing.small)

            LabDashboardConfiguredWidgetTile(widget: configuredWidget)
                .frame(
                    maxWidth: selectedSize == .square
                        ? LabDashboardWidgetSizing.tileHeight
                        : .infinity
                )

            Spacer(minLength: AppSpacing.small)

            Button {
                onAdd(configuredWidget)
                dismiss()
            } label: {
                Label("Add to Dashboard", systemImage: "plus")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(selectedType.style.primary)
            .accessibilityHint("Adds this sample widget for the current Lab session")
        }
    }

    private var configuredWidget: LabDashboardConfiguredWidget {
        LabDashboardConfiguredWidget(
            type: selectedType,
            size: selectedSize,
            sample: selectedSample
        )
    }

    private func moveBack() {
        switch step {
        case .type:
            dismiss()
        case .size:
            step = .type
        case .sample:
            step = .size
        case .preview:
            step = selectedType.samples.isEmpty ? .size : .sample
        }
    }
}

private enum LabDashboardWidgetPickerStep: Int, CaseIterable, Identifiable {
    case type
    case size
    case sample
    case preview

    var id: Int { rawValue }

    var navigationTitle: String {
        switch self {
        case .type:
            return "Add Widget"
        case .size:
            return "Choose Size"
        case .sample:
            return "Choose Information"
        case .preview:
            return "Widget Preview"
        }
    }
}

struct LabDashboardConfiguredWidgetCollection: View {

    let widgets: [LabDashboardConfiguredWidget]

    private var rows: [LabDashboardConfiguredWidgetRow] {
        LabDashboardConfiguredWidgetRow.makeRows(from: widgets)
    }

    var body: some View {
        VStack(spacing: LabDashboardWidgetSizing.tileSpacing) {
            ForEach(rows) { row in
                rowView(row)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: LabDashboardConfiguredWidgetRow) -> some View {
        switch row.content {
        case let .wide(widget):
            LabDashboardConfiguredWidgetTile(widget: widget)

        case let .squares(leading, trailing):
            HStack(alignment: .top, spacing: LabDashboardWidgetSizing.tileSpacing) {
                LabDashboardConfiguredWidgetTile(widget: leading)
                    .frame(maxWidth: .infinity)

                if let trailing {
                    LabDashboardConfiguredWidgetTile(widget: trailing)
                        .frame(maxWidth: .infinity)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: LabDashboardWidgetSizing.tileHeight)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

private struct LabDashboardConfiguredWidgetRow: Identifiable {

    enum Content {
        case wide(LabDashboardConfiguredWidget)
        case squares(LabDashboardConfiguredWidget, LabDashboardConfiguredWidget?)
    }

    let id: String
    let content: Content

    static func makeRows(
        from widgets: [LabDashboardConfiguredWidget]
    ) -> [LabDashboardConfiguredWidgetRow] {
        var rows: [LabDashboardConfiguredWidgetRow] = []
        var pendingSquare: LabDashboardConfiguredWidget?

        for widget in widgets {
            switch widget.size {
            case .wide:
                if let pendingSquare {
                    rows.append(
                        LabDashboardConfiguredWidgetRow(
                            id: pendingSquare.id.uuidString,
                            content: .squares(pendingSquare, nil)
                        )
                    )
                }

                pendingSquare = nil
                rows.append(
                    LabDashboardConfiguredWidgetRow(
                        id: widget.id.uuidString,
                        content: .wide(widget)
                    )
                )

            case .square:
                if let leading = pendingSquare {
                    rows.append(
                        LabDashboardConfiguredWidgetRow(
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
                LabDashboardConfiguredWidgetRow(
                    id: pendingSquare.id.uuidString,
                    content: .squares(pendingSquare, nil)
                )
            )
        }

        return rows
    }
}

private struct LabDashboardConfiguredWidgetTile: View {

    @Environment(\.colorScheme) private var colorScheme

    let widget: LabDashboardConfiguredWidget

    private var style: CalderaCategoryStyle {
        widget.type.style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    systemImage: widget.type.systemImage,
                    colors: style.gradient,
                    size: 34,
                    iconSize: 13
                )

                Text(widget.type.title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)

                Spacer(minLength: 0)
            }

            widgetContent
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
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var widgetContent: some View {
        switch widget.type {
        case .availableToSpend:
            LabConfiguredMetricContent(
                value: "$1,842",
                label: "After Set Aside",
                detail: "Planned money is held back.",
                color: style.primary
            )

        case .setAsideTotal:
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                LabConfiguredMetricContent(
                    value: "$2,838",
                    label: "held back",
                    detail: "Goals · Upcoming · Plans",
                    color: style.primary
                )

                LabConfiguredProgressBar(progress: 0.72, color: style.primary)
            }

        case .paymentPlanProgress:
            paymentPlanContent

        case .upcomingExpense:
            upcomingExpenseContent

        case .savingsGoalProgress:
            savingsGoalContent

        case .planAhead:
            LabConfiguredPlanAheadContent()

        case .needsAttention:
            LabConfiguredMetricContent(
                value: "2",
                label: "items to review",
                detail: "1 past due · 1 needs funding",
                color: style.primary
            )

        case .bankSync:
            LabConfiguredMetricContent(
                value: "Up to date",
                label: "4 accounts",
                detail: "Refreshed 8 min ago",
                color: CalderaCategoryStyle.style(for: .covered).primary
            )

        case .whatChanged:
            LabConfiguredMetricContent(
                value: "+$120",
                label: "Available to Spend",
                detail: "since your last sync",
                color: CalderaCategoryStyle.style(for: .covered).primary
            )

        case .quickActions:
            LabConfiguredQuickActionsContent()
        }
    }

    @ViewBuilder
    private var paymentPlanContent: some View {
        if widget.sample?.id == "payment.nextThree" {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("$835 of $1,586")
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()

                Text("Next 3 Payment Plans")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)

                LabConfiguredSegmentedBar(color: style.primary)
            }
        } else {
            let isAmex = widget.sample?.id == "payment.amex"
            let value = isAmex ? "$384 of $384" : "$451 of $700"
            let progress = isAmex ? 1.0 : 451.0 / 700.0

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                LabConfiguredMetricContent(
                    value: value,
                    label: widget.sample?.title ?? "Platinum Card®",
                    detail: isAmex ? "Due Aug 13" : "Due Sep 1",
                    color: style.primary
                )

                LabConfiguredProgressBar(progress: progress, color: style.primary)
            }
        }
    }

    private var upcomingExpenseContent: some View {
        let data = upcomingExpenseData

        return VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            LabConfiguredMetricContent(
                value: data.value,
                label: widget.sample?.title ?? "Rent",
                detail: data.detail,
                color: style.primary
            )

            LabConfiguredProgressBar(progress: data.progress, color: style.primary)
        }
    }

    private var savingsGoalContent: some View {
        let data = savingsGoalData

        return VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            LabConfiguredMetricContent(
                value: data.value,
                label: widget.sample?.title ?? "Emergency Fund",
                detail: data.detail,
                color: style.primary
            )

            LabConfiguredProgressBar(progress: data.progress, color: style.primary)
        }
    }

    private var upcomingExpenseData: (value: String, detail: String, progress: Double) {
        switch widget.sample?.id {
        case "expense.insurance":
            return ("$180 of $240", "Due Aug 8", 0.75)
        case "expense.phone":
            return ("$80 of $95", "Due Aug 12", 80.0 / 95.0)
        case "expense.nextThree":
            return ("$1,380 of $2,035", "Next 3 expenses", 1_380.0 / 2_035.0)
        default:
            return ("$1,120 of $1,700", "Due Aug 1", 1_120.0 / 1_700.0)
        }
    }

    private var savingsGoalData: (value: String, detail: String, progress: Double) {
        switch widget.sample?.id {
        case "goal.vacation":
            return ("$3,400 of $5,000", "68% saved", 0.68)
        case "goal.car":
            return ("$4,400 of $20,000", "22% saved", 0.22)
        default:
            return ("$7,600 of $10,000", "76% saved", 0.76)
        }
    }
}

private struct LabConfiguredMetricContent: View {

    let value: String
    let label: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.60)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(detail)
                .font(.caption2)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct LabConfiguredProgressBar: View {

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

private struct LabConfiguredSegmentedBar: View {

    let color: Color

    private let segments: [(width: CGFloat, progress: Double)] = [
        (384.0 / 1_586.0, 1),
        (700.0 / 1_586.0, 451.0 / 700.0),
        (502.0 / 1_586.0, 0)
    ]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(segments.indices, id: \.self) { index in
                    GeometryReader { segmentProxy in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(AppColors.secondaryText.opacity(0.16))

                            Capsule(style: .continuous)
                                .fill(color)
                                .frame(
                                    width: segmentProxy.size.width * segments[index].progress
                                )
                        }
                    }
                    .frame(
                        width: max(
                            (proxy.size.width - 6) * segments[index].width,
                            0
                        )
                    )
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

private struct LabConfiguredPlanAheadContent: View {

    private let items = [
        ("Aug 1", "Rent", "$1,700"),
        ("Aug 13", "Amex", "$384"),
        ("Aug 14", "Vacation", "$500")
    ]

    var body: some View {
        VStack(spacing: AppSpacing.xxSmall) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: AppSpacing.xSmall) {
                    Text(items[index].0)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 42, alignment: .leading)

                    Text(items[index].1)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: AppSpacing.xSmall)

                    Text(items[index].2)
                        .font(.caption.weight(.bold))
                        .foregroundColor(AppColors.primaryText)
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct LabConfiguredQuickActionsContent: View {

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            quickAction("Goal", "target", CalderaCategoryStyle.style(for: .savingsGoal).primary)
            quickAction("Expense", CalderaCategoryStyle.style(for: .upcomingExpense).icon, CalderaCategoryStyle.style(for: .upcomingExpense).primary)
            quickAction("Plan", "creditcard.fill", CalderaCategoryStyle.style(for: .debtPayoff).primary)
        }
    }

    private func quickAction(
        _ title: String,
        _ systemImage: String,
        _ color: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xxSmall) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(color.opacity(0.12))
                )

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
    }
}

#endif
