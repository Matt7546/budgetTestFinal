import Foundation
import SwiftData

enum DebtPayoffKind: String, CaseIterable, Identifiable {
    case linkedCreditCard
    case autoLoan
    case mortgage
    case studentLoan
    case personalLoan
    case other

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .linkedCreditCard:
            return "Credit Card"

        case .autoLoan:
            return "Auto Loan"

        case .mortgage:
            return "Mortgage"

        case .studentLoan:
            return "Student Loan"

        case .personalLoan:
            return "Personal Loan"

        case .other:
            return "Other Debt"
        }
    }

    var isManualInstallmentDebt: Bool {
        self != .linkedCreditCard
    }
}

@Model
final class DebtPayoffBucket {

    var id: UUID
    var plaidAccountID: String
    var accountName: String
    var institutionName: String?
    var dueDate: Date
    var paymentTargetAmount: Double
    var protectedAmount: Double
    var debtKindRawValue: String?
    var manualCurrentBalance: Double?
    var monthlyPayment: Double?
    var originalBalance: Double?
    var interestRate: Double?
    var notes: String?
    var hasPaymentDueDate: Bool?
    var startDate: Date?
    var endDate: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        plaidAccountID: String,
        accountName: String,
        institutionName: String? = nil,
        dueDate: Date,
        paymentTargetAmount: Double,
        protectedAmount: Double = 0,
        debtKind: DebtPayoffKind = .linkedCreditCard,
        manualCurrentBalance: Double? = nil,
        monthlyPayment: Double? = nil,
        originalBalance: Double? = nil,
        interestRate: Double? = nil,
        notes: String? = nil,
        hasPaymentDueDate: Bool? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.plaidAccountID = plaidAccountID
        self.accountName = accountName
        self.institutionName = institutionName
        self.dueDate = dueDate
        self.paymentTargetAmount = paymentTargetAmount
        self.protectedAmount = protectedAmount
        self.debtKindRawValue = debtKind.rawValue
        self.manualCurrentBalance = manualCurrentBalance
        self.monthlyPayment = monthlyPayment
        self.originalBalance = originalBalance
        self.interestRate = interestRate
        self.notes = notes
        self.hasPaymentDueDate = hasPaymentDueDate
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var debtKind: DebtPayoffKind {
        get {
            if let debtKindRawValue,
               let kind = DebtPayoffKind(rawValue: debtKindRawValue) {
                return kind
            }

            return plaidAccountID.isEmpty ? .other : .linkedCreditCard
        }
        set {
            debtKindRawValue = newValue.rawValue
        }
    }

    var isLinkedCreditCard: Bool {
        debtKind == .linkedCreditCard
    }

    var shouldDisplayDueDate: Bool {
        get {
            hasPaymentDueDate ?? true
        }
        set {
            hasPaymentDueDate = newValue
        }
    }
}

extension Array where Element == DebtPayoffBucket {

    var totalProtectedAmount: Double {
        reduce(0.0) { total, bucket in
            total + Swift.max(bucket.protectedAmount, 0)
        }
    }
}

enum DebtPayoffFundingState {
    case notStarted
    case partiallyFunded
    case fullyFundedForNextPayment
    case overFunded
    case balanceUnavailable
}

struct DebtPayoffDisplayModel {

    let title: String
    let typeLabel: String
    let setAsideValue: String
    let dueDateValue: String
    let balanceLine: String?
    let progressTargetValue: String
    let isLinkedCreditCard: Bool
    let progressValue: Double
    let progressCaption: String
    let progressAccessibilityLabel: String
    let fundingState: DebtPayoffFundingState

    init(
        bucket: DebtPayoffBucket,
        linkedAccount: PlaidAccount?
    ) {
        let kind = bucket.debtKind
        let usesLinkedCreditAccount = bucket.isLinkedCreditCard &&
            !bucket.plaidAccountID.isEmpty
        isLinkedCreditCard = bucket.isLinkedCreditCard
        let linkedBalance = linkedAccount?.debtBalanceValue
        let balance = bucket.isLinkedCreditCard
            ? (
                usesLinkedCreditAccount
                    ? linkedBalance
                    : bucket.manualCurrentBalance
            )
            : bucket.manualCurrentBalance
        let paymentAmount = bucket.isLinkedCreditCard
            ? bucket.paymentTargetAmount
            : bucket.monthlyPayment ?? bucket.paymentTargetAmount
        let hasPayment = paymentAmount > 0
        let hasBalance = (balance ?? 0) > 0
        let progressTarget = bucket.isLinkedCreditCard
            ? (
                hasPayment
                    ? paymentAmount
                    : balance ?? 0
            )
            : paymentAmount

        title = Self.title(
            bucket: bucket,
            linkedAccount: linkedAccount
        )
        typeLabel = bucket.isLinkedCreditCard
            ? "\(kind.title) · \(usesLinkedCreditAccount ? "Linked" : "Manual")"
            : "\(kind.title) · Manual"

        let setAsideText = AppFormatters.currency(bucket.protectedAmount)
        setAsideValue = setAsideText

        if bucket.isLinkedCreditCard {
            balanceLine = nil
            progressTargetValue = hasBalance
                ? "\(AppFormatters.currency(balance ?? 0)) balance"
                : "Balance unavailable"
        } else {
            balanceLine = hasBalance
                ? "\(AppFormatters.currency(balance ?? 0)) remaining"
                : nil
            progressTargetValue = hasPayment
                ? "\(AppFormatters.currency(paymentAmount)) payment"
                : "Payment not set"
        }

        dueDateValue = Self.dueDateValue(bucket)

        if progressTarget > 0 {
            let rawProgress = bucket.protectedAmount / progressTarget
            progressValue = min(
                max(rawProgress, 0),
                1
            )
            let percentage = Int(progressValue * 100)
            progressCaption = bucket.isLinkedCreditCard
                ? "\(percentage)% toward balance"
                : "\(percentage)% toward next payment"
            progressAccessibilityLabel = bucket.isLinkedCreditCard
                ? "\(setAsideText) set aside toward \(AppFormatters.currency(progressTarget)) credit card balance"
                : "\(setAsideText) set aside toward \(AppFormatters.currency(progressTarget)) \(kind.title.lowercased()) payment"
        } else {
            progressValue = 0
            progressCaption = bucket.isLinkedCreditCard
                ? "Balance unavailable"
                : "Payment not set"
            progressAccessibilityLabel = progressCaption
        }

        if bucket.isLinkedCreditCard,
           !hasBalance {
            fundingState = .balanceUnavailable
        } else if bucket.protectedAmount <= 0 {
            fundingState = .notStarted
        } else if progressTarget > 0,
                  bucket.protectedAmount > progressTarget {
            fundingState = .overFunded
        } else if progressTarget > 0,
                  bucket.protectedAmount >= progressTarget {
            fundingState = .fullyFundedForNextPayment
        } else {
            fundingState = .partiallyFunded
        }
    }

    private static func title(
        bucket: DebtPayoffBucket,
        linkedAccount: PlaidAccount?
    ) -> String {
        let trimmedName = bucket.accountName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedName.isEmpty {
            return trimmedName
        }

        if let linkedAccount {
            return linkedAccount.name
        }

        return bucket.debtKind.title
    }

    private static func dueDateValue(
        _ bucket: DebtPayoffBucket
    ) -> String {
        guard bucket.shouldDisplayDueDate else {
            return "Due date not set"
        }

        return "Due \(AppFormatters.abbreviatedMonthDay(bucket.dueDate))"
    }

}
