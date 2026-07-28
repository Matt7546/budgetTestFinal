#if DEBUG

import SwiftUI

struct LabPaymentPlanAdaptiveBarPrototypeView: View {

    @State private var paymentCount: LabPaymentPlanTimelineCount = .three

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    private var payments: [LabPaymentPlanTimelinePayment] {
        Array(Self.samplePayments.prefix(paymentCount.rawValue))
    }

    var body: some View {
        AppScreen {
            previewControls

            SavingsSectionShell(
                title: "Payment Plans",
                description: "Plan for upcoming card payments.",
                style: style
            ) {
                SavingsSeeAllLabel()
            } content: {
                VStack(spacing: AppSpacing.small) {
                    LabPaymentPlanTimelineSummary(
                        payments: payments,
                        style: style
                    )

                    ForEach(Array(payments.enumerated()), id: \.element.id) {
                        index,
                        payment in
                        LabPaymentPlanTimelinePreviewRow(
                            payment: payment,
                            style: style,
                            showsDivider: index < payments.count - 1
                        )
                    }

                    Label(
                        "Card balances refreshed just now",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                    Label(
                        "\(AppBrand.shortName) does not make payments.",
                        systemImage: "info.circle"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                    SavingsQuickAddButton(
                        title: "Create Payment Plan",
                        style: style,
                        accessibilityLabel: "Create Payment Plan prototype"
                    ) {
                        // This Lab surface intentionally has no production action.
                    }
                }
            }
        }
        .navigationTitle("Adaptive Bar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewControls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text("Timeline preview")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            Picker("Payments shown", selection: $paymentCount) {
                ForEach(LabPaymentPlanTimelineCount.allCases) { count in
                    Text(count.title).tag(count)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Changes the number of upcoming payment markers in the Lab prototype.")
        }
    }

    private static let samplePayments = [
        LabPaymentPlanTimelinePayment(
            name: "Amex Gold",
            target: 384,
            setAside: 384,
            dueDate: "Aug 13"
        ),
        LabPaymentPlanTimelinePayment(
            name: "Platinum",
            target: 700,
            setAside: 451,
            dueDate: "Sep 1"
        ),
        LabPaymentPlanTimelinePayment(
            name: "Chase",
            target: 502,
            setAside: 0,
            dueDate: "Sep 3"
        )
    ]
}

private enum LabPaymentPlanTimelineCount: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }

    var title: String { "\(rawValue)" }
}

private struct LabPaymentPlanTimelinePayment: Identifiable {
    let name: String
    let target: Double
    let setAside: Double
    let dueDate: String

    var id: String { name }

    var remaining: Double {
        max(target - setAside, 0)
    }

    var fundingProgress: Double {
        guard target > 0 else {
            return 0
        }

        return min(max(setAside / target, 0), 1)
    }

    var status: String {
        switch fundingProgress {
        case 1:
            return "Funded"
        case 0:
            return "Not funded"
        default:
            return "Partly funded"
        }
    }
}

private struct LabPaymentPlanTimelineSummary: View {

    let payments: [LabPaymentPlanTimelinePayment]
    let style: CalderaCategoryStyle

    private var totalTarget: Double {
        payments.reduce(0) { $0 + $1.target }
    }

    private var totalSetAside: Double {
        payments.reduce(0) { $0 + $1.setAside }
    }

    private var stillNeeded: Double {
        max(totalTarget - totalSetAside, 0)
    }

    private var countText: String {
        "\(payments.count) upcoming payment\(payments.count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(countText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)

            Text(
                "\(AppFormatters.currency(totalSetAside)) of \(AppFormatters.currency(totalTarget)) set aside"
            )
            .font(.caption.weight(.medium))
            .foregroundColor(AppColors.secondaryText)
            .monospacedDigit()

            Text("\(AppFormatters.currency(stillNeeded)) still needed")
                .font(.caption.weight(.semibold))
                .foregroundColor(style.primary)
                .monospacedDigit()

            LabPaymentPlanAdaptiveTimelineBar(
                payments: payments,
                style: style
            )
            .padding(.top, AppSpacing.xxSmall)
        }
        .padding(.vertical, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(countText), \(AppFormatters.currency(totalSetAside)) of \(AppFormatters.currency(totalTarget)) set aside, \(AppFormatters.currency(stillNeeded)) still needed"
        )
    }
}

