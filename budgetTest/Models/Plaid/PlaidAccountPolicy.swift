import Foundation

struct PlaidAccountClassification: Equatable {

    let normalizedType: String
    let normalizedSubtype: String

    init(
        type: String,
        subtype: String?
    ) {
        normalizedType = type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        normalizedSubtype = subtype?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    init(account: PlaidAccount) {
        self.init(
            type: account.type,
            subtype: account.subtype
        )
    }

    var isDepository: Bool {
        normalizedType == "depository"
    }

    var isChecking: Bool {
        isDepository &&
        normalizedSubtype == "checking"
    }

    var isSavings: Bool {
        isDepository &&
        normalizedSubtype == "savings"
    }

    var isCredit: Bool {
        normalizedType == "credit"
    }

    var isLoan: Bool {
        normalizedType == "loan"
    }

    var isCashTotalAccount: Bool {
        isDepository
    }

    var isDebtTotalAccount: Bool {
        isCredit || isLoan
    }

    var isLiabilityDisplayAccount: Bool {
        isDebtTotalAccount
    }

    #if DEBUG
    var debugDescription: String {
        [
            isChecking ? "checking" : nil,
            isSavings ? "savings" : nil,
            isCashTotalAccount ? "cash" : nil,
            isCredit ? "credit" : nil,
            isLoan ? "loan" : nil,
            isDebtTotalAccount ? "debt" : nil
        ]
        .compactMap { $0 }
        .joined(separator: ",")
    }
    #endif
}

enum PlaidAccountBalancePolicy {

    static func cashBalance(
        for account: PlaidAccount
    ) -> Double {
        let classification = PlaidAccountClassification(
            account: account
        )

        if classification.isSavings {
            return account.balances.current
        }

        if classification.isDepository {
            return account.balances.available ?? account.balances.current
        }

        return 0
    }

    static func debtBalance(
        for account: PlaidAccount
    ) -> Double {
        let classification = PlaidAccountClassification(
            account: account
        )

        guard classification.isDebtTotalAccount else {
            return 0
        }

        return abs(account.balances.current)
    }

    static func currentBalance(
        for account: PlaidAccount
    ) -> Double {
        account.balances.current
    }

    static func availableBalance(
        for account: PlaidAccount
    ) -> Double {
        account.balances.available ?? account.balances.current
    }
}
