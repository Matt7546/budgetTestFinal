import Foundation

/// The required SwiftData inputs consumed by `SavingsGoalsView`.
///
/// Production supplies both the records and failure bits directly from its
/// `@Query` properties. Controlled validation failures are additive, so they
/// preserve the last records delivered by SwiftData and can never conceal a
/// real fetch error or turn an unavailable result into an available one.
struct SavingsGoalsRequiredQueryResult {
    let events: [PlannerEvent]
    let allocations: [EventAllocation]
    let occurrenceStatuses: [ExpenseOccurrenceStatus]
    let debtPayoffBuckets: [DebtPayoffBucket]
    let paymentPlanCycles: [PaymentPlanCycle]
    let reserveSettings: [ReserveSettings]
    let failedRequiredReads: Set<PlanningPersistenceReadDomain>
}

enum SavingsGoalsRequiredQueryResultAdapter {
    static func resolve(
        events: [PlannerEvent],
        eventsFetchFailed: Bool,
        allocations: [EventAllocation],
        allocationsFetchFailed: Bool,
        occurrenceStatuses: [ExpenseOccurrenceStatus],
        occurrenceStatusesFetchFailed: Bool,
        debtPayoffBuckets: [DebtPayoffBucket],
        debtPayoffBucketsFetchFailed: Bool,
        paymentPlanCycles: [PaymentPlanCycle],
        paymentPlanCyclesFetchFailed: Bool,
        reserveSettings: [ReserveSettings],
        reserveSettingsFetchFailed: Bool,
        additionalControlledFailures:
            Set<PlanningPersistenceReadDomain> = []
    ) -> SavingsGoalsRequiredQueryResult {
        var failures = additionalControlledFailures
        if eventsFetchFailed { failures.insert(.plannerEvents) }
        if allocationsFetchFailed { failures.insert(.eventAllocations) }
        if occurrenceStatusesFetchFailed {
            failures.insert(.occurrenceStatuses)
        }
        if debtPayoffBucketsFetchFailed {
            failures.insert(.debtPayoffBuckets)
        }
        if paymentPlanCyclesFetchFailed {
            failures.insert(.paymentPlanCycles)
        }
        if reserveSettingsFetchFailed {
            failures.insert(.reserveSettings)
        }

        return SavingsGoalsRequiredQueryResult(
            events: events,
            allocations: allocations,
            occurrenceStatuses: occurrenceStatuses,
            debtPayoffBuckets: debtPayoffBuckets,
            paymentPlanCycles: paymentPlanCycles,
            reserveSettings: reserveSettings,
            failedRequiredReads: failures
        )
    }
}
