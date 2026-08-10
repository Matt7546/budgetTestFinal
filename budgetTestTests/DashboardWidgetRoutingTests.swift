import XCTest
@testable import Caldera_Money

@MainActor
final class DashboardWidgetRoutingTests: XCTestCase {

    func testSavingsGoalActionPreservesGoalIdentity() {
        let goalID = UUID()
        let snapshot = makeSnapshot(
            kind: .savingsGoal,
            destination: .savingsGoal(goalID)
        )

        XCTAssertEqual(
            DashboardWidgetActionResolver.parentAction(for: snapshot),
            .openSavingsGoal(goalID)
        )
    }

    func testUpcomingExpenseChildActionPreservesOccurrenceIdentity() {
        let eventID = UUID()
        let occurrenceID = "\(eventID.uuidString)_2026-08-14"
        let item = makeItem(
            destination: .upcomingExpense(
                eventID: eventID,
                occurrenceID: occurrenceID
            )
        )
        let snapshot = makeSnapshot(
            kind: .upcomingExpenses,
            destination: .planAhead,
            items: [item]
        )

        XCTAssertEqual(
            DashboardWidgetActionResolver.childAction(
                for: item,
                in: snapshot
            ),
            .openUpcomingExpense(
                eventID: eventID,
                occurrenceID: occurrenceID
            )
        )
    }

    func testPaymentPlanChildActionPreservesBucketAndCycleIdentity() {
        let bucketID = UUID()
        let cycleID = UUID()
        let item = makeItem(
            destination: .paymentPlan(
                bucketID: bucketID,
                cycleID: cycleID
            )
        )
        let snapshot = makeSnapshot(
            kind: .paymentPlans,
            destination: .setAside,
            items: [item]
        )

        XCTAssertEqual(
            DashboardWidgetActionResolver.childAction(
                for: item,
                in: snapshot
            ),
            .openPaymentPlan(
                bucketID: bucketID,
                cycleID: cycleID
            )
        )
    }

    func testLegacyOtherDebtUsesFallbackEditorRoute() {
        let bucket = DebtPayoffBucket(
            plaidAccountID: "",
            accountName: "Other Debt",
            dueDate: Date(),
            paymentTargetAmount: 200,
            debtKind: .other
        )
        let cycleID = UUID()
        let action = DashboardWidgetAction.openPaymentPlan(
            bucketID: bucket.id,
            cycleID: cycleID
        )

        XCTAssertEqual(
            DashboardWidgetActionResolver.paymentPlanEditorRoute(
                for: action,
                in: [bucket]
            ),
            .legacy(bucketID: bucket.id, cycleID: cycleID)
        )
    }

    func testLinkedCardUsesModernPaymentPlanEditorRoute() {
        let bucket = DebtPayoffBucket(
            plaidAccountID: "card-1",
            accountName: "Amex Gold",
            dueDate: Date(),
            paymentTargetAmount: 384,
            debtKind: .linkedCreditCard
        )
        let action = DashboardWidgetAction.openPaymentPlan(
            bucketID: bucket.id,
            cycleID: nil
        )

        XCTAssertEqual(
            DashboardWidgetActionResolver.paymentPlanEditorRoute(
                for: action,
                in: [bucket]
            ),
            .modern(bucketID: bucket.id, cycleID: nil)
        )
    }

    func testReviewUpdatesRequiresAtLeastOneItem() {
        let empty = makeSnapshot(
            kind: .reviewUpdates,
            destination: .reviewUpdates
        )
        let populated = makeSnapshot(
            kind: .reviewUpdates,
            destination: .reviewUpdates,
            items: [makeItem(destination: .reviewUpdates)]
        )

        XCTAssertNil(
            DashboardWidgetActionResolver.parentAction(for: empty)
        )
        XCTAssertEqual(
            DashboardWidgetActionResolver.parentAction(for: populated),
            .openReviewUpdates
        )
    }

    func testHiddenWidgetDoesNotCreateParentOrChildActions() {
        let item = makeItem(
            destination: .upcomingExpense(
                eventID: UUID(),
                occurrenceID: "hidden-occurrence"
            )
        )
        let snapshot = makeSnapshot(
            kind: .upcomingExpenses,
            destination: .planAhead,
            state: .hidden,
            items: [item]
        )

        XCTAssertNil(
            DashboardWidgetActionResolver.parentAction(for: snapshot)
        )
        XCTAssertNil(
            DashboardWidgetActionResolver.childAction(
                for: item,
                in: snapshot
            )
        )
    }

