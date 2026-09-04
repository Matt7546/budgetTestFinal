import Foundation

struct DashboardWidgetSnapshotBuilder {

    struct Input {
        let financialSummary: FinancialSummary
        let isSignedIn: Bool
        let canShowBankData: Bool
        let linkedAccounts: [PlaidAccount]
        let bankSyncState: BankSyncRefreshState
        let accountsLastUpdatedText: String
        let savingsGoals: [SavingsGoal]
        let events: [PlannerEvent]
        let allocations: [EventAllocation]
        let occurrenceStatuses: [ExpenseOccurrenceStatus]
        let paymentPlans: [DebtPayoffBucket]
        let paymentPlanCycles: [PaymentPlanCycle]
        let reviewItems: [ReviewUpdateItem]
        let upcomingExpensesTimeframe: DashboardWidgetTimeframe
        let now: Date
        let calendar: Calendar

        init(
            financialSummary: FinancialSummary,
            isSignedIn: Bool,
            canShowBankData: Bool,
            linkedAccounts: [PlaidAccount],
            bankSyncState: BankSyncRefreshState,
            accountsLastUpdatedText: String,
            savingsGoals: [SavingsGoal],
            events: [PlannerEvent],
            allocations: [EventAllocation],
            occurrenceStatuses: [ExpenseOccurrenceStatus],
            paymentPlans: [DebtPayoffBucket],
            paymentPlanCycles: [PaymentPlanCycle],
            reviewItems: [ReviewUpdateItem],
            upcomingExpensesTimeframe: DashboardWidgetTimeframe = .next30Days,
            now: Date = Date(),
            calendar: Calendar = .current
        ) {
            self.financialSummary = financialSummary
            self.isSignedIn = isSignedIn
            self.canShowBankData = canShowBankData
            self.linkedAccounts = linkedAccounts
            self.bankSyncState = bankSyncState
            self.accountsLastUpdatedText = accountsLastUpdatedText
            self.savingsGoals = savingsGoals
            self.events = events
            self.allocations = allocations
            self.occurrenceStatuses = occurrenceStatuses
            self.paymentPlans = paymentPlans
            self.paymentPlanCycles = paymentPlanCycles
            self.reviewItems = reviewItems
            self.upcomingExpensesTimeframe = upcomingExpensesTimeframe
            self.now = now
            self.calendar = calendar
        }
    }

    static func build(
        from input: Input
    ) -> DashboardWidgetSnapshotCollection {
        let context = Context(input: input)
        let snapshots = [
            setAsideSnapshot(input.financialSummary),
            bankSyncSnapshot(input),
            reviewUpdatesSnapshot(input.reviewItems),
            savingsGoalSnapshot(input.savingsGoals),
            upcomingExpensesSnapshot(context),
            paymentPlansSnapshot(context),
            planAheadSnapshot(context)
        ]

        precondition(
            snapshots.map(\.kind) == DashboardWidgetKind.defaultOrder,
            "Dashboard widget snapshots must preserve the fixed default order."
        )

        return DashboardWidgetSnapshotCollection(
            orderedSnapshots: snapshots
        )
    }

    private struct Context {
        let input: Input
        let allocationByOccurrenceID: [String: EventAllocation]
        let upcomingExpenseForecasts: [ForecastEvent]
        let activePaymentPlans: [DebtPayoffBucket]
        let activePaymentPlanByID: [UUID: DebtPayoffBucket]
        let paymentPlanAccountByID: [String: PlaidAccount]

        init(input: Input) {
            self.input = input
            allocationByOccurrenceID = input.allocations.reduce(into: [:]) {
                result,
                allocation in
                if result[allocation.occurrenceID] == nil {
                    result[allocation.occurrenceID] = allocation
                }
            }

            let inactiveOccurrenceIDs =
                ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
                    from: input.occurrenceStatuses
                )
            let startOfToday = input.calendar.startOfDay(for: input.now)
            let forecasts = PlannerForecastCalculator(
                events: input.events,
                totalAvailable: 0,
                totalGoalAllocated: 0,
                includeFutureIncome: true,
                protectGoals: true,
                now: input.now,
                calendar: input.calendar,
                inactiveOccurrenceIDs: inactiveOccurrenceIDs
            )
            .forecastEvents

