import SwiftUI

struct PlannerEventRow: View {

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
                return "Shortfall Before \(event.name)"
            }

            return "Low Buffer Until Payday"
        }

        if projectedAvailable < 0 {
            return "Shortfall Before \(event.name)"
        }

        if projectedAvailable < 500 {
            return "Low Buffer Until Payday"
        }

        return "Safe Through \(occurrenceDate.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var statusColor: Color {
        if isOverdue {
            return isCovered
                ? AppColors.spendable
                : AppColors.warning
        }

        if usesCoverageAwareStatus,
           event.type == .expense {
            if isCovered ||
                currentSafeToSpend >= remainingAmount {
                return AppColors.spendable
            }

            if currentSafeToSpend < 0 {
                return AppColors.negative
            }

            return AppColors.warning
        }

        if projectedAvailable < 0 {
            return AppColors.negative
        }

        if projectedAvailable < 500 {
            return AppColors.warning
        }

        return AppColors.spendable
    }

    private var iconColor: Color {

        switch event.type {

        case .expense:
            return AppColors.obligation

        case .income:
            return AppColors.spendable
        }
    }

    private var monthText: String {

        occurrenceDate.formatted(
            .dateTime.month(.abbreviated)
        )
        .uppercased()
    }

    private var dayText: String {

        occurrenceDate.formatted(
            .dateTime.day()
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

                HStack(spacing: 16) {

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

                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {

                        Text(event.name)
                            .font(.headline)

                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(statusColor)

                        Text(
                            "After Event: \(projectedAvailable.formatted(.currency(code: "USD")))"
                        )
                        .font(.caption)
                        .foregroundStyle(AppColors.secondaryText)
                    }

                    Spacer()

                    VStack(
                        alignment: .trailing,
                        spacing: 6
                    ) {

                        Text(
                            event.amount,
                            format: .currency(
                                code: "USD"
                            )
                        )
                        .font(.headline.bold())
                        .foregroundColor(iconColor)

                        if event.frequency != .once {

                            Text(event.frequency.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(
                                            AppColors.secondaryText.opacity(0.12)
                                        )
                                )
                        }
                    }
                }

                allocationSummary
            }
            .padding(20)
            .background {


            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .fill(.ultraThinMaterial)


            }
            .overlay {


            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        AppColors.glassOverlayWhite,
                        AppColors.glassOverlaySurface,
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )


            }
            .overlay {


            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                LinearGradient(
                    colors: [
                        AppColors.glassHighlight,
                        AppColors.glassSubtleHighlight
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )


            }
            .shadow(
            color: AppColors.glassSubtleHighlight,
            radius: 2,
            y: -1
            )
            .shadow(
            color: AppColors.shadowCompact,
            radius: 24,
            y: 12
            )

        }
        .buttonStyle(.plain)
    }

    private var allocationSummary: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.secondaryText.opacity(0.14))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.protected,
                                    AppColors.accent
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: proxy.size.width * allocationProgress
                        )
                }
            }
            .frame(height: 8)

            HStack(alignment: .firstTextBaseline) {
                Text(
                    "\(clampedAllocatedAmount.formatted(.currency(code: "USD"))) of \(event.amount.formatted(.currency(code: "USD"))) allocated"
                )
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                Spacer()

                Text(
                    isCovered
                        ? "Covered"
                        : "\(remainingAmount.formatted(.currency(code: "USD"))) remaining"
                )
                .font(.caption2.weight(.semibold))
                .foregroundColor(
                    isCovered
                        ? AppColors.spendable
                        : AppColors.warning
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
    }
}
