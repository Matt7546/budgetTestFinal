import XCTest
import Combine
import SwiftData
@testable import Caldera_Money

@MainActor
final class CoreFinancialCalculationsTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    func testIncludedCheckingAccountCountsTowardAvailableToSpend() {
        let checking = account(
            accountID: "checking-1",
            type: "depository",
            subtype: "checking",
            balance: 1_250
        )
        let scopedAccounts = AvailableToSpendAccountScope.financialSummaryAccounts(
            from: [checking],
            userID: "user-a",
            selections: [
                AvailableToSpendAccountSelection(
                    userID: "user-a",
                    plaidAccountID: checking.account_id,
                    isIncluded: true
                )
            ]
        )

        let summary = FinancialSummaryCalculator.calculate(
            accounts: scopedAccounts,
            goals: [],
            reserveBalance: 0
        )

        XCTAssertEqual(summary.cash, 1_250, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpend, 1_250, accuracy: 0.001)
    }

    func testExcludedSavingsAccountDoesNotCountTowardAvailableToSpend() {
        let savings = account(
            accountID: "savings-1",
            type: "depository",
            subtype: "savings",
            balance: 2_000
        )
        let scopedAccounts = AvailableToSpendAccountScope.financialSummaryAccounts(
            from: [savings],
            userID: "user-a",
            selections: [
                AvailableToSpendAccountSelection(
                    userID: "user-a",
                    plaidAccountID: savings.account_id,
                    isIncluded: false
                )
            ]
        )

        XCTAssertTrue(scopedAccounts.cashAccounts.isEmpty)
        XCTAssertEqual(scopedAccounts.totalCashBalance, 0, accuracy: 0.001)
    }

    func testCreditCardNeverCountsAsAvailableCash() {
        let creditCard = account(
            accountID: "credit-1",
            type: "credit",
            subtype: "credit card",
            balance: 400
        )
        let scopedAccounts = AvailableToSpendAccountScope.financialSummaryAccounts(
            from: [creditCard],
            userID: "user-a",
            selections: []
        )
        let summary = FinancialSummaryCalculator.calculate(
            accounts: scopedAccounts,
            goals: [],
            reserveBalance: 0
        )

        XCTAssertFalse(
            AvailableToSpendAccountScope.isIncluded(
                account: creditCard,
                userID: "user-a",
                selections: []
            )
        )
        XCTAssertEqual(summary.cash, 0, accuracy: 0.001)
        XCTAssertEqual(summary.debt, 400, accuracy: 0.001)
    }

    func testCashAccountDefaultsToIncludedWithoutPreference() {
        let checking = account(
            accountID: "checking-new",
            type: "depository",
            subtype: "checking",
            balance: 700
        )

        XCTAssertTrue(
            AvailableToSpendAccountScope.isIncluded(
                account: checking,
                userID: "user-a",
                selections: []
            )
        )
    }

    func testAccountPreferenceIsIsolatedAcrossUsers() {
        let checking = account(
            accountID: "shared-account-id",
            type: "depository",
            subtype: "checking",
            balance: 900
        )
        let selections = [
            AvailableToSpendAccountSelection(
                userID: "user-a",
                plaidAccountID: checking.account_id,
                isIncluded: false
            )
        ]

        XCTAssertFalse(
            AvailableToSpendAccountScope.isIncluded(
                account: checking,
                userID: "user-a",
                selections: selections
            )
        )
        XCTAssertTrue(
            AvailableToSpendAccountScope.isIncluded(
                account: checking,
                userID: "user-b",
                selections: selections
            )
        )
    }

    func testAccountPreferencePersistsScopedState() throws {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: AvailableToSpendAccountPreference.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        context.insert(
            AvailableToSpendAccountPreference(
                userID: "user-a",
                plaidAccountID: "checking-1",
                isIncluded: false
            )
        )

        try context.save()

        let records = try context.fetch(
            FetchDescriptor<AvailableToSpendAccountPreference>()
        )
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].userID, "user-a")
        XCTAssertEqual(records[0].plaidAccountID, "checking-1")
        XCTAssertFalse(records[0].isIncluded)
    }

    func testAuthenticatedAccountLoadGateReloadsSameUserAfterSignOut() {
        var gate = AuthenticatedAccountLoadGate()

        XCTAssertTrue(
            gate.shouldStartLoad(
                isSignedIn: true,
                userID: "user-a"
            )
        )
        XCTAssertFalse(
            gate.shouldStartLoad(
                isSignedIn: true,
                userID: "user-a"
            )
        )
        XCTAssertFalse(
            gate.shouldStartLoad(
                isSignedIn: false,
                userID: nil
            )
        )
        XCTAssertTrue(
            gate.shouldStartLoad(
                isSignedIn: true,
                userID: "user-a"
            )
        )
    }

    func testAuthenticatedAccountLoadGateStartsOnceForSwitchedUser() {
        var gate = AuthenticatedAccountLoadGate()

        XCTAssertTrue(
            gate.shouldStartLoad(
                isSignedIn: true,
                userID: "user-a"
            )
        )
        XCTAssertTrue(
            gate.shouldStartLoad(
                isSignedIn: true,
                userID: "user-b"
            )
        )
        XCTAssertFalse(
            gate.shouldStartLoad(
                isSignedIn: true,
                userID: "user-b"
            )
        )
    }

    func testAccountScopePreferenceStillAppliesAfterReloginLoad() {
        var gate = AuthenticatedAccountLoadGate()
        let checking = account(
            accountID: "checking-1",
            type: "depository",
            subtype: "checking",
            balance: 1_000
        )
        let selections = [
            AvailableToSpendAccountSelection(
                userID: "user-a",
                plaidAccountID: checking.account_id,
                isIncluded: false
            )
        ]

        XCTAssertTrue(
            gate.shouldStartLoad(
                isSignedIn: true,
                userID: "user-a"
            )
        )
        _ = gate.shouldStartLoad(
            isSignedIn: false,
            userID: nil
        )
        XCTAssertTrue(
            gate.shouldStartLoad(
                isSignedIn: true,
                userID: "user-a"
            )
        )
        XCTAssertFalse(
            AvailableToSpendAccountScope.isIncluded(
                account: checking,
                userID: "user-a",
                selections: selections
            )
        )
    }

    func testAuthenticatedAndPostLinkRefreshReasonsRemainAllowed() {
        XCTAssertTrue(
            PlaidRefreshReason.authenticatedSessionAvailable.isAllowedInManualOnly
        )
        XCTAssertTrue(
            PlaidRefreshReason.linkSuccessInitialLoad.isAllowedInManualOnly
        )
        XCTAssertFalse(
            PlaidRefreshReason.authenticatedSessionAvailable.isManual
        )
    }

    func testSignedOutEmptyAccountInputCannotExposePriorUserScope() {
        let priorUserSelections = [
            AvailableToSpendAccountSelection(
                userID: "user-a",
                plaidAccountID: "checking-1",
                isIncluded: false
            )
        ]
        let signedOutAccounts = AvailableToSpendAccountScope.financialSummaryAccounts(
            from: [],
            userID: nil,
            selections: priorUserSelections
        )

        XCTAssertTrue(signedOutAccounts.isEmpty)
    }

    func testMissingOrRelinkedAccountIDDefaultsSafelyToIncluded() {
        let relinkedChecking = account(
            accountID: "new-checking-id",
            type: "depository",
            subtype: "checking",
            balance: 1_100
        )
        let oldSelection = AvailableToSpendAccountSelection(
            userID: "user-a",
            plaidAccountID: "old-checking-id",
            isIncluded: false
        )

        XCTAssertTrue(
            AvailableToSpendAccountScope.isIncluded(
                account: relinkedChecking,
                userID: "user-a",
                selections: [oldSelection]
            )
        )
    }

    func testDashboardInsightsAndForecastShareScopedCashTotal() {
        let checking = account(
            accountID: "checking-1",
            type: "depository",
            subtype: "checking",
            balance: 2_000
        )
        let excludedSavings = account(
            accountID: "savings-1",
            type: "depository",
            subtype: "savings",
            balance: 5_000
        )
        let scopedAccounts = AvailableToSpendAccountScope.financialSummaryAccounts(
            from: [checking, excludedSavings],
            userID: "user-a",
            selections: [
                AvailableToSpendAccountSelection(
                    userID: "user-a",
                    plaidAccountID: excludedSavings.account_id,
                    isIncluded: false
                )
            ]
        )
        let dashboardSummary = FinancialSummaryCalculator.calculate(
            accounts: scopedAccounts,
            goals: [],
            reserveBalance: 0
        )
        let summaryViewModel = SummaryViewModel(
            accountsPublisher: Just(scopedAccounts).eraseToAnyPublisher(),
            goalsPublisher: Just([]).eraseToAnyPublisher(),
            reservePublisher: Just(0).eraseToAnyPublisher()
        )
        let forecast = PlannerForecastCalculator(
            events: [],
            totalAvailable: summaryViewModel.totalAvailable,
            totalGoalAllocated: 0,
            reserveBalance: 0,
            includeFutureIncome: true,
            protectGoals: true
        )

        XCTAssertEqual(dashboardSummary.cash, 2_000, accuracy: 0.001)
        XCTAssertEqual(summaryViewModel.totalCash, dashboardSummary.cash, accuracy: 0.001)
        XCTAssertEqual(summaryViewModel.totalAvailable, dashboardSummary.safeToSpend, accuracy: 0.001)
        XCTAssertEqual(forecast.plannerAvailable, dashboardSummary.safeToSpend, accuracy: 0.001)
    }

    func testSafeToSpendDoesNotSubtractDebt() {
        let summary = FinancialSummaryCalculator.calculate(
            accounts: [
                account(
                    name: "Checking",
                    type: "depository",
                    balance: 2_000
                ),
                account(
                    name: "Credit Card",
                    type: "credit",
                    balance: -500
                )
            ],
            goals: [
                goal(
                    currentAmount: 300,
                    targetAmount: 1_000
                )
            ],
            reserveBalance: 200
        )
        let summaryWithUpcoming = FinancialSummaryCalculator.calculate(
            accounts: [
                account(
                    name: "Checking",
                    type: "depository",
                    balance: 2_000
                ),
                account(
                    name: "Credit Card",
                    type: "credit",
                    balance: -500
                )
            ],
            goals: [
                goal(
                    currentAmount: 300,
                    targetAmount: 1_000
                )
            ],
            reserveBalance: 200,
            upcomingExpensesSetAside: 400
        )

        XCTAssertEqual(summary.cash, 2_000, accuracy: 0.001)
        XCTAssertEqual(summary.debt, 500, accuracy: 0.001)
        XCTAssertEqual(summaryWithUpcoming.safeToSpend, 1_100, accuracy: 0.001)
        XCTAssertEqual(summaryWithUpcoming.protectedMoney, 900, accuracy: 0.001)
        XCTAssertNotEqual(
            summaryWithUpcoming.safeToSpend,
            600,
            accuracy: 0.001
        )
    }

    func testSafeToSpendMatchesNoDebtComparison() {
        let summary = FinancialSummaryCalculator.calculate(
            accounts: [
                account(
                    type: "depository",
                    balance: 2_000
                )
            ],
            goals: [
                goal(
                    currentAmount: 300,
                    targetAmount: 1_000
                )
            ],
            reserveBalance: 200,
            upcomingExpensesSetAside: 400
        )

        XCTAssertEqual(summary.safeToSpend, 1_100, accuracy: 0.001)
        XCTAssertEqual(summary.protectedMoney, 900, accuracy: 0.001)
    }

    func testDebtOnlyDoesNotReduceSafeToSpendButReducesNetWorth() {
        let summary = FinancialSummaryCalculator.calculate(
            accounts: [
                account(
                    type: "depository",
                    balance: 2_000
                ),
                account(
                    type: "loan",
                    balance: -1_500
                )
            ],
            goals: [],
            reserveBalance: 0
        )

        XCTAssertEqual(summary.safeToSpend, 2_000, accuracy: 0.001)
        XCTAssertEqual(summary.debt, 1_500, accuracy: 0.001)
        XCTAssertEqual(summary.netWorth, 500, accuracy: 0.001)
    }

    func testProtectedMoneyUsesSavedGoalAmountsNotTargets() {
        let summary = FinancialSummaryCalculator.calculate(
            accounts: [],
            goals: [
                goal(
                    currentAmount: 200,
                    targetAmount: 5_000
                )
            ],
            reserveBalance: 100,
            upcomingExpensesSetAside: 300
        )

        XCTAssertEqual(summary.savingsGoalsSetAside, 200, accuracy: 0.001)
        XCTAssertEqual(summary.protectedMoney, 600, accuracy: 0.001)
    }

    func testFinancialSummaryCalculatorCentralizesCoreTotals() {
        let summary = FinancialSummaryCalculator.calculate(
            accounts: [
                account(
                    name: "Checking",
                    type: "depository",
                    subtype: "checking",
                    available: 1_250,
                    balance: 0
                ),
                account(
                    name: "Savings",
                    type: "depository",
                    subtype: "savings",
                    available: 900,
                    balance: 500
                ),
                account(
                    name: "Credit Card",
                    type: "credit",
                    subtype: "credit card",
                    balance: -300
                ),
                account(
                    name: "Loan",
                    type: "loan",
                    subtype: "student",
                    balance: -1_200
                )
            ],
            goals: [
                goal(
                    currentAmount: 200,
                    targetAmount: 2_000
                )
            ],
            reserveBalance: 100,
            upcomingExpensesSetAside: 50
        )

        XCTAssertEqual(summary.checking, 1_250, accuracy: 0.001)
        XCTAssertEqual(summary.savings, 500, accuracy: 0.001)
        XCTAssertEqual(summary.cash, 1_750, accuracy: 0.001)
        XCTAssertEqual(summary.debt, 1_500, accuracy: 0.001)
        XCTAssertEqual(summary.netWorth, 250, accuracy: 0.001)
        XCTAssertEqual(summary.savingsGoalsSetAside, 200, accuracy: 0.001)
        XCTAssertEqual(summary.reserve, 100, accuracy: 0.001)
        XCTAssertEqual(summary.upcomingExpensesSetAside, 50, accuracy: 0.001)
        XCTAssertEqual(summary.protectedMoney, 350, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpendBeforeUpcomingExpenses, 1_450, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpend, 1_400, accuracy: 0.001)
    }

    func testFinancialSummaryCalculatorUsesActiveUpcomingAllocationTotals() {
        let forecast = singleExpenseForecast(
            amount: 1_000,
            date: date(2026, 7, 21)
        )
        let activeUpcomingSetAside = FinancialSummaryCalculator.activeUpcomingExpensesSetAside(
            allocations: [
                allocation(
                    for: forecast,
                    amount: 1_200
                )
            ],
            forecastEvents: [forecast]
        )
        let summary = FinancialSummaryCalculator.calculate(
            accounts: [
                account(
                    type: "depository",
                    subtype: "checking",
                    available: 2_000,
                    balance: 0
                )
            ],
            goals: [
                goal(
                    currentAmount: 300,
                    targetAmount: 1_000
                )
            ],
            reserveBalance: 200,
            upcomingExpensesSetAside: activeUpcomingSetAside
        )

        XCTAssertEqual(activeUpcomingSetAside, 1_000, accuracy: 0.001)
        XCTAssertEqual(summary.protectedMoney, 1_500, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpendBeforeUpcomingExpenses, 1_500, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpend, 500, accuracy: 0.001)
    }

    func testFinancialSummaryCalculatorCanPreviewDebtPaymentSetAside() {
        let summary = FinancialSummaryCalculator.calculate(
            accounts: [
                account(
                    type: "depository",
                    subtype: "checking",
                    available: 2_000,
                    balance: 0
                ),
                account(
                    type: "credit",
                    subtype: "credit card",
                    balance: -4_500
                )
            ],
            goals: [
                goal(
                    currentAmount: 300,
                    targetAmount: 1_000
                )
            ],
            reserveBalance: 200,
            upcomingExpensesSetAside: 400,
            debtPaymentsSetAside: 650
        )

        XCTAssertEqual(summary.debt, 4_500, accuracy: 0.001)
        XCTAssertEqual(summary.debtPaymentsSetAside, 650, accuracy: 0.001)
        XCTAssertEqual(summary.protectedMoney, 1_550, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpend, 450, accuracy: 0.001)
        XCTAssertEqual(summary.netWorth, -2_500, accuracy: 0.001)
    }

    func testFinancialSummaryCalculatorIncludesDebtPayoffInProtectedMoney() {
        let summary = FinancialSummaryCalculator.calculate(
            accounts: [
                account(
                    type: "depository",
                    subtype: "checking",
                    available: 3_000,
                    balance: 3_000
                ),
                account(
                    type: "credit",
                    subtype: "credit card",
                    balance: -1_200
                ),
                account(
                    type: "loan",
                    subtype: "loan",
                    balance: -8_500
                )
            ],
            goals: [
                goal(
                    currentAmount: 500,
                    targetAmount: 1_000
                )
            ],
            reserveBalance: 400,
            upcomingExpensesSetAside: 600,
            debtPaymentsSetAside: 300
        )

        XCTAssertEqual(summary.cash, 3_000, accuracy: 0.001)
        XCTAssertEqual(summary.debt, 9_700, accuracy: 0.001)
        XCTAssertEqual(summary.savingsGoalsSetAside, 500, accuracy: 0.001)
        XCTAssertEqual(summary.reserve, 400, accuracy: 0.001)
        XCTAssertEqual(summary.upcomingExpensesSetAside, 600, accuracy: 0.001)
        XCTAssertEqual(summary.debtPaymentsSetAside, 300, accuracy: 0.001)
        XCTAssertEqual(summary.protectedMoney, 1_800, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpend, 1_200, accuracy: 0.001)
    }

    func testFinancialSummaryCalculatorDebtPayoffDefaultsToPriorBehavior() {
        let summary = FinancialSummaryCalculator.calculate(
            accounts: [
                account(
                    type: "depository",
                    subtype: "checking",
                    available: 3_000,
                    balance: 3_000
                )
            ],
            goals: [
                goal(
                    currentAmount: 500,
                    targetAmount: 1_000
                )
            ],
            reserveBalance: 400,
            upcomingExpensesSetAside: 600
        )

        XCTAssertEqual(summary.debtPaymentsSetAside, 0, accuracy: 0.001)
        XCTAssertEqual(summary.protectedMoney, 1_500, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpend, 1_500, accuracy: 0.001)
    }

    func testPlaidCheckingAccountDecodesAsDepositorySubtypeAndUsesAvailableBalance() throws {
        let response = try decodeAccountsResponse(
            """
            {
              "accounts": [
                {
                  "account_id": "chase-checking-001",
                  "name": "Total Checking",
                  "official_name": "Chase Total Checking",
                  "type": "depository",
                  "subtype": "checking",
                  "mask": "1234",
                  "balances": {
                    "available": 1250.75,
                    "current": 0
                  },
                  "item_id": "item-chase",
                  "institution_name": "Chase",
                  "institution_id": "ins_chase"
                }
              ],
              "partial_failure": false
            }
            """
        )
        let checking = try XCTUnwrap(response.accounts.first)

        XCTAssertTrue(checking.isDepositoryAccount)
        XCTAssertTrue(checking.isCheckingGroupAccount)
        XCTAssertFalse(checking.isSavingsGroupAccount)
        XCTAssertTrue(checking.isCashTotalAccount)
        XCTAssertFalse(checking.isDebtTotalAccount)
        XCTAssertEqual(checking.cashBalanceValue, 1250.75, accuracy: 0.001)
        XCTAssertEqual(response.accounts.checkingAccounts.map(\.account_id), ["chase-checking-001"])
        XCTAssertEqual(response.accounts.cashAccounts.map(\.account_id), ["chase-checking-001"])
        XCTAssertEqual(response.accounts.totalCashBalance, 1250.75, accuracy: 0.001)
        XCTAssertEqual(response.accounts.totalDebtBalance, 0, accuracy: 0.001)
        XCTAssertEqual(checking.institution_name, "Chase")
        XCTAssertEqual(checking.item_id, "item-chase")
    }

    func testPlaidSavingsAccountUsesCurrentBalanceAndStillCountsAsCash() {
        let savings = account(
            name: "Savings",
            accountID: "savings-001",
            type: "depository",
            subtype: "savings",
            available: 900,
            balance: 1_500
        )

        XCTAssertTrue(savings.isDepositoryAccount)
        XCTAssertTrue(savings.isSavingsGroupAccount)
        XCTAssertTrue(savings.isCashTotalAccount)
        XCTAssertFalse(savings.isDebtTotalAccount)
        XCTAssertEqual(savings.cashBalanceValue, 1_500, accuracy: 0.001)
        XCTAssertEqual([savings].totalSavingsBalance, 1_500, accuracy: 0.001)
        XCTAssertEqual([savings].totalCashBalance, 1_500, accuracy: 0.001)
    }

    func testPlaidNilAvailableBalanceFallsBackToCurrentBalance() throws {
        let response = try decodeAccountsResponse(
            """
            {
              "accounts": [
                {
                  "account_id": "checking-null-available",
                  "name": "Everyday Checking",
                  "official_name": null,
                  "type": "depository",
                  "subtype": "checking",
                  "mask": "4321",
                  "balances": {
                    "available": null,
                    "current": 840.10
                  }
                }
              ],
              "partial_failure": false
            }
            """
        )
        let checking = try XCTUnwrap(response.accounts.first)

        XCTAssertTrue(checking.isCheckingGroupAccount)
        XCTAssertEqual(checking.cashBalanceValue, 840.10, accuracy: 0.001)
        XCTAssertEqual(checking.displayAvailableBalance, 840.10, accuracy: 0.001)
        XCTAssertEqual(response.accounts.totalCashBalance, 840.10, accuracy: 0.001)
    }

    func testPlaidCreditAndLoanAccountsAreDebtAndExcludedFromCash() {
        let accounts = [
            account(
                name: "Checking",
                accountID: "checking-001",
                type: "depository",
                subtype: "checking",
                available: 500,
                balance: 550
            ),
            account(
                name: "Credit Card",
                accountID: "credit-001",
                type: "credit",
                subtype: "credit card",
                available: 2_000,
                balance: -450
            ),
            account(
                name: "Auto Loan",
                accountID: "loan-001",
                type: "loan",
                subtype: "auto",
                balance: -12_000
            )
        ]

        XCTAssertEqual(accounts.cashAccounts.map(\.account_id), ["checking-001"])
        XCTAssertEqual(accounts.debtAccounts.map(\.account_id), ["credit-001", "loan-001"])
        XCTAssertEqual(accounts.totalCashBalance, 500, accuracy: 0.001)
        XCTAssertEqual(accounts.totalDebtBalance, 12_450, accuracy: 0.001)
    }

    func testPlaidNilSubtypeDepositoryCountsAsCashButNotCheckingOrSavings() {
        let account = account(
            name: "Cash Management",
            accountID: "cash-001",
            type: "depository",
            subtype: nil,
            available: 250,
            balance: 300
        )

        XCTAssertTrue(account.isDepositoryAccount)
        XCTAssertTrue(account.isCashTotalAccount)
        XCTAssertFalse(account.isCheckingGroupAccount)
        XCTAssertFalse(account.isSavingsGroupAccount)
        XCTAssertEqual(account.cashBalanceValue, 250, accuracy: 0.001)
    }

    func testPlaidClassificationNormalizesWhitespaceAndCapitalization() {
        let checking = account(
            name: "Checking",
            accountID: "checking-normalized",
            type: " Depository ",
            subtype: " Checking ",
            available: 700,
            balance: 0
        )
        let credit = account(
            name: "Credit",
            accountID: "credit-normalized",
            type: " CREDIT ",
            subtype: " credit card ",
            balance: -80
        )

        XCTAssertTrue(checking.isDepositoryAccount)
        XCTAssertTrue(checking.isCheckingGroupAccount)
        XCTAssertEqual(checking.cashBalanceValue, 700, accuracy: 0.001)
        XCTAssertTrue(credit.isCreditGroupAccount)
        XCTAssertTrue(credit.isDebtTotalAccount)
        XCTAssertEqual(credit.debtBalanceValue, 80, accuracy: 0.001)
    }

    func testActiveUpcomingExpenseAllocationAndRemainingAmount() {
        let forecast = singleExpenseForecast(
            amount: 1_000,
            date: date(2026, 7, 21)
        )
        let allocation = allocation(
            for: forecast,
            amount: 400
        )

        let activeTotal = EventAllocationTotals.activeTotal(
            allocations: [allocation],
            forecastEvents: [forecast]
        )

        XCTAssertEqual(activeTotal, 400, accuracy: 0.001)
        XCTAssertEqual(
            max(forecast.event.amount - activeTotal, 0),
            600,
            accuracy: 0.001
        )
    }

    func testOverAllocatedUpcomingExpenseCapsAtAmountDue() {
        let forecast = singleExpenseForecast(
            amount: 1_000,
            date: date(2026, 7, 21)
        )
        let allocation = allocation(
            for: forecast,
            amount: 1_200
        )

        let activeTotal = EventAllocationTotals.activeTotal(
            allocations: [allocation],
            forecastEvents: [forecast]
        )
        let remaining = max(
            forecast.event.amount - activeTotal,
            0
        )
        let progress = min(
            activeTotal / forecast.event.amount,
            1
        )

        XCTAssertEqual(activeTotal, 1_000, accuracy: 0.001)
        XCTAssertEqual(remaining, 0, accuracy: 0.001)
        XCTAssertEqual(progress, 1, accuracy: 0.001)
    }

    func testPaidOccurrenceIsExcludedFromActiveTotalsAndNextExpense() {
        let rent = event(
            name: "Rent",
            amount: 1_000,
            date: date(2026, 7, 21),
            frequency: .once
        )
        let utilities = event(
            name: "Utilities",
            amount: 200,
            date: date(2026, 7, 22),
            frequency: .once
        )
        let baseCalculator = calculator(
            events: [
                rent,
                utilities
            ],
            now: date(2026, 7, 20)
        )
        let rentForecast = try! XCTUnwrap(
            baseCalculator.forecastEvents.first {
                $0.event.id == rent.id
            }
        )
        let paidStatus = status(
            for: rentForecast,
            resolution: .paid
        )
        let inactiveIDs = ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: [paidStatus]
        )
        let filteredCalculator = calculator(
            events: [
                rent,
                utilities
            ],
            now: date(2026, 7, 20),
            inactiveOccurrenceIDs: inactiveIDs
        )
        let activeTotal = EventAllocationTotals.activeTotal(
            allocations: [
                allocation(
                    for: rentForecast,
                    amount: 1_000
                )
            ],
            forecastEvents: filteredCalculator.forecastEvents
        )

        XCTAssertEqual(activeTotal, 0, accuracy: 0.001)
        XCTAssertEqual(filteredCalculator.nextExpense?.event.name, "Utilities")
    }

    func testSkippedOccurrenceIsExcludedFromActiveTotals() {
        let forecast = singleExpenseForecast(
            amount: 1_000,
            date: date(2026, 7, 21)
        )
        let inactiveIDs = ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: [
                status(
                    for: forecast,
                    resolution: .skipped
                )
            ]
        )
        let filteredForecasts = [forecast].filter {
            !inactiveIDs.contains($0.occurrenceID)
        }
        let activeTotal = EventAllocationTotals.activeTotal(
            allocations: [
                allocation(
                    for: forecast,
                    amount: 1_000
                )
            ],
            forecastEvents: filteredForecasts
        )

        XCTAssertTrue(filteredForecasts.isEmpty)
        XCTAssertEqual(activeTotal, 0, accuracy: 0.001)
    }

    func testOverdueUnresolvedOccurrenceStaysActive() {
        let now = date(2026, 7, 21)
        let forecast = singleExpenseForecast(
            amount: 1_000,
            date: date(2026, 7, 20),
            now: now
        )
        let activeTotal = EventAllocationTotals.activeTotal(
            allocations: [
                allocation(
                    for: forecast,
                    amount: 500
                )
            ],
            forecastEvents: [forecast]
        )

        XCTAssertEqual(
            ExpenseOccurrenceLifecycleResolver.lifecycle(
                for: forecast,
                statuses: [],
                now: now,
                calendar: calendar
            ),
            .overdue
        )
        XCTAssertEqual(activeTotal, 500, accuracy: 0.001)
    }

    func testMonthlyOccurrenceAllocationsAndStatusesAreIndependent() {
        let rent = event(
            name: "Rent",
            amount: 1_000,
            date: date(2026, 7, 1),
            frequency: .monthly
        )
        let baseCalculator = calculator(
            events: [rent],
            now: date(2026, 7, 1)
        )
        let forecasts = baseCalculator.forecastEvents
        let july = try! XCTUnwrap(
            forecasts.first {
                dateKey($0.occurrenceDate) == "2026-07-01"
            }
        )
        let august = try! XCTUnwrap(
            forecasts.first {
                dateKey($0.occurrenceDate) == "2026-08-01"
            }
        )
        let julyAllocation = allocation(
            for: july,
            amount: 400
        )

        XCTAssertNotEqual(july.occurrenceID, august.occurrenceID)
        XCTAssertEqual(
            EventAllocationTotals.activeTotal(
                allocations: [julyAllocation],
                forecastEvents: [july]
            ),
            400,
            accuracy: 0.001
        )
        XCTAssertEqual(
            EventAllocationTotals.activeTotal(
                allocations: [julyAllocation],
                forecastEvents: [august]
            ),
            0,
            accuracy: 0.001
        )

        let inactiveIDs = ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: [
                status(
                    for: july,
                    resolution: .paid
                )
            ]
        )
        let filteredCalculator = calculator(
            events: [rent],
            now: date(2026, 7, 1),
            inactiveOccurrenceIDs: inactiveIDs
        )

        XCTAssertFalse(
            filteredCalculator.forecastEvents.contains {
                $0.occurrenceID == july.occurrenceID
            }
        )
        XCTAssertTrue(
            filteredCalculator.forecastEvents.contains {
                $0.occurrenceID == august.occurrenceID
            }
        )
    }

    func testDashboardNextExpenseUsesFullAmountDueAndCoveredStatus() {
        let rent = event(
            name: "Rent",
            amount: 1_000,
            date: date(2026, 7, 21),
            frequency: .once
        )
        let forecast = try! XCTUnwrap(
            calculator(
                events: [rent],
                now: date(2026, 7, 20)
            )
            .nextExpense
        )
        let partialAllocation = allocation(
            for: forecast,
            amount: 400
        )
        let fullAllocation = allocation(
            for: forecast,
            amount: 1_000
        )

        XCTAssertEqual(forecast.event.amount, 1_000, accuracy: 0.001)
        XCTAssertFalse(isCovered(forecast, allocation: partialAllocation))
        XCTAssertTrue(isCovered(forecast, allocation: fullAllocation))
    }

    func testMonthlyJan29PreservesAnchorDayWhenPossible() {
        XCTAssertEqual(
            occurrenceKeys(
                frequency: .monthly,
                start: date(2026, 1, 29),
                now: date(2026, 1, 1),
                count: 4
            ),
            [
                "2026-01-29",
                "2026-02-28",
                "2026-03-29",
                "2026-04-29"
            ]
        )
    }

    func testMonthlyJan30PreservesAnchorDayWhenPossible() {
        XCTAssertEqual(
            occurrenceKeys(
                frequency: .monthly,
                start: date(2026, 1, 30),
                now: date(2026, 1, 1),
                count: 4
            ),
            [
                "2026-01-30",
                "2026-02-28",
                "2026-03-30",
                "2026-04-30"
            ]
        )
    }

    func testMonthlyJan31PreservesAnchorDayWhenPossible() {
        XCTAssertEqual(
            occurrenceKeys(
                frequency: .monthly,
                start: date(2026, 1, 31),
                now: date(2026, 1, 1),
                count: 5
            ),
            [
                "2026-01-31",
                "2026-02-28",
                "2026-03-31",
                "2026-04-30",
                "2026-05-31"
            ]
        )
    }

    func testQuarterlyJan31PreservesAnchorDayWhenPossible() {
        XCTAssertEqual(
            occurrenceKeys(
                frequency: .quarterly,
                start: date(2026, 1, 31),
                now: date(2026, 1, 1),
                count: 5
            ),
            [
                "2026-01-31",
                "2026-04-30",
                "2026-07-31",
                "2026-10-31",
                "2027-01-31"
            ]
        )
    }

    func testBiweeklyYearEndRepeatsEveryFourteenDays() {
        XCTAssertEqual(
            occurrenceKeys(
                frequency: .biweekly,
                start: date(2026, 12, 25),
                now: date(2026, 12, 24),
                count: 4
            ),
            [
                "2026-12-25",
                "2027-01-08",
                "2027-01-22",
                "2027-02-05"
            ]
        )
    }
}

