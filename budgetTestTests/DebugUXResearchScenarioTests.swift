#if DEBUG
import Foundation
import SwiftData
import XCTest
@testable import Caldera_Money

@MainActor
final class DebugUXResearchScenarioTests: XCTestCase {

    private static var retainedServices: [PlaidService] = []
    private static var retainedContainers: [ModelContainer] = []

    private var calendar: Calendar!
    private var resetDate: Date!

    override func setUp() {
        super.setUp()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        resetDate = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 13,
                hour: 12
            )
        )!
    }

    override func tearDown() {
        calendar = nil
        resetDate = nil
        super.tearDown()
    }

    func testGateRequiresExplicitDebugLocalAndRejectsLabAndRelease() {
        let debugEnvironment = AppEnvironment(
            apiBaseURL: URL(string: "http://127.0.0.1:3001")!,
            displayName: "Local Sandbox",
            expectedPlaidEnvironment: "sandbox",
            isDebug: true
        )
        let releaseEnvironment = AppEnvironment(
            apiBaseURL: URL(string: "https://example.com")!,
            displayName: "Production",
            expectedPlaidEnvironment: "production",
            isDebug: false
        )

        XCTAssertTrue(
            DebugLocalFeatureGate.isEnabled(
                explicitLocalValue: "1",
                labValue: nil,
                environment: debugEnvironment
            )
        )
        XCTAssertFalse(
            DebugLocalFeatureGate.isEnabled(
                explicitLocalValue: nil,
                labValue: nil,
                environment: debugEnvironment
            )
        )
        XCTAssertFalse(
            DebugLocalFeatureGate.isEnabled(
                explicitLocalValue: "1",
                labValue: "1",
                environment: debugEnvironment
            )
        )
        XCTAssertFalse(
            DebugLocalFeatureGate.isEnabled(
                explicitLocalValue: "1",
                labValue: nil,
                environment: releaseEnvironment
            )
        )
    }

    func testFixtureConstructionIsDeterministicAndDueDateIsResetPlusFifteenDays() throws {
        let firstAccounts = DebugUXResearchScenario.accounts()
        let secondAccounts = DebugUXResearchScenario.accounts()
        let firstDetails = try XCTUnwrap(
            DebugUXResearchScenario.cardPaymentDetails(
                resetAt: resetDate,
                hasRefreshed: false,
                calendar: calendar
            ).first
        )
        let secondDetails = try XCTUnwrap(
            DebugUXResearchScenario.cardPaymentDetails(
                resetAt: resetDate,
                hasRefreshed: false,
                calendar: calendar
            ).first
        )

        XCTAssertEqual(firstAccounts.map(\.account_id), secondAccounts.map(\.account_id))
        XCTAssertEqual(firstAccounts.map(\.balances.current), [2_500, 1_000, 1_250])
        XCTAssertEqual(firstAccounts[0].balances.available, 2_500)
        XCTAssertEqual(firstAccounts[1].balances.available, 1_000)
        XCTAssertEqual(firstDetails.last_statement_balance, 350)
        XCTAssertEqual(firstDetails.minimum_payment_amount, 45)
        XCTAssertEqual(firstDetails.next_payment_due_date, "2026-07-28")
        XCTAssertEqual(firstDetails.last_statement_balance, secondDetails.last_statement_balance)
        XCTAssertEqual(firstDetails.next_payment_due_date, secondDetails.next_payment_due_date)
    }

    func testConnectCreatesExactlyThreeFullyUpdatedAccountsWithoutExplicitScope() throws {
        let service = serviceFixture()
        XCTAssertTrue(service.debugResetUXResearchScenario(resetAt: resetDate))
        XCTAssertTrue(service.accounts.isEmpty)

        XCTAssertTrue(service.debugConnectUXResearchAccounts(connectedAt: resetDate))

        XCTAssertTrue(service.debugUXResearchAccountsAreConnected)
        XCTAssertEqual(service.accounts.count, 3)
        XCTAssertEqual(service.bankSyncRefreshState.phase, .fullyUpdated)
        XCTAssertEqual(service.bankSyncRefreshState.balances, .updated)
        XCTAssertEqual(service.bankSyncRefreshState.transactions, .updated)
        XCTAssertFalse(service.bankSyncRefreshState.balanceNeedsAttention)
        XCTAssertEqual(service.plaidCallsThisSession, 0)
        XCTAssertFalse(
            AvailableToSpendAccountScope.hasExplicitSelection(
                userID: "debug-user",
                linkedCashAccountIDs: Set([
                    DebugUXResearchScenario.checkingAccountID,
                    DebugUXResearchScenario.savingsAccountID
                ]),
                selections: []
            )
        )

        let summary = FinancialSummaryCalculator.calculate(
            accounts: service.financialSummaryAccounts,
            goals: [],
            reserveBalance: 0
        )
        XCTAssertEqual(summary.cash, 3_500, accuracy: 0.001)
        XCTAssertEqual(summary.safeToSpend, 3_500, accuracy: 0.001)
    }

    func testDeterministicRefreshUsesExistingReviewPipelineWithoutMutatingPlan() throws {
        let service = serviceFixture()
        XCTAssertTrue(service.debugResetUXResearchScenario(resetAt: resetDate))
        XCTAssertTrue(service.debugConnectUXResearchAccounts(connectedAt: resetDate))

        let initialDetails = try XCTUnwrap(service.cardPaymentDetails.first)
        let dueDate = try XCTUnwrap(
            PaymentPlanStatementIssueDate.parse(
                initialDetails.next_payment_due_date
            )
        )
        let statementIssueDate = try XCTUnwrap(
            PaymentPlanStatementIssueDate.parse(
                initialDetails.last_statement_issue_date
            )
        )
        let plan = DebtPayoffBucket(
            plaidAccountID: DebugUXResearchScenario.creditCardAccountID,
            accountName: "Research Credit Card",
            dueDate: dueDate,
            paymentTargetAmount: 350,
            protectedAmount: 0,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: .statementBalance,
            targetChosenAt: resetDate,
            targetStatementIssueDate: statementIssueDate
        )

        XCTAssertTrue(
            PaymentPlanReviewUpdates.updates(
                paymentPlans: [plan],
                cardPaymentDetails: service.cardPaymentDetails,
                calendar: calendar
            ).isEmpty
        )

        XCTAssertTrue(
            service.debugSimulateUXResearchPaymentDetailRefresh(
                refreshedAt: resetDate.addingTimeInterval(60)
            )
        )
        let refreshedDetails = try XCTUnwrap(service.cardPaymentDetails.first)
        let updates = PaymentPlanReviewUpdates.updates(
            paymentPlans: [plan],
            cardPaymentDetails: service.cardPaymentDetails,
            calendar: calendar
        )

        XCTAssertEqual(initialDetails.last_statement_balance, 350)
        XCTAssertEqual(refreshedDetails.last_statement_balance, 400)
        XCTAssertEqual(refreshedDetails.next_payment_due_date, initialDetails.next_payment_due_date)
        XCTAssertEqual(refreshedDetails.minimum_payment_amount, initialDetails.minimum_payment_amount)
        XCTAssertEqual(refreshedDetails.current_balance, initialDetails.current_balance)
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.paymentPlanID, plan.id)
        XCTAssertEqual(plan.paymentTargetAmount, 350)
        XCTAssertEqual(plan.dueDate, dueDate)
        XCTAssertEqual(plan.targetStatementIssueDate, statementIssueDate)
    }

    func testResetTwiceClearsLocalStateAndReturnsConnectionTo350() {
        let service = serviceFixture()

        for _ in 0..<2 {
            XCTAssertTrue(service.debugResetUXResearchScenario(resetAt: resetDate))
            XCTAssertTrue(service.accounts.isEmpty)
            XCTAssertTrue(service.transactions.isEmpty)
            XCTAssertTrue(service.cardPaymentDetails.isEmpty)
            XCTAssertTrue(service.savingsGoals.isEmpty)
            XCTAssertEqual(service.reserveBalance, 0)

            XCTAssertTrue(service.debugConnectUXResearchAccounts(connectedAt: resetDate))
            XCTAssertEqual(
                service.cardPaymentDetails.first?.last_statement_balance,
                350
            )
            XCTAssertTrue(service.debugSimulateUXResearchPaymentDetailRefresh())
            XCTAssertEqual(
                service.cardPaymentDetails.first?.last_statement_balance,
                400
            )
        }

        XCTAssertTrue(service.debugResetUXResearchScenario(resetAt: resetDate))
        XCTAssertTrue(service.debugConnectUXResearchAccounts(connectedAt: resetDate))
        XCTAssertEqual(service.cardPaymentDetails.first?.last_statement_balance, 350)
    }

    func testResetClearsAllPlanningAndAccountScopeRecords() throws {
        let schema = Schema([
            PlannerEvent.self,
            EventAllocation.self,
            ExpenseOccurrenceStatus.self,
            SavingsGoalRecord.self,
            ReserveSettings.self,
            DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            AvailableToSpendAccountPreference.self,
            IncomeSchedule.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let expense = PlannerEvent(
            name: "Research Rent",
            amount: 1_200,
            date: resetDate,
            type: .expense
        )
        let plan = DebtPayoffBucket(
            plaidAccountID: DebugUXResearchScenario.creditCardAccountID,
            accountName: "Research Credit Card",
            dueDate: resetDate,
            paymentTargetAmount: 350
        )

        context.insert(expense)
        context.insert(
            EventAllocation(
                occurrenceID: "research-occurrence",
                sourceEventID: expense.id,
                occurrenceDate: resetDate,
                allocatedAmount: 100
            )
        )
        context.insert(
            ExpenseOccurrenceStatus(
                occurrenceID: "research-occurrence",
                sourceEventID: expense.id,
                occurrenceDate: resetDate,
                status: .paid
            )
        )
        context.insert(
            SavingsGoalRecord(
                name: "Research Goal",
                targetAmount: 500,
                currentAmount: 100
            )
        )
        context.insert(ReserveSettings(balance: 75))
        context.insert(plan)
        context.insert(
            PaymentPlanCycle(
                paymentPlanID: plan.id,
                dueDate: resetDate,
                frozenTargetAmount: 350
            )
        )
        context.insert(
            AvailableToSpendAccountPreference(
                userID: "debug-user",
                plaidAccountID: DebugUXResearchScenario.checkingAccountID,
                isIncluded: false
            )
        )
        context.insert(
            IncomeSchedule(
                ownerScopeID: IncomeScheduleOwnerScope.current(
                    authenticatedUserID: "debug-user"
                ),
                takeHomeAmountCents: 200_000,
                frequency: .biweekly,
                lastPaydayDateKey: "2026-07-10",
                nextExpectedPaydayDateKey: "2026-07-24",
                dateBasis: .calculated
            )
        )
        try context.save()

        let service = serviceFixture()
        service.configurePersistence(modelContext: context)
        Self.retainedContainers.append(container)

        XCTAssertTrue(service.debugResetUXResearchScenario(resetAt: resetDate))

        XCTAssertTrue(try context.fetch(FetchDescriptor<PlannerEvent>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<EventAllocation>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ExpenseOccurrenceStatus>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SavingsGoalRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ReserveSettings>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DebtPayoffBucket>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PaymentPlanCycle>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<IncomeSchedule>()).isEmpty)
        XCTAssertTrue(
            try context.fetch(
                FetchDescriptor<AvailableToSpendAccountPreference>()
            ).isEmpty
        )
        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertTrue(service.cardPaymentDetails.isEmpty)
        XCTAssertTrue(service.savingsGoals.isEmpty)
        XCTAssertEqual(service.reserveBalance, 0)
    }

    func testFirstRunAndAllRecommendationHistoryResetAreRepeatable() throws {
        let suiteName = "DebugUXResearchScenarioTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("Taylor", forKey: AppPersonalizationKeys.preferredName)
        defaults.set(true, forKey: AppPersonalizationKeys.hasCompletedPersonalization)

        let historyID = RecurringExpenseRecommendationIdentity.familyID(
            normalizedName: "research subscription",
            accountID: "research-checking"
        )
        let suggestion = RecurringExpenseSuggestion(
            id: RecurringExpenseRecommendationIdentity.suggestionID(
                familyID: historyID,
                amount: 20,
                dayOfMonth: 10
            ),
            historyID: historyID,
            merchantName: "Research Subscription",
            normalizedName: "research subscription",
            amount: 20,
            nextDueDate: resetDate,
            dayOfMonth: 10,
            occurrenceCount: 3,
            isAlreadyInPlan: false
        )
        let historyStore = RecurringExpenseRecommendationHistoryStore(defaults: defaults)
        historyStore.record(
            suggestion,
            status: .dismissed,
            plannerEventID: nil,
            for: "debug-user"
        )
        historyStore.record(
            suggestion,
            status: .added,
            plannerEventID: UUID(),
            for: "other-debug-user"
        )

        for _ in 0..<2 {
            DebugUXResearchScenario.resetFirstRunState(defaults: defaults)
            DebugUXResearchScenario.clearRecurringRecommendationHistory(
                defaults: defaults
            )

            XCTAssertTrue(defaults.bool(forKey: "hasCompletedOnboarding"))
            XCTAssertFalse(defaults.bool(forKey: AppPersonalizationKeys.hasCompletedPersonalization))
            XCTAssertNil(defaults.string(forKey: AppPersonalizationKeys.preferredName))
            XCTAssertTrue(historyStore.records(for: "debug-user").isEmpty)
            XCTAssertTrue(historyStore.records(for: "other-debug-user").isEmpty)
        }
    }

    func testSignOutClearsConnectedFixtureSafely() throws {
        let service = serviceFixture()
        XCTAssertTrue(service.debugResetUXResearchScenario(resetAt: resetDate))
        XCTAssertTrue(service.debugConnectUXResearchAccounts(connectedAt: resetDate))

        service.clearLocalFinancialDataForSignOut()

        XCTAssertTrue(service.accounts.isEmpty)
        XCTAssertTrue(service.cardPaymentDetails.isEmpty)
        XCTAssertNil(service.debugUXResearchResetDate)
        XCTAssertEqual(service.reserveBalance, 0)
    }

    private func serviceFixture() -> PlaidService {
        let service = PlaidService(
            sessionTokenProvider: { "debug-token" },
            authenticatedUserIDProvider: { "debug-user" }
        )
        Self.retainedServices.append(service)
        return service
    }
}
#endif
