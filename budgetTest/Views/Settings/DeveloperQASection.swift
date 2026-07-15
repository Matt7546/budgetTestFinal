#if DEBUG
import SwiftUI
import SwiftData
import UIKit

struct DeveloperQASection: View {

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var plaid: PlaidService
    @EnvironmentObject private var navigation: AppNavigation
    @Environment(\.modelContext)
    private var modelContext

    @State private var pendingQAAction: DeveloperQAAction?
    @State private var qaStatusMessage: String?
    @State private var isCheckingCardPaymentDetails = false

    var body: some View {
        SettingsSection(
            title: "Debug QA",
            systemImage: "wrench.and.screwdriver.fill",
            color: AppColors.warning
        ) {
            SettingsInfoRow(
                title: "Debug QA",
                description: "Local backend, Plaid Sandbox, local dev auth, and safe manual testing tools for this build.",
                systemImage: "checklist.checked",
                color: AppColors.warning
            )

            VStack(spacing: AppSpacing.small) {
                DeveloperQADiagnosticRow(
                    title: "Build Configuration",
                    value: buildConfigurationLabel,
                    systemImage: "hammer.fill",
                    color: AppColors.warning
                )

                DeveloperQADiagnosticRow(
                    title: "Active Backend URL",
                    value: AppConfig.backendBaseURL.absoluteString,
                    systemImage: "network",
                    color: AppColors.accent
                )

                DeveloperQADiagnosticRow(
                    title: "Expected Environment",
                    value: expectedEnvironmentLabel,
                    systemImage: "building.columns.fill",
                    color: AppColors.accent
                )

                DeveloperQADiagnosticRow(
                    title: "Auth State",
                    value: authStateLabel,
                    systemImage: "person.crop.circle.badge.checkmark",
                    color: AppColors.secondaryText
                )

                DeveloperQADiagnosticRow(
                    title: "Plaid Capabilities",
                    value: plaidCapabilitiesLabel,
                    systemImage: "switch.2",
                    color: AppColors.protected
                )

                DeveloperQADiagnosticRow(
                    title: "Card Payment Details",
                    value: cardPaymentDetailsDebugSummary,
                    systemImage: "creditcard.fill",
                    color: AppColors.warning
                )

                DeveloperQADiagnosticRow(
                    title: "Account Refresh",
                    value: accountRefreshStatusLabel,
                    systemImage: "arrow.clockwise.circle.fill",
                    color: AppColors.secondaryText
                )

                DeveloperQADiagnosticRow(
                    title: "Linked Account Count",
                    value: "\(safeLinkedAccountCount)",
                    systemImage: "number.circle.fill",
                    color: AppColors.secondaryText
                )

                DeveloperQADiagnosticRow(
                    title: "Local Dev Auth",
                    value: "Available in Debug",
                    systemImage: "hammer.circle.fill",
                    color: AppColors.accent
                )

                DeveloperQADiagnosticRow(
                    title: "Lab",
                    value: labStateLabel,
                    systemImage: "sparkles",
                    color: AppConfig.isLabEnabled ? AppColors.accent : AppColors.secondaryText
                )

                DeveloperQADiagnosticRow(
                    title: "App Version",
                    value: appVersionBuildLabel,
                    systemImage: "info.circle.fill",
                    color: AppColors.secondaryText
                )
            }

            SecondaryButton(
                isCheckingCardPaymentDetails ? "Checking Card Payment Details" : "Check Card Payment Details",
                systemImage: "creditcard.fill",
                cornerRadius: AppRadii.button,
                foregroundColor: AppColors.warning,
                fillsWidth: true
            ) {
                checkCardPaymentDetails()
            }
            .disabled(isCheckingCardPaymentDetails)
            .accessibilityLabel("Check card payment details")

            if !plaid.cardPaymentDetails.isEmpty {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.small
                ) {
                    Text("Sanitized Card Payment Details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    ForEach(plaid.cardPaymentDetails) { card in
                        DeveloperQACardPaymentDetailsCard(
                            card: card
                        )
                    }
                }
            }

            SecondaryButton(
                "Copy Diagnostics",
                systemImage: "doc.on.doc.fill",
                cornerRadius: AppRadii.button,
                foregroundColor: AppColors.accent,
                fillsWidth: true
            ) {
                copyDiagnosticsToClipboard()
            }
            .accessibilityLabel("Copy safe debug diagnostics")

            Divider()

            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
                Text("Debug Smoke Test")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                ForEach(debugSmokeTestItems, id: \.self) { item in
                    DeveloperQAChecklistRow(title: item)
                }
            }