            upcomingExpenseForecasts = forecasts.filter { forecast in
                forecast.event.type == .expense &&
                    input.calendar.startOfDay(for: forecast.occurrenceDate) >=
                        startOfToday
            }

            activePaymentPlans = input.paymentPlans.filter { bucket in
                PaymentPlanCycleStore.isActiveOrLegacy(
                    paymentPlanID: bucket.id,
                    cycles: input.paymentPlanCycles
                )
            }
            activePaymentPlanByID = Dictionary(
                uniqueKeysWithValues: activePaymentPlans.map { ($0.id, $0) }
            )
            paymentPlanAccountByID = Dictionary(
                uniqueKeysWithValues: input.linkedAccounts
                    .deduplicatedForDisplayAndTotals
                    .debtAccounts
                    .map { ($0.account_id, $0) }
            )
        }

        func allocatedAmount(
            for forecast: ForecastEvent
        ) -> Double {
            min(
                max(
                    allocationByOccurrenceID[forecast.occurrenceID]?
                        .allocatedAmount ?? 0,
                    0
                ),
                max(forecast.event.amount, 0)
            )
        }

        func activeCycle(
            for bucket: DebtPayoffBucket
        ) -> PaymentPlanCycle? {
            PaymentPlanCycleStore.activeCycle(
                for: bucket.id,
                in: input.paymentPlanCycles
            )
        }

