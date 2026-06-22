import SwiftUI

struct UpcomingExpenseAllocation: Identifiable {

    let forecast: ForecastEvent
    let allocatedAmount: Double

    var id: String {
        forecast.occurrenceID
    }

    var remainingAmount: Double {
        max(
            forecast.event.amount - allocatedAmount,
            0
        )
    }
}

struct UpcomingExpensesSection: View {

    let expenses: [UpcomingExpenseAllocation]

    private var totalAllocated: Double {
        expenses.reduce(0) {
            $0 + $1.allocatedAmount
        }
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Upcoming Expenses")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)

                    Text("Money allocated toward upcoming planner expenses")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                MetricValue(
                    totalAllocated,
                    font: .headline.bold(),
                    color: AppColors.protected,
                    minimumScaleFactor: 0.7,
                    lineLimit: 1
                )
            }

            ForEach(expenses.prefix(4)) { expense in
                Divider()

                HStack(spacing: AppSpacing.medium) {
                    IconBadge(
                        systemImage: "calendar.badge.exclamationmark",
                        color: AppColors.obligation,
                        size: 34,
                        iconSize: 14
                    )

                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.xxSmall
                    ) {
                        Text(expense.forecast.event.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)

                        Text(
                            expense.forecast.occurrenceDate.formatted(
                                .dateTime
                                    .month(.abbreviated)
                                    .day()
                                    .year()
                            )
                        )
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                    }

                    Spacer()

                    VStack(
                        alignment: .trailing,
                        spacing: AppSpacing.xxSmall
                    ) {
                        MetricValue(
                            expense.allocatedAmount,
                            font: .subheadline.weight(.bold),
                            color: AppColors.protected,
                            minimumScaleFactor: 0.7,
                            lineLimit: 1
                        )

                        Text(
                            expense.remainingAmount <= 0
                                ? "Covered"
                                : "\(expense.remainingAmount.formatted(.currency(code: "USD"))) remaining"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(
                            expense.remainingAmount <= 0
                                ? AppColors.spendable
                                : AppColors.warning
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                }
            }
        }
        .padding(AppSpacing.card)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.warning.opacity(0.07),
                    AppColors.glassOverlaySurface
                ]
            ),
            accent: AppColors.warning,
            shadow: AppShadows.softPanel
        )
    }
}
