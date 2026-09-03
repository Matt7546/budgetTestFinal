import Foundation

enum PaymentPlanSetAsideChangeMode: String, CaseIterable, Identifiable {
    case add
    case use

    var id: Self { self }

    var title: String {
        switch self {
        case .add:
            return "Add"
        case .use:
            return "Use"
        }
    }

    var heroTitle: String {
        switch self {
        case .add:
            return "Add to Set Aside"
        case .use:
            return "Use Set Aside"
        }
    }
}

enum PaymentPlanDetailsCardTrigger: String, Identifiable {
    case planName
    case planContext
    case options

    var id: Self { self }
}

enum PaymentPlanDueDateDraftSource: String, CaseIterable, Identifiable {
    case statement
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .statement:
            return "Statement due date"
        case .custom:
            return "Custom due date"
        }
    }
}

struct PaymentPlanUpdateOriginal: Equatable {
    let name: String
    let dueDate: Date
    let paymentTargetAmount: Double
    let protectedAmount: Double
    let paymentTargetChoice: DebtPayoffLinkedCardPaymentTargetChoice?
    let targetChosenAt: Date?
    let targetStatementIssueDate: Date?
    let shouldDisplayDueDate: Bool

    init(bucket: DebtPayoffBucket) {
        name = bucket.accountName
        dueDate = bucket.dueDate
        paymentTargetAmount = bucket.paymentTargetAmount
        protectedAmount = bucket.protectedAmount
        paymentTargetChoice = bucket.paymentTargetChoice
        targetChosenAt = bucket.targetChosenAt
        targetStatementIssueDate = bucket.targetStatementIssueDate
        shouldDisplayDueDate = bucket.shouldDisplayDueDate
    }
}

struct EditPaymentPlanInput: Equatable {
    let original: PaymentPlanUpdateOriginal
    let isLinkedAccount: Bool
    var name: String
    var dueDate: Date
    var paymentTargetAmountText: String
    var paymentTargetChoice: DebtPayoffLinkedCardPaymentTargetChoice?
    var targetChosenAt: Date?
    var targetStatementIssueDate: Date?
    var shouldDisplayDueDate: Bool
    var didExplicitlyChooseTarget = false
    var setAsideChangeMode: PaymentPlanSetAsideChangeMode = .add
    var setAsideAmountText = ""
    var shouldCreateActiveCycle = false
    var cycleDueDayAnchor: Int

    init(bucket: DebtPayoffBucket, calendar: Calendar = .current) {
        let original = PaymentPlanUpdateOriginal(bucket: bucket)
        self.original = original
        isLinkedAccount = bucket.isLinkedCreditCard &&
            !bucket.plaidAccountID.isEmpty
        name = original.name
        dueDate = original.dueDate
        paymentTargetAmountText = Self.amountText(
            original.paymentTargetAmount
        )
        paymentTargetChoice = original.paymentTargetChoice
        targetChosenAt = original.targetChosenAt
        targetStatementIssueDate = original.targetStatementIssueDate
        shouldDisplayDueDate = original.shouldDisplayDueDate
        cycleDueDayAnchor = calendar.component(
            .day,
            from: original.dueDate
        )
    }

    var paymentTargetAmount: Double? {
        guard let amount = MoneyAmountParser.parse(
            paymentTargetAmountText
        ), amount.isFinite, amount > 0 else {
            return nil
        }

        return amount
    }

    var setAsideChangeAmount: Double? {
        let trimmed = setAsideAmountText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return 0
        }

        guard let amount = MoneyAmountParser.parse(trimmed),
              amount.isFinite,
              amount >= 0 else {
            return nil
        }