private extension CoreFinancialCalculationsTests {

    func account(
        name: String = "Account",
        accountID: String = UUID().uuidString,
        officialName: String? = nil,
        type: String,
        subtype: String? = nil,
        available: Double? = nil,
        balance: Double
    ) -> PlaidAccount {
        PlaidAccount(
            account_id: accountID,
            name: name,
            official_name: officialName,
            type: type,
            subtype: subtype,
            mask: nil,
            balances: PlaidBalance(
                available: available ?? balance,
                current: balance
            )
        )
    }

    func decodeAccountsResponse(
        _ json: String
    ) throws -> AccountsResponse {
        try JSONDecoder().decode(
            AccountsResponse.self,
            from: Data(json.utf8)
        )
    }

    func goal(
        currentAmount: Double,
        targetAmount: Double
    ) -> SavingsGoal {
        SavingsGoal(
            name: "Goal",
            targetAmount: targetAmount,
            currentAmount: currentAmount
        )
    }

    func event(
        id: UUID = UUID(),
        name: String = "Expense",
        amount: Double,
        date: Date,
        frequency: PlannerFrequency,
        type: PlannerEventType = .expense
    ) -> PlannerEvent {
        PlannerEvent(
            id: id,
            name: name,
            amount: amount,
            date: date,
            frequency: frequency,
            type: type
        )
    }

