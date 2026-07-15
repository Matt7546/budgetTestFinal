import Foundation
import SwiftData

enum PaymentPlanCycleStatus: String, Codable {
    case active
    case handled
}

enum PaymentPlanCycleResolution: String, Codable {
    case paid

    var displayTitle: String {
        "Handled"
    }
}

@Model
final class PaymentPlanCycle {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var cycleKey: String
    var paymentPlanID: UUID
    var dueDate: Date
    var dueDayAnchor: Int
    var frozenTargetAmount: Double
    var statusRawValue: String
    var resolutionRawValue: String?
    var handledAt: Date?
    var releasedSetAsideAmount: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        paymentPlanID: UUID,
        dueDate: Date,
        dueDayAnchor: Int? = nil,
        frozenTargetAmount: Double,
        status: PaymentPlanCycleStatus = .active,
        resolution: PaymentPlanCycleResolution? = nil,
        handledAt: Date? = nil,
        releasedSetAsideAmount: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.id = id
        self.paymentPlanID = paymentPlanID
        self.dueDate = dueDate
        self.dueDayAnchor = dueDayAnchor ?? calendar.component(.day, from: dueDate)
        self.frozenTargetAmount = max(frozenTargetAmount, 0)
        self.statusRawValue = status.rawValue
        self.resolutionRawValue = resolution?.rawValue
        self.handledAt = handledAt
        self.releasedSetAsideAmount = max(releasedSetAsideAmount, 0)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cycleKey = Self.identityKey(
            paymentPlanID: paymentPlanID,
            dueDate: dueDate,
            calendar: calendar
        )
    }

    var status: PaymentPlanCycleStatus {
        get { PaymentPlanCycleStatus(rawValue: statusRawValue) ?? .active }
        set {
            statusRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    var resolution: PaymentPlanCycleResolution? {
        get { resolutionRawValue.flatMap(PaymentPlanCycleResolution.init(rawValue:)) }
        set {
            resolutionRawValue = newValue?.rawValue
            updatedAt = Date()
        }
    }

    var isActive: Bool { status == .active }

    static func identityKey(
        paymentPlanID: UUID,
        dueDate: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: dueDate)
        return "\(paymentPlanID.uuidString.lowercased())|\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

enum PaymentPlanCycleStore {
    static func cycles(
        for paymentPlanID: UUID,
        in cycles: [PaymentPlanCycle]
    ) -> [PaymentPlanCycle] {
        cycles
            .filter { $0.paymentPlanID == paymentPlanID }
            .sorted {
                if $0.dueDate != $1.dueDate { return $0.dueDate > $1.dueDate }
                return $0.createdAt > $1.createdAt
            }
    }

    static func activeCycle(
        for paymentPlanID: UUID,
        in cycles: [PaymentPlanCycle]
    ) -> PaymentPlanCycle? {
        self.cycles(for: paymentPlanID, in: cycles).first(where: \.isActive)
    }

    static func latestCycle(
        for paymentPlanID: UUID,
        in cycles: [PaymentPlanCycle]
    ) -> PaymentPlanCycle? {
        self.cycles(for: paymentPlanID, in: cycles).first
    }

    static func isActiveOrLegacy(
        paymentPlanID: UUID,
        cycles: [PaymentPlanCycle]
    ) -> Bool {
        let planCycles = self.cycles(for: paymentPlanID, in: cycles)
        return planCycles.isEmpty || planCycles.contains(where: \.isActive)
    }

    static func makeActiveCycle(
        for bucket: DebtPayoffBucket,
        dueDate: Date,
        targetAmount: Double,
        dueDayAnchor: Int? = nil,
        existingCycles: [PaymentPlanCycle],
        calendar: Calendar = .current
    ) -> PaymentPlanCycle? {
        guard activeCycle(for: bucket.id, in: existingCycles) == nil else { return nil }

        let identity = PaymentPlanCycle.identityKey(
            paymentPlanID: bucket.id,
            dueDate: dueDate,
            calendar: calendar
        )
        guard !existingCycles.contains(where: { $0.cycleKey == identity }) else { return nil }

        return PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: dueDate,
            dueDayAnchor: dueDayAnchor,
            frozenTargetAmount: targetAmount,
            calendar: calendar
        )
    }
}

enum PaymentPlanCycleSchedule {
    static func nextMonthlyDueDate(
        after dueDate: Date,
        anchorDay: Int,
        calendar: Calendar = .current
    ) -> Date {
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: dueDate)
        ) ?? dueDate
        let nextMonthStart = calendar.date(
            byAdding: .month,
            value: 1,
            to: monthStart
        ) ?? dueDate
        let lastDay = calendar.range(of: .day, in: .month, for: nextMonthStart)?.count ?? 28
        var components = calendar.dateComponents([.year, .month], from: nextMonthStart)
        components.day = min(max(anchorDay, 1), lastDay)
        return calendar.date(from: components) ?? nextMonthStart
    }
}

