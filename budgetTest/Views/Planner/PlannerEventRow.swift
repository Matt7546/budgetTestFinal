import SwiftUI

struct PlannerEventRow: View {

    @Environment(\.colorScheme) private var colorScheme

    let event: PlannerEvent
    let occurrenceDate: Date
    let projectedAvailable: Double
    let currentSafeToSpend: Double
    let allocatedAmount: Double
    let usesCoverageAwareStatus: Bool
    let onModify: () -> Void

    private let currencyTolerance = 0.005

    private var clampedAllocatedAmount: Double {
        min(
            max(allocatedAmount, 0),
            event.amount
        )
    }

    private var remainingAmount: Double {
        max(
            event.amount - clampedAllocatedAmount,
            0
        )
    }

    private var allocationProgress: Double {
        guard event.amount > 0 else {
            return 0
        }

        return min(
            max(clampedAllocatedAmount / event.amount, 0),
            1
        )
    }

    private var safeAllocationProgress: Double {
        guard allocationProgress.isFinite else {
            return 0
        }

        return min(
            max(allocationProgress, 0),
            1
        )
    }

    private var isCovered: Bool {
        remainingAmount <= currencyTolerance
    }

    private var isOverdue: Bool {
        event.type == .expense &&
        Calendar.current.startOfDay(for: occurrenceDate) <
        Calendar.current.startOfDay(for: Date())
    }

    private var statusText: String {
        if isOverdue {
            return isCovered
                ? "Overdue · Covered"
                : "Overdue"
        }

        if usesCoverageAwareStatus,
           event.type == .expense {
            if isCovered {
                return "Next expense covered"
            }

            if currentSafeToSpend >= remainingAmount {
                return "Enough available for next expense"
            }

            if currentSafeToSpend < 0 {
                return "Needs money before \(event.name)"
            }

            return "Low buffer before payday"
        }

        if projectedAvailable < 0 {
            return "Needs money before \(event.name)"
        }

        if projectedAvailable < 500 {
            return "Low buffer before payday"
        }

        return "Covered Through \(AppFormatters.abbreviatedMonthDay(occurrenceDate))"
    }

    private var statusColor: Color {
        if isOverdue {
            return isCovered
                ? CalderaCategoryStyle.style(for: .covered).primary
                : CalderaCategoryStyle.style(for: .needsMoney).primary
        }

        if usesCoverageAwareStatus,
           event.type == .expense {
            if isCovered ||
                currentSafeToSpend >= remainingAmount {
                return CalderaCategoryStyle.style(for: .covered).primary
            }

            if currentSafeToSpend < 0 {
                return CalderaCategoryStyle.style(for: .shortfall).primary
            }

            return CalderaCategoryStyle.style(for: .needsMoney).primary
        }

        if projectedAvailable < 0 {
            return CalderaCategoryStyle.style(for: .shortfall).primary
        }

        if projectedAvailable < 500 {
            return CalderaCategoryStyle.style(for: .needsMoney).primary
        }

        return CalderaCategoryStyle.style(for: .covered).primary
    }

    private var eventAccentColor: Color? {
        guard event.type == .expense else {
            return nil
        }

        return PlannerEventColor.color(for: event.accentColorID)
    }

    private var iconColor: Color {

        switch event.type {

        case .expense:
            return CalderaCategoryStyle.style(for: .upcomingExpense).primary

        case .income:
            return CalderaCategoryStyle.style(for: .income).primary
        }
    }

    private var amountColor: Color {
        switch event.type {
        case .expense:
            return statusColor == AppColors.negative
                ? CalderaCategoryStyle.style(for: .shortfall).primary
                : CalderaCategoryStyle.style(for: .upcomingExpense).primary

        case .income:
            return CalderaCategoryStyle.style(for: .income).primary
        }
    }

    private var afterEventLabel: String {
        switch event.type {
        case .expense:
            return "After this expense"

        case .income:
            return "After this income"
        }
    }

    private var monthText: String {

        AppFormatters.abbreviatedMonth(
            occurrenceDate
        )
        .uppercased()
    }

    private var dayText: String {

        AppFormatters.day(
            occurrenceDate
        )
    }

    var body: some View {

        Button {

            onModify()

        } label: {

            VStack(
                alignment: .leading,
                spacing: AppSpacing.medium
            ) {

                HStack(spacing: AppSpacing.medium) {

                    VStack(spacing: 2) {

                        Text(monthText)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColors.secondaryText)

                        Text(dayText)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColors.primaryText)
                    }
                    .frame(width: 50)
                    .padding(.vertical, AppSpacing.small)
                    .calderaGlassCard(
                        cornerRadius: 18,
                        fillOpacity: 0.70,
                        strokeOpacity: 0.54,
                        shadowOpacity: 0,
                        shadowRadius: 0,
                        shadowY: 0
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {

                        Text(event.name)
                            .font(.headline)
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)

                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(statusColor)
                            .lineLimit(2)

                        Text(
                            "\(afterEventLabel): \(AppFormatters.currency(projectedAvailable))"
                        )
                        .font(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    VStack(
                        alignment: .trailing,
                        spacing: 6
                    ) {

                        Text(
                            AppFormatters.currency(
                                event.amount
                            )
                        )
                        .font(.headline.bold())
                        .foregroundColor(amountColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                        if event.frequency != .once {

                            Text(event.frequency.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(AppColors.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(
                                            AppColors.secondaryText.opacity(0.10)
                                        )
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            AppColors.glassSubtleHighlight.opacity(0.45),
                                            lineWidth: 1
                                        )
                                }
                        }
                    }
                }

                allocationSummary
            }
            .padding(20)
            .calderaGlassCard(
                cornerRadius: 28,
                fillOpacity: 0.86,
                strokeOpacity: 0.72,
                shadowOpacity: 0.038,
                shadowRadius: 18,
                shadowY: 9
            )
            .overlay(alignment: .leading) {
                if let eventAccentColor {
                    RoundedRectangle(
                        cornerRadius: 3,
                        style: .continuous
                    )
                    .fill(eventAccentColor)
                    .frame(width: 5)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
                }
            }

        }
        .buttonStyle(.plain)
    }

    private var allocationSummary: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            CalderaProgressBar(
                progress: safeAllocationProgress,
                colors: [
                    statusColor == AppColors.negative
                        ? CalderaCategoryStyle.style(for: .shortfall).primary
                        : CalderaCategoryStyle.style(for: .upcomingExpense).primary,
                    statusColor == AppColors.warning
                        ? CalderaCategoryStyle.style(for: .needsMoney).primary
                        : CalderaCategoryStyle.style(for: .covered).primary,
                    CalderaCategoryStyle.style(for: .safeToSpend).primary
                ]
            )

            HStack(alignment: .firstTextBaseline) {
                Text(
                    "\(AppFormatters.currency(clampedAllocatedAmount)) set aside of \(AppFormatters.currency(event.amount))"
                )
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Spacer()

                Text(
                    isCovered
                        ? "Covered"
                        : "Needs \(AppFormatters.currency(remainingAmount))"
                )
                .font(.caption2.weight(.semibold))
                .foregroundColor(
                    isCovered
                        ? CalderaCategoryStyle.style(for: .covered).primary
                        : CalderaCategoryStyle.style(for: .needsMoney).primary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
    }
}
