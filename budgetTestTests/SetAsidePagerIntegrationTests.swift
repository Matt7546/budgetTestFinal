import XCTest
@testable import Caldera_Money

final class SetAsidePagerIntegrationTests: XCTestCase {

    func testFeatureFlagDefaultsToLegacyExperience() {
        XCTAssertEqual(
            SetAsidePagerFeature.experience(storedValue: false),
            .legacy
        )
    }

    func testFeatureFlagEnablesPagerWithoutReplacingLegacyPath() {
        XCTAssertEqual(
            SetAsidePagerFeature.experience(storedValue: true),
            .pager
        )
        XCTAssertEqual(
            SetAsidePagerFeature.experience(storedValue: false),
            .legacy
        )
    }

    func testFeatureFlagStorageKeyRemainsStable() {
        XCTAssertEqual(
            SetAsidePagerFeature.storageKey,
            "caldera.setAside.pager.enabled"
        )
    }

    func testCashCushionRoutesPreserveExistingAddAndUseModes() {
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(.addCashCushion),
            .adjustCashCushion(.add)
        )
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(.useCashCushion),
            .adjustCashCushion(.use)
        )
    }

    func testSavingsGoalRoutesPreserveCreateSeeAllAndExactGoal() {
        let goalID = UUID()

        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(.createSavingsGoal),
            .createSavingsGoal
        )
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(.seeAllSavingsGoals),
            .seeAllSavingsGoals
        )
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(
                .contributeToSavingsGoal(goalID: goalID)
            ),
            .editSavingsGoal(goalID: goalID)
        )
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(
                .updateSavingsGoal(goalID: goalID)
            ),
            .editSavingsGoal(goalID: goalID)
        )
    }

    func testPaymentRoutesPreserveModernAndLegacyEditorsAndCycleIdentity() {
        let modernBucketID = UUID()
        let activeCycleID = UUID()
        let legacyBucketID = UUID()

        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(
                .contributeToPaymentPlan(
                    bucketID: modernBucketID,
                    cycleID: activeCycleID,
                    editor: .modernCard
                )
            ),
            .editPaymentPlan(
                bucketID: modernBucketID,
                cycleID: activeCycleID,
                editor: .modernCard
            )
        )
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(
                .updatePaymentPlan(
                    bucketID: legacyBucketID,
                    cycleID: nil,
                    editor: .legacyDebt
                )
            ),
            .editPaymentPlan(
                bucketID: legacyBucketID,
                cycleID: nil,
                editor: .legacyDebt
            )
        )
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(.createPaymentPlan),
            .createPaymentPlan
        )
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(.seeAllPaymentPlans),
            .seeAllPaymentPlans
        )
    }

    func testUpcomingRoutePreservesExactOccurrenceIdentity() {
        let eventID = UUID()
        let occurrenceID = "event|2026-08-14"

        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(
                .contributeToUpcomingExpense(
                    eventID: eventID,
                    occurrenceID: occurrenceID
                )
            ),
            .editUpcomingExpense(
                eventID: eventID,
                occurrenceID: occurrenceID
            )
        )
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(
                .updateUpcomingExpense(
                    eventID: eventID,
                    occurrenceID: occurrenceID
                )
            ),
            .editUpcomingExpense(
                eventID: eventID,
                occurrenceID: occurrenceID
            )
        )
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(.createUpcomingExpense),
            .createUpcomingExpense
        )
        XCTAssertEqual(
            SetAsidePagerRouteResolver.resolve(.seeAllUpcomingExpenses),
            .seeAllUpcomingExpenses
        )
    }

    func testPagerSupportsIntentionalInitialSections() {
        XCTAssertEqual(
            SetAsidePagerSection.defaultSelection,
            .savingsGoals
        )
        XCTAssertEqual(
            SetAsidePagerSection.allCases,
            [.upcomingExpenses, .paymentPlans, .savingsGoals]
        )
    }
}
