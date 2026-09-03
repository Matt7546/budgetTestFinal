import XCTest
@testable import Caldera_Money

@MainActor
final class DashboardNextActionPresentationTests: XCTestCase {

    func testExpandedPresentationShowsFullMessageAndAction() {
        let presentation = DashboardNextActionPresentation.make(
            for: .paymentPlanNeedsMoney,
            isCollapsed: false
        )

        XCTAssertFalse(presentation.isCollapsed)
        XCTAssertTrue(presentation.showsExpandedMessage)
        XCTAssertTrue(presentation.showsPrimaryAction)
        XCTAssertEqual(presentation.toggleTitle, "Collapse")
        XCTAssertEqual(presentation.toggleSystemImage, "chevron.up")
    }

    func testCollapsedPresentationHidesLongMessageAndKeepsAction() {
        let presentation = DashboardNextActionPresentation.make(
            for: .paymentPlanNeedsMoney,
            isCollapsed: true
        )

        XCTAssertTrue(presentation.isCollapsed)
        XCTAssertFalse(presentation.showsExpandedMessage)
        XCTAssertTrue(presentation.showsPrimaryAction)
        XCTAssertEqual(presentation.toggleTitle, "Show")
        XCTAssertEqual(presentation.toggleSystemImage, "chevron.down")
        XCTAssertEqual(
            presentation.compactMessage,
            "1 Payment Plan needs set aside."
        )
    }

    func testPrimaryActionTitleIsUnchangedAcrossPresentationStates() {
        let action = DashboardNextAction.paymentPlanNeedsMoney
        let expanded = DashboardNextActionPresentation.make(
            for: action,
            isCollapsed: false
        )
        let collapsed = DashboardNextActionPresentation.make(
            for: action,
            isCollapsed: true
        )

        XCTAssertEqual(action.actionTitle, "Open Set Aside")
        XCTAssertTrue(expanded.showsPrimaryAction)
        XCTAssertTrue(collapsed.showsPrimaryAction)
    }

    func testPaymentPlanNextActionRoutesToSetAsidePayments() {
        let navigation = AppNavigation()
        let action = DashboardNextAction.paymentPlanNeedsMoney
        let section = action.setAsideSectionDestination

        XCTAssertEqual(section, .paymentPlans)

        guard let section else {
            return XCTFail("Expected a Payment Plans destination")
        }

        navigation.openSavings(section: section)

        XCTAssertEqual(navigation.selectedTab, 1)
        XCTAssertEqual(navigation.setAsideSectionToOpen, .paymentPlans)
    }

    func testAllClearStateDoesNotCreateFakePrimaryAction() {
        let expanded = DashboardNextActionPresentation.make(
            for: .allClear,
            isCollapsed: false
        )
        let collapsed = DashboardNextActionPresentation.make(
            for: .allClear,
            isCollapsed: true
        )

        XCTAssertFalse(expanded.showsPrimaryAction)
        XCTAssertFalse(collapsed.showsPrimaryAction)
        XCTAssertEqual(
            collapsed.compactMessage,
            "Planned expenses are covered."
        )
    }

    func testCollapsePreferenceRoundTripsThroughUserDefaults() {
        let suiteName = "DashboardNextActionPresentationTests.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Expected isolated UserDefaults suite")
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(
            true,
            forKey: DashboardNextActionCollapsePreference.storageKey
        )

        XCTAssertTrue(
            defaults.bool(
                forKey: DashboardNextActionCollapsePreference.storageKey
            )
        )
    }
}