            Divider()

            SettingsInfoRow(
                title: "QA Scenario Tools",
                description: "Debug-only reset/load tools for local manual testing. They do not affect Release/TestFlight builds.",
                systemImage: "testtube.2",
                color: AppColors.warning
            )

            if AppConfig.isDebugLocal {
                SettingsInfoRow(
                    title: "UX Research Scenario",
                    description: "Start from nickname setup, then deliberately connect three synthetic accounts. No Plaid request is made.",
                    systemImage: "person.crop.rectangle.stack.fill",
                    color: AppColors.accent
                )

                DestructiveButton(
                    "Reset UX Research Scenario",
                    systemImage: "arrow.counterclockwise.circle.fill",
                    cornerRadius: AppRadii.button
                ) {
                    pendingQAAction = .resetUXResearchScenario
                }
                .accessibilityLabel("Reset UX research scenario")

                SecondaryButton(
                    plaid.debugUXResearchPaymentDetailHasAdvanced
                        ? "Research Update Applied"
                        : "Simulate $400 Card Update",
                    systemImage: "arrow.triangle.2.circlepath",
                    cornerRadius: AppRadii.button,
                    foregroundColor: AppColors.accent,
                    fillsWidth: true
                ) {
                    simulateUXResearchPaymentDetailRefresh()
                }
                .disabled(
                    !plaid.debugUXResearchAccountsAreConnected ||
                        plaid.debugUXResearchPaymentDetailHasAdvanced
                )
                .accessibilityLabel("Simulate research card payment update to 400 dollars")
            }

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

    private var buildConfigurationLabel: String {
        "Debug"
    }

    private var expectedEnvironmentLabel: String {
        "Local Backend · Plaid Sandbox · Local Dev Auth"
    }

    private var authStateLabel: String {
        switch auth.state {
        case .signedOut:
            return "Signed out"

        case .signingIn:
            return "Signing in"

        case .signedIn:
            return "Signed in"

        case .failed:
            return "Sign-in failed"
        }
    }

    private var plaidCapabilitiesLabel: String {
        let accountsStatus = plaid.backendAccountsEnabled ? "accounts enabled" : "accounts disabled"
        let transactionsStatus = plaid.backendTransactionsEnabled ? "transactions enabled" : "transactions disabled"
        let liabilitiesStatus = plaid.backendLiabilitiesEnabled ? "card payment details enabled" : "card payment details disabled"

        return "\(accountsStatus), \(transactionsStatus), \(liabilitiesStatus)"
    }

    private var accountRefreshStatusLabel: String {
        if plaid.isRefreshingPlaidData {
            return "Refreshing"
        }

        if let message = plaid.manualPlaidRefreshMessage,
           !message.isEmpty {
            return message
        }

        if let message = plaid.accountRefreshMessage,
           !message.isEmpty {
            return message
        }

        return plaid.accountsLastUpdatedText
    }

    private var cardPaymentDetailsDebugSummary: String {
        let response = plaid.latestCardPaymentDetailsResponse
        let isEnabled = response?.enabled ?? plaid.backendLiabilitiesEnabled
        let enabledText = isEnabled ? "enabled" : "disabled"
        let cardCount = response?.cards.count ?? plaid.cardPaymentDetails.count
        var parts = [
            "Card payment details: \(enabledText)",
            "\(cardCount) cards"
        ]

        if response?.partial_failure == true {
            parts.append(
                "partial failure"
            )
        }

        if let message = response?.message,
           !message.isEmpty {
            parts.append(
                message
            )
        }

        if let error = response?.error,
           !error.isEmpty {
            parts.append(
                "error: \(error)"
            )
        }

        return parts.joined(
            separator: " · "
        )
    }