struct PaymentPlanCycleResolutionUndo {
    let cycle: PaymentPlanCycle
    let priorStatusRawValue: String
    let priorResolutionRawValue: String?
    let priorHandledAt: Date?
    let priorReleasedSetAsideAmount: Double
    let priorCycleUpdatedAt: Date
    let bucket: DebtPayoffBucket
    let priorProtectedAmount: Double
    let priorBucketUpdatedAt: Date

    func restore() {
        cycle.statusRawValue = priorStatusRawValue
        cycle.resolutionRawValue = priorResolutionRawValue
        cycle.handledAt = priorHandledAt
        cycle.releasedSetAsideAmount = priorReleasedSetAsideAmount
        cycle.updatedAt = priorCycleUpdatedAt
        bucket.protectedAmount = priorProtectedAmount
        bucket.updatedAt = priorBucketUpdatedAt
    }
}

enum PaymentPlanCycleResolutionMutation {
    static func apply(
        _ resolution: PaymentPlanCycleResolution,
        to cycle: PaymentPlanCycle,
        bucket: DebtPayoffBucket,
        handledAt: Date = Date()
    ) -> PaymentPlanCycleResolutionUndo? {
        guard cycle.isActive else { return nil }

        let undo = PaymentPlanCycleResolutionUndo(
            cycle: cycle,
            priorStatusRawValue: cycle.statusRawValue,
            priorResolutionRawValue: cycle.resolutionRawValue,
            priorHandledAt: cycle.handledAt,
            priorReleasedSetAsideAmount: cycle.releasedSetAsideAmount,
            priorCycleUpdatedAt: cycle.updatedAt,
            bucket: bucket,
            priorProtectedAmount: bucket.protectedAmount,
            priorBucketUpdatedAt: bucket.updatedAt
        )
        let releasedAmount = max(bucket.protectedAmount, 0)
        cycle.statusRawValue = PaymentPlanCycleStatus.handled.rawValue
        cycle.resolutionRawValue = resolution.rawValue
        cycle.handledAt = handledAt
        cycle.releasedSetAsideAmount = releasedAmount
        cycle.updatedAt = handledAt
        bucket.protectedAmount = 0
        bucket.updatedAt = handledAt
        return undo
    }
}

struct PaymentPlanPaymentCandidate: Identifiable, Equatable {
    let paymentPlanID: UUID
    let cycleID: UUID
    let transactionID: String
    let amount: Double
    let postedDate: Date
    let isCorroboratedByCardDetails: Bool

    var id: String {
        "\(cycleID.uuidString.lowercased())|\(transactionID)"
    }
}

enum PaymentPlanPaymentDetector {

    /// A card payment normally posts shortly before its due date. Looking no
    /// farther than 14 days before or 7 days after keeps older credits out of
    /// the candidate set while allowing ordinary posting delays.
    static let daysBeforeDueDate = 14
    static let daysAfterDueDate = 7

    /// Payment targets and Plaid amounts are currency values. A one-cent
    /// tolerance allows floating-point representation noise without treating
    /// a meaningfully different amount as a match.
    static let amountTolerance = 0.01

