import Foundation

extension PlaidAccount {

    private var normalizedType: String {
        type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedSubtype: String {
        subtype?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    var isCashTotalAccount: Bool {
        normalizedType == "depository"
    }

    var isDebtTotalAccount: Bool {
        isCreditGroupAccount || isLoanGroupAccount
    }

    var isCheckingGroupAccount: Bool {
        normalizedType == "depository" &&
        normalizedSubtype == "checking"
    }

    var isSavingsGroupAccount: Bool {
        normalizedType == "depository" &&
        normalizedSubtype == "savings"
    }

    var isCreditGroupAccount: Bool {
        normalizedType == "credit"
    }

    var isLoanGroupAccount: Bool {
        normalizedType == "loan"
    }

    var isLiabilityDisplayAccount: Bool {
        isCreditGroupAccount || isLoanGroupAccount
    }
}

extension Array where Element == PlaidAccount {

    var cashAccounts: [PlaidAccount] {
        filter(\.isCashTotalAccount)
    }

    var debtAccounts: [PlaidAccount] {
        filter(\.isDebtTotalAccount)
    }

    var checkingAccounts: [PlaidAccount] {
        filter(\.isCheckingGroupAccount)
    }

    var savingsAccounts: [PlaidAccount] {
        filter(\.isSavingsGroupAccount)
    }

    var creditAccounts: [PlaidAccount] {
        filter(\.isCreditGroupAccount)
    }

    var loanAccounts: [PlaidAccount] {
        filter(\.isLoanGroupAccount)
    }

    var totalCashBalance: Double {
        cashAccounts.reduce(0.0) {
            $0 + $1.balances.current
        }
    }

    var totalSavingsBalance: Double {
        savingsAccounts.reduce(0.0) {
            $0 + $1.balances.current
        }
    }

    var totalDebtBalance: Double {
        debtAccounts.reduce(0.0) {
            $0 + abs($1.balances.current)
        }
    }
}

extension Array where Element == SavingsGoal {

    var totalSaved: Double {
        reduce(0.0) {
            $0 + $1.currentAmount
        }
    }

    var totalTarget: Double {
        reduce(0.0) {
            $0 + $1.targetAmount
        }
    }
}

struct AccountTotals {

    let totalCash: Double
    let totalSavings: Double
    let totalGoalAllocated: Double
    let reserveBalance: Double
    let totalDebt: Double
    let totalAvailable: Double
    let totalNetWorth: Double

    init(
        accounts: [PlaidAccount],
        goals: [SavingsGoal],
        reserveBalance: Double = 0
    ) {
        totalCash = accounts.totalCashBalance
        totalSavings = accounts.totalSavingsBalance
        totalGoalAllocated = goals.totalSaved
        self.reserveBalance = reserveBalance
        totalDebt = accounts.totalDebtBalance
        totalNetWorth = totalCash - totalDebt
        totalAvailable = totalCash - totalGoalAllocated - reserveBalance
    }
}