    private var safeLinkedAccountCount: Int {
        plaid.accounts.deduplicatedForDisplayAndTotals.count
    }

    private var labStateLabel: String {
        AppConfig.isLabEnabled ? "Lab Enabled" : "Lab Disabled"
    }

    private var appVersionBuildLabel: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "Unknown"

        return "\(version) (\(build))"
    }

    private var debugSmokeTestItems: [String] {
        [
            "Local backend running",
            "Local dev sign-in works",
            "Plaid Sandbox link opens",
            "Accounts load",
            "Available to Spend updates",
            "Savings opens",
            "Timeline opens",
            "Settings opens"
        ]
    }

    private var safeDiagnosticsText: String {
        [
            "Caldera Debug Diagnostics",
            "Build configuration: \(buildConfigurationLabel)",
            "Backend URL: \(AppConfig.backendBaseURL.absoluteString)",
            "Expected environment: \(expectedEnvironmentLabel)",
            "Auth state: \(authStateLabel)",
            "Plaid capabilities: \(plaidCapabilitiesLabel)",
            "Card payment details: \(cardPaymentDetailsDebugSummary)",
            "Account refresh: \(accountRefreshStatusLabel)",
            "Linked account count: \(safeLinkedAccountCount)",
            "Local dev auth: Available in Debug",
            "Lab: \(labStateLabel)",
            "App version: \(appVersionBuildLabel)"
        ]
        .joined(separator: "\n")
    }

    private func copyDiagnosticsToClipboard() {
        UIPasteboard.general.string = safeDiagnosticsText
        qaStatusMessage = "Copied safe diagnostics."
    }

    private func checkCardPaymentDetails() {
        isCheckingCardPaymentDetails = true
        qaStatusMessage = "Checking card payment details..."

        plaid.fetchCardPaymentDetails(
            reason: .debugTool
        ) { response in
            isCheckingCardPaymentDetails = false

            if response != nil {
                qaStatusMessage = cardPaymentDetailsDebugSummary
            } else {
                qaStatusMessage = "Card payment details check did not return a response."
            }
        }
    }

    private func performQAAction(
        _ action: DeveloperQAAction
    ) {
        switch action {
        case .resetUXResearchScenario:
            resetUXResearchScenario()

        case .resetLocalData:
            resetLocalDataForQA()

        case .loadScenario:
            loadQAScenario()

        case .loadRecurrenceEdgeCases:
            loadRecurrenceEdgeCases()
        }
    }

    private func resetUXResearchScenario() {
        guard plaid.debugResetUXResearchScenario() else {
            qaStatusMessage = "UX research reset is available only in Caldera Debug Local."
            return
        }

        DebugUXResearchScenario.clearRecurringRecommendationHistory()
        DebugUXResearchScenario.resetFirstRunState()
        navigation.resetForUXResearch()
        auth.debugResetLocalSessionForUXResearch()
        qaStatusMessage = "Reset UX research scenario."
    }

    private func simulateUXResearchPaymentDetailRefresh() {
        qaStatusMessage = plaid.debugSimulateUXResearchPaymentDetailRefresh()
            ? "Research card details changed from $350 to $400. Review Updates now derives the suggested plan change."
            : "Connect research accounts before simulating the card update."
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
            PaymentPlanCycle.self
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
                    "\(index + 1). \(qaDateKey(occurrence.occurrenceDate)) | id: \(occurrence.occurrenceID) | \(activeText) | status: \(lifecycle.qaConsoleTitle) | has set-aside: \(allocatedAmount > 0)"
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

private struct DeveloperQADiagnosticRow: View {

    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(
            alignment: .top,
            spacing: AppSpacing.small
        ) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundColor(color)
                .frame(width: 20, height: 20)

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: 0.70,
            strokeOpacity: 0.54,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: color
        )
    }
}

