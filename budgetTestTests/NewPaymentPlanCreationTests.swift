import XCTest
@testable import Caldera_Money

@MainActor
final class NewPaymentPlanCreationTests: XCTestCase {

    func testManualCreationRequiresNameAndPositiveTarget() {
        var input = NewPaymentPlanCreationInput()

        XCTAssertNil(
            input.draft(
                accounts: [],
                cardPaymentDetails: []
            )
        )
        XCTAssertEqual(
            input.validationMessage(
                accounts: [],
                cardPaymentDetails: []
            ),
            "Add a payment name and target amount to save."
        )

        input.manualName = "Visa"
        input.manualTargetAmountText = "0"

        XCTAssertNil(
            input.draft(
                accounts: [],
                cardPaymentDetails: []
            )
        )
        XCTAssertEqual(
            input.validationMessage(
                accounts: [],
                cardPaymentDetails: []
            ),
            "Enter a Payment Target greater than $0."
        )
    }

    func testManualCreationIsCardFocusedAndPreservesDecimalTarget() throws {
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        var input = NewPaymentPlanCreationInput()
        input.manualName = "  Platinum Card  "
        input.manualTargetAmountText = "$202.59"
        input.customDueDate = dueDate

        let draft = try XCTUnwrap(
            input.draft(
                accounts: [],
                cardPaymentDetails: []
            )
        )

        XCTAssertEqual(draft.debtKind, .linkedCreditCard)
        XCTAssertEqual(draft.plaidAccountID, "")
        XCTAssertEqual(draft.accountName, "Platinum Card")
        XCTAssertEqual(draft.dueDate, dueDate)
        XCTAssertEqual(
            draft.paymentTargetAmount,
            202.59,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(draft.manualCurrentBalance),
            202.59,
            accuracy: 0.001
        )
        XCTAssertEqual(draft.protectedAmount, 0)
        XCTAssertNil(draft.paymentTargetChoice)
        XCTAssertNil(draft.targetChosenAt)
        XCTAssertNil(draft.targetStatementIssueDate)
        XCTAssertTrue(draft.shouldCreateActiveCycle)
        XCTAssertEqual(
            NewPaymentPlanCreationMode.allCases,
            [.manual, .linked]
        )
    }

    func testLinkedCreationRequiresExplicitTargetChoice() {
        let account = makeCreditAccount(
            id: "card-1",
            currentBalance: 1_042.17
        )
        var input = NewPaymentPlanCreationInput()
        input.mode = .linked
        input.selectedAccountID = account.account_id

        XCTAssertNil(
            input.draft(
                accounts: [account],
                cardPaymentDetails: []
            )
        )
        XCTAssertEqual(
            input.validationMessage(
                accounts: [account],
                cardPaymentDetails: []
            ),
            "Choose what you'd like to plan for."
        )
    }

    func testLinkedTargetChoicesMapAmountsAndProvenance() throws {
        let account = makeCreditAccount(
            id: "card-1",
            currentBalance: 1_042.17
        )
        let details = makeCardPaymentDetails(
            accountID: account.account_id,
            statementBalance: 866.04,
            minimumPayment: 202.59,
            statementIssueDate: "2026-07-03",
            dueDate: "2026-08-14"
        )
        let chosenAt = Date(timeIntervalSince1970: 1_799_000_000)
        let expectedAmounts: [
            DebtPayoffLinkedCardPaymentTargetChoice: Double
        ] = [
            .statementBalance: 866.04,
            .minimumPayment: 202.59,
            .currentBalance: 1_042.17,
            .customAmount: 315.75
        ]

        for choice in DebtPayoffLinkedCardPaymentTargetChoice.allCases {
            var input = NewPaymentPlanCreationInput()
            input.mode = .linked
            input.selectedAccountID = account.account_id
            input.linkedTargetChoice = choice
            input.linkedCustomTargetAmountText = "315.75"
            input.dueDateSource = .statement

            let draft = try XCTUnwrap(
                input.draft(
                    accounts: [account],
                    cardPaymentDetails: [details],
                    now: chosenAt
                )
            )

            XCTAssertEqual(draft.plaidAccountID, account.account_id)
            XCTAssertEqual(draft.accountName, account.name)
            XCTAssertEqual(
                draft.paymentTargetAmount,
                try XCTUnwrap(expectedAmounts[choice]),
                accuracy: 0.001
            )
            XCTAssertEqual(draft.paymentTargetChoice, choice)
            XCTAssertEqual(draft.targetChosenAt, chosenAt)
            XCTAssertEqual(
                draft.targetStatementIssueDate != nil,
                choice == .statementBalance
            )
            XCTAssertTrue(draft.shouldCreateActiveCycle)
        }
    }