        return amount
    }

    var projectedSetAsideAmount: Double? {
        guard let target = paymentTargetAmount,
              let change = setAsideChangeAmount else {
            return nil
        }

        let projected: Double
        switch setAsideChangeMode {
        case .add:
            projected = original.protectedAmount + change
        case .use:
            guard change <= original.protectedAmount else {
                return nil
            }
            projected = original.protectedAmount - change
        }

        guard projected.isFinite,
              projected >= 0,
              projected <= target + PaymentPlanSuggestedUpdateRules.amountTolerance else {
            return nil
        }

        return min(projected, target)
    }

    var remainingAmount: Double {
        max(
            (paymentTargetAmount ?? original.paymentTargetAmount) -
                (projectedSetAsideAmount ?? original.protectedAmount),
            0
        )
    }

    var projectedProgress: Double {
        let target = paymentTargetAmount ?? original.paymentTargetAmount
        let setAside = projectedSetAsideAmount ?? original.protectedAmount
        guard target > 0 else { return 0 }
        return min(max(setAside / target, 0), 1)
    }

    var hasDetailsChange: Bool {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let targetChanged = paymentTargetAmount.map {
            !PaymentPlanSuggestedUpdateRules.amountsMatch(
                $0,
                original.paymentTargetAmount
            )
        } ?? true

        return trimmedName != original.name ||
            targetChanged ||
            !Calendar.current.isDate(dueDate, inSameDayAs: original.dueDate) ||
            paymentTargetChoice != original.paymentTargetChoice ||
            targetStatementIssueDate != original.targetStatementIssueDate ||
            shouldDisplayDueDate != original.shouldDisplayDueDate
    }

    var hasSetAsideChange: Bool {
        (setAsideChangeAmount ?? 0) >
            PaymentPlanSuggestedUpdateRules.amountTolerance
    }

    var hasValidChange: Bool {
        validationMessage == nil &&
            (hasDetailsChange || hasSetAsideChange || shouldCreateActiveCycle)
    }

    var validationMessage: String? {
        guard !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return "Add a Payment Plan name to save."
        }

        guard let target = paymentTargetAmount else {
            return "Enter a Payment Target greater than $0."
        }

        guard let change = setAsideChangeAmount else {
            return "Enter a valid Set Aside amount."
        }

        if setAsideChangeMode == .use,
           change > original.protectedAmount {
            return "You can use up to \(AppFormatters.currency(original.protectedAmount)) from this plan."
        }

        if setAsideChangeMode == .add,
           original.protectedAmount + change >
            target + PaymentPlanSuggestedUpdateRules.amountTolerance {
            return "You can add up to \(AppFormatters.currency(max(target - original.protectedAmount, 0))) to this plan."
        }

        guard projectedSetAsideAmount != nil else {
            return "Set Aside cannot be more than the Payment Target."
        }

        guard hasDetailsChange || hasSetAsideChange || shouldCreateActiveCycle else {
            return "Make a change to save."
        }

        return nil
    }

    func draft(
        for bucket: DebtPayoffBucket,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DebtPayoffBucketDraft? {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedName.isEmpty,
              let target = paymentTargetAmount,
              let projectedSetAsideAmount else {
            return nil
        }

        let provenance = resolvedTargetProvenance(
            bucket: bucket,
            savedPaymentTarget: target,
            now: now
        )

        return DebtPayoffBucketDraft(
            debtKind: bucket.debtKind,
            plaidAccountID: bucket.plaidAccountID,
            accountName: trimmedName,
            institutionName: bucket.institutionName,
            dueDate: dueDate,
            paymentTargetAmount: target,
            protectedAmount: projectedSetAsideAmount,
            paymentTargetChoice: provenance.choice,
            targetChosenAt: provenance.chosenAt,
            targetStatementIssueDate: provenance.statementIssueDate,
            manualCurrentBalance: bucket.manualCurrentBalance,
            monthlyPayment: bucket.monthlyPayment,
            originalBalance: bucket.originalBalance,
            interestRate: bucket.interestRate,
            notes: bucket.notes,
            hasPaymentDueDate: shouldDisplayDueDate,
            startDate: bucket.startDate,
            endDate: bucket.endDate,
            shouldCreateActiveCycle: shouldCreateActiveCycle,
            cycleDueDayAnchor: shouldCreateActiveCycle
                ? cycleDueDayAnchor
                : calendar.component(.day, from: dueDate)
        )
    }

    mutating func resetBaseline(
        from bucket: DebtPayoffBucket,
        calendar: Calendar = .current
    ) {
        self = EditPaymentPlanInput(
            bucket: bucket,
            calendar: calendar
        )
    }

    private func resolvedTargetProvenance(
        bucket: DebtPayoffBucket,
        savedPaymentTarget: Double,
        now: Date
    ) -> (
        choice: DebtPayoffLinkedCardPaymentTargetChoice?,
        chosenAt: Date?,
        statementIssueDate: Date?
    ) {
        guard isLinkedAccount else {
            return (nil, nil, nil)
        }

        if didExplicitlyChooseTarget {
            return (
                paymentTargetChoice,
                now,
                paymentTargetChoice == .statementBalance
                    ? targetStatementIssueDate
                    : nil
            )
        }

        if PaymentPlanSuggestedUpdateRules.amountsMatch(
            savedPaymentTarget,
            bucket.paymentTargetAmount
        ) {
            return (
                bucket.paymentTargetChoice,
                bucket.targetChosenAt,
                bucket.targetStatementIssueDate
            )
        }

        if bucket.paymentTargetChoice != nil {
            return (.customAmount, now, nil)
        }

        return (nil, nil, nil)
    }

    static func amountText(_ amount: Double) -> String {
        String(format: "%.2f", max(amount, 0))
    }
}