    func testZeroTargetItemDoesNotCreateInvisibleChildAction() {
        let item = DashboardWidgetItemSnapshot(
            id: "zero-target",
            title: "No target",
            context: "Context",
            primaryValue: "$0",
            secondaryValue: nil,
            progress: 0,
            targetAmount: 0,
            setAsideAmount: 0,
            destination: .paymentPlan(
                bucketID: UUID(),
                cycleID: nil
            ),
            accessibilityLabel: "No target"
        )
        let snapshot = makeSnapshot(
            kind: .paymentPlans,
            destination: .setAside,
            items: [item]
        )

        XCTAssertNil(
            DashboardWidgetActionResolver.childAction(
                for: item,
                in: snapshot
            )
        )
        XCTAssertEqual(
            DashboardWidgetActionResolver.parentAction(for: snapshot),
            .openSetAside
        )
    }

    func testBroadWidgetDestinationsRemainAvailable() {
        XCTAssertEqual(
            DashboardWidgetActionResolver.parentAction(
                for: makeSnapshot(
                    kind: .setAside,
                    destination: .setAside
                )
            ),
            .openSetAside
        )
        XCTAssertEqual(
            DashboardWidgetActionResolver.parentAction(
                for: makeSnapshot(
                    kind: .bankSync,
                    destination: .bankSync
                )
            ),
            .openBankSync
        )
        XCTAssertEqual(
            DashboardWidgetActionResolver.parentAction(
                for: makeSnapshot(
                    kind: .planAhead,
                    destination: .planAhead
                )
            ),
            .openPlanAhead
        )
    }

    func testAppNavigationPreservesExactWidgetRequests() {
        let navigation = AppNavigation()
        let goalID = UUID()
        let eventID = UUID()
        let bucketID = UUID()
        let cycleID = UUID()

        navigation.openSavingsEditGoal(goalID)
        XCTAssertEqual(navigation.selectedTab, 1)
        XCTAssertEqual(navigation.savingsGoalToEditID, goalID)

        navigation.openTimelineEditUpcomingExpense(
            eventID: eventID,
            occurrenceID: "occurrence-1"
        )
        XCTAssertEqual(navigation.selectedTab, 2)
        XCTAssertEqual(
            navigation.upcomingExpenseToEditRequest,
            UpcomingExpenseEditNavigationRequest(
                eventID: eventID,
                occurrenceID: "occurrence-1"
            )
        )

        navigation.openSavingsEditDebtPayoff(
            bucketID,
            cycleID: cycleID
        )
        XCTAssertEqual(navigation.selectedTab, 1)
        XCTAssertEqual(navigation.debtPayoffToEditID, bucketID)
        XCTAssertEqual(navigation.debtPayoffCycleToEditID, cycleID)

        navigation.openReviewUpdates()
        XCTAssertEqual(navigation.selectedTab, 2)
        XCTAssertTrue(navigation.shouldOpenReviewUpdates)
    }

    private func makeSnapshot(
        kind: DashboardWidgetKind,
        destination: DashboardWidgetDestinationIdentity?,
        state: DashboardWidgetContentState = .content,
        items: [DashboardWidgetItemSnapshot] = []
    ) -> DashboardWidgetSnapshot {
        DashboardWidgetSnapshot(
            kind: kind,
            title: kind.rawValue,
            subtitle: "Context",
            primaryValue: "$100",
            secondaryValue: nil,
            status: nil,
            progress: nil,
            categoryRole: .bankAccount,
            destination: destination,
            contentState: state,
            items: items,
            accessibilityLabel: kind.rawValue
        )
    }

    private func makeItem(
        destination: DashboardWidgetDestinationIdentity?
    ) -> DashboardWidgetItemSnapshot {
        DashboardWidgetItemSnapshot(
            id: UUID().uuidString,
            title: "Item",
            context: "Context",
            primaryValue: "$100",
            secondaryValue: nil,
            progress: 0.5,
            targetAmount: 100,
            setAsideAmount: 50,
            destination: destination,
            accessibilityLabel: "Item"
        )
    }
}