private struct LabPaymentPlanAdaptiveTimelineBar: View {

    let payments: [LabPaymentPlanTimelinePayment]
    let style: CalderaCategoryStyle

    private var totalTarget: Double {
        payments.reduce(0) { $0 + $1.target }
    }

    var body: some View {
        GeometryReader { proxy in
            let barWidth = max(proxy.size.width, 1)

            ZStack(alignment: .topLeading) {
                fundingTrack(width: barWidth)

                ForEach(Array(payments.enumerated()), id: \.element.id) {
                    index,
                    payment in
                    marker(
                        for: payment,
                        at: markerFraction(after: index),
                        barWidth: barWidth
                    )
                }
            }
        }
        .frame(height: 64)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(timelineAccessibilityLabel)
    }

    private func fundingTrack(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(payments) { payment in
                let segmentWidth = width * targetFraction(for: payment)
                let fundedWidth = segmentWidth * payment.fundingProgress

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(style.primary)
                        .frame(width: fundedWidth)

                    Rectangle()
                        .fill(AppColors.secondaryText.opacity(0.18))
                        .frame(width: max(segmentWidth - fundedWidth, 0))
                }
                .frame(width: segmentWidth, alignment: .leading)
            }
        }
        .frame(width: width, height: 8, alignment: .leading)
        .clipShape(Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(AppColors.secondaryText.opacity(0.14), lineWidth: 1)
        }
        .padding(.top, 4)
    }

    private func marker(
        for payment: LabPaymentPlanTimelinePayment,
        at fraction: Double,
        barWidth: CGFloat
    ) -> some View {
        let markerX = barWidth * fraction
        let labelWidth = min(max(barWidth * 0.28, 76), 94)
        let labelX = min(
            max(markerX, labelWidth / 2),
            barWidth - labelWidth / 2
        )

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(style.primary.opacity(0.7))
                .frame(width: 1, height: 13)
                .position(x: markerX, y: 8)

            VStack(spacing: 1) {
                Text(AppFormatters.currency(payment.target))
                    .font(.caption2.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()

                Text("\(payment.name) · \(payment.dueDate)")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .multilineTextAlignment(.center)
            .frame(width: labelWidth)
            .position(x: labelX, y: 39)
        }
    }

    private func targetFraction(
        for payment: LabPaymentPlanTimelinePayment
    ) -> CGFloat {
        guard totalTarget > 0 else {
            return 0
        }

        return payment.target / totalTarget
    }

    private func markerFraction(after index: Int) -> CGFloat {
        guard totalTarget > 0 else {
            return 0
        }

        let cumulativeTarget = payments
            .prefix(index + 1)
            .reduce(0) { $0 + $1.target }
        return cumulativeTarget / totalTarget
    }

    private var timelineAccessibilityLabel: String {
        payments.map { payment in
            "\(payment.name), \(AppFormatters.currency(payment.target)) due \(payment.dueDate), \(AppFormatters.currency(payment.setAside)) set aside"
        }
        .joined(separator: ". ")
    }
}

private struct LabPaymentPlanTimelinePreviewRow: View {

    let payment: LabPaymentPlanTimelinePayment
    let style: CalderaCategoryStyle
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    style: style,
                    size: 30,
                    iconSize: 12
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(payment.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text("Due \(payment.dueDate) · Statement balance")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: AppSpacing.xSmall)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(payment.status)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(
                            payment.fundingProgress == 1
                                ? CalderaCategoryStyle.style(for: .covered).primary.opacity(0.82)
                                : style.primary.opacity(0.82)
                        )

                    Text(AppFormatters.currency(payment.target))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(style.primary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: AppSpacing.small) {
                Text("\(AppFormatters.currency(payment.setAside)) set aside")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .monospacedDigit()

                Spacer(minLength: AppSpacing.small)

                Text("\(AppFormatters.currency(payment.remaining)) needed")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .monospacedDigit()
            }

            CalderaProgressBar(
                progress: payment.fundingProgress,
                colors: style.gradient
            )
            .frame(height: 5)
        }
        .padding(.vertical, AppSpacing.small)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(AppColors.secondaryText.opacity(0.14))
                    .frame(height: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(payment.name), \(payment.status), \(AppFormatters.currency(payment.target)) due \(payment.dueDate), \(AppFormatters.currency(payment.setAside)) set aside, \(AppFormatters.currency(payment.remaining)) needed"
        )
    }
}

#endif
