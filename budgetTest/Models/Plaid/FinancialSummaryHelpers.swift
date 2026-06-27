import Foundation

extension PlaidAccount {

    private var normalizedType: String {
        type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedSubtype: String {
        subtype?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    var isCashTotalAccount: Bool {
        isDepositoryAccount
    }

    var isDebtTotalAccount: Bool {
        isCreditGroupAccount || isLoanGroupAccount
    }

    var isDepositoryAccount: Bool {
        normalizedType == "depository"
    }

    var isCheckingGroupAccount: Bool {
        isDepositoryAccount &&
        normalizedSubtype == "checking"
    }

    var isSavingsGroupAccount: Bool {
        isDepositoryAccount &&
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

    var cashBalanceValue: Double {
        if isSavingsGroupAccount {
            return balances.current
        }

        if isDepositoryAccount {
            return balances.available ?? balances.current
        }

        return 0
    }

    var displayCurrentBalance: Double {
        balances.current
    }

    var displayAvailableBalance: Double {
        balances.available ?? balances.current
    }

    #if DEBUG
    var plaidDebugClassification: String {
        [
            isCheckingGroupAccount ? "checking" : nil,
            isSavingsGroupAccount ? "savings" : nil,
            isCashTotalAccount ? "cash" : nil,
            isCreditGroupAccount ? "credit" : nil,
            isLoanGroupAccount ? "loan" : nil,
            isDebtTotalAccount ? "debt" : nil
        ]
        .compactMap { $0 }
        .joined(separator: ",")
    }
    #endif
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
            $0 + $1.cashBalanceValue
        }
    }

    var totalSavingsBalance: Double {
        savingsAccounts.reduce(0.0) {
            $0 + $1.cashBalanceValue
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
