import XCTest
import SwiftData
@testable import Caldera_Money

@MainActor
final class PaymentPlanCycleTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCycleIdentityAndActiveUniqueness() {
        let bucket = paymentPlan(dueDate: date(2026, 7, 31))
        let first = PaymentPlanCycleStore.makeActiveCycle(
            for: bucket,
            dueDate: bucket.dueDate,
            targetAmount: 250,
            existingCycles: [],
            calendar: calendar
        )

        let cycle = try! XCTUnwrap(first)
        let duplicate = PaymentPlanCycleStore.makeActiveCycle(
            for: bucket,
            dueDate: bucket.dueDate,
            targetAmount: 250,
            existingCycles: [cycle],
            calendar: calendar
        )

        XCTAssertNil(duplicate)
        XCTAssertEqual(cycle.paymentPlanID, bucket.id)
        XCTAssertEqual(cycle.status, .active)
        XCTAssertEqual(cycle.frozenTargetAmount, 250, accuracy: 0.001)
    }

    func testNewPlanSaveFoundationCreatesOneActiveCycle() throws {
        let bucket = paymentPlan(dueDate: date(2026, 8, 15))
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DebtPayoffBucket.self,
            PaymentPlanCycle.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        context.insert(bucket)

        let cycle = try XCTUnwrap(
            PaymentPlanCycleStore.makeActiveCycle(
                for: bucket,
                dueDate: bucket.dueDate,
                targetAmount: bucket.paymentTargetAmount,
                existingCycles: [],
                calendar: calendar
            )
        )
        context.insert(cycle)
        try context.save()

        let cycles = try context.fetch(FetchDescriptor<PaymentPlanCycle>())
        XCTAssertEqual(cycles.count, 1)
        XCTAssertTrue(cycles[0].isActive)
    }

    func testLegacyPlanRemainsVisibleWithoutCreatingCycle() {
        let legacy = paymentPlan(dueDate: date(2026, 8, 15))
        let cycles: [PaymentPlanCycle] = []

        XCTAssertNil(
            PaymentPlanCycleStore.activeCycle(
                for: legacy.id,
                in: cycles
            )
        )
        XCTAssertTrue(
            PaymentPlanCycleStore.isActiveOrLegacy(
                paymentPlanID: legacy.id,
                cycles: cycles
            )
        )
        XCTAssertEqual(legacy.paymentTargetAmount, 250, accuracy: 0.001)
        XCTAssertEqual(legacy.protectedAmount, 125, accuracy: 0.001)
    }

    func testHandledCycleReleasesSetAsideAndUndoRestoresExactly() {
        let bucket = paymentPlan(dueDate: date(2026, 7, 31))
        let originalUpdatedAt = bucket.updatedAt
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: bucket.paymentTargetAmount,
            calendar: calendar
        )
        let cycleUpdatedAt = cycle.updatedAt

        let undo = PaymentPlanCycleResolutionMutation.apply(
            .paid,
            to: cycle,
            bucket: bucket,
            handledAt: date(2026, 7, 31)
        )

        XCTAssertEqual(cycle.status, .handled)
        XCTAssertEqual(cycle.resolution, .paid)
        XCTAssertEqual(cycle.releasedSetAsideAmount, 125, accuracy: 0.001)
        XCTAssertEqual(bucket.protectedAmount, 0, accuracy: 0.001)
        XCTAssertEqual([bucket].totalProtectedAmount, 0, accuracy: 0.001)

        undo?.restore()

        XCTAssertEqual(cycle.status, .active)
        XCTAssertNil(cycle.resolution)
        XCTAssertNil(cycle.handledAt)
        XCTAssertEqual(cycle.releasedSetAsideAmount, 0, accuracy: 0.001)
        XCTAssertEqual(cycle.updatedAt, cycleUpdatedAt)
        XCTAssertEqual(bucket.protectedAmount, 125, accuracy: 0.001)
        XCTAssertEqual(bucket.updatedAt, originalUpdatedAt)
        XCTAssertEqual([bucket].totalProtectedAmount, 125, accuracy: 0.001)
    }

    func testHandledCycleNoLongerAppearsActiveOrPastDue() {
        let bucket = paymentPlan(dueDate: date(2026, 7, 1))
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            frozenTargetAmount: bucket.paymentTargetAmount,
            status: .handled,
            resolution: .paid,
            handledAt: date(2026, 7, 2),
            calendar: calendar
        )

        XCTAssertNil(
            PaymentPlanCycleStore.activeCycle(
                for: bucket.id,
                in: [cycle]
            )
        )
        XCTAssertFalse(
            PaymentPlanCycleStore.isActiveOrLegacy(
                paymentPlanID: bucket.id,
                cycles: [cycle]
            )
        )
    }

    func testPlanNextPaymentCreatesOneCycleOnlyWhenSaved() {
        let bucket = paymentPlan(dueDate: date(2026, 1, 31))
        let handled = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: bucket.dueDate,
            dueDayAnchor: 31,
            frozenTargetAmount: bucket.paymentTargetAmount,
            status: .handled,
            resolution: .paid,
            handledAt: date(2026, 2, 1),
            calendar: calendar
        )
        let suggestedDueDate = PaymentPlanCycleSchedule.nextMonthlyDueDate(
            after: handled.dueDate,
            anchorDay: handled.dueDayAnchor,
            calendar: calendar
        )

        XCTAssertEqual([handled].count, 1)

        let next = PaymentPlanCycleStore.makeActiveCycle(
            for: bucket,
            dueDate: suggestedDueDate,
            targetAmount: bucket.paymentTargetAmount,
            dueDayAnchor: handled.dueDayAnchor,
            existingCycles: [handled],
            calendar: calendar
        )
        let nextCycle = try! XCTUnwrap(next)
        let duplicate = PaymentPlanCycleStore.makeActiveCycle(
            for: bucket,
            dueDate: suggestedDueDate,
            targetAmount: bucket.paymentTargetAmount,
            dueDayAnchor: handled.dueDayAnchor,
            existingCycles: [handled, nextCycle],
            calendar: calendar
        )

        XCTAssertTrue(nextCycle.isActive)
        XCTAssertNil(duplicate)
    }

    func testMonthEndSchedulePreservesAnchorDay() {
        let january31 = date(2026, 1, 31)
        let february = PaymentPlanCycleSchedule.nextMonthlyDueDate(
            after: january31,
            anchorDay: 31,
            calendar: calendar
        )
        let march = PaymentPlanCycleSchedule.nextMonthlyDueDate(
            after: february,
            anchorDay: 31,
            calendar: calendar
        )

        XCTAssertEqual(dateKey(february), "2026-02-28")
        XCTAssertEqual(dateKey(march), "2026-03-31")
    }

    func testManualAndLinkedPlansRetainTheirExistingIdentityAndProvenance() {
        let linked = paymentPlan(
            plaidAccountID: "card-1",
            dueDate: date(2026, 8, 15),
            kind: .linkedCreditCard,
            choice: .statementBalance
        )
        let manual = paymentPlan(
            plaidAccountID: "",
            dueDate: date(2026, 8, 20),
            kind: .other
        )

        let linkedCycle = PaymentPlanCycleStore.makeActiveCycle(
            for: linked,
            dueDate: linked.dueDate,
            targetAmount: linked.paymentTargetAmount,
            existingCycles: [],
            calendar: calendar
        )
        let manualCycle = PaymentPlanCycleStore.makeActiveCycle(
            for: manual,
            dueDate: manual.dueDate,
            targetAmount: manual.paymentTargetAmount,
            existingCycles: [],
            calendar: calendar
        )

        XCTAssertNotNil(linkedCycle)
        XCTAssertNotNil(manualCycle)
        XCTAssertEqual(linked.paymentTargetChoice, .statementBalance)
        XCTAssertEqual(linked.plaidAccountID, "card-1")
        XCTAssertEqual(manual.debtKind, .other)
        XCTAssertTrue(manual.plaidAccountID.isEmpty)
    }

    // MARK: - Review-first card payment detection

    func testExactPostedPaymentProducesHighConfidenceCandidate() throws {
        let bucket = linkedPaymentPlanForDetection()
        let cycle = activeDetectionCycle(for: bucket)
        let candidate = PaymentPlanPaymentDetector.candidate(
            for: bucket,
            cycle: cycle,
            transactions: [
                transaction(
                    id: "payment-1",
                    name: "AUTOMATIC PAYMENT - THANK YOU",
                    amount: -250,
                    date: "2026-07-15",
                    accountID: "card-1"
                )
            ],
            cardDetails: nil,
            dataIsEligible: true,
            calendar: calendar
        )

        let unwrapped = try XCTUnwrap(candidate)
        XCTAssertEqual(unwrapped.transactionID, "payment-1")
        XCTAssertEqual(unwrapped.amount, 250, accuracy: 0.001)
        XCTAssertFalse(unwrapped.isCorroboratedByCardDetails)
    }

    func testWrongAmountDoesNotProduceCandidate() {
        let bucket = linkedPaymentPlanForDetection()
        let cycle = activeDetectionCycle(for: bucket)

        XCTAssertNil(
            PaymentPlanPaymentDetector.candidate(
                for: bucket,
                cycle: cycle,
                transactions: [
                    transaction(
                        name: "CARD PAYMENT",
                        amount: -249.98,
                        date: "2026-07-15",
                        accountID: "card-1"
                    )
                ],
                cardDetails: nil,
                dataIsEligible: true,
                calendar: calendar
            )
        )
    }

    func testCorrectAmountOnWrongCardDoesNotProduceCandidate() {
        let bucket = linkedPaymentPlanForDetection()
        let cycle = activeDetectionCycle(for: bucket)

        XCTAssertNil(
            PaymentPlanPaymentDetector.candidate(
                for: bucket,
                cycle: cycle,
                transactions: [
                    transaction(
                        name: "CARD PAYMENT",
                        amount: -250,
                        date: "2026-07-15",
                        accountID: "card-2"
                    )
                ],
                cardDetails: nil,
                dataIsEligible: true,
                calendar: calendar
            )
        )
    }

    func testRefundCreditAndPositiveOutflowShapesAreRejected() {
        let bucket = linkedPaymentPlanForDetection()
        let cycle = activeDetectionCycle(for: bucket)
        let rejectedTransactions = [
            transaction(
                id: "refund",
                name: "PAYMENT REFUND",
                amount: -250,
                date: "2026-07-15",
                accountID: "card-1"
            ),
            transaction(
                id: "credit",
                name: "STATEMENT CREDIT",
                amount: -250,
                date: "2026-07-15",
                accountID: "card-1"
            ),
            transaction(
                id: "outflow",
                name: "CARD PAYMENT",
                amount: 250,
                date: "2026-07-15",
                accountID: "card-1"
            ),
        ]

        XCTAssertNil(
            PaymentPlanPaymentDetector.candidate(
                for: bucket,
                cycle: cycle,
                transactions: rejectedTransactions,
                cardDetails: nil,
                dataIsEligible: true,
                calendar: calendar
            )
        )
    }

    func testPendingOrUnknownPostingStateIsRejected() {
        let bucket = linkedPaymentPlanForDetection()
        let cycle = activeDetectionCycle(for: bucket)

        for pending in [true, nil] as [Bool?] {
            XCTAssertNil(
                PaymentPlanPaymentDetector.candidate(
                    for: bucket,
                    cycle: cycle,
                    transactions: [
                        transaction(
                            name: "CARD PAYMENT",
                            amount: -250,
                            date: "2026-07-15",
                            accountID: "card-1",
                            pending: pending
                        )
                    ],
                    cardDetails: nil,
                    dataIsEligible: true,
                    calendar: calendar
                )
            )
        }
    }

    func testTransactionPendingStateDecodesPresentAndAbsent() throws {
        let decoder = JSONDecoder()
        let posted = try decoder.decode(
            PlaidTransaction.self,
            from: Data(
                #"{"transaction_id":"posted","name":"CARD PAYMENT","amount":-250,"date":"2026-07-15","pending":false,"account_id":"card-1"}"#.utf8
            )
        )
        let pending = try decoder.decode(
            PlaidTransaction.self,
            from: Data(
                #"{"transaction_id":"pending","name":"CARD PAYMENT","amount":-250,"date":"2026-07-15","pending":true,"account_id":"card-1"}"#.utf8
            )
        )
        let legacyCached = try decoder.decode(
            PlaidTransaction.self,
            from: Data(
                #"{"transaction_id":"legacy","name":"CARD PAYMENT","amount":-250,"date":"2026-07-15","account_id":"card-1"}"#.utf8
            )
        )

        XCTAssertEqual(posted.pending, false)
        XCTAssertEqual(pending.pending, true)
        XCTAssertNil(legacyCached.pending)
    }

    func testTransactionOutsideCycleWindowDoesNotProduceCandidate() {
        let bucket = linkedPaymentPlanForDetection()
        let cycle = activeDetectionCycle(for: bucket)

        XCTAssertNil(
            PaymentPlanPaymentDetector.candidate(
                for: bucket,
                cycle: cycle,
                transactions: [
                    transaction(
                        name: "CARD PAYMENT",
                        amount: -250,
                        date: "2026-07-05",
                        accountID: "card-1"
                    )
                ],
                cardDetails: nil,
                dataIsEligible: true,
                calendar: calendar
            )
        )
    }

    func testOnlyFullyUpdatedManualTransactionDataIsEligible() {
        let refreshedAt = date(2026, 7, 16)

        XCTAssertTrue(
            PaymentPlanPaymentDetectionEligibility.canEvaluate(
                backendTransactionsEnabled: true,
                transactionState: .updated,
                hasUsableTransactions: true,
                lastSuccessfulTransactionRefresh: refreshedAt,
                lastSuccessfulManualTransactionRefresh: refreshedAt
            )
        )

        for state: BankSyncResourceState in [
            .partiallyUpdated,
            .showingEarlierData,
            .unavailable,
            .rateLimited,
            .disabled,
        ] {
            XCTAssertFalse(
                PaymentPlanPaymentDetectionEligibility.canEvaluate(
                    backendTransactionsEnabled: true,
                    transactionState: state,
                    hasUsableTransactions: true,
                    lastSuccessfulTransactionRefresh: refreshedAt,
                    lastSuccessfulManualTransactionRefresh: refreshedAt
                )
            )
        }

        XCTAssertFalse(
            PaymentPlanPaymentDetectionEligibility.canEvaluate(
                backendTransactionsEnabled: false,
                transactionState: .updated,
                hasUsableTransactions: true,
                lastSuccessfulTransactionRefresh: refreshedAt,
                lastSuccessfulManualTransactionRefresh: refreshedAt
            )
        )
        XCTAssertFalse(
            PaymentPlanPaymentDetectionEligibility.canEvaluate(
                backendTransactionsEnabled: true,
                transactionState: .updated,
                hasUsableTransactions: true,
                lastSuccessfulTransactionRefresh: refreshedAt,
                lastSuccessfulManualTransactionRefresh: nil
            )
        )
        XCTAssertFalse(
            PaymentPlanPaymentDetectionEligibility.canEvaluate(
                backendTransactionsEnabled: true,
                transactionState: .updated,
                hasUsableTransactions: true,
                lastSuccessfulTransactionRefresh: refreshedAt.addingTimeInterval(0.5),
                lastSuccessfulManualTransactionRefresh: refreshedAt
            )
        )
    }

    func testHandledCycleNeverProducesCandidate() {
        let bucket = linkedPaymentPlanForDetection()
        let cycle = PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: date(2026, 7, 20),
            frozenTargetAmount: 250,
            status: .handled,
            resolution: .paid,
            handledAt: date(2026, 7, 16),
            createdAt: date(2026, 7, 1),
            calendar: calendar
        )

        XCTAssertNil(
            PaymentPlanPaymentDetector.candidate(
                for: bucket,
                cycle: cycle,
                transactions: [
                    transaction(
                        name: "CARD PAYMENT",
                        amount: -250,
                        date: "2026-07-15",
                        accountID: "card-1"
                    )
                ],
                cardDetails: nil,
                dataIsEligible: true,
                calendar: calendar
            )
        )
    }

    func testLastPaymentDetailsOnlyCorroborateTransactionCandidate() throws {
        let bucket = linkedPaymentPlanForDetection()
        let cycle = activeDetectionCycle(for: bucket)
        let cardDetails = try JSONDecoder().decode(
            LinkedCardPaymentDetails.self,
            from: Data(
                #"{"account_id":"card-1","last_payment_amount":250,"last_payment_date":"2026-07-15"}"#.utf8
            )
        )

        let candidate = PaymentPlanPaymentDetector.candidate(
            for: bucket,
            cycle: cycle,
            transactions: [
                transaction(
                    name: "CARD PAYMENT",
                    amount: -250,
                    date: "2026-07-15",
                    accountID: "card-1"
                )
            ],
            cardDetails: cardDetails,
            dataIsEligible: true,
            calendar: calendar
        )

        XCTAssertTrue(try XCTUnwrap(candidate).isCorroboratedByCardDetails)

        XCTAssertNil(
            PaymentPlanPaymentDetector.candidate(
                for: bucket,
                cycle: cycle,
                transactions: [],
                cardDetails: cardDetails,
                dataIsEligible: true,
                calendar: calendar
            )
        )
    }

    func testDetectionDoesNotMutateCycleOrSetAside() {
        let bucket = linkedPaymentPlanForDetection()
        let cycle = activeDetectionCycle(for: bucket)
        let originalStatus = cycle.statusRawValue
        let originalSetAside = bucket.protectedAmount

        _ = PaymentPlanPaymentDetector.candidate(
            for: bucket,
            cycle: cycle,
            transactions: [
                transaction(
                    name: "CARD PAYMENT",
                    amount: -250,
                    date: "2026-07-15",
                    accountID: "card-1"
                )
            ],
            cardDetails: nil,
            dataIsEligible: true,
            calendar: calendar
        )

        XCTAssertEqual(cycle.statusRawValue, originalStatus)
        XCTAssertEqual(bucket.protectedAmount, originalSetAside, accuracy: 0.001)
        XCTAssertTrue(cycle.isActive)
        XCTAssertNil(cycle.resolution)
    }

    func testAmbiguousMatchingTransactionsProduceNoCandidate() {
        let bucket = linkedPaymentPlanForDetection()
        let cycle = activeDetectionCycle(for: bucket)
        let matches = [
            transaction(
                id: "payment-1",
                name: "CARD PAYMENT",
                amount: -250,
                date: "2026-07-14",
                accountID: "card-1"
            ),
            transaction(
                id: "payment-2",
                name: "ONLINE PAYMENT",
                amount: -250,
                date: "2026-07-15",
                accountID: "card-1"
            ),
        ]

        XCTAssertNil(
            PaymentPlanPaymentDetector.candidate(
                for: bucket,
                cycle: cycle,
                transactions: matches,
                cardDetails: nil,
                dataIsEligible: true,
                calendar: calendar
            )
        )
    }

    private func linkedPaymentPlanForDetection() -> DebtPayoffBucket {
        paymentPlan(
            plaidAccountID: "card-1",
            dueDate: date(2026, 7, 20),
            kind: .linkedCreditCard,
            choice: .statementBalance
        )
    }

    private func activeDetectionCycle(
        for bucket: DebtPayoffBucket
    ) -> PaymentPlanCycle {
        PaymentPlanCycle(
            paymentPlanID: bucket.id,
            dueDate: date(2026, 7, 20),
            frozenTargetAmount: 250,
            createdAt: date(2026, 7, 1),
            calendar: calendar
        )
    }

    private func transaction(
        id: String = UUID().uuidString,
        name: String,
        amount: Double,
        date: String,
        accountID: String,
        pending: Bool? = false
    ) -> PlaidTransaction {
        PlaidTransaction(
            transaction_id: id,
            name: name,
            amount: amount,
            date: date,
            pending: pending,
            account_id: accountID
        )
    }

    private func paymentPlan(
        plaidAccountID: String = "",
        dueDate: Date,
        kind: DebtPayoffKind = .other,
        choice: DebtPayoffLinkedCardPaymentTargetChoice? = nil
    ) -> DebtPayoffBucket {
        DebtPayoffBucket(
            plaidAccountID: plaidAccountID,
            accountName: plaidAccountID.isEmpty ? "Manual payment" : "Linked card",
            dueDate: dueDate,
            paymentTargetAmount: 250,
            protectedAmount: 125,
            debtKind: kind,
            paymentTargetChoice: choice,
            manualCurrentBalance: plaidAccountID.isEmpty ? 1_000 : nil,
            monthlyPayment: kind == .other ? 250 : nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dateKey(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