    func testStatementDueDateAndCustomDueDateRemainSeparateChoices() throws {
        let account = makeCreditAccount(
            id: "card-1",
            currentBalance: 500
        )
        let details = makeCardPaymentDetails(
            accountID: account.account_id,
            statementBalance: nil,
            minimumPayment: nil,
            statementIssueDate: nil,
            dueDate: "2026-08-14"
        )
        let customDate = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(
                    year: 2026,
                    month: 8,
                    day: 20
                )
            )
        )
        var input = NewPaymentPlanCreationInput()
        input.mode = .linked
        input.selectedAccountID = account.account_id
        input.linkedTargetChoice = .currentBalance
        input.customDueDate = customDate
        input.dueDateSource = .statement

        let statementDraft = try XCTUnwrap(
            input.draft(
                accounts: [account],
                cardPaymentDetails: [details]
            )
        )
        XCTAssertEqual(
            Calendar.current.component(.day, from: statementDraft.dueDate),
            14
        )

        input.dueDateSource = .custom
        let customDraft = try XCTUnwrap(
            input.draft(
                accounts: [account],
                cardPaymentDetails: [details]
            )
        )
        XCTAssertEqual(customDraft.dueDate, customDate)
    }

    func testUnavailableCardDetailsKeepFullAndCustomFallbacks() throws {
        let account = makeCreditAccount(
            id: "card-1",
            currentBalance: 500
        )
        var input = NewPaymentPlanCreationInput()
        input.mode = .linked
        input.selectedAccountID = account.account_id
        input.linkedTargetChoice = .statementBalance

        XCTAssertNil(
            input.draft(
                accounts: [account],
                cardPaymentDetails: []
            )
        )

        input.linkedTargetChoice = .currentBalance
        XCTAssertEqual(
            try XCTUnwrap(
                input.draft(
                    accounts: [account],
                    cardPaymentDetails: []
                )
            ).paymentTargetAmount,
            500,
            accuracy: 0.001
        )

        input.linkedTargetChoice = .customAmount
        input.linkedCustomTargetAmountText = "125.50"
        XCTAssertEqual(
            try XCTUnwrap(
                input.draft(
                    accounts: [account],
                    cardPaymentDetails: []
                )
            ).paymentTargetAmount,
            125.50,
            accuracy: 0.001
        )
    }

    func testExistingLinkedPlansAreExcludedWithoutHidingOtherCards() {
        let plannedAccount = makeCreditAccount(
            id: "card-1",
            currentBalance: 500
        )
        let availableAccount = makeCreditAccount(
            id: "card-2",
            currentBalance: 700
        )
        let existingPlan = DebtPayoffBucket(
            plaidAccountID: plannedAccount.account_id,
            accountName: plannedAccount.name,
            dueDate: Date(),
            paymentTargetAmount: 100,
            debtKind: .linkedCreditCard
        )

        let eligible = NewPaymentPlanLinkedAccountEligibility
            .selectableAccounts(
                from: [plannedAccount, availableAccount],
                existingPaymentPlans: [existingPlan]
            )

        XCTAssertEqual(
            eligible.map(\.account_id),
            [availableAccount.account_id]
        )
    }

    func testAmountPresentationPreservesCents() {
        XCTAssertEqual(
            NewPaymentPlanAmountPresentation.displayText(
                for: "$1,042.17"
            ),
            "1,042.17"
        )
    }

    func testFailedPersistenceKeepsPaymentPlanCreationOnScreen() {
        var input = NewPaymentPlanCreationInput()
        input.manualName = "Platinum Card"
        input.manualTargetAmountText = "202.59"
        let originalName = input.manualName
        let originalTarget = input.manualTargetAmountText

        let result = PlanningCreationPersistenceResult(
            didPersist: false,
            failureMessage:
                "Your Payment Plan wasn't saved. Please try again."
        )

        XCTAssertFalse(result.startsSuccessFlow)
        XCTAssertFalse(result.dismissesAfterSuccessFlow)
        XCTAssertEqual(
            result.errorMessage,
            "Your Payment Plan wasn't saved. Please try again."
        )
        XCTAssertEqual(input.manualName, originalName)
        XCTAssertEqual(input.manualTargetAmountText, originalTarget)
    }

    func testTargetPresentationUsesIntentionalBalanceCopy() {
        XCTAssertEqual(
            NewPaymentPlanTargetPresentation.title(
                for: .statementBalance
            ),
            "Statement balance"
        )
        XCTAssertEqual(
            NewPaymentPlanTargetPresentation.title(
                for: .minimumPayment
            ),
            "Minimum payment"
        )
        XCTAssertEqual(
            NewPaymentPlanTargetPresentation.title(
                for: .currentBalance
            ),
            "Full balance"
        )
        XCTAssertEqual(
            NewPaymentPlanTargetPresentation.title(
                for: .customAmount
            ),
            "Custom balance"
        )
    }

    func testCardDetailsStatusIsTruthfulAcrossRefreshOutcomes() {
        XCTAssertEqual(
            NewPaymentPlanCardDetailsStatus.resolve(
                hasDetails: true,
                consentRequired: false,
                requestState: .idle
            ),
            .ready
        )
        XCTAssertEqual(
            NewPaymentPlanCardDetailsStatus.resolve(
                hasDetails: false,
                consentRequired: false,
                requestState: .refreshing
            ),
            .refreshing
        )
        XCTAssertEqual(
            NewPaymentPlanCardDetailsStatus.resolve(
                hasDetails: true,
                consentRequired: false,
                requestState: .updated
            ),
            .updated
        )
        XCTAssertEqual(
            NewPaymentPlanCardDetailsStatus.resolve(
                hasDetails: false,
                consentRequired: true,
                requestState: .idle
            ),
            .needsPermission
        )
        XCTAssertEqual(
            NewPaymentPlanCardDetailsStatus.resolve(
                hasDetails: true,
                consentRequired: false,
                requestState: .unavailable
            ),
            .showingEarlierDetails
        )
        XCTAssertEqual(
            NewPaymentPlanCardDetailsStatus.resolve(
                hasDetails: false,
                consentRequired: false,
                requestState: .unavailable
            ),
            .unavailable
        )
    }

    private func makeCreditAccount(
        id: String,
        currentBalance: Double
    ) -> PlaidAccount {
        PlaidAccount(
            account_id: id,
            name: "Card \(id)",
            official_name: nil,
            type: "credit",
            subtype: "credit card",
            mask: "1234",
            balances: PlaidBalance(
                available: nil,
                current: currentBalance,
                limit: 5_000,
                iso_currency_code: "USD",
                unofficial_currency_code: nil
            ),
            item_id: "item-1",
            institution_name: "Test Bank",
            institution_id: "ins-1"
        )
    }

    private func makeCardPaymentDetails(
        accountID: String,
        statementBalance: Double?,
        minimumPayment: Double?,
        statementIssueDate: String?,
        dueDate: String?
    ) -> LinkedCardPaymentDetails {
        LinkedCardPaymentDetails(
            account_id: accountID,
            account_name: "Test Card",
            institution_name: "Test Bank",
            mask: "1234",
            current_balance: 1_042.17,
            available_credit: 3_957.83,
            last_statement_balance: statementBalance,
            last_statement_issue_date: statementIssueDate,
            minimum_payment_amount: minimumPayment,
            next_payment_due_date: dueDate,
            last_payment_amount: nil,
            last_payment_date: nil,
            is_overdue: false,
            last_refreshed_at: "2026-07-27T00:00:00Z"
        )
    }
}
