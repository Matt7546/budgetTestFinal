import SwiftUI

struct SavingsDebtPayoffSection: View {

    let hasDebtPayoffBuckets: Bool
    let activeBuckets: [DebtPayoffBucket]
    let visibleBuckets: [DebtPayoffBucket]
    let paymentPlanCycles: [PaymentPlanCycle]
    let accountByID: [String: PlaidAccount]
    let balanceLastUpdatedText: String
    let trailing: AnyView
    let addAction: () -> Void
    let editAction: (DebtPayoffBucket) -> Void

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)
    private let presentation = SetAsideSectionPresentation.content(
        for: .paymentPlans
    )

    var body: some View {
        SavingsSectionShell(
            title: presentation.title,
            description: presentation.purpose,
            style: style
        ) {
            trailing
        } content: {
            VStack(spacing: AppSpacing.small) {
                if !hasDebtPayoffBuckets {
                    SavingsEmptyPreviewRow(
                        title: presentation.emptyTitle,
                        subtitle: presentation.emptyDetail,
                        style: style
                    )
                } else {
                    PaymentPlanSetAsideSummary(
                        buckets: activeBuckets,
                        paymentPlanCycles: paymentPlanCycles,
                        style: style
                    )

                    ForEach(visibleBuckets) { bucket in
                        debtRow(bucket)
                    }

                    if let balanceRefreshLine {
                        Label(
                            balanceRefreshLine,
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .accessibilityLabel(balanceRefreshLine)
                    }

                    Label(
                        "\(AppBrand.shortName) does not make payments.",
                        systemImage: "info.circle"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                SavingsQuickAddButton(
                    title: presentation.quickAddTitle ?? "Create Payment Plan",
                    style: style,
                    accessibilityLabel: presentation.quickAddTitle ?? "Create Payment Plan",
                    action: addAction
                )
            }
        }
    }

    private func debtRow(
        _ bucket: DebtPayoffBucket
    ) -> some View {
        let account = accountByID[bucket.plaidAccountID]
        let display = DebtPayoffDisplayModel(
            bucket: bucket,
            linkedAccount: account,
            cycle: PaymentPlanCycleStore.activeCycle(
                for: bucket.id,
                in: paymentPlanCycles
            )
        )
        let rowStyle = debtPayoffCategoryStyle(
            for: bucket,
            account: account
        )

        return PaymentPlanSetAsidePreviewRow(
            display: display,
            style: rowStyle
        ) {
            editAction(bucket)
        }
    }

    private var balanceRefreshLine: String? {
        guard activeBuckets.contains(where: { bucket in
            bucket.isLinkedCreditCard &&
                accountByID[bucket.plaidAccountID] != nil
        }),
        balanceLastUpdatedText != "Not refreshed yet" else {
            return nil
        }

        let refreshText = balanceLastUpdatedText
            .replacingOccurrences(
                of: "Last fully refreshed",
                with: "fully refreshed"
            )
            .replacingOccurrences(
                of: "Last refreshed",
                with: "refreshed"
            )
        return "Card balances \(refreshText)"
    }
}

private struct PaymentPlanSetAsideSummary: View {

    let buckets: [DebtPayoffBucket]
    let paymentPlanCycles: [PaymentPlanCycle]
    let style: CalderaCategoryStyle

    private var planCount: Int {
        buckets.count
    }

    private var totalPlanned: Double {
        buckets.reduce(0) { total, bucket in
            let display = DebtPayoffDisplayModel(
                bucket: bucket,
                linkedAccount: nil,
                cycle: PaymentPlanCycleStore.activeCycle(
                    for: bucket.id,
                    in: paymentPlanCycles
                )
            )
            return total + max(display.plannedPaymentAmount, 0)
        }
    }

    private var totalSetAside: Double {
        buckets.reduce(0) { total, bucket in
            total + max(bucket.protectedAmount, 0)
        }
    }

    private var stillNeeded: Double {
        max(totalPlanned - totalSetAside, 0)
    }

    private var progress: Double {
        guard totalPlanned > 0 else {
            return 0
        }

        return clampedProgressValue(totalSetAside / totalPlanned)
    }

    private var upcomingPaymentSegments: [PaymentPlanSetAsideSegment] {
        let sortedSegments = buckets.map { bucket in
            let cycle = PaymentPlanCycleStore.activeCycle(
                for: bucket.id,
                in: paymentPlanCycles
            )
            let display = DebtPayoffDisplayModel(
                bucket: bucket,
                linkedAccount: nil,
                cycle: cycle
            )

            return PaymentPlanSetAsideSegment(
                id: bucket.id,
                title: display.title,
                target: max(display.plannedPaymentAmount, 0),
                setAside: max(bucket.protectedAmount, 0),
                dueDate: cycle?.dueDate ?? bucket.dueDate
            )
        }
        .sorted { $0.dueDate < $1.dueDate }

        return Array(
            sortedSegments
                .prefix(3)
                .filter { $0.target > 0 }
        )
    }

    private var planCountText: String {
        "\(planCount) active payment plan\(planCount == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(planCountText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)

            Text(
                "\(AppFormatters.currency(totalSetAside)) of \(AppFormatters.currency(totalPlanned)) set aside"
            )
            .font(.caption.weight(.medium))
            .foregroundColor(AppColors.secondaryText)
            .monospacedDigit()

            stillNeededLabel

            PaymentPlanAdaptiveSegmentedBar(
                segments: upcomingPaymentSegments,
                fallbackProgress: progress,
                style: style
            )
        }
        .padding(.vertical, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(planCountText), \(AppFormatters.currency(totalSetAside)) of \(AppFormatters.currency(totalPlanned)) set aside, \(AppFormatters.currency(stillNeeded)) still needed"
        )
    }

    private var stillNeededLabel: some View {
        Text("\(AppFormatters.currency(stillNeeded)) still needed")
            .font(.caption.weight(.semibold))
            .foregroundColor(style.primary)
            .monospacedDigit()
    }

}

private struct PaymentPlanSetAsideSegment: Identifiable {

    let id: UUID
    let title: String
    let target: Double
    let setAside: Double
    let dueDate: Date

    var fundingProgress: Double {
        guard target > 0 else {
            return 0
        }

        return min(max(setAside / target, 0), 1)
    }
}

private struct PaymentPlanAdaptiveSegmentedBar: View {

    let segments: [PaymentPlanSetAsideSegment]
    let fallbackProgress: Double
    let style: CalderaCategoryStyle

    private let segmentSpacing: CGFloat = 3

    private var totalTarget: Double {
        segments.reduce(0) { $0 + $1.target }
    }

    var body: some View {
        Group {
            if segments.isEmpty || totalTarget <= 0 {
                CalderaProgressBar(
                    progress: fallbackProgress,
                    colors: style.gradient
                )
                .frame(height: 7)
            } else {
                GeometryReader { proxy in
                    let segmentWidths = widths(for: proxy.size.width)

                    VStack(spacing: AppSpacing.xSmall) {
                        HStack(spacing: segmentSpacing) {
                            ForEach(segments.indices, id: \.self) { index in
                                fundingSegment(for: segments[index])
                                    .frame(width: segmentWidths[index], height: 9)
                            }
                        }

                        HStack(spacing: segmentSpacing) {
                            ForEach(segments.indices, id: \.self) { index in
                                segmentLabel(
                                    for: segments[index],
                                    at: index
                                )
                                .frame(
                                    width: segmentWidths[index],
                                    alignment: labelAlignment(for: index)
                                )
                            }
                        }
                    }
                }
                .frame(height: 42)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabel)
            }
        }
    }

    private func fundingSegment(
        for segment: PaymentPlanSetAsideSegment
    ) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppColors.secondaryText.opacity(0.18))

                Rectangle()
                    .fill(style.primary)
                    .frame(width: proxy.size.width * segment.fundingProgress)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AppColors.secondaryText.opacity(0.14), lineWidth: 1)
            }
        }
    }

    private func segmentLabel(
        for segment: PaymentPlanSetAsideSegment,
        at index: Int
    ) -> some View {
        VStack(spacing: 1) {
            Text(AppFormatters.currency(segment.target))
                .font(.caption2.weight(.bold))
                .foregroundColor(style.primary)
                .monospacedDigit()

            Text("\(segment.title) · \(AppFormatters.abbreviatedMonthDay(segment.dueDate))")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .multilineTextAlignment(textAlignment(for: index))
    }

    private func widths(for totalWidth: CGFloat) -> [CGFloat] {
        let totalSpacing = segmentSpacing * CGFloat(max(segments.count - 1, 0))
        let availableWidth = max(totalWidth - totalSpacing, 0)
        return segments.map { availableWidth * ($0.target / totalTarget) }
    }

    private func labelAlignment(for index: Int) -> Alignment {
        if segments.count == 1 || index == segments.count - 1 {
            return .trailing
        }

        return index == 0 ? .leading : .center
    }

    private func textAlignment(for index: Int) -> TextAlignment {
        if segments.count == 1 || index == segments.count - 1 {
            return .trailing
        }

        return index == 0 ? .leading : .center
    }

    private var accessibilityLabel: String {
        segments.map { segment in
            "\(segment.title), \(AppFormatters.currency(segment.target)) due \(AppFormatters.abbreviatedMonthDay(segment.dueDate)), \(AppFormatters.currency(min(segment.setAside, segment.target))) set aside"
        }
        .joined(separator: ". ")
    }
}

