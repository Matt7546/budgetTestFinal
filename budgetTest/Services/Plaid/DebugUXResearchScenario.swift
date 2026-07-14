#if DEBUG
import Foundation

enum DebugUXResearchScenario {

    static let checkingAccountID = "debug-research-checking"
    static let savingsAccountID = "debug-research-savings"
    static let creditCardAccountID = "debug-research-credit-card"

    static let initialStatementAmount = 350.0
    static let refreshedStatementAmount = 400.0
    static let minimumPaymentAmount = 45.0
    static let creditCardBalance = 1_250.0

    static func normalizedResetDate(
        _ date: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.startOfDay(for: date)
    }

    static func dueDate(
        resetAt: Date,
        calendar: Calendar = .current
    ) -> Date {
        let resetDate = normalizedResetDate(
            resetAt,
            calendar: calendar
        )

        return calendar.date(
            byAdding: .day,
            value: 15,
            to: resetDate
        ) ?? resetDate
    }

    static func accounts() -> [PlaidAccount] {
        [
            PlaidAccount(
                account_id: checkingAccountID,
                name: "Research Checking",
                official_name: "Synthetic Research Checking",
                type: "depository",
                subtype: "checking",
                mask: "0101",
                balances: PlaidBalance(
                    available: 2_500,
                    current: 2_500
                ),
                item_id: "debug-research-item",
                institution_name: "Caldera Research Bank (Synthetic)",
                institution_id: "debug-research-institution"
            ),
            PlaidAccount(
                account_id: savingsAccountID,
                name: "Research Savings",
                official_name: "Synthetic Research Savings",
                type: "depository",
                subtype: "savings",
                mask: "0202",
                balances: PlaidBalance(
                    available: 1_000,
                    current: 1_000
                ),
                item_id: "debug-research-item",
                institution_name: "Caldera Research Bank (Synthetic)",
                institution_id: "debug-research-institution"
            ),
            PlaidAccount(
                account_id: creditCardAccountID,
                name: "Research Credit Card",
                official_name: "Synthetic Research Credit Card",
                type: "credit",
                subtype: "credit card",
                mask: "0303",
                balances: PlaidBalance(
                    available: 3_750,
                    current: creditCardBalance,
                    limit: 5_000
                ),
                item_id: "debug-research-item",
                institution_name: "Caldera Research Bank (Synthetic)",
                institution_id: "debug-research-institution"
            )
        ]
    }

    static func cardPaymentDetails(
        resetAt: Date,
        hasRefreshed: Bool,
        calendar: Calendar = .current
    ) -> [LinkedCardPaymentDetails] {
        let resetDate = normalizedResetDate(
            resetAt,
            calendar: calendar
        )
        let statementAmount = hasRefreshed
            ? refreshedStatementAmount
            : initialStatementAmount

        return [
            LinkedCardPaymentDetails(
                account_id: creditCardAccountID,
                account_name: "Research Credit Card",
                institution_name: "Caldera Research Bank (Synthetic)",
                mask: "0303",
                current_balance: creditCardBalance,
                available_credit: 3_750,
                last_statement_balance: statementAmount,
                last_statement_issue_date: dateKey(
                    resetDate,
                    calendar: calendar
                ),
                minimum_payment_amount: minimumPaymentAmount,
                next_payment_due_date: dateKey(
                    dueDate(
                        resetAt: resetDate,
                        calendar: calendar
                    ),
                    calendar: calendar
                ),
                last_payment_amount: nil,
                last_payment_date: nil,
                is_overdue: false,
                last_refreshed_at: dateKey(
                    resetDate,
                    calendar: calendar
                )
            )
        ]
    }

    static func completeTransactionSnapshotMetadata(
        resetAt: Date,
        calendar: Calendar = .current
    ) -> TransactionSnapshotMetadata {
        let key = dateKey(
            normalizedResetDate(resetAt, calendar: calendar),
            calendar: calendar
        )

        return TransactionSnapshotMetadata(
            windowStart: key,
            windowEnd: key,
            lookbackDays: 0,
            totalTransactions: 0,
            returnedTransactions: 0,
            complete: true,
            partialFailure: false
        )
    }

    static func resetFirstRunState(
        defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(false, forKey: AppPersonalizationKeys.hasCompletedPersonalization)
        defaults.set(false, forKey: AppPersonalizationKeys.hasCompletedTutorial)
        defaults.set(false, forKey: AppPersonalizationKeys.shouldAutoLaunchTutorial)
        defaults.removeObject(forKey: AppPersonalizationKeys.preferredName)
        defaults.removeObject(forKey: AppPersonalizationKeys.focus)
        defaults.removeObject(forKey: AppPersonalizationKeys.paySchedulePreset)
    }

    static func clearRecurringRecommendationHistory(
        defaults: UserDefaults = .standard
    ) {
        RecurringExpenseRecommendationHistoryStore(
            defaults: defaults
        )
        .clearAllHistoryForLocalTesting()
    }

    static func containsOnlyResearchAccounts(
        _ accounts: [PlaidAccount]
    ) -> Bool {
        Set(accounts.map(\.account_id)) == Set([
            checkingAccountID,
            savingsAccountID,
            creditCardAccountID
        ])
    }

    private static func dateKey(
        _ date: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )

        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
#endif
