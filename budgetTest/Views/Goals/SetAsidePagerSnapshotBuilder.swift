import Foundation

struct SetAsidePagerSnapshotBuilder {

    struct Input {
        let reserveBalance: Double
        let savingsGoals: [SavingsGoal]
        let events: [PlannerEvent]
        let allocations: [EventAllocation]
        let occurrenceStatuses: [ExpenseOccurrenceStatus]
        let paymentPlans: [DebtPayoffBucket]
        let paymentPlanCycles: [PaymentPlanCycle]
        let debtAccounts: [PlaidAccount]
        let now: Date
        let calendar: Calendar

        init(
            reserveBalance: Double,
            savingsGoals: [SavingsGoal],
            events: [PlannerEvent],
            allocations: [EventAllocation],
            occurrenceStatuses: [ExpenseOccurrenceStatus],
            paymentPlans: [DebtPayoffBucket],
            paymentPlanCycles: [PaymentPlanCycle],
            debtAccounts: [PlaidAccount],
            now: Date = Date(),
            calendar: Calendar = .current
        ) {
            self.reserveBalance = reserveBalance
            self.savingsGoals = savingsGoals
            self.events = events
            self.allocations = allocations
            self.occurrenceStatuses = occurrenceStatuses
            self.paymentPlans = paymentPlans
            self.paymentPlanCycles = paymentPlanCycles
            self.debtAccounts = debtAccounts
            self.now = now
            self.calendar = calendar
        }
    }

    static func build(
        from input: Input
    ) -> SetAsidePagerSnapshot {
        let context = Context(input: input)

        return SetAsidePagerSnapshot(
            cashCushion: cashCushionSnapshot(input.reserveBalance),
            goals: goalsSnapshot(input.savingsGoals),
            payments: paymentsSnapshot(context),
            upcomingExpenses: upcomingSnapshot(context)
        )
    }

    private struct Context {
        let input: Input
        let allocationByOccurrenceID: [String: EventAllocation]
        let upcomingExpenseForecasts: [ForecastEvent]
        let activePaymentPlans: [DebtPayoffBucket]
        let debtAccountByID: [String: PlaidAccount]

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
            upcomingExpenseForecasts = PlannerForecastCalculator(
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
            .filter { forecast in
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
            debtAccountByID = Dictionary(
                uniqueKeysWithValues: input.debtAccounts
                    .deduplicatedForDisplayAndTotals
                    .map { ($0.account_id, $0) }
            )
        }

        func allocatedAmount(
            for forecast: ForecastEvent
        ) -> Double {
            min(
                normalizedAmount(
                    allocationByOccurrenceID[forecast.occurrenceID]?
                        .allocatedAmount ?? 0
                ),
                normalizedAmount(forecast.event.amount)
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
                linkedAccount: debtAccountByID[bucket.plaidAccountID],
                cycle: activeCycle(for: bucket),
                today: input.now,
                calendar: input.calendar
            )
        }
    }

    private static func cashCushionSnapshot(
        _ reserveBalance: Double
    ) -> SetAsidePagerCashCushionSnapshot {
        let amount = CashCushionBalancePolicy.normalized(reserveBalance)

        return SetAsidePagerCashCushionSnapshot(
            title: SetAsideSectionPresentation.content(for: .cashCushion).title,
            currentAmount: amount,
            targetAmount: nil,
            progress: nil,
            style: .cashCushion,
            isEmpty: amount <= 0.005,
            addDestination: .addCashCushion,
            useDestination: amount > 0.005 ? .useCashCushion : nil,
            accessibilityLabel: "Cash Cushion, \(AppFormatters.currency(amount)) set aside."
        )
    }

    private static func goalsSnapshot(
        _ goals: [SavingsGoal]
    ) -> SetAsidePagerGoalsSnapshot {
        let presentation = SetAsideSectionPresentation.content(
            for: .savingsGoals
        )
        let pinnedGoals = goals.filter(\.isPinned)
        let previewGoals = pinnedGoals.isEmpty
            ? Array(goals.prefix(3))
            : Array(pinnedGoals.prefix(3))
        let totalSaved = normalizedAmount(
            FinancialSummaryCalculator.calculate(
                accounts: [],
                goals: goals
            )
            .savingsGoalsSetAside
        )
        let totalTarget = goals.reduce(0) {
            $0 + normalizedAmount($1.targetAmount)
        }
        let remaining = max(totalTarget - totalSaved, 0)
        let progress = progress(current: totalSaved, target: totalTarget)
        let rows = previewGoals.map { goal in
            goalRow(goal)
        }
        let count = goals.count

        return SetAsidePagerGoalsSnapshot(
            title: presentation.title,
            totalSaved: totalSaved,
            totalTarget: totalTarget,
            remainingAmount: remaining,
            progress: progress,
            activeCount: count,
            allGoalsCount: count,
            style: .savingsGoals,
            rows: rows,
            isEmpty: goals.isEmpty,
            emptyState: SetAsidePagerEmptyStateSnapshot(
                title: presentation.emptyTitle,
                detail: presentation.emptyDetail
            ),
            hasAdditionalItems: count > rows.count,
            createDestination: .createSavingsGoal,
            seeAllDestination: .seeAllSavingsGoals,
            accessibilityLabel: "Savings Goals. \(count) active. \(AppFormatters.currency(totalSaved)) saved of \(AppFormatters.currency(totalTarget)). \(AppFormatters.currency(remaining)) remaining."
        )
    }