private struct PaymentPlanSetAsidePreviewRow: View {

    let display: DebtPayoffDisplayModel
    let style: CalderaCategoryStyle
    let action: () -> Void

    private var statusTitle: String? {
        switch display.presentationStatus {
        case .notYetFunded:
            return nil
        case .partlyFunded:
            return "Partly funded"
        case .fullyCovered:
            return "Funded"
        case .pastDue:
            return "Past due"
        case .paymentAmountNeeded:
            return nil
        case .handled:
            return "Handled"
        }
    }

    private var statusColor: Color {
        display.presentationStatus.isReassuring
            ? CalderaCategoryStyle.style(for: .covered).primary
            : style.primary
    }

    private var remainingText: String {
        if display.plannedPaymentAmount <= 0 {
            return "Payment target needed"
        }

        return "\(AppFormatters.currency(max(display.remainingPaymentAmount, 0))) needed"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                HStack(alignment: .center, spacing: AppSpacing.small) {
                    CalderaGradientIcon(
                        style: style,
                        size: 30,
                        iconSize: 12
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(detailLine)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: AppSpacing.xSmall)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(display.plannedPaymentValue)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(style.primary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        if let statusTitle {
                            Text(statusTitle)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(statusColor.opacity(0.82))
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.small) {
                        fundingStatusLine
                        Spacer(minLength: AppSpacing.small)
                        remainingLabel
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        fundingStatusLine
                        remainingLabel
                    }
                }

                CalderaProgressBar(
                    progress: display.progressValue,
                    colors: style.gradient
                )
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(display.accessibilitySummary)
        .accessibilityHint("Opens this Payment Plan.")
    }

    private var detailLine: String {
        guard display.isLinkedCreditCard else {
            return display.dueDateValue
        }

        return "\(display.dueDateValue) · \(display.plannedPaymentMeaningValue)"
    }

    private var fundingStatusLine: some View {
        Text("\(display.setAsideValue) set aside")
            .font(.caption2.weight(.medium))
            .foregroundColor(AppColors.secondaryText)
            .monospacedDigit()
    }

    private var remainingLabel: some View {
        Text(remainingText)
            .font(.caption2.weight(.medium))
            .foregroundColor(remainingColor)
            .monospacedDigit()
    }

    private var remainingColor: Color {
        switch display.presentationStatus {
        case .pastDue, .paymentAmountNeeded:
            return style.primary
        default:
            return AppColors.secondaryText
        }
    }
}

struct DebtPayoffCompactCard: View {