private struct DeveloperQACardPaymentDetailsCard: View {

    let card: LinkedCardPaymentDetails

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xSmall
        ) {
            HStack(
                alignment: .top,
                spacing: AppSpacing.small
            ) {
                Image(systemName: "creditcard.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.warning)
                    .frame(width: 20, height: 20)

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(notAvailableIfEmpty(card.account_name))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(cardSubtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(spacing: AppSpacing.xxSmall) {
                detailRow("Current balance", value: currency(card.current_balance))
                detailRow("Available credit", value: currency(card.available_credit))
                detailRow("Last statement balance", value: currency(card.last_statement_balance))
                detailRow("Statement issue date", value: notAvailableIfEmpty(card.last_statement_issue_date))
                detailRow("Minimum payment", value: currency(card.minimum_payment_amount))
                detailRow("Next payment due", value: notAvailableIfEmpty(card.next_payment_due_date))
                detailRow("Last payment", value: lastPaymentText)
                detailRow("Overdue status", value: overdueText)
                detailRow("Last refreshed", value: notAvailableIfEmpty(card.last_refreshed_at))
            }
        }
        .padding(AppSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: 0.70,
            strokeOpacity: 0.54,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: AppColors.warning
        )
    }

    private var cardSubtitle: String {
        let institution = notAvailableIfEmpty(card.institution_name)
        let mask = card.mask.flatMap { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : "••••\(value)"
        } ?? "Not available"

        return "\(institution) · \(mask)"
    }

    private var lastPaymentText: String {
        let amount = currency(card.last_payment_amount)
        let date = notAvailableIfEmpty(card.last_payment_date)

        if amount == "Not available", date == "Not available" {
            return "Not available"
        }

        if amount == "Not available" {
            return date
        }

        if date == "Not available" {
            return amount
        }

        return "\(amount) on \(date)"
    }

    private var overdueText: String {
        guard let isOverdue = card.is_overdue else {
            return "Not available"
        }

        return isOverdue ? "Overdue" : "Not overdue"
    }

    private func detailRow(
        _ title: String,
        value: String
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            Spacer(minLength: AppSpacing.small)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func notAvailableIfEmpty(
        _ value: String?
    ) -> String {
        guard let value = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
              !value.isEmpty else {
            return "Not available"
        }

        return value
    }

    private func currency(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "Not available"
        }

        return AppFormatters.currency(
            value
        )
    }
}

private struct DeveloperQAChecklistRow: View {

    let title: String

    var body: some View {
        Label(
            title,
            systemImage: "circle"
        )
        .font(.caption.weight(.semibold))
        .foregroundColor(AppColors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private enum DeveloperQAAction: Identifiable {
    case resetUXResearchScenario
    case resetLocalData
    case loadScenario
    case loadRecurrenceEdgeCases

    var id: String {
        switch self {
        case .resetUXResearchScenario:
            return "resetUXResearchScenario"

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
        case .resetUXResearchScenario:
            return "Reset UX Research Scenario?"

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
        case .resetUXResearchScenario:
            return "Reset UX Research Scenario"

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
        case .resetUXResearchScenario:
            return "This signs out and deletes all local mock accounts, account choices, planning data, recommendation history, and review state. It returns the app to “What should we call you?” with the card detail reset to $350."

        case .resetLocalData:
            return "This removes local debug/test accounts, Savings Goals, Cash Cushion, Timeline events, set-aside amounts, and paid/skipped occurrence records."

        case .loadScenario:
            return "This resets local debug data, then loads Cash $3,000, Cash Cushion $400, one Savings Goal with $500 saved, monthly Rent $1,000 with $600 set aside, and Debt Payoff with $300 set aside."

        case .loadRecurrenceEdgeCases:
            return "This resets local debug data, then loads monthly, quarterly, and every-2-weeks Timeline expenses for recurrence edge-case testing."
        }
    }

    var role: ButtonRole? {
        switch self {
        case .resetUXResearchScenario,
             .resetLocalData:
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
