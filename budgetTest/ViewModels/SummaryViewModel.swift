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


}