    let display: DebtPayoffDisplayModel
    let style: CalderaCategoryStyle
    let balanceLastUpdatedText: String?
    let action: () -> Void

    private var plaidSyncLine: String? {
        guard display.isLinkedCreditCard else {
            return nil
        }

        switch display.linkedCardBalanceState {
        case .notLinked:
            return nil

        case .available(let balanceText):
            guard let balanceLastUpdatedText,
                  balanceLastUpdatedText != "Not refreshed yet" else {
                return "Card balance \(balanceText) · Not refreshed yet"
            }

            return "Card balance \(balanceText) · \(balanceLastUpdatedText)"

        case .notFound:
            return "Linked card not found. Reconnect or create a new payment plan."
        }
    }

    private var statusColor: Color {
        display.presentationStatus.isReassuring
            ? CalderaCategoryStyle.style(for: .covered).primary
            : CalderaCategoryStyle.style(for: .needsMoney).primary
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            HStack(
                alignment: .top,
                spacing: AppSpacing.medium
            ) {
                CalderaGradientIcon(
                    style: style,
                    size: 32,
                    iconSize: 13
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(display.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Payment Plan")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer(minLength: AppSpacing.small)

                Text(display.presentationStatusValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(statusColor)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("Planned payment")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                Text(display.plannedPaymentValue)
                    .font(.title3.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)

                Text(display.plannedPaymentMeaningValue)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                Text(display.dueDateValue)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            amountSummary

            Text("Next: \(display.nextActionValue)")
                .font(.caption.weight(.semibold))
                .foregroundColor(statusColor)
                .fixedSize(horizontal: false, vertical: true)

            if let plaidSyncLine {
                Text(plaidSyncLine)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(
                        display.fundingState == .balanceUnavailable
                            ? CalderaCategoryStyle.style(for: .needsMoney).primary
                            : AppColors.secondaryText.opacity(0.86)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            } else if let balanceLine = display.balanceLine {
                Text(balanceLine)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(display.accessibilitySummary)
        .accessibilityHint("Opens this Payment Plan.")
    }

    private var amountSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.small) {
                amountValue(
                    title: "Set aside",
                    value: display.setAsideValue
                )

                amountValue(
                    title: "Still needed",
                    value: display.remainingValue
                )
            }

            VStack(spacing: AppSpacing.xSmall) {
                amountValue(
                    title: "Set aside",
                    value: display.setAsideValue
                )

                amountValue(
                    title: "Still needed",
                    value: display.remainingValue
                )
            }
        }
    }

    private func amountValue(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.small)
        .background(
            RoundedRectangle(
                cornerRadius: AppRadii.field,
                style: .continuous
            )
            .fill(style.primary.opacity(0.07))
        )
    }
}