struct PaymentPlanDetailsDraft: Equatable {
    var name: String
    var paymentTargetAmountText: String
    var paymentTargetChoice: DebtPayoffLinkedCardPaymentTargetChoice?
    var dueDate: Date
    var dueDateSource: PaymentPlanDueDateDraftSource
    var targetStatementIssueDate: Date?
    var didExplicitlyChooseTarget: Bool

    init(
        input: EditPaymentPlanInput,
        statementDueDate: Date? = nil,
        calendar: Calendar = .current
    ) {
        name = input.name
        paymentTargetAmountText = input.paymentTargetAmountText
        paymentTargetChoice = input.paymentTargetChoice
        dueDate = input.dueDate
        dueDateSource = statementDueDate.map {
            calendar.isDate($0, inSameDayAs: input.dueDate)
                ? .statement
                : .custom
        } ?? .custom
        targetStatementIssueDate = input.targetStatementIssueDate
        didExplicitlyChooseTarget = input.didExplicitlyChooseTarget
    }

    var paymentTargetAmount: Double? {
        guard let amount = MoneyAmountParser.parse(
            paymentTargetAmountText
        ), amount.isFinite, amount > 0 else {
            return nil
        }
        return amount
    }

    var isValid: Bool {
        !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty && paymentTargetAmount != nil
    }
}

enum PaymentPlanDetailsDraftCoordinator {
    static func apply(
        draft: PaymentPlanDetailsDraft,
        to input: inout EditPaymentPlanInput
    ) -> Bool {
        guard draft.isValid else { return false }

        input.name = draft.name
        input.paymentTargetAmountText = draft.paymentTargetAmountText
        input.paymentTargetChoice = draft.paymentTargetChoice
        input.dueDate = draft.dueDate
        input.targetStatementIssueDate = draft.targetStatementIssueDate
        input.didExplicitlyChooseTarget = draft.didExplicitlyChooseTarget
        return true
    }
}

enum PaymentPlanLifecycleDraftPreparationResult: Equatable {
    case blockedInvalidDetails
    case ready
    case requiresSwipeSave
}

enum PaymentPlanLifecycleDraftCoordinator {
    static func prepareMarkAsHandled(
        draft: PaymentPlanDetailsDraft,
        input: inout EditPaymentPlanInput
    ) -> PaymentPlanLifecycleDraftPreparationResult {
        guard PaymentPlanDetailsDraftCoordinator.apply(
            draft: draft,
            to: &input
        ) else {
            return .blockedInvalidDetails
        }

        return input.hasValidChange ? .requiresSwipeSave : .ready
    }

    static func preparePlanNextPayment(
        draft: PaymentPlanDetailsDraft,
        latestCycle: PaymentPlanCycle,
        input: inout EditPaymentPlanInput
    ) -> PaymentPlanLifecycleDraftPreparationResult {
        guard PaymentPlanDetailsDraftCoordinator.apply(
            draft: draft,
            to: &input
        ) else {
            return .blockedInvalidDetails
        }

        input.dueDate = PaymentPlanCycleSchedule.nextMonthlyDueDate(
            after: latestCycle.dueDate,
            anchorDay: latestCycle.dueDayAnchor
        )
        input.cycleDueDayAnchor = latestCycle.dueDayAnchor
        input.setAsideChangeMode = .use
        input.setAsideAmountText = EditPaymentPlanInput.amountText(
            input.original.protectedAmount
        )
        input.shouldCreateActiveCycle = true
        return .requiresSwipeSave
    }