        func paymentPlanDisplay(
            for bucket: DebtPayoffBucket
        ) -> DebtPayoffDisplayModel {
            DebtPayoffDisplayModel(
                bucket: bucket,
                linkedAccount: paymentPlanAccountByID[bucket.plaidAccountID],
                cycle: activeCycle(for: bucket),
                today: input.now,
                calendar: input.calendar
            )
        }
    }

    private static func setAsideSnapshot(
        _ summary: FinancialSummary
    ) -> DashboardWidgetSnapshot {
        let parts = [
            setAsidePart(
                id: "cash-cushion",
                title: "Cash Cushion",
                amount: summary.reserve
            ),
            setAsidePart(
                id: "savings-goals",
                title: "Savings Goals",
                amount: summary.savingsGoalsSetAside
            ),
            setAsidePart(
                id: "upcoming-expenses",
                title: "Upcoming Expenses",
                amount: summary.upcomingExpensesSetAside
            ),
            setAsidePart(
                id: "payment-plans",
                title: "Payment Plans",
                amount: summary.debtPaymentsSetAside
            )
        ]
        let total = max(summary.protectedMoney, 0)

        return DashboardWidgetSnapshot(
            kind: .setAside,
            title: "Set Aside",
            subtitle: "Money held back by purpose",
            primaryValue: AppFormatters.currency(total),
            secondaryValue: "Across your current Set Aside plan",
            status: total > 0.005 ? "Active" : "Nothing set aside yet",
            progress: nil,
            categoryRole: .reserve,
            destination: .setAside,
            contentState: total > 0.005 ? .content : .empty,
            items: parts,
            accessibilityLabel: "Set Aside, \(AppFormatters.currency(total)). Cash Cushion \(AppFormatters.currency(max(summary.reserve, 0))), Savings Goals \(AppFormatters.currency(max(summary.savingsGoalsSetAside, 0))), Upcoming Expenses \(AppFormatters.currency(max(summary.upcomingExpensesSetAside, 0))), Payment Plans \(AppFormatters.currency(max(summary.debtPaymentsSetAside, 0)))."
        )
    }

    private static func setAsidePart(
        id: String,
        title: String,
        amount: Double
    ) -> DashboardWidgetItemSnapshot {
        let value = AppFormatters.currency(max(amount, 0))
        return DashboardWidgetItemSnapshot(
            id: id,
            title: title,
            context: "Set aside",
            primaryValue: value,
            secondaryValue: nil,
            progress: nil,
            destination: .setAside,
            accessibilityLabel: "\(title), \(value) set aside."
        )
    }

    private static func bankSyncSnapshot(
        _ input: Input
    ) -> DashboardWidgetSnapshot {
        let accounts = input.canShowBankData
            ? input.linkedAccounts.deduplicatedForDisplayAndTotals
            : []
        let accountCount = accounts.count
        let accountText = "\(accountCount) account\(accountCount == 1 ? "" : "s")"
        let state: DashboardWidgetContentState
        let primaryValue: String
        let secondaryValue: String?
        let status: String

        if !input.canShowBankData || !input.isSignedIn {
            state = .empty
            primaryValue = "Sign in required"
            secondaryValue = "Sign in with Apple to use Bank Sync."
            status = "Not connected"
        } else if accounts.isEmpty {
            state = .empty
            primaryValue = "No linked accounts"
            secondaryValue = "Connect an account to use Bank Sync."
            status = "Not connected"
        } else {
            state = .content
            primaryValue = bankSyncPrimaryValue(input.bankSyncState)
            secondaryValue = "\(accountText) · \(input.accountsLastUpdatedText)"
            status = input.bankSyncState.statusTitle
        }

        return DashboardWidgetSnapshot(
            kind: .bankSync,
            title: "Bank Sync",
            subtitle: secondaryValue ?? "Linked account status",
            primaryValue: primaryValue,
            secondaryValue: secondaryValue,
            status: status,
            progress: nil,
            categoryRole: .bankAccount,
            destination: .bankSync,
            contentState: state,
            items: [],
            accessibilityLabel: "Bank Sync. \(primaryValue). \(secondaryValue ?? status)"
        )
    }

    private static func bankSyncPrimaryValue(
        _ state: BankSyncRefreshState
    ) -> String {
        switch state.phase {
        case .fullyUpdated:
            return "Up to date"
        case .loading:
            return "Refreshing"
        case .partiallyUpdated:
            return "Partially updated"
        case .showingEarlierData:
            return "Showing earlier data"
        case .unavailable:
            return "Unavailable"
        case .rateLimited:
            return "Briefly paused"
        case .notConnected:
            return "No linked accounts"
        case .authenticationRequired:
            return "Sign in required"
        case .idle:
            return "Ready to refresh"
        }
    }

    private static func reviewUpdatesSnapshot(
        _ reviewItems: [ReviewUpdateItem]
    ) -> DashboardWidgetSnapshot {
        guard !reviewItems.isEmpty else {
            return hiddenSnapshot(
                kind: .reviewUpdates,
                title: "Review Updates",
                subtitle: "Nothing to review",
                categoryRole: .needsMoney
            )
        }

        let count = reviewItems.count
        let countText = "\(count)"
        let detail = count == 1 ? "update to review" : "updates to review"
        let items = reviewItems.prefix(3).map { item in
            DashboardWidgetItemSnapshot(
                id: item.id,
                title: item.title,
                context: item.kind.accessibilityLabel,
                primaryValue: item.actionTitle,
                secondaryValue: item.detail,
                progress: nil,
                destination: .reviewUpdates,
                accessibilityLabel: item.accessibilityLabel
            )
        }

        return DashboardWidgetSnapshot(
            kind: .reviewUpdates,
            title: "Review Updates",
            subtitle: reviewItems[0].title,
            primaryValue: countText,
            secondaryValue: detail,
            status: "Needs review",
            progress: nil,
            categoryRole: .needsMoney,
            destination: .reviewUpdates,
            contentState: .content,
            items: Array(items),
            accessibilityLabel: "Review Updates. \(countText) \(detail). First: \(reviewItems[0].accessibilityLabel)"
        )
    }

    private static func savingsGoalSnapshot(
        _ goals: [SavingsGoal]
    ) -> DashboardWidgetSnapshot {
        guard let goal = goals.first(where: \.isPinned) ?? goals.first else {
            return hiddenSnapshot(
                kind: .savingsGoal,
                title: "Savings Goal",
                subtitle: "No Savings Goals yet",
                categoryRole: .savingsGoal
            )
        }

        let current = max(goal.currentAmount, 0)
        let target = max(goal.targetAmount, 0)
        let currentText = AppFormatters.currency(current)
        let targetText = AppFormatters.currency(target)

        return DashboardWidgetSnapshot(
            kind: .savingsGoal,
            title: "Savings Goal",
            subtitle: goal.name.isEmpty ? "Untitled Savings Goal" : goal.name,
            primaryValue: currentText,
            secondaryValue: "of \(targetText)",
            status: "\(Int(goal.progress * 100))% saved",
            progress: clampedProgress(goal.progress),
            categoryRole: .savingsGoal,
            destination: .savingsGoal(goal.id),
            contentState: .content,
            items: [],
            accessibilityLabel: "Savings Goal, \(goal.name.isEmpty ? "Untitled Savings Goal" : goal.name), \(currentText) saved of \(targetText), \(Int(goal.progress * 100)) percent."
        )
    }

    private static func upcomingExpensesSnapshot(
        _ context: Context
    ) -> DashboardWidgetSnapshot {
        guard !context.upcomingExpenseForecasts.isEmpty else {
            return hiddenSnapshot(
                kind: .upcomingExpenses,
                title: "Upcoming Expenses",
                subtitle: "No Upcoming Expenses",
                categoryRole: .upcomingExpense
            )
        }

        let timeframe = context.input.upcomingExpensesTimeframe
        let startOfToday = context.input.calendar.startOfDay(
            for: context.input.now
        )
        let endOfTimeframe = context.input.calendar.date(
            byAdding: .day,
            value: timeframe.dayCount,
            to: startOfToday
        ) ?? startOfToday
        let forecasts = Array(
            context.upcomingExpenseForecasts.filter { forecast in
                context.input.calendar.startOfDay(
                    for: forecast.occurrenceDate
                ) < endOfTimeframe
            }
            .prefix(3)
        )

        guard !forecasts.isEmpty else {
            return DashboardWidgetSnapshot(
                kind: .upcomingExpenses,
                title: "Upcoming Expenses",
                subtitle: "No expenses in \(timeframe.displayName)",
                primaryValue: "Nothing due",
                secondaryValue: nil,
                status: nil,
                progress: 0,
                categoryRole: .upcomingExpense,
                destination: .planAhead,
                contentState: .empty,
                items: [],
                accessibilityLabel: "Upcoming Expenses. No expenses in \(timeframe.displayName).",
                timeframe: timeframe
            )
        }

        let amounts = forecasts.map { forecast -> (total: Double, setAside: Double) in
            (
                max(forecast.event.amount, 0),
                context.allocatedAmount(for: forecast)
            )
        }
        let total = amounts.reduce(0) { $0 + $1.total }
        let setAside = amounts.reduce(0) { $0 + $1.setAside }
        let remaining = max(total - setAside, 0)
        let items = forecasts.map { forecast in
            upcomingExpenseItem(
                forecast,
                allocatedAmount: context.allocatedAmount(for: forecast)
            )
        }
        let count = forecasts.count

        return DashboardWidgetSnapshot(
            kind: .upcomingExpenses,
            title: "Upcoming Expenses",
            subtitle: "Next \(count) expense\(count == 1 ? "" : "s")",
            primaryValue: AppFormatters.currency(remaining),
            secondaryValue: "still needed",
            status: "\(AppFormatters.currency(setAside)) set aside",
            progress: progress(current: setAside, target: total),
            categoryRole: .upcomingExpense,
            destination: .planAhead,
            contentState: .content,
            items: items,
            accessibilityLabel: "Upcoming Expenses. \(timeframe.displayName). \(AppFormatters.currency(remaining)) still needed across the next \(count) expense\(count == 1 ? "" : "s"). \(AppFormatters.currency(setAside)) set aside of \(AppFormatters.currency(total)).",
            timeframe: timeframe
        )
    }

    private static func upcomingExpenseItem(
        _ forecast: ForecastEvent,
        allocatedAmount: Double
    ) -> DashboardWidgetItemSnapshot {
        let total = max(forecast.event.amount, 0)
        let setAside = min(max(allocatedAmount, 0), total)
        let remaining = max(total - setAside, 0)
        let dueDate = AppFormatters.abbreviatedMonthDay(forecast.occurrenceDate)

        return DashboardWidgetItemSnapshot(
            id: forecast.occurrenceID,
            title: forecast.event.name,
            context: "Due \(dueDate)",
            primaryValue: AppFormatters.currency(total),
            secondaryValue: "\(AppFormatters.currency(setAside)) set aside · \(AppFormatters.currency(remaining)) needed",
            progress: progress(current: setAside, target: total),
            targetAmount: total,
            setAsideAmount: setAside,
            destination: .upcomingExpense(
                eventID: forecast.event.id,
                occurrenceID: forecast.occurrenceID
            ),
            accessibilityLabel: "\(forecast.event.name), due \(dueDate), \(AppFormatters.currency(total)), \(AppFormatters.currency(setAside)) set aside, \(AppFormatters.currency(remaining)) still needed."
        )
    }

    private static func paymentPlansSnapshot(
        _ context: Context
    ) -> DashboardWidgetSnapshot {
        let plans = context.activePaymentPlans
            .sorted { lhs, rhs in
                let leftDueDate = context.activeCycle(for: lhs)?.dueDate ?? lhs.dueDate
                let rightDueDate = context.activeCycle(for: rhs)?.dueDate ?? rhs.dueDate

                if leftDueDate != rightDueDate {
                    return leftDueDate < rightDueDate
                }

                return lhs.accountName.localizedCaseInsensitiveCompare(
                    rhs.accountName
                ) == .orderedAscending
            }
            .prefix(3)

        guard !plans.isEmpty else {
            return hiddenSnapshot(
                kind: .paymentPlans,
                title: "Payment Plans",
                subtitle: "No active Payment Plans",
                categoryRole: .debtPayoff
            )
        }

        let planValues = plans.map { bucket in
            (
                bucket: bucket,
                cycle: context.activeCycle(for: bucket),
                display: context.paymentPlanDisplay(for: bucket)
            )
        }
        let total = planValues.reduce(0) {
            $0 + max($1.display.plannedPaymentAmount, 0)
        }
        let setAside = planValues.reduce(0) {
            $0 + max($1.bucket.protectedAmount, 0)
        }
        let remaining = max(total - setAside, 0)
        let items = planValues.map { value in
            paymentPlanItem(
                bucket: value.bucket,
                cycle: value.cycle,
                display: value.display
            )
        }
        let count = planValues.count

        return DashboardWidgetSnapshot(
            kind: .paymentPlans,
            title: "Payment Plans",
            subtitle: "Next \(count) payment\(count == 1 ? "" : "s")",
            primaryValue: "\(AppFormatters.currency(setAside)) of \(AppFormatters.currency(total))",
            secondaryValue: "set aside",
            status: "\(AppFormatters.currency(remaining)) still needed",
            progress: progress(current: setAside, target: total),
            categoryRole: .debtPayoff,
            destination: .setAside,
            contentState: .content,
            items: items,
            accessibilityLabel: "Payment Plans. \(AppFormatters.currency(setAside)) of \(AppFormatters.currency(total)) set aside across the next \(count) payment\(count == 1 ? "" : "s"). \(AppFormatters.currency(remaining)) still needed."
        )
    }

    private static func paymentPlanItem(
        bucket: DebtPayoffBucket,
        cycle: PaymentPlanCycle?,
        display: DebtPayoffDisplayModel
    ) -> DashboardWidgetItemSnapshot {
        DashboardWidgetItemSnapshot(
            id: bucket.id.uuidString.lowercased(),
            title: display.title,
            context: "\(display.dueDateValue) · \(display.plannedPaymentMeaningValue)",
            primaryValue: display.plannedPaymentValue,
            secondaryValue: "\(display.setAsideValue) set aside · \(display.remainingValue)",
            progress: clampedProgress(display.progressValue),
            targetAmount: max(display.plannedPaymentAmount, 0),
            setAsideAmount: max(display.coveredPaymentAmount, 0),
            destination: .paymentPlan(
                bucketID: bucket.id,
                cycleID: cycle?.id
            ),
            accessibilityLabel: display.accessibilitySummary
        )
    }

    private static func planAheadSnapshot(
        _ context: Context
    ) -> DashboardWidgetSnapshot {
        let paymentPlans = context.activePaymentPlans.map { bucket in
            PlanAheadPaymentPlan(
                bucket: bucket,
                dueDate: PlanAheadPaymentPlanWindow.effectiveDueDate(
                    bucketDueDate: bucket.dueDate,
                    activeCycle: context.activeCycle(for: bucket)
                )
            )
        }
        let timelineItems = Array(
            PlanAheadTimelineItems.upcoming(
                expenses: context.upcomingExpenseForecasts,
                paymentPlans: paymentPlans,
                startOfToday: context.input.calendar.startOfDay(
                    for: context.input.now
                ),
                calendar: context.input.calendar
            )
            .prefix(3)
        )

        guard !timelineItems.isEmpty else {
            return hiddenSnapshot(
                kind: .planAhead,
                title: "Plan Ahead",
                subtitle: "Nothing coming up",
                categoryRole: .bankAccount
            )
        }

        let items = timelineItems.compactMap { item in
            planAheadItem(item, context: context)
        }
        let count = items.count
        let firstContext = items.first?.context ?? ""

        return DashboardWidgetSnapshot(
            kind: .planAhead,
            title: "Plan Ahead",
            subtitle: "Next \(count) dated item\(count == 1 ? "" : "s")",
            primaryValue: firstContext,
            secondaryValue: items.first?.title,
            status: "Coming up",
            progress: nil,
            categoryRole: .bankAccount,
            destination: .planAhead,
            contentState: .content,
            items: items,
            accessibilityLabel: "Plan Ahead. Next \(count) dated item\(count == 1 ? "" : "s"). \(items.map(\.accessibilityLabel).joined(separator: " "))"
        )
    }

    private static func planAheadItem(
        _ item: PlanAheadTimelineItem,
        context: Context
    ) -> DashboardWidgetItemSnapshot? {
        switch item {
        case .upcomingExpense(let forecast):
            let allocatedAmount = context.allocatedAmount(for: forecast)
            let snapshot = upcomingExpenseItem(
                forecast,
                allocatedAmount: allocatedAmount
            )
            return DashboardWidgetItemSnapshot(
                id: "expense-\(snapshot.id)",
                title: snapshot.title,
                context: AppFormatters.abbreviatedMonthDay(forecast.occurrenceDate),
                primaryValue: snapshot.primaryValue,
                secondaryValue: snapshot.secondaryValue,
                progress: snapshot.progress,
                targetAmount: snapshot.targetAmount,
                setAsideAmount: snapshot.setAsideAmount,
                destination: snapshot.destination,
                accessibilityLabel: snapshot.accessibilityLabel
            )

        case .paymentPlan(let paymentPlan):
            guard let bucket = context.activePaymentPlanByID[
                paymentPlan.bucket.id
            ] else {
                return nil
            }
            let cycle = context.activeCycle(for: bucket)
            let display = context.paymentPlanDisplay(for: bucket)
            return DashboardWidgetItemSnapshot(
                id: "payment-plan-\(bucket.id.uuidString.lowercased())",
                title: display.title,
                context: AppFormatters.abbreviatedMonthDay(paymentPlan.dueDate),
                primaryValue: display.plannedPaymentValue,
                secondaryValue: display.remainingValue,
                progress: clampedProgress(display.progressValue),
                targetAmount: max(display.plannedPaymentAmount, 0),
                setAsideAmount: max(display.coveredPaymentAmount, 0),
                destination: .paymentPlan(
                    bucketID: bucket.id,
                    cycleID: cycle?.id
                ),
                accessibilityLabel: display.accessibilitySummary
            )
        }
    }

    private static func hiddenSnapshot(
        kind: DashboardWidgetKind,
        title: String,
        subtitle: String,
        categoryRole: CalderaFinanceSemanticRole
    ) -> DashboardWidgetSnapshot {
        DashboardWidgetSnapshot(
            kind: kind,
            title: title,
            subtitle: subtitle,
            primaryValue: "",
            secondaryValue: nil,
            status: nil,
            progress: nil,
            categoryRole: categoryRole,
            destination: nil,
            contentState: .hidden,
            items: [],
            accessibilityLabel: "\(title). \(subtitle)."
        )
    }

    private static func progress(
        current: Double,
        target: Double
    ) -> Double {
        guard target > 0 else {
            return 0
        }

        return clampedProgress(current / target)
    }

    private static func clampedProgress(
        _ value: Double
    ) -> Double {
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0), 1)
    }
}
