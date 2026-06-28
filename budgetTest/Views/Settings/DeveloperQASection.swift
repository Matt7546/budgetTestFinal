#if DEBUG
import SwiftUI
import SwiftData

struct DeveloperQASection: View {

    @EnvironmentObject private var plaid: PlaidService
    @Environment(\.modelContext)
    private var modelContext

    @State private var pendingQAAction: DeveloperQAAction?
    @State private var qaStatusMessage: String?

    var body: some View {
        SettingsSection(
            title: "Developer QA",
            systemImage: "wrench.and.screwdriver.fill",
            color: AppColors.warning
        ) {
            SettingsInfoRow(
                title: "QA Scenario",
                description: "Debug-only tools for resetting local app data and loading a known manual testing scenario.",
                systemImage: "testtube.2",
                color: AppColors.warning
            )

            Divider()

            PrimaryButton(
                "Load QA Scenario",
                systemImage: "tray.and.arrow.down.fill",
                trailingSystemImage: nil,
                cornerRadius: AppRadii.button,
                fillsWidth: true
            ) {
                pendingQAAction = .loadScenario
            }
            .accessibilityLabel("Load QA scenario")

            PrimaryButton(
                "Load Recurrence Edge Cases",
                systemImage: "calendar.badge.exclamationmark",
                trailingSystemImage: nil,
                cornerRadius: AppRadii.button,
                fillsWidth: true
            ) {
                pendingQAAction = .loadRecurrenceEdgeCases
            }
            .accessibilityLabel("Load recurrence edge cases")

            DestructiveButton(
                "Reset Local Data",
                systemImage: "trash.fill",
                cornerRadius: AppRadii.button
            ) {
                pendingQAAction = .resetLocalData
            }
            .accessibilityLabel("Reset local data")

            if let qaStatusMessage {
                Text(qaStatusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(qaStatusMessage)
            }
        }
        .confirmationDialog(
            pendingQAAction?.title ?? "Developer QA",
            isPresented: Binding(
                get: {
                    pendingQAAction != nil
                },
                set: { isPresented in
                    if !isPresented {
                        pendingQAAction = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingQAAction {
                Button(
                    pendingQAAction.confirmationTitle,
                    role: pendingQAAction.role
                ) {
                    performQAAction(
                        pendingQAAction
                    )
                    self.pendingQAAction = nil
                }
            }

            Button("Cancel", role: .cancel) {
                pendingQAAction = nil
            }
        } message: {
            Text(
                pendingQAAction?.message ?? ""
            )
        }
    }

    private func performQAAction(
        _ action: DeveloperQAAction
    ) {
        switch action {
        case .resetLocalData:
            resetLocalDataForQA()

        case .loadScenario:
            loadQAScenario()

        case .loadRecurrenceEdgeCases:
            loadRecurrenceEdgeCases()
        }
    }

    private func loadQAScenario() {
        resetLocalDataForQA()
        plaid.debugLoadQAFinancialScenario()

        let rent = PlannerEvent(
            name: "Rent",
            amount: 1_000,
            date: nextQAExpenseDate,
            frequency: .monthly,
            type: .expense
        )

        modelContext.insert(
            rent
        )

        let rentOccurrence = ForecastEvent(
            event: rent,
            occurrenceDate: rent.date
        )

        modelContext.insert(
            EventAllocation(
                occurrenceID: rentOccurrence.occurrenceID,
                sourceEventID: rent.id,
                occurrenceDate: rentOccurrence.normalizedOccurrenceDate,
                allocatedAmount: 600
            )
        )

        modelContext.insert(
            DebtPayoffBucket(
                id: UUID(
                    uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
                ) ?? UUID(),
                plaidAccountID: "debug-qa-credit-card",
                accountName: "QA Credit Card",
                dueDate: nextQADebtDueDate,
                paymentTargetAmount: 1_200,
                protectedAmount: 300
            )
        )

        saveQAContext()
        qaStatusMessage = "Loaded QA scenario."
    }

    private func loadRecurrenceEdgeCases() {
        resetLocalDataForQA()

        let events = recurrenceEdgeCaseEvents

        for event in events {
            modelContext.insert(
                event
            )
        }

        saveQAContext()
        logRecurrenceEdgeCases(
            events
        )
        qaStatusMessage = "Loaded recurrence edge cases."
    }

    private func resetLocalDataForQA() {
        plaid.debugResetLocalUserData()

        deleteAll(
            PlannerEvent.self
        )
        deleteAll(
            EventAllocation.self
        )
        deleteAll(
            ExpenseOccurrenceStatus.self
        )
        deleteAll(
            DebtPayoffBucket.self
        )

        saveQAContext()
        qaStatusMessage = "Reset local data."
    }

    private var recurrenceEdgeCaseEvents: [PlannerEvent] {
        [
            PlannerEvent(
                name: "Monthly Jan 29 Test",
                amount: 129,
                date: qaDate(
                    month: 1,
                    day: 29
                ),
                frequency: .monthly,
                type: .expense
            ),
            PlannerEvent(
                name: "Monthly Jan 30 Test",
                amount: 130,
                date: qaDate(
                    month: 1,
                    day: 30
                ),
                frequency: .monthly,
                type: .expense
            ),
            PlannerEvent(
                name: "Monthly Jan 31 Test",
                amount: 131,
                date: qaDate(
                    month: 1,
                    day: 31
                ),
                frequency: .monthly,
                type: .expense
            ),
            PlannerEvent(
                name: "Every 3 Months Jan 31 Test",
                amount: 331,
                date: qaDate(
                    month: 1,
                    day: 31
                ),
                frequency: .quarterly,
                type: .expense
            ),
            PlannerEvent(
                name: "Every 2 Weeks Year-End Test",
                amount: 225,
                date: qaDate(
                    month: 12,
                    day: 25
                ),
                frequency: .biweekly,
                type: .expense
            )
        ]
    }

    private func qaDate(
        month: Int,
        day: Int
    ) -> Date {
        let calendar = Calendar.current
        let currentYear = calendar.component(
            .year,
            from: Date()
        )

        return calendar.date(
            from: DateComponents(
                year: currentYear,
                month: month,
                day: day
            )
        ) ?? Date()
    }

    private func logRecurrenceEdgeCases(
        _ events: [PlannerEvent]
    ) {
        let allocations = fetchAll(
            EventAllocation.self
        )
        let statuses = fetchAll(
            ExpenseOccurrenceStatus.self
        )

        for event in events {
            let calculator = PlannerForecastCalculator(
                events: [
                    event
                ],
                totalAvailable: 0,
                totalGoalAllocated: 0,
                includeFutureIncome: true,
                protectGoals: true,
                now: event.date
            )
            let occurrences = calculator
                .forecastEvents
                .filter {
                    $0.event.id == event.id
                }
                .prefix(12)
            let occurrenceIDs = occurrences.map(\.occurrenceID)
            let uniqueOccurrenceIDs = Set(occurrenceIDs)

            AppLogger.developerQA("")
            AppLogger.developerQA("=== Recurrence QA: \(event.name) ===")
            AppLogger.developerQA("Frequency: \(event.frequency.rawValue)")
            AppLogger.developerQA("Anchor: \(qaDateKey(event.date))")

            for (index, occurrence) in occurrences.enumerated() {
                let lifecycle = ExpenseOccurrenceLifecycleResolver.lifecycle(
                    for: occurrence,
                    statuses: statuses
                )
                let allocatedAmount = allocations.first {
                    $0.occurrenceID == occurrence.occurrenceID
                }?
                .allocatedAmount ?? 0
                let activeText = isActiveLifecycle(lifecycle)
                    ? "active"
                    : "inactive"

                AppLogger.developerQA(
                    "\(index + 1). \(qaDateKey(occurrence.occurrenceDate)) | id: \(occurrence.occurrenceID) | \(activeText) | status: \(lifecycle.qaConsoleTitle) | has allocation: \(allocatedAmount > 0)"
                )
            }

            AppLogger.developerQA("Unique occurrence IDs: \(uniqueOccurrenceIDs.count) / \(occurrenceIDs.count)")

            if uniqueOccurrenceIDs.count != occurrenceIDs.count {
                AppLogger.warning(
                    "duplicate occurrence IDs found",
                    category: .developerQA
                )
            }
        }
    }

    private func fetchAll<T: PersistentModel>(
        _ modelType: T.Type
    ) -> [T] {
        let descriptor = FetchDescriptor<T>()

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func qaDateKey(
        _ date: Date
    ) -> String {
        let components = Calendar.current.dateComponents(
            [
                .year,
                .month,
                .day
            ],
            from: date
        )

        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func isActiveLifecycle(
        _ lifecycle: ExpenseOccurrenceLifecycle
    ) -> Bool {
        switch lifecycle {
        case .upcoming,
                .overdue:
            return true

        case .paid,
                .skipped:
            return false
        }
    }

    private var nextQAExpenseDate: Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(
            for: Date()
        )

        return calendar.date(
            byAdding: .day,
            value: 1,
            to: startOfToday
        ) ?? startOfToday
    }

    private var nextQADebtDueDate: Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(
            for: Date()
        )

        return calendar.date(
            byAdding: .day,
            value: 10,
            to: startOfToday
        ) ?? startOfToday
    }

    private func deleteAll<T: PersistentModel>(
        _ modelType: T.Type
    ) {
        let descriptor = FetchDescriptor<T>()
        let records = (try? modelContext.fetch(descriptor)) ?? []

        for record in records {
            modelContext.delete(record)
        }
    }

    private func saveQAContext() {
        do {
            try modelContext.save()
        } catch {
            AppLogger.error(
                "Developer QA persistence error: \(error.localizedDescription)",
                category: .developerQA
            )
        }
    }
}

private enum DeveloperQAAction: Identifiable {
    case resetLocalData
    case loadScenario
    case loadRecurrenceEdgeCases

    var id: String {
        switch self {
        case .resetLocalData:
            return "resetLocalData"

        case .loadScenario:
            return "loadScenario"

        case .loadRecurrenceEdgeCases:
            return "loadRecurrenceEdgeCases"
        }
    }

    var title: String {
        switch self {
        case .resetLocalData:
            return "Reset Local Data?"

        case .loadScenario:
            return "Load QA Scenario?"

        case .loadRecurrenceEdgeCases:
            return "Load Recurrence Edge Cases?"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .resetLocalData:
            return "Reset Local Data"

        case .loadScenario:
            return "Load QA Scenario"

        case .loadRecurrenceEdgeCases:
            return "Load Recurrence Edge Cases"
        }
    }

    var message: String {
        switch self {
        case .resetLocalData:
            return "This removes local debug/test accounts, Savings Goals, Savings Reserve, Timeline events, set-aside amounts, and paid/skipped occurrence records."

        case .loadScenario:
            return "This resets local debug data, then loads Cash $3,000, Savings Reserve $400, one Savings Goal with $500 saved, monthly Rent $1,000 with $600 set aside, and Debt Payoff with $300 set aside."

        case .loadRecurrenceEdgeCases:
            return "This resets local debug data, then loads monthly, quarterly, and every-2-weeks Timeline expenses for recurrence edge-case testing."
        }
    }

    var role: ButtonRole? {
        switch self {
        case .resetLocalData:
            return .destructive

        case .loadScenario:
            return nil

        case .loadRecurrenceEdgeCases:
            return nil
        }
    }
}

private extension ExpenseOccurrenceLifecycle {

    var qaConsoleTitle: String {
        switch self {
        case .upcoming:
            return "upcoming"

        case .overdue:
            return "overdue"

        case .paid:
            return "paid"

        case .skipped:
            return "skipped"
        }
    }
}
#endif