    static func prepareTrackPayment(
        draft: PaymentPlanDetailsDraft,
        input: inout EditPaymentPlanInput
    ) -> PaymentPlanLifecycleDraftPreparationResult {
        guard PaymentPlanDetailsDraftCoordinator.apply(
            draft: draft,
            to: &input
        ) else {
            return .blockedInvalidDetails
        }

        input.shouldCreateActiveCycle = true
        return .requiresSwipeSave
    }
}

enum PaymentPlanUpdateRouting {
    static func usesModernEditor(for bucket: DebtPayoffBucket) -> Bool {
        bucket.debtKind == .linkedCreditCard
    }
}

enum PaymentPlanUpdatePersistenceCoordinator {

    static func persist(
        draft: DebtPayoffBucketDraft,
        bucket: DebtPayoffBucket,
        activeCycle: PaymentPlanCycle?,
        existingCycles: [PaymentPlanCycle],
        now: Date = Date(),
        insertCycle: (PaymentPlanCycle) -> Void,
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> PlanningCreationPersistenceResult {
        let bucketSnapshot = BucketSnapshot(bucket: bucket)
        let cycleSnapshot = activeCycle.map {
            CycleSnapshot(cycle: $0)
        }

        apply(
            draft: draft,
            to: bucket,
            activeCycle: activeCycle,
            existingCycles: existingCycles,
            now: now,
            insertCycle: insertCycle
        )

        do {
            try persistChanges()
            return .saved
        } catch {
            rollback()
            bucketSnapshot.restore(bucket)
            if let activeCycle,
               let cycleSnapshot {
                cycleSnapshot.restore(activeCycle)
            }
            return .failed(
                message: "Your Payment Plan update wasn't saved. Please try again."
            )
        }
    }

    private static func apply(
        draft: DebtPayoffBucketDraft,
        to bucket: DebtPayoffBucket,
        activeCycle: PaymentPlanCycle?,
        existingCycles: [PaymentPlanCycle],
        now: Date,
        insertCycle: (PaymentPlanCycle) -> Void
    ) {
        bucket.debtKind = draft.debtKind
        bucket.plaidAccountID = draft.plaidAccountID
        bucket.accountName = draft.accountName
        bucket.institutionName = draft.institutionName
        bucket.dueDate = draft.dueDate
        bucket.paymentTargetAmount = draft.paymentTargetAmount
        bucket.protectedAmount = draft.protectedAmount
        bucket.paymentTargetChoice = draft.paymentTargetChoice
        bucket.targetChosenAt = draft.targetChosenAt
        bucket.targetStatementIssueDate = draft.targetStatementIssueDate
        bucket.manualCurrentBalance = draft.manualCurrentBalance
        bucket.monthlyPayment = draft.monthlyPayment
        bucket.originalBalance = draft.originalBalance
        bucket.interestRate = draft.interestRate
        bucket.notes = draft.notes
        bucket.hasPaymentDueDate = draft.hasPaymentDueDate
        bucket.startDate = draft.startDate
        bucket.endDate = draft.endDate
        bucket.updatedAt = now

        if let activeCycle {
            activeCycle.dueDate = draft.dueDate
            activeCycle.dueDayAnchor = draft.cycleDueDayAnchor
            activeCycle.frozenTargetAmount = draft.paymentTargetAmount
            activeCycle.cycleKey = PaymentPlanCycle.identityKey(
                paymentPlanID: bucket.id,
                dueDate: draft.dueDate
            )
            activeCycle.updatedAt = now
        } else if draft.shouldCreateActiveCycle,
                  let cycle = PaymentPlanCycleStore.makeActiveCycle(
                    for: bucket,
                    dueDate: draft.dueDate,
                    targetAmount: draft.paymentTargetAmount,
                    dueDayAnchor: draft.cycleDueDayAnchor,
                    existingCycles: existingCycles
                  ) {
            insertCycle(cycle)
        }
    }

    private struct BucketSnapshot {
        let debtKind: DebtPayoffKind
        let plaidAccountID: String
        let accountName: String
        let institutionName: String?
        let dueDate: Date
        let paymentTargetAmount: Double
        let protectedAmount: Double
        let paymentTargetChoice: DebtPayoffLinkedCardPaymentTargetChoice?
        let targetChosenAt: Date?
        let targetStatementIssueDate: Date?
        let manualCurrentBalance: Double?
        let monthlyPayment: Double?
        let originalBalance: Double?
        let interestRate: Double?
        let notes: String?
        let hasPaymentDueDate: Bool?
        let startDate: Date?
        let endDate: Date?
        let updatedAt: Date

        init(bucket: DebtPayoffBucket) {
            debtKind = bucket.debtKind
            plaidAccountID = bucket.plaidAccountID
            accountName = bucket.accountName
            institutionName = bucket.institutionName
            dueDate = bucket.dueDate
            paymentTargetAmount = bucket.paymentTargetAmount
            protectedAmount = bucket.protectedAmount
            paymentTargetChoice = bucket.paymentTargetChoice
            targetChosenAt = bucket.targetChosenAt
            targetStatementIssueDate = bucket.targetStatementIssueDate
            manualCurrentBalance = bucket.manualCurrentBalance
            monthlyPayment = bucket.monthlyPayment
            originalBalance = bucket.originalBalance
            interestRate = bucket.interestRate
            notes = bucket.notes
            hasPaymentDueDate = bucket.hasPaymentDueDate
            startDate = bucket.startDate
            endDate = bucket.endDate
            updatedAt = bucket.updatedAt
        }

        func restore(_ bucket: DebtPayoffBucket) {
            bucket.debtKind = debtKind
            bucket.plaidAccountID = plaidAccountID
            bucket.accountName = accountName
            bucket.institutionName = institutionName
            bucket.dueDate = dueDate
            bucket.paymentTargetAmount = paymentTargetAmount
            bucket.protectedAmount = protectedAmount
            bucket.paymentTargetChoice = paymentTargetChoice
            bucket.targetChosenAt = targetChosenAt
            bucket.targetStatementIssueDate = targetStatementIssueDate
            bucket.manualCurrentBalance = manualCurrentBalance
            bucket.monthlyPayment = monthlyPayment
            bucket.originalBalance = originalBalance
            bucket.interestRate = interestRate
            bucket.notes = notes
            bucket.hasPaymentDueDate = hasPaymentDueDate
            bucket.startDate = startDate
            bucket.endDate = endDate
            bucket.updatedAt = updatedAt
        }
    }

    private struct CycleSnapshot {
        let dueDate: Date
        let dueDayAnchor: Int
        let frozenTargetAmount: Double
        let cycleKey: String
        let updatedAt: Date

        init(cycle: PaymentPlanCycle) {
            dueDate = cycle.dueDate
            dueDayAnchor = cycle.dueDayAnchor
            frozenTargetAmount = cycle.frozenTargetAmount
            cycleKey = cycle.cycleKey
            updatedAt = cycle.updatedAt
        }

        func restore(_ cycle: PaymentPlanCycle) {
            cycle.dueDate = dueDate
            cycle.dueDayAnchor = dueDayAnchor
            cycle.frozenTargetAmount = frozenTargetAmount
            cycle.cycleKey = cycleKey
            cycle.updatedAt = updatedAt
        }
    }
}

struct PaymentPlanCoverInFullSnapshot: Equatable {
    let paymentPlanID: UUID
    let cycleID: UUID?
    let targetAmount: Double
    let currentAmount: Double
    let remainingAmount: Double
}

enum PaymentPlanCoverInFullAvailability: Equatable {
    case available(PaymentPlanCoverInFullSnapshot)
    case covered
    case unavailable