    private static func goalRow(
        _ goal: SavingsGoal
    ) -> SetAsidePagerGoalRowSnapshot {
        let saved = normalizedAmount(goal.currentAmount)
        let target = normalizedAmount(goal.targetAmount)
        let remaining = max(target - saved, 0)

        return SetAsidePagerGoalRowSnapshot(
            id: goal.id,
            title: goal.name.isEmpty ? "Untitled Savings Goal" : goal.name,
            savedAmount: saved,
            targetAmount: target,
            remainingAmount: remaining,
            progress: progress(current: saved, target: target),
            updateDestination: .updateSavingsGoal(goalID: goal.id),
            contributeDestination: .contributeToSavingsGoal(goalID: goal.id),
            accessibilityLabel: "\(goal.name.isEmpty ? "Untitled Savings Goal" : goal.name), \(AppFormatters.currency(saved)) saved of \(AppFormatters.currency(target)), \(AppFormatters.currency(remaining)) remaining."
        )
    }

    private static func paymentsSnapshot(
        _ context: Context
    ) -> SetAsidePagerPaymentsSnapshot {
        let presentation = SetAsideSectionPresentation.content(
            for: .paymentPlans
        )
        let activePlans = context.activePaymentPlans.sorted { lhs, rhs in
            let leftDate = context.activeCycle(for: lhs)?.dueDate ?? lhs.dueDate
            let rightDate = context.activeCycle(for: rhs)?.dueDate ?? rhs.dueDate

            if leftDate != rightDate {
                return leftDate < rightDate
            }

            return lhs.accountName.localizedCaseInsensitiveCompare(
                rhs.accountName
            ) == .orderedAscending
        }
        let values = activePlans.map { bucket in
            (
                bucket: bucket,
                cycle: context.activeCycle(for: bucket),
                display: context.paymentPlanDisplay(for: bucket)
            )
        }
        let totalPlanned = values.reduce(0) {
            $0 + normalizedAmount($1.display.plannedPaymentAmount)
        }
        let totalSetAside = values.reduce(0) {
            $0 + normalizedAmount($1.bucket.protectedAmount)
        }
        let remaining = max(totalPlanned - totalSetAside, 0)
        let rows = values.prefix(3).map { value in
            paymentRow(
                bucket: value.bucket,
                cycle: value.cycle,
                display: value.display
            )
        }
        let segments = rows.compactMap { row in
            paymentSegment(row)
        }

        return SetAsidePagerPaymentsSnapshot(
            title: presentation.title,
            totalSetAside: totalSetAside,
            totalPlanned: totalPlanned,
            remainingAmount: remaining,
            progress: progress(
                current: totalSetAside,
                target: totalPlanned
            ),
            activeCount: values.count,
            allPaymentPlanCount: context.input.paymentPlans.count,
            style: .paymentPlans,
            rows: Array(rows),
            segments: segments,
            isEmpty: values.isEmpty,
            emptyState: SetAsidePagerEmptyStateSnapshot(
                title: presentation.emptyTitle,
                detail: presentation.emptyDetail
            ),
            hasAdditionalItems: context.input.paymentPlans.count > rows.count,
            createDestination: .createPaymentPlan,
            seeAllDestination: .seeAllPaymentPlans,
            accessibilityLabel: "Payment Plans. \(values.count) active. \(AppFormatters.currency(totalSetAside)) of \(AppFormatters.currency(totalPlanned)) set aside. \(AppFormatters.currency(remaining)) remaining."
        )
    }

    private static func paymentRow(
        bucket: DebtPayoffBucket,
        cycle: PaymentPlanCycle?,
        display: DebtPayoffDisplayModel
    ) -> SetAsidePagerPaymentRowSnapshot {
        let target = normalizedAmount(display.plannedPaymentAmount)
        let setAside = normalizedAmount(bucket.protectedAmount)
        let remaining = max(target - setAside, 0)
        let dueDate = cycle?.dueDate ?? bucket.dueDate
        let editor: SetAsidePagerPaymentPlanEditor =
            PaymentPlanUpdateRouting.usesModernEditor(for: bucket)
                ? .modernCard
                : .legacyDebt

        return SetAsidePagerPaymentRowSnapshot(
            bucketID: bucket.id,
            cycleID: cycle?.id,
            title: display.title,
            plannedAmount: target,
            setAsideAmount: setAside,
            remainingAmount: remaining,
            progress: progress(current: setAside, target: target),
            dueDate: dueDate,
            targetBasis: display.plannedPaymentMeaningValue,
            status: display.presentationStatusValue,
            editor: editor,
            updateDestination: .updatePaymentPlan(
                bucketID: bucket.id,
                cycleID: cycle?.id,
                editor: editor
            ),
            contributeDestination: .contributeToPaymentPlan(
                bucketID: bucket.id,
                cycleID: cycle?.id,
                editor: editor
            ),
            accessibilityLabel: display.accessibilitySummary
        )
    }

