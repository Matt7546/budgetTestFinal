import Foundation
import Combine

final class SummaryViewModel: ObservableObject {


// MARK: - Dashboard Metrics

@Published var totalCash: Double = 0
@Published var totalSavings: Double = 0
@Published var totalGoalAllocated: Double = 0
@Published var reserveBalance: Double = 0
@Published var totalDebt: Double = 0

// Available to spend
@Published var totalAvailable: Double = 0

// True net worth
@Published var totalNetWorth: Double = 0

private var cancellables = Set<AnyCancellable>()

init(
    accountsPublisher: AnyPublisher<[PlaidAccount], Never>,
    goalsPublisher: AnyPublisher<[SavingsGoal], Never>,
    reservePublisher: AnyPublisher<Double, Never>
) {

    Publishers.CombineLatest3(
        accountsPublisher,
        goalsPublisher,
        reservePublisher
    )
    .sink { [weak self] accounts, goals, reserveBalance in

        guard let self = self else { return }

        let totals = AccountTotals(
            accounts: accounts,
            goals: goals,
            reserveBalance: reserveBalance
        )

        #if DEBUG
        Self.logAccountSummaryInputs(
            accounts,
            totals: totals
        )
        #endif

        // MARK: Cash (all depository accounts)

        self.totalCash = totals.totalCash

        // MARK: Savings (display only)

        self.totalSavings = totals.totalSavings

        // MARK: Debt

        self.totalDebt = totals.totalDebt

        // MARK: Goal Allocations

        self.totalGoalAllocated = totals.totalGoalAllocated

        // MARK: Reserve

        self.reserveBalance = totals.reserveBalance

        // MARK: Net Worth

        self.totalNetWorth = totals.totalNetWorth

        // MARK: Safe To Spend

        self.totalAvailable = totals.totalAvailable
    }
    .store(in: &cancellables)
    }

    #if DEBUG
    private static func logAccountSummaryInputs(
        _ accounts: [PlaidAccount],
        totals: AccountTotals
    ) {
        AppLogger.plaidAccountSnapshot(
            "Summary input accounts=\(accounts.count); totalCash=\(totals.totalCash); totalSavings=\(totals.totalSavings); totalDebt=\(totals.totalDebt)"
        )

        for account in accounts {
            let institution = account.institution_name ?? "none"
            let officialName = account.official_name ?? "none"
            let subtype = account.subtype ?? "none"
            let mask = account.mask ?? "none"
            let available = account.balances.available.map { String(describing: $0) } ?? "none"

            AppLogger.plaidAccountSnapshot(
                "summary name=\(account.name); official_name=\(officialName); institution=\(institution); account_id=\(account.account_id); type=\(account.type); subtype=\(subtype); mask=\(mask); current=\(account.balances.current); available=\(available); cash_value=\(account.cashBalanceValue); classifications=\(account.plaidDebugClassification)"
            )
        }
    }
    #endif

}