    var snapshot: PaymentPlanCoverInFullSnapshot? {
        guard case .available(let snapshot) = self else {
            return nil
        }

        return snapshot
    }
}

struct PaymentPlanCoverInFullRequest: Identifiable, Equatable {
    let coverRequest: CoverInFullRequest
    let paymentPlanID: UUID
    let cycleID: UUID?

    var id: UUID { coverRequest.id }
}

enum PaymentPlanCoverInFullPersistenceResult: Equatable {
    case saved(amount: Double)
    case unavailable
    case failed(message: String)

    var didSave: Bool {
        guard case .saved = self else { return false }
        return true
    }

    var errorMessage: String? {
        switch self {
        case .saved:
            return nil
        case .unavailable:
            return CoverInFullPolicy.failureMessage
        case .failed(let message):
            return message
        }
    }
}

enum PaymentPlanCoverInFullCoordinator {

    static func availability(
        for bucket: DebtPayoffBucket,
        activeCycle: PaymentPlanCycle?,
        cycles: [PaymentPlanCycle]
    ) -> PaymentPlanCoverInFullAvailability {
        let planCycles = PaymentPlanCycleStore.cycles(
            for: bucket.id,
            in: cycles
        )

        let cycleID: UUID?
        let targetAmount: Double

        if let activeCycle {
            guard activeCycle.paymentPlanID == bucket.id,
                  activeCycle.isActive,
                  let exactCycle = planCycles.first(where: {
                    $0.id == activeCycle.id && $0.isActive
                  }) else {
                return .unavailable
            }

            cycleID = exactCycle.id
            targetAmount = exactCycle.frozenTargetAmount
        } else {
            guard planCycles.isEmpty else {
                return .unavailable
            }

            cycleID = nil
            targetAmount = cyclelessTarget(for: bucket)
        }

        guard targetAmount.isFinite,
              targetAmount > 0,
              bucket.protectedAmount.isFinite else {
            return .unavailable
        }

        let currentAmount = max(bucket.protectedAmount, 0)
        let remainingAmount = CoverInFullPolicy.remainingAmount(
            target: targetAmount,
            current: currentAmount
        )

        guard remainingAmount > 0 else {
            return .covered
        }

        return .available(
            PaymentPlanCoverInFullSnapshot(
                paymentPlanID: bucket.id,
                cycleID: cycleID,
                targetAmount: targetAmount,
                currentAmount: currentAmount,
                remainingAmount: remainingAmount
            )
        )
    }

