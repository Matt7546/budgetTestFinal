import SwiftData
import SwiftUI

struct SettingsIncomePlanningSection: View {
    let ownerScopeID: String

    @Query
    private var schedules: [IncomeSchedule]

    @State
    private var editorRequest: IncomeScheduleEditorRequest?

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

    private var visibleSchedule: IncomeSchedule? {
        IncomeSchedulePhaseOnePolicy.visibleSchedule(
            from: schedules,
            ownerScopeID: ownerScopeID
        )
    }

    var body: some View {
        SettingsSection(
            title: "Planning",
            systemImage: "calendar.badge.clock",
            color: CalderaCategoryStyle.style(for: .income).primary
        ) {
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
