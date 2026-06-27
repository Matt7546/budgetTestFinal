import Foundation

extension PlaidAccount {

    var classification: PlaidAccountClassification {
        PlaidAccountClassification(
            account: self
        )
    }

    var isCashTotalAccount: Bool {
        classification.isCashTotalAccount
    }

    var isDebtTotalAccount: Bool {
        classification.isDebtTotalAccount
    }

    var isDepositoryAccount: Bool {
        classification.isDepository
    }

    var isCheckingGroupAccount: Bool {
        classification.isChecking
    }

    var isSavingsGroupAccount: Bool {
        classification.isSavings
    }

    var isCreditGroupAccount: Bool {
        classification.isCredit
    }

    var isLoanGroupAccount: Bool {
        classification.isLoan
    }

    var isLiabilityDisplayAccount: Bool {
        classification.isLiabilityDisplayAccount
    }

    var cashBalanceValue: Double {
        PlaidAccountBalancePolicy.cashBalance(
            for: self
        )
    }

    var debtBalanceValue: Double {
        PlaidAccountBalancePolicy.debtBalance(
            for: self
        )
    }

    var displayCurrentBalance: Double {
        PlaidAccountBalancePolicy.currentBalance(
            for: self
        )
    }

    var displayAvailableBalance: Double {
        PlaidAccountBalancePolicy.availableBalance(
            for: self
        )
    }

    #if DEBUG
    var plaidDebugClassification: String {
        classification.debugDescription
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
            $0 + $1.debtBalanceValue
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