    static func request(
        for bucket: DebtPayoffBucket,
        activeCycle: PaymentPlanCycle?,
        cycles: [PaymentPlanCycle]
    ) -> PaymentPlanCoverInFullRequest? {
        guard let snapshot = availability(
            for: bucket,
            activeCycle: activeCycle,
            cycles: cycles
        ).snapshot else {
            return nil
        }

        return PaymentPlanCoverInFullRequest(
            coverRequest: CoverInFullRequest(
                name: bucket.accountName,
                amount: snapshot.remainingAmount
            ),
            paymentPlanID: snapshot.paymentPlanID,
            cycleID: snapshot.cycleID
        )
    }

    static func persist(
        _ request: PaymentPlanCoverInFullRequest,
        bucket: DebtPayoffBucket,
        activeCycle: PaymentPlanCycle?,
        cycles: [PaymentPlanCycle],
        now: Date = Date(),
        persistChanges: () throws -> Void,
        rollback: () -> Void
    ) -> PaymentPlanCoverInFullPersistenceResult {
        guard request.paymentPlanID == bucket.id,
              let snapshot = availability(
                for: bucket,
                activeCycle: activeCycle,
                cycles: cycles
              ).snapshot,
              snapshot.paymentPlanID == request.paymentPlanID,
              snapshot.cycleID == request.cycleID,
              abs(
                snapshot.remainingAmount - request.coverRequest.amount
              ) <= CoverInFullPolicy.amountTolerance else {
            return .unavailable
        }

        let priorProtectedAmount = bucket.protectedAmount
        let priorUpdatedAt = bucket.updatedAt

        bucket.protectedAmount = snapshot.targetAmount
        bucket.updatedAt = now

        do {
            try persistChanges()
            return .saved(amount: snapshot.remainingAmount)
        } catch {
            rollback()
            bucket.protectedAmount = priorProtectedAmount
            bucket.updatedAt = priorUpdatedAt
            return .failed(message: CoverInFullPolicy.failureMessage)
        }
    }

    private static func cyclelessTarget(
        for bucket: DebtPayoffBucket
    ) -> Double {
        if bucket.paymentTargetAmount.isFinite,
           bucket.paymentTargetAmount > 0 {
            return bucket.paymentTargetAmount
        }

        guard bucket.debtKind.isManualInstallmentDebt,
              let monthlyPayment = bucket.monthlyPayment,
              monthlyPayment.isFinite,
              monthlyPayment > 0 else {
            return 0
        }

        return monthlyPayment
    }
}
