import Foundation
import Combine

final class SummaryViewModel: ObservableObject {


// MARK: - Dashboard Metrics

@Published var totalCash: Double = 0
@Published var totalSavings: Double = 0
@Published var totalGoalAllocated: Double = 0
@Published var totalDebt: Double = 0

// Available to spend
@Published var totalAvailable: Double = 0

// True net worth
@Published var totalNetWorth: Double = 0

private var cancellables = Set<AnyCancellable>()

init(
    accountsPublisher: AnyPublisher<[PlaidAccount], Never>,
    goalsPublisher: AnyPublisher<[SavingsGoal], Never>
) {

    Publishers.CombineLatest(
        accountsPublisher,
        goalsPublisher
    )
    .sink { [weak self] accounts, goals in

        guard let self = self else { return }

        // MARK: Cash (all depository accounts)

        self.totalCash = accounts
            .filter {
                $0.type.lowercased() == "depository"
            }
            .reduce(0.0) {
                $0 + $1.balances.current
            }

        // MARK: Savings (display only)

        self.totalSavings = accounts
            .filter {
                ($0.subtype ?? "").lowercased() == "savings"
            }
            .reduce(0.0) {
                $0 + $1.balances.current
            }

        // MARK: Debt

        self.totalDebt = accounts
            .filter {
                $0.type.lowercased() == "credit"
                || $0.type.lowercased() == "loan"
            }
            .reduce(0.0) {
                $0 + abs($1.balances.current)
            }

        // MARK: Goal Allocations

        self.totalGoalAllocated = goals
            .reduce(0.0) {
                $0 + $1.currentAmount
            }

        // MARK: Net Worth

        self.totalNetWorth =
            self.totalCash
            - self.totalDebt

        // MARK: Available To Spend

        self.totalAvailable =
            self.totalCash
            - self.totalDebt
            - self.totalGoalAllocated
    }
    .store(in: &cancellables)
}


}
