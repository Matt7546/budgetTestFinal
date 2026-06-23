import SwiftUI
import SwiftData

struct SettingsView: View {

    @EnvironmentObject private var plaid: PlaidService

    @State private var showDisconnectConfirmation = false

    #if DEBUG
    @Environment(\.modelContext)
    private var modelContext

    @State private var pendingQAAction: DeveloperQAAction?
    @State private var qaStatusMessage: String?
    #endif

    @AppStorage("appearanceMode")
    private var appearanceMode = AppearanceMode.system.rawValue

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
    }

    private var connectionStatus: String {
        if plaid.accounts.isEmpty {
            return "No bank accounts connected"
        }

        return "\(plaid.accounts.count) connected account\(plaid.accounts.count == 1 ? "" : "s")"
    }

    var body: some View {
        AppScreen {
            header

            appearanceSection

            #if DEBUG
            debugEnvironmentSection
            #endif

            accountsSection

            privacySection

            aboutSection

            supportSection

            #if DEBUG
            developerQASection
            #endif

            legalSection
        }
        .sheet(isPresented: $plaid.isLinkOpen) {
            if let handler = plaid.linkHandler {
                PlaidLinkView(handler: handler)
            }
        }
        .confirmationDialog(
            "Disconnect Bank?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect Bank", role: .destructive) {
                plaid.disconnectBank()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the linked bank connection from Caldera and clears cached account and transaction data on this device. Your Savings, Timeline events, and Savings Reserve stay in place.")
        }
        #if DEBUG
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
        #endif
    }

    private var selectedAppearance: Binding<AppearanceMode> {
        Binding(
            get: {
                AppearanceMode(rawValue: appearanceMode) ?? .system
            },
            set: {
                appearanceMode = $0.rawValue
            }
        )
    }

    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            Text("Preferences & Trust")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            Text("Settings")
                .font(
                    .system(
                        size: 38,
                        weight: .bold
                    )
                )
                .foregroundColor(AppColors.primaryText)
        }
    }

    private var appearanceSection: some View {
        SettingsSection(
            title: "Appearance",
            systemImage: "moon.stars.fill",
            color: AppColors.accent
        ) {
            Picker(
                "Appearance",
                selection: selectedAppearance
            ) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Appearance")

            Text("Choose a polished light theme, deep dark theme, or follow your device setting.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    #if DEBUG
    private var debugEnvironmentSection: some View {
        SettingsSection(
            title: "Environment",
            systemImage: "server.rack",
            color: AppColors.accent
        ) {
            SettingsValueRow(
                title: "Mode",
                value: AppConfig.environmentDisplayName,
                systemImage: "switch.2",
                color: AppColors.accent
            )

            Divider()

            SettingsValueRow(
                title: "Backend",
                value: AppConfig.backendBaseURL.host ?? "Unknown",
                systemImage: "network",
                color: AppColors.secondaryText
            )

            Divider()

            SettingsValueRow(
                title: "Plaid",
                value: AppConfig.expectedPlaidEnvironment.capitalized,
                systemImage: "building.columns.fill",
                color: AppColors.protected
            )

            if !AppConfig.debugConfigurationWarnings.isEmpty {
                Divider()

                ForEach(
                    AppConfig.debugConfigurationWarnings,
                    id: \.self
                ) { warning in
                    SettingsInfoRow(
                        title: "Configuration Warning",
                        description: warning,
                        systemImage: "exclamationmark.triangle.fill",
                        color: AppColors.warning
                    )
                }
            }
        }
    }

    #endif

    private var accountsSection: some View {
        SettingsSection(
            title: "Accounts & Connections",
            systemImage: "building.columns.fill",
            color: AppColors.accent
        ) {
            SettingsInfoRow(
                title: "Bank Connection",
                description: connectionStatus,
                systemImage: plaid.accounts.isEmpty
                    ? "link.badge.plus"
                    : "checkmark.circle.fill",
                color: plaid.accounts.isEmpty
                    ? AppColors.accent
                    : AppColors.spendable
            )

            Divider()

            SettingsInfoRow(
                title: "Powered by Plaid",
                description: "Secure bank connection infrastructure for account linking.",
                systemImage: "shield.lefthalf.filled",
                color: AppColors.protected
            )

            if let message = plaid.accountRefreshMessage {
                Divider()

                SettingsInfoRow(
                    title: "Refresh Status",
                    description: message,
                    systemImage: "wifi.exclamationmark",
                    color: AppColors.warning
                )
            }

            Divider()

            if plaid.accounts.isEmpty {
                PrimaryButton(
                    "Connect Account",
                    systemImage: "link",
                    trailingSystemImage: nil,
                    cornerRadius: AppRadii.button,
                    fillsWidth: true
                ) {
                    plaid.createLinkToken()
                }
            } else {
                DestructiveButton(
                    "Disconnect Bank",
                    systemImage: "xmark.circle.fill",
                    cornerRadius: AppRadii.button
                ) {
                    showDisconnectConfirmation = true
                }
                .accessibilityLabel("Disconnect linked bank")
            }
        }
    }

    private var privacySection: some View {
        SettingsSection(
            title: "Privacy",
            systemImage: "hand.raised.fill",
            color: AppColors.protected
        ) {
            SettingsInfoRow(
                title: "Bank connections are powered by Plaid.",
                description: "Plaid handles the secure connection between your bank and the app.",
                systemImage: "shield.fill",
                color: AppColors.protected
            )

            Divider()

            SettingsInfoRow(
                title: "Credentials stay out of the app.",
                description: "Your banking credentials are never stored in this app.",
                systemImage: "key.slash.fill",
                color: AppColors.warning
            )

            Divider()

            SettingsInfoRow(
                title: "Timeline and protection data stays local.",
                description: "User-created Upcoming Events, Savings Goals, and Savings Reserve values are stored locally on device.",
                systemImage: "lock.iphone",
                color: AppColors.accent
            )
        }
    }

    private var aboutSection: some View {
        SettingsSection(
            title: "About",
            systemImage: "info.circle.fill",
            color: AppColors.accent
        ) {
            Text("A personal finance planner for seeing today’s Safe To Spend, your timeline, and Protected Money.")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
                .lineSpacing(3)

            Divider()

            SettingsValueRow(
                title: "Version",
                value: appVersion,
                systemImage: "app.badge.fill",
                color: AppColors.accent
            )

            Divider()

            SettingsValueRow(
                title: "Build",
                value: buildNumber,
                systemImage: "hammer.fill",
                color: AppColors.secondaryText
            )
        }
    }

    private var supportSection: some View {
        SettingsSection(
            title: "Support",
            systemImage: "questionmark.circle.fill",
            color: AppColors.warning
        ) {
            SettingsPlaceholderRow(
                title: "Contact Support",
                description: "Support contact options are coming soon.",
                systemImage: "envelope.fill",
                color: AppColors.accent
            )

            Divider()

            SettingsPlaceholderRow(
                title: "Report a Problem",
                description: "Issue reporting will be available in a future update.",
                systemImage: "exclamationmark.bubble.fill",
                color: AppColors.warning
            )
        }
    }

    private var legalSection: some View {
        SettingsSection(
            title: "Legal",
            systemImage: "doc.text.fill",
            color: AppColors.secondaryText
        ) {
            SettingsPlaceholderRow(
                title: "Privacy Policy",
                description: "A full privacy policy will be added before release.",
                systemImage: "lock.doc.fill",
                color: AppColors.protected
            )

            Divider()

            SettingsPlaceholderRow(
                title: "Terms",
                description: "Terms of use will be added before release.",
                systemImage: "doc.plaintext.fill",
                color: AppColors.secondaryText
            )
        }
    }

    #if DEBUG
    private var developerQASection: some View {
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
                allocatedAmount: 400
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

            print("")
            print("=== Recurrence QA: \(event.name) ===")
            print("Frequency: \(event.frequency.rawValue)")
            print("Anchor: \(qaDateKey(event.date))")
            print("Amount: \(event.amount.formatted(.currency(code: "USD")))")

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

                print(
                    "\(index + 1). \(qaDateKey(occurrence.occurrenceDate)) | id: \(occurrence.occurrenceID) | \(activeText) | status: \(lifecycle.qaConsoleTitle) | allocated: \(allocatedAmount.formatted(.currency(code: "USD")))"
                )
            }

            print("Unique occurrence IDs: \(uniqueOccurrenceIDs.count) / \(occurrenceIDs.count)")

            if uniqueOccurrenceIDs.count != occurrenceIDs.count {
                print("WARNING: duplicate occurrence IDs found")
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
            print("❌ Developer QA persistence error:", error)
        }
    }
    #endif
}

#if DEBUG
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
            return "This resets local debug data, then loads Cash $2,000, Savings Reserve $200, one Savings Goal with $300 saved, and monthly Rent $1,000 with $400 set aside."

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

private struct SettingsSection<Content: View>: View {

    let title: String
    let systemImage: String
    let color: Color
    let content: Content

    init(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.small) {
                IconBadge(
                    systemImage: systemImage,
                    color: color,
                    size: 34,
                    iconSize: 14
                )

                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
            }

            VStack(
                alignment: .leading,
                spacing: AppSpacing.medium
            ) {
                content
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
                    color.opacity(0.05),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: AppShadows.softPanelCompact
        )
    }
}

private struct SettingsInfoRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color

    var body: some View {
        SettingsRowShell(
            title: title,
            description: description,
            systemImage: systemImage,
            color: color
        )
    }
}

private struct SettingsToggleRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            SettingsRowShell(
                title: title,
                description: description,
                systemImage: systemImage,
                color: color
            )

            Toggle(
                "",
                isOn: $isOn
            )
            .labelsHidden()
            .tint(color)
        }
    }
}

private struct SettingsValueRow: View {

    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            SettingsRowShell(
                title: title,
                description: nil,
                systemImage: systemImage,
                color: color
            )

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
        }
    }
}

private struct SettingsPlaceholderRow: View {

    let title: String
    let description: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            SettingsRowShell(
                title: title,
                description: description,
                systemImage: systemImage,
                color: color
            )

            Text("Coming Soon")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AppColors.secondaryText.opacity(0.10))
                )
        }
        .opacity(0.82)
    }
}

private struct SettingsRowShell: View {

    let title: String
    let description: String?
    let systemImage: String
    let color: Color

    init(
        title: String,
        description: String?,
        systemImage: String,
        color: Color
    ) {
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            IconBadge(
                systemImage: systemImage,
                color: color
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}
