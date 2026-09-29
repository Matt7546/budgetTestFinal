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

    /// A repeated exact ID is one account only when every field agrees.
    /// Provider IDs are opaque: display fields and case are never identity.
    var accountsWithUnambiguousIdentity: [PlaidAccount]? {
        var accountByID: [String: PlaidAccount] = [:]
        var uniqueAccounts: [PlaidAccount] = []

        for account in self {
            let accountID = account.account_id
            guard !accountID.isEmpty,
                  accountID == accountID.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ) else {
                return nil
            }

            if let existing = accountByID[accountID] {
                guard existing == account else { return nil }
                continue
            }

            accountByID[accountID] = account
            uniqueAccounts.append(account)
        }

        return uniqueAccounts
    }

    var deduplicatedForDisplayAndTotals: [PlaidAccount] {
        guard let accounts = accountsWithUnambiguousIdentity else {
            preconditionFailure(
                "Account identities must be validated before financial presentation."
            )
        }
        return accounts
    }

    var cashAccounts: [PlaidAccount] {
        deduplicatedForDisplayAndTotals.filter(\.isCashTotalAccount)
    }

    var debtAccounts: [PlaidAccount] {
        deduplicatedForDisplayAndTotals.filter(\.isDebtTotalAccount)
    }

    var checkingAccounts: [PlaidAccount] {
        deduplicatedForDisplayAndTotals.filter(\.isCheckingGroupAccount)
    }

    var savingsAccounts: [PlaidAccount] {
        deduplicatedForDisplayAndTotals.filter(\.isSavingsGroupAccount)
    }

    var creditAccounts: [PlaidAccount] {
        deduplicatedForDisplayAndTotals.filter(\.isCreditGroupAccount)
    }

    var loanAccounts: [PlaidAccount] {
        deduplicatedForDisplayAndTotals.filter(\.isLoanGroupAccount)
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
