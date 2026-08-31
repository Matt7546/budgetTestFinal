import XCTest
@testable import Caldera_Money

@MainActor
final class DashboardBankRefreshTests: XCTestCase {

    func testSignedOutRefreshRequiresSignIn() {
        XCTAssertEqual(
            DashboardRefreshPresentation.tapDecision(
                isSignedIn: false,
                hasLinkedAccounts: false,
                isRefreshing: false
            ),
            .signInRequired
        )
    }

    func testSignedInRefreshWithoutLinkedAccountsRequiresLink() {
        XCTAssertEqual(
            DashboardRefreshPresentation.tapDecision(
                isSignedIn: true,
                hasLinkedAccounts: false,
                isRefreshing: false
            ),
            .linkAccountRequired
        )
    }

    func testRefreshIgnoresDuplicateTapWhileAlreadyRefreshing() {
        XCTAssertEqual(
            DashboardRefreshPresentation.tapDecision(
                isSignedIn: true,
                hasLinkedAccounts: true,
                isRefreshing: true
            ),
            .ignoreWhileRefreshing
        )
        XCTAssertEqual(
            DashboardRefreshPresentation.buttonTitle(isRefreshing: true),
            "Refreshing…"
        )
    }

    func testRefreshFailurePreservesEarlierBalanceDataAndTimestamp() {
        let previousRefresh = date(2026, 8, 20)
        let previousState = state(
            phase: .fullyUpdated,
            balances: .updated,
            transactions: .updated,
            balanceRefresh: previousRefresh,
            transactionRefresh: date(2026, 8, 21),
            hasBalances: true,
            hasTransactions: true
        )

        let result = BankSyncRefreshReducer.resolve(
            accountOutcome: .failure,
            transactionOutcome: .failure,
            previousState: previousState,
            hasUsableBalances: true,
            hasUsableTransactions: true,
            completedAt: date(2026, 8, 30)
        )

        XCTAssertEqual(result.phase, .showingEarlierData)
        XCTAssertTrue(result.hasUsableBalances)
        XCTAssertEqual(result.lastSuccessfulBalanceRefresh, previousRefresh)
        XCTAssertEqual(
            DashboardRefreshPresentation.statusText(
                isRefreshing: false,
                state: result,
                accountsLastUpdatedText: "Last fully refreshed Aug 20"
            ),
            "Couldn’t refresh everything. Try again in a little bit."
        )
    }

    func testRateLimitUsesCalmRetryLaterCopyAndPreservesData() {
        let previousRefresh = date(2026, 8, 20)
        let result = BankSyncRefreshReducer.resolve(
            accountOutcome: .rateLimited("Technical rate-limit detail"),
            transactionOutcome: .rateLimited("Technical rate-limit detail"),
            previousState: state(
                phase: .fullyUpdated,
                balances: .updated,
                transactions: .updated,
                balanceRefresh: previousRefresh,
                transactionRefresh: previousRefresh,
                hasBalances: true,
                hasTransactions: true
            ),
            hasUsableBalances: true,
            hasUsableTransactions: true,
            completedAt: date(2026, 8, 30)
        )

        XCTAssertEqual(result.phase, .rateLimited)
        XCTAssertTrue(result.hasUsableBalances)
        XCTAssertEqual(result.lastSuccessfulBalanceRefresh, previousRefresh)
        XCTAssertEqual(
            DashboardRefreshPresentation.statusText(
                isRefreshing: false,
                state: result,
                accountsLastUpdatedText: "Last fully refreshed Aug 20"
            ),
            "Try again in a little bit."
        )
    }

    func testSuccessfulRefreshUpdatesTimestampAndDashboardCopy() {
        let completedAt = date(2026, 8, 30)
        let result = BankSyncRefreshReducer.resolve(
            accountOutcome: .success,
            transactionOutcome: .success,
            previousState: state(
                phase: .idle,
                balances: .notRequested,
                transactions: .notRequested,
                balanceRefresh: nil,
                transactionRefresh: nil,
                hasBalances: false,
                hasTransactions: false
            ),
            hasUsableBalances: true,
            hasUsableTransactions: true,
            completedAt: completedAt
        )

        XCTAssertEqual(result.phase, .fullyUpdated)
        XCTAssertEqual(result.lastSuccessfulBalanceRefresh, completedAt)
        XCTAssertEqual(result.lastSuccessfulTransactionRefresh, completedAt)
        XCTAssertEqual(
            DashboardRefreshPresentation.statusText(
                isRefreshing: false,
                state: result,
                accountsLastUpdatedText: "Last refreshed just now"
            ),
            "Updated just now"
        )
    }

    private func state(
        phase: BankSyncRefreshPhase,
        balances: BankSyncResourceState,
        transactions: BankSyncResourceState,
        balanceRefresh: Date?,
        transactionRefresh: Date?,
        hasBalances: Bool,
        hasTransactions: Bool
    ) -> BankSyncRefreshState {
        BankSyncRefreshState(
            phase: phase,
            balances: balances,
            transactions: transactions,
            lastSuccessfulBalanceRefresh: balanceRefresh,
            lastSuccessfulTransactionRefresh: transactionRefresh,
            hasUsableBalances: hasBalances,
            hasUsableTransactions: hasTransactions,
            rateLimitMessage: nil
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int
    ) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(
                year: year,
                month: month,
                day: day
            )
        )!
    }
}
