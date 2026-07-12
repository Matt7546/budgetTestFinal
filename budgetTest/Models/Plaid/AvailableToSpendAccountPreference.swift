import Foundation
import SwiftData

struct AvailableToSpendAccountSelection: Equatable {
    let userID: String
    let plaidAccountID: String
    let isIncluded: Bool
}

@Model
final class AvailableToSpendAccountPreference {

    @Attribute(.unique)
    var scopedAccountID: String
    var userID: String
    var plaidAccountID: String
    var isIncluded: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        userID: String,
        plaidAccountID: String,
        isIncluded: Bool,
        now: Date = Date()
    ) {
        self.scopedAccountID = Self.scopedAccountID(
            userID: userID,
            plaidAccountID: plaidAccountID
        )
        self.userID = userID
        self.plaidAccountID = plaidAccountID
        self.isIncluded = isIncluded
        self.createdAt = now
        self.updatedAt = now
    }

    var selection: AvailableToSpendAccountSelection {
        AvailableToSpendAccountSelection(
            userID: userID,
            plaidAccountID: plaidAccountID,
            isIncluded: isIncluded
        )
    }

    static func scopedAccountID(
        userID: String,
        plaidAccountID: String
    ) -> String {
        "\(userID.count):\(userID)\(plaidAccountID)"
    }
}

enum AvailableToSpendAccountScope {

    static func isIncluded(
        account: PlaidAccount,
        userID: String?,
        selections: [AvailableToSpendAccountSelection]
    ) -> Bool {
        guard account.isCashTotalAccount else {
            return false
        }

        guard let userID = normalized(userID) else {
            return true
        }

        return selections.first {
            $0.userID == userID &&
            $0.plaidAccountID == account.account_id
        }?
        .isIncluded ?? true
    }

    static func financialSummaryAccounts(
        from accounts: [PlaidAccount],
        userID: String?,
        selections: [AvailableToSpendAccountSelection]
    ) -> [PlaidAccount] {
        accounts.deduplicatedForDisplayAndTotals.filter { account in
            !account.isCashTotalAccount || isIncluded(
                account: account,
                userID: userID,
                selections: selections
            )
        }
    }

    private static func normalized(
        _ value: String?
    ) -> String? {
        guard let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}
