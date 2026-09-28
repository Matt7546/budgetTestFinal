import SwiftData
import SwiftUI

struct SettingsIncomePlanningSection: View {
    let ownerScopeID: String
    let basePlanningAvailability: PlanningSnapshotAvailability
    let retryPlanningSnapshot: () -> Void

    @Query
    private var schedules: [IncomeSchedule]

    @State
    private var editorRequest: IncomeScheduleEditorRequest?

    init(
        ownerScopeID: String,
        basePlanningAvailability: PlanningSnapshotAvailability,
        retryPlanningSnapshot: @escaping () -> Void
    ) {
        self.ownerScopeID = ownerScopeID
        self.basePlanningAvailability = basePlanningAvailability
        self.retryPlanningSnapshot = retryPlanningSnapshot
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

    private var visibleSchedule: IncomeSchedule? {
        IncomeSchedulePhaseOnePolicy.visibleSchedule(
            from: schedules,
            ownerScopeID: ownerScopeID
        )
    }

    private var planningAvailability: PlanningSnapshotAvailability {
        PlanningSnapshotAvailability.resolving(
            base: basePlanningAvailability,
            failedRequiredReads: _schedules.fetchError == nil
                ? []
                : [.incomeSchedules]
        )
    }

    var body: some View {
        SettingsSection(
            title: "Planning",
            systemImage: "calendar.badge.clock",
            color: CalderaCategoryStyle.style(for: .income).primary
        ) {
            if planningAvailability == .available {
                Button {
                    if let visibleSchedule {
                        editorRequest = .edit(visibleSchedule)
                    } else {
                        editorRequest = .create(ownerScopeID: ownerScopeID)
                    }
                } label: {
                    SettingsNavigationRow(
                        title: visibleSchedule == nil
                            ? "Set up expected income"
                            : "Expected income",
                        description: scheduleDescription,
                        systemImage: "banknote.fill",
                        color: CalderaCategoryStyle.style(for: .income).primary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settingsAccessibilityLabel)
            } else {
                planningUnavailableContent
            }
        }
        .sheet(item: $editorRequest) { request in
            switch request {
            case .create(let ownerScopeID):
                IncomeScheduleEditorView(
                    ownerScopeID: ownerScopeID,
                    editingSchedule: nil
                )

            case .edit(let schedule):
                IncomeScheduleEditorView(
                    ownerScopeID: schedule.ownerScopeID,
                    editingSchedule: schedule
                )
            }
        }
        .onChange(of: planningAvailability) { _, availability in
            if availability != .available {
                editorRequest = nil
            }
        }
    }

    @ViewBuilder
    private var planningUnavailableContent: some View {
        HStack(spacing: AppSpacing.medium) {
            if planningAvailability == .loading {
                ProgressView()
            } else {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundColor(
                        CalderaCategoryStyle.style(for: .income).primary
                    )
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(
                    planningAvailability == .loading
                        ? "Loading expected income"
                        : "Expected income couldn’t load"
                )
                .font(.headline)

                Text("Your saved schedule is unchanged.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer(minLength: AppSpacing.small)

            if planningAvailability == .unavailable {
                Button("Try Again", action: retryPlanningSnapshot)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var scheduleDescription: String {
        guard let schedule = visibleSchedule,
              let frequency = schedule.frequency else {
            return "Add what usually lands in your bank account and when you expect it."
        }

        if IncomeScheduleCalendar.needsExplicitPaydayUpdate(schedule) {
            return "Update your next payday."
        }

        guard let nextDate = IncomeScheduleCalendar.nextDisplayDate(
            for: schedule
        ) else {
            return "Review this expected-income schedule."
        }

        return "\(AppFormatters.currency(schedule.takeHomeAmount)) \(frequency.summaryPhrase) · Next \(AppFormatters.abbreviatedMonthDay(nextDate))"
    }

    private var settingsAccessibilityLabel: String {
        if visibleSchedule == nil {
            return "Set up expected income"
        }

        return "Expected income. \(scheduleDescription)"
    }
}

private enum IncomeScheduleEditorRequest: Identifiable {
    case create(ownerScopeID: String)
    case edit(IncomeSchedule)

    var id: String {
        switch self {
        case .create(let ownerScopeID):
            return "create-\(ownerScopeID)"
        case .edit(let schedule):
            return "edit-\(schedule.id.uuidString)"
        }
    }
}