    func allocation(
        for forecast: ForecastEvent,
        amount: Double
    ) -> EventAllocation {
        EventAllocation(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.occurrenceDate,
            allocatedAmount: amount
        )
    }

    func status(
        for forecast: ForecastEvent,
        resolution: ExpenseOccurrenceResolution
    ) -> ExpenseOccurrenceStatus {
        ExpenseOccurrenceStatus(
            occurrenceID: forecast.occurrenceID,
            sourceEventID: forecast.event.id,
            occurrenceDate: forecast.occurrenceDate,
            status: resolution
        )
    }

    func singleExpenseForecast(
        amount: Double,
        date: Date,
        now: Date? = nil
    ) -> ForecastEvent {
        let expense = event(
            amount: amount,
            date: date,
            frequency: .once
        )

        return calculator(
            events: [expense],
            now: now ?? date
        )
        .forecastEvents[0]
    }

    func calculator(
        events: [PlannerEvent],
        now: Date,
        totalAvailable: Double = 2_000,
        totalGoalAllocated: Double = 0,
        reserveBalance: Double = 0,
        protectedEventAllocations: Double = 0,
        inactiveOccurrenceIDs: Set<String> = []
    ) -> PlannerForecastCalculator {
        PlannerForecastCalculator(
            events: events,
            totalAvailable: totalAvailable,
            totalGoalAllocated: totalGoalAllocated,
            reserveBalance: reserveBalance,
            protectedEventAllocations: protectedEventAllocations,
            includeFutureIncome: true,
            protectGoals: true,
            now: now,
            calendar: calendar,
            inactiveOccurrenceIDs: inactiveOccurrenceIDs
        )
    }

    func occurrenceKeys(
        frequency: PlannerFrequency,
        start: Date,
        now: Date,
        count: Int
    ) -> [String] {
        let recurringEvent = event(
            amount: 100,
            date: start,
            frequency: frequency
        )

        return Array(
            calculator(
                events: [recurringEvent],
                now: now
            )
            .forecastEvents
            .prefix(count)
            .map {
                dateKey($0.occurrenceDate)
            }
        )
    }

    func isCovered(
        _ forecast: ForecastEvent,
        allocation: EventAllocation
    ) -> Bool {
        allocation.allocatedAmount + 0.005 >= forecast.event.amount
    }

    func date(
        _ year: Int,
        _ month: Int,
        _ day: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: 12
            )
        )!
    }

    func dateKey(
        _ date: Date
    ) -> String {
        let components = calendar.dateComponents(
            [
                .year,
                .month,
                .day
            ],
            from: date
        )

        return String(
            format: "%04d-%02d-%02d",
            components.year!,
            components.month!,
            components.day!
        )
    }
}
