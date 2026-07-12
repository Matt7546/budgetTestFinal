import XCTest
import SwiftData
@testable import Caldera_Money

@MainActor
final class PaymentPlanTargetProvenanceTests: XCTestCase {

    // MARK: - Persistence round trip

    func testPaymentTargetChoiceRoundTripsThroughRawValue() {
        let chosenAt = Date()
        let bucket = DebtPayoffBucket(
            plaidAccountID: "acct-1",
            accountName: "Amex",
            dueDate: Date(),
            paymentTargetAmount: 150,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: .statementBalance,
            targetChosenAt: chosenAt
        )

        XCTAssertEqual(
            bucket.paymentTargetChoiceRawValue,
            DebtPayoffLinkedCardPaymentTargetChoice.statementBalance.rawValue
        )
        XCTAssertEqual(bucket.paymentTargetChoice, .statementBalance)
        XCTAssertEqual(bucket.targetChosenAt, chosenAt)
        XCTAssertNil(bucket.targetStatementIssueDate)

        bucket.paymentTargetChoice = .customAmount
        XCTAssertEqual(
            bucket.paymentTargetChoiceRawValue,
            DebtPayoffLinkedCardPaymentTargetChoice.customAmount.rawValue
        )

        bucket.paymentTargetChoice = nil
        XCTAssertNil(bucket.paymentTargetChoiceRawValue)
    }

    // MARK: - Legacy compatibility

    func testLegacyPlanWithoutProvenanceStaysUnknown() {
        let bucket = DebtPayoffBucket(
            plaidAccountID: "acct-legacy",
            accountName: "Old Card",
            dueDate: Date(),
            paymentTargetAmount: 150,
            debtKind: .linkedCreditCard
        )

        XCTAssertNil(bucket.paymentTargetChoiceRawValue)
        XCTAssertNil(bucket.paymentTargetChoice)
        XCTAssertNil(bucket.targetChosenAt)
        XCTAssertNil(bucket.targetStatementIssueDate)

        let display = DebtPayoffDisplayModel(
            bucket: bucket,
            linkedAccount: nil
        )

        XCTAssertNil(display.targetBasisValue)
    }

    func testUnrecognizedStoredChoiceValueReadsAsUnknown() {
        let bucket = DebtPayoffBucket(
            plaidAccountID: "acct-1",
            accountName: "Amex",
            dueDate: Date(),
            paymentTargetAmount: 150,
            debtKind: .linkedCreditCard
        )
        bucket.paymentTargetChoiceRawValue = "somethingFromTheFuture"

        XCTAssertNil(bucket.paymentTargetChoice)
    }

    func testDisplayModelShowsSavedBasisForLinkedCardOnly() {
        let linked = DebtPayoffBucket(
            plaidAccountID: "acct-1",
            accountName: "Amex",
            dueDate: Date(),
            paymentTargetAmount: 150,
            debtKind: .linkedCreditCard,
            paymentTargetChoice: .statementBalance
        )

        XCTAssertEqual(
            DebtPayoffDisplayModel(bucket: linked, linkedAccount: nil).targetBasisValue,
            "Target: Statement balance"
        )

        let manual = DebtPayoffBucket(
            plaidAccountID: "",
            accountName: "Car Loan",
            dueDate: Date(),
            paymentTargetAmount: 320,
            debtKind: .autoLoan,
            manualCurrentBalance: 9000,
            monthlyPayment: 320
        )

        XCTAssertNil(
            DebtPayoffDisplayModel(bucket: manual, linkedAccount: nil).targetBasisValue
        )
    }

    // MARK: - Choice-aware Suggested Update rules

    /// The Amex trust case: a $150 statement-balance plan must not surface a
    /// target update just because newer spending moved the current balance
    /// to $200.
    func testStatementChoiceIgnoresCurrentBalanceDrift() {
        XCTAssertFalse(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .currentBalance,
                liveAmount: 200,
                storedChoice: .statementBalance,
                currentTarget: 150
            )
        )

        XCTAssertFalse(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .minimumPayment,
                liveAmount: 35,
                storedChoice: .statementBalance,
                currentTarget: 150
            )
        )
    }

    func testStatementChoiceStillSurfacesStatementBalanceChanges() {
        XCTAssertTrue(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .statementBalance,
                liveAmount: 175,
                storedChoice: .statementBalance,
                currentTarget: 150
            )
        )

        XCTAssertFalse(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .statementBalance,
                liveAmount: 150,
                storedChoice: .statementBalance,
                currentTarget: 150
            )
        )
    }

    func testMinimumPaymentChoiceDoesNotSuggestSwitchingBasis() {
        XCTAssertFalse(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .statementBalance,
                liveAmount: 150,
                storedChoice: .minimumPayment,
                currentTarget: 35
            )
        )
        XCTAssertFalse(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .currentBalance,
                liveAmount: 200,
                storedChoice: .minimumPayment,
                currentTarget: 35
            )
        )
        XCTAssertTrue(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .minimumPayment,
                liveAmount: 40,
                storedChoice: .minimumPayment,
                currentTarget: 35
            )
        )
    }

    func testCurrentBalanceChoiceSurfacesCurrentBalanceChanges() {
        XCTAssertTrue(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .currentBalance,
                liveAmount: 200,
                storedChoice: .currentBalance,
                currentTarget: 150
            )
        )

        XCTAssertFalse(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .currentBalance,
                liveAmount: 150,
                storedChoice: .currentBalance,
                currentTarget: 150
            )
        )
    }

    func testCustomChoiceIgnoresAllLiveAmountDrift() {
        for kind: PaymentPlanLiveAmountKind in [
            .statementBalance,
            .minimumPayment,
            .currentBalance
        ] {
            XCTAssertFalse(
                PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                    kind: kind,
                    liveAmount: 500,
                    storedChoice: .customAmount,
                    currentTarget: 100
                )
            )
        }
    }

    func testLegacyPlanKeepsPriorSuggestionBehavior() {
        for kind: PaymentPlanLiveAmountKind in [
            .statementBalance,
            .minimumPayment,
            .currentBalance
        ] {
            XCTAssertTrue(
                PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                    kind: kind,
                    liveAmount: 200,
                    storedChoice: nil,
                    currentTarget: 150
                )
            )

            XCTAssertFalse(
                PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                    kind: kind,
                    liveAmount: 150,
                    storedChoice: nil,
                    currentTarget: 150
                )
            )
        }
    }

    func testMissingOrZeroLiveAmountNeverSuggests() {
        XCTAssertFalse(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .statementBalance,
                liveAmount: nil,
                storedChoice: nil,
                currentTarget: 150
            )
        )
        XCTAssertFalse(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .statementBalance,
                liveAmount: 0,
                storedChoice: .statementBalance,
                currentTarget: 150
            )
        )
    }

    func testMissingTargetStillSurfacesAllowedAmounts() {
        XCTAssertTrue(
            PaymentPlanSuggestedUpdateRules.shouldSuggestTargetUpdate(
                kind: .statementBalance,
                liveAmount: 150,
                storedChoice: .statementBalance,
                currentTarget: nil
            )
        )
    }
}
