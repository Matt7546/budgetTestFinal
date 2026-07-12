import SwiftData
import SwiftUI

struct ExpectedIncomePlanAheadSection: View {
    let ownerScopeID: String

    @Query
    private var schedules: [IncomeSchedule]

    init(ownerScopeID: String) {
        self.ownerScopeID = ownerScopeID
        let exactOwnerScopeID = ownerScopeID

        _schedules = Query(
            filter: #Predicate<IncomeSchedule> {
                $0.ownerScopeID == exactOwnerScopeID
            },
            sort: [
                SortDescriptor(\IncomeSchedule.sortOrder),
                SortDescriptor(\IncomeSchedule.createdAt)
            ]
        )
    }

    private var schedule: IncomeSchedule? {
        IncomeSchedulePhaseOnePolicy.visibleSchedule(
            from: schedules,
            ownerScopeID: ownerScopeID
        )
    }

    var body: some View {
        if let schedule {
            ExpectedIncomeCard(schedule: schedule)
        }
    }
}

private struct ExpectedIncomeCard: View {
    let schedule: IncomeSchedule

    private var nextDate: Date? {
        IncomeScheduleCalendar.nextDisplayDate(for: schedule)
    }

    private var needsUpdate: Bool {
        IncomeScheduleCalendar.needsExplicitPaydayUpdate(schedule)
    }

    private var incomeColor: Color {
        CalderaCategoryStyle.style(for: .income).primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: CalderaCategoryStyle.style(for: .income),
                    size: 46,
                    iconSize: 19
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Planning estimate")
                        .font(.caption.weight(.bold))
                        .foregroundColor(incomeColor)

                    Text(needsUpdate ? "Update your next payday" : "Expected income")
                        .font(.title3.weight(.bold))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppSpacing.small)
            }

            if needsUpdate {
                Text("Your saved next payday has passed. Update it in More before relying on this plan.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(AppFormatters.currency(schedule.takeHomeAmount)) expected")
                        .font(.headline.weight(.bold))
                        .foregroundColor(incomeColor)
                        .monospacedDigit()

                    Spacer(minLength: AppSpacing.small)

                    if let nextDate {
                        Text(fullDate(nextDate))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Divider()

            Text("Not included in Available to Spend until it arrives in a linked account.")
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.88,
            strokeOpacity: 0.72,
            shadowOpacity: 0.035,
            shadowRadius: 16,
            shadowY: 8,
            darkGlowColor: incomeColor
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if needsUpdate {
            return "Planning estimate. Update your next payday. Not included in Available to Spend."
        }

        let dateText = nextDate.map(fullDate) ?? "date unavailable"
        return "Planning estimate. \(AppFormatters.currency(schedule.takeHomeAmount)) expected \(dateText). Not included in Available to Spend until it arrives in a linked account."
    }

    private func fullDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
        )
    }
}