    private static func paymentSegment(
        _ row: SetAsidePagerPaymentRowSnapshot
    ) -> SetAsidePagerPaymentSegmentSnapshot? {
        guard row.plannedAmount > 0 else {
            return nil
        }

        return SetAsidePagerPaymentSegmentSnapshot(
            bucketID: row.bucketID,
            cycleID: row.cycleID,
            title: row.title,
            targetAmount: row.plannedAmount,
            setAsideAmount: row.setAsideAmount,
            progress: row.progress,
            dueDate: row.dueDate
        )
    }

    private static func upcomingSnapshot(
        _ context: Context
    ) -> SetAsidePagerUpcomingSnapshot {
        let presentation = SetAsideSectionPresentation.content(
            for: .upcomingExpenses
        )
        let displayedForecasts = Array(
            context.upcomingExpenseForecasts.prefix(
                SetAsidePagerUpcomingSnapshot.summaryLimit
            )
        )
        let rows = displayedForecasts.map { forecast in
            upcomingRow(
                forecast,
                allocatedAmount: context.allocatedAmount(for: forecast)
            )
        }
        let totalNeeded = rows.reduce(0) { $0 + $1.amountNeeded }
        let totalSetAside = rows.reduce(0) { $0 + $1.setAsideAmount }
        let remaining = max(totalNeeded - totalSetAside, 0)
        let count = rows.count

        return SetAsidePagerUpcomingSnapshot(
            title: presentation.title,
            summaryLabel: upcomingSummaryLabel(count: count),
            totalSetAside: totalSetAside,
            totalNeeded: totalNeeded,
            remainingAmount: remaining,
            progress: progress(
                current: totalSetAside,
                target: totalNeeded
            ),
            activeDisplayedCount: count,
            allUpcomingOccurrenceCount:
                context.upcomingExpenseForecasts.count,
            style: .upcomingExpenses,
            rows: rows,
            isEmpty: rows.isEmpty,
            emptyState: SetAsidePagerEmptyStateSnapshot(
                title: presentation.emptyTitle,
                detail: presentation.emptyDetail
            ),
            hasAdditionalItems:
                context.upcomingExpenseForecasts.count > rows.count,
            createDestination: .createUpcomingExpense,
            seeAllDestination: .seeAllUpcomingExpenses,
            accessibilityLabel: "Upcoming Expenses. \(upcomingSummaryLabel(count: count)). \(AppFormatters.currency(totalSetAside)) set aside of \(AppFormatters.currency(totalNeeded)). \(AppFormatters.currency(remaining)) remaining."
        )
    }

    private static func upcomingRow(
        _ forecast: ForecastEvent,
        allocatedAmount: Double
    ) -> SetAsidePagerUpcomingRowSnapshot {
        let target = normalizedAmount(forecast.event.amount)
        let setAside = min(normalizedAmount(allocatedAmount), target)
        let remaining = max(target - setAside, 0)
        let title = forecast.event.name.isEmpty
            ? "Untitled Upcoming Expense"
            : forecast.event.name

        return SetAsidePagerUpcomingRowSnapshot(
            eventID: forecast.event.id,
            occurrenceID: forecast.occurrenceID,
            title: title,
            amountNeeded: target,
            setAsideAmount: setAside,
            remainingAmount: remaining,
            progress: progress(current: setAside, target: target),
            occurrenceDate: forecast.occurrenceDate,
            recurrence: forecast.event.frequency.rawValue,
            updateDestination: .updateUpcomingExpense(
                eventID: forecast.event.id,
                occurrenceID: forecast.occurrenceID
            ),
            contributeDestination: .contributeToUpcomingExpense(
                eventID: forecast.event.id,
                occurrenceID: forecast.occurrenceID
            ),
            accessibilityLabel: "\(title), due \(AppFormatters.abbreviatedMonthDay(forecast.occurrenceDate)), \(AppFormatters.currency(target)), \(AppFormatters.currency(setAside)) set aside, \(AppFormatters.currency(remaining)) remaining."
        )
    }

    private static func upcomingSummaryLabel(
        count: Int
    ) -> String {
        if count == 0 {
            return "Next 3 upcoming expenses"
        }

        return "Next \(count) upcoming expense\(count == 1 ? "" : "s")"
    }

    private static func progress(
        current: Double,
        target: Double
    ) -> Double {
        guard target > 0 else {
            return 0
        }

        return clampedProgressValue(current / target)
    }

    private static func normalizedAmount(
        _ amount: Double
    ) -> Double {
        guard amount.isFinite else {
            return 0
        }

        return max(amount, 0)
    }
}
