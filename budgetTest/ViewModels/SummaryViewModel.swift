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

        let financialSummary = FinancialSummaryCalculator.calculate(
            accounts: accounts,
            goals: goals,
            reserveBalance: reserveBalance
        )

        #if DEBUG
        Self.logAccountSummaryInputs(
            accounts,
            financialSummary: financialSummary
        )
        #endif

        // MARK: Cash (all depository accounts)

        self.totalCash = financialSummary.cash

        // MARK: Savings (display only)

        self.totalSavings = financialSummary.savings

        // MARK: Debt

        self.totalDebt = financialSummary.debt

        // MARK: Goal Allocations

        self.totalGoalAllocated = financialSummary.savingsGoalsSetAside

        // MARK: Reserve

        self.reserveBalance = financialSummary.reserve

        // MARK: Net Worth

        self.totalNetWorth = financialSummary.netWorth

        // MARK: Safe To Spend

        self.totalAvailable = financialSummary.safeToSpendBeforeUpcomingExpenses
    }
    .store(in: &cancellables)
    }

    #if DEBUG
    private static func logAccountSummaryInputs(
        _ accounts: [PlaidAccount],
        financialSummary: FinancialSummary
    ) {
        AppLogger.plaidAccountSnapshot(
            "Summary input accounts=\(accounts.count); cashAccounts=\(accounts.filter { $0.isCashTotalAccount }.count); debtAccounts=\(accounts.filter { $0.isDebtTotalAccount }.count)"
        )

        let summaries = Dictionary(
            grouping: accounts,
            by: { account in
                "\(account.type)/\(account.subtype ?? "none")/\(account.plaidDebugClassification)"
            }
        )

        for key in summaries.keys.sorted() {
            AppLogger.plaidAccountSnapshot(
                "summary account group=\(key); count=\(summaries[key]?.count ?? 0)"
            )
        }
    }
    #endif

}
