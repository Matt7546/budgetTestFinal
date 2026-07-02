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

    fileprivate var normalizedAccountID: String {
        account_id
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    fileprivate var normalizedDisplayDuplicateKey: String? {
        guard let mask = mask?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !mask.isEmpty else {
            return nil
        }

        let institution = (
            institution_id ??
            institution_name ??
            ""
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedType = type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedSubtype = subtype?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        guard !institution.isEmpty,
              !normalizedName.isEmpty else {
            return nil
        }

        return [
            institution,
            normalizedName,
            mask,
            normalizedType,
            normalizedSubtype
        ]
        .joined(separator: "|")
    }

    #if DEBUG
    var plaidDebugClassification: String {
        classification.debugDescription
    }
    #endif
}

extension Array where Element == PlaidAccount {

    var deduplicatedForDisplayAndTotals: [PlaidAccount] {
        var selectedIndexByAccountID: [String: Int] = [:]
        var selectedIndexByDisplayKey: [String: Int] = [:]

        for (index, account) in enumerated() {
            if !account.normalizedAccountID.isEmpty {
                selectedIndexByAccountID[account.normalizedAccountID] = index
            }

            if let displayKey = account.normalizedDisplayDuplicateKey {
                selectedIndexByDisplayKey[displayKey] = index
            }
        }

        return enumerated().compactMap { index, account in
            if !account.normalizedAccountID.isEmpty,
               selectedIndexByAccountID[account.normalizedAccountID] != index {
                return nil
            }

            if let displayKey = account.normalizedDisplayDuplicateKey,
               selectedIndexByDisplayKey[displayKey] != index {
                return nil
            }

            return account
        }
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