    static func candidate(
        for bucket: DebtPayoffBucket,
        cycle: PaymentPlanCycle,
        transactions: [PlaidTransaction],
        cardDetails: LinkedCardPaymentDetails?,
        dataIsEligible: Bool,
        calendar: Calendar = .current
    ) -> PaymentPlanPaymentCandidate? {
        guard dataIsEligible,
              bucket.isLinkedCreditCard,
              !bucket.plaidAccountID.isEmpty,
              cycle.isActive,
              cycle.paymentPlanID == bucket.id,
              cycle.frozenTargetAmount > 0 else {
            return nil
        }

        let dueDate = calendar.startOfDay(for: cycle.dueDate)
        guard let dueWindowStart = calendar.date(
                byAdding: .day,
                value: -daysBeforeDueDate,
                to: dueDate
              ),
              let windowEnd = calendar.date(
                byAdding: .day,
                value: daysAfterDueDate,
                to: dueDate
              ) else {
            return nil
        }

        let cycleCreatedDate = calendar.startOfDay(for: cycle.createdAt)
        let windowStart = max(dueWindowStart, cycleCreatedDate)

        guard windowStart <= windowEnd else {
            return nil
        }

        let matchingTransactions = transactions.compactMap { transaction in
            match(
                transaction,
                bucket: bucket,
                cycle: cycle,
                cardDetails: cardDetails,
                windowStart: windowStart,
                windowEnd: windowEnd,
                calendar: calendar
            )
        }
        .sorted {
            if $0.postedDate != $1.postedDate {
                return $0.postedDate > $1.postedDate
            }

            return $0.transactionID < $1.transactionID
        }

        guard !matchingTransactions.isEmpty else {
            return nil
        }

        let corroborated = matchingTransactions.filter(
            \.isCorroboratedByCardDetails
        )

        if corroborated.count == 1 {
            return corroborated[0]
        }

        return matchingTransactions.count == 1
            ? matchingTransactions[0]
            : nil
    }

    private static func match(
        _ transaction: PlaidTransaction,
        bucket: DebtPayoffBucket,
        cycle: PaymentPlanCycle,
        cardDetails: LinkedCardPaymentDetails?,
        windowStart: Date,
        windowEnd: Date,
        calendar: Calendar
    ) -> PaymentPlanPaymentCandidate? {
        guard transaction.account_id == bucket.plaidAccountID,
              transaction.pending == false,
              transaction.amount.isFinite,
              transaction.amount < 0,
              isPaymentDescription(transaction.name),
              amountsMatch(
                abs(transaction.amount),
                cycle.frozenTargetAmount
              ),
              let postedDate = PaymentPlanCalendarDate.parse(
                transaction.date,
                calendar: calendar
              ) else {
            return nil
        }

        let postedDay = calendar.startOfDay(for: postedDate)
        guard postedDay >= windowStart,
              postedDay <= windowEnd else {
            return nil
        }

        return PaymentPlanPaymentCandidate(
            paymentPlanID: bucket.id,
            cycleID: cycle.id,
            transactionID: transaction.transaction_id,
            amount: abs(transaction.amount),
            postedDate: postedDate,
            isCorroboratedByCardDetails: cardDetailsCorroborate(
                cardDetails,
                accountID: bucket.plaidAccountID,
                amount: abs(transaction.amount),
                postedDate: postedDate,
                calendar: calendar
            )
        )
    }

    private static func isPaymentDescription(
        _ value: String
    ) -> Bool {
        let normalized = value
            .lowercased()
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let excludedSignals = [
            "refund",
            "return",
            "reversal",
            "reversed",
            "cash back",
            "cashback",
            "reward",
            "rebate",
            "chargeback",
            "statement credit",
            "merchant credit",
            "purchase adjustment",
        ]

        guard !excludedSignals.contains(where: normalized.contains) else {
            return false
        }

        let paymentSignals = [
            "payment",
            "pymt",
            "autopay",
            "auto pay",
            "thank you",
            "thankyou",
        ]

        return paymentSignals.contains(where: normalized.contains)
    }

    private static func cardDetailsCorroborate(
        _ cardDetails: LinkedCardPaymentDetails?,
        accountID: String,
        amount: Double,
        postedDate: Date,
        calendar: Calendar
    ) -> Bool {
        guard cardDetails?.account_id == accountID,
              let lastPaymentAmount = cardDetails?.last_payment_amount,
              amountsMatch(lastPaymentAmount, amount),
              let lastPaymentDate = PaymentPlanCalendarDate.parse(
                cardDetails?.last_payment_date,
                calendar: calendar
              ) else {
            return false
        }

        return calendar.isDate(
            lastPaymentDate,
            inSameDayAs: postedDate
        )
    }

    private static func amountsMatch(
        _ lhs: Double,
        _ rhs: Double
    ) -> Bool {
        abs(lhs - rhs) <= amountTolerance
    }

}
