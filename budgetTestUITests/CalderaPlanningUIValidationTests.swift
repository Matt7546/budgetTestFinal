import XCTest

final class CalderaPlanningUIValidationTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["CALDERA_DEBUG_LOCAL"] = "1"
        app.launch()
        XCTAssertFalse(
            app.staticTexts["ui-validation-unexpected-request"].exists
        )
    }

    func testOwnerTransitionDismissesOpenEditorAndPreservesEachOwner() {
        signIn(expectedOwner: "ui-user-a")
        assertPersistedSummary(contains: [
            "owner=ui-user-a",
            "bill=A Rent",
            "billAmount=1000.0",
            "billSetAside=200.0",
            "goal=A Emergency",
            "goalAmount=400.0",
            "cushion=300.0",
            "plan=A Card",
            "planSetAside=275.0"
        ])

        app.tabBars.buttons["Set Aside"].tap()
        let aPlan = button(containing: "A Card")
        XCTAssertTrue(aPlan.waitForExistence(timeout: 5))
        aPlan.tap()

        let editorSignOut = app.buttons[
            "ui-validation-normal-sign-out"
        ]
        XCTAssertTrue(editorSignOut.waitForExistence(timeout: 5))
        editorSignOut.tap()

        assertCurrentOwner("signed-out")
        XCTAssertFalse(editorSignOut.exists)

        signIn(expectedOwner: "ui-user-b")
        assertPersistedSummary(contains: [
            "owner=ui-user-b",
            "bill=B Rent",
            "billAmount=300.0",
            "billSetAside=50.0",
            "goal=B Emergency",
            "goalAmount=25.0",
            "cushion=75.0",
            "plan=B Card",
            "planSetAside=100.0"
        ])
        XCTAssertFalse(button(containing: "A Card").exists)

        normalSignOutFromSettings()
        signIn(expectedOwner: "ui-user-a")
        assertPersistedSummary(contains: [
            "owner=ui-user-a",
            "bill=A Rent",
            "billSetAside=200.0",
            "goal=A Emergency",
            "goalAmount=400.0",
            "cushion=300.0",
            "plan=A Card",
            "planSetAside=275.0"
        ])
        assertNoUnexpectedRequest()
    }

    func testPlanAheadModesAndPhysicalHoldUpdateAuthoritativePlan() {
        signIn(expectedOwner: "ui-user-a")

        app.tabBars.buttons["Plan Ahead"].tap()
        XCTAssertTrue(app.navigationBars["Plan Ahead"].waitForExistence(timeout: 5))
        XCTAssertTrue(button(containing: "A Rent").waitForExistence(timeout: 5))
        XCTAssertTrue(button(containing: "A Card").exists)

        app.buttons["Cards"].tap()
        XCTAssertTrue(app.buttons["Cards"].isSelected)
        XCTAssertTrue(button(containing: "A Rent").exists)
        XCTAssertTrue(button(containing: "A Card").exists)

        app.buttons["List"].tap()
        XCTAssertTrue(app.buttons["List"].isSelected)

        app.tabBars.buttons["Set Aside"].tap()
        let plan = button(containing: "A Card")
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        plan.tap()

        let cover = app.buttons["Cover in Full"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        cover.press(forDuration: 1.2)

        let predicate = NSPredicate(
            format: "label CONTAINS %@",
            "planSetAside=900.0"
        )
        expectation(
            for: predicate,
            evaluatedWith: persistedSummary
        )
        waitForExpectations(timeout: 5)

        app.buttons["Cancel Payment Plan updates"].tap()
        app.tabBars.buttons["Plan Ahead"].tap()
        let updatedPlan = button(containing: "A Card")
        XCTAssertTrue(updatedPlan.waitForExistence(timeout: 5))
        XCTAssertTrue(
            updatedPlan.label.contains("$900.00") &&
                updatedPlan.label.contains("Covered"),
            "Expected the updated Plan Ahead row to show the $900 covered allocation; got \(updatedPlan.label)"
        )
        app.buttons["Cards"].tap()
        XCTAssertTrue(app.buttons["Cards"].isSelected)
        XCTAssertTrue(button(containing: "A Card").label.contains("Covered"))
        app.buttons["List"].tap()
        XCTAssertTrue(app.buttons["List"].isSelected)

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].isSelected)
        let updatedSetAside = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "Set Aside, $1,800.00"
            )
        ).firstMatch
        XCTAssertTrue(updatedSetAside.waitForExistence(timeout: 5))
        let updatedPayments = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "Payments, $900.00"
            )
        ).firstMatch
        XCTAssertTrue(updatedPayments.waitForExistence(timeout: 5))
        assertPersistedSummary(contains: [
            "owner=ui-user-a",
            "plan=A Card",
            "planSetAside=900.0"
        ])
        assertNoUnexpectedRequest()
    }

    func testBillAndGoalPhysicalHoldsPropagateAcrossPlanningSurfaces() {
        signIn(expectedOwner: "ui-user-a")

        app.tabBars.buttons["Set Aside"].tap()
        let bill = app.staticTexts["A Rent"]
        XCTAssertTrue(bill.waitForExistence(timeout: 5))
        bill.tap()

        let billCover = app.buttons["Cover in Full"]
        XCTAssertTrue(billCover.waitForExistence(timeout: 5))
        billCover.press(forDuration: 1.2)
        waitForPersistedSummary(containing: "billSetAside=1000.0")
        app.buttons["Cancel Set Aside update"].tap()

        let goal = button(containing: "A Emergency")
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        goal.tap()

        let goalCover = app.buttons["Cover in Full"]
        XCTAssertTrue(goalCover.waitForExistence(timeout: 5))
        goalCover.press(forDuration: 1.2)
        waitForPersistedSummary(containing: "goalAmount=2000.0")

        app.tabBars.buttons["Plan Ahead"].tap()
        let updatedBill = button(containing: "A Rent")
        XCTAssertTrue(updatedBill.waitForExistence(timeout: 5))
        XCTAssertTrue(
            updatedBill.label.contains("$1,000.00") &&
                updatedBill.label.contains("Covered"),
            "Expected Plan Ahead to show the fully covered bill; got \(updatedBill.label)"
        )
        app.buttons["Cards"].tap()
        XCTAssertTrue(app.buttons["Cards"].isSelected)
        XCTAssertTrue(button(containing: "A Rent").label.contains("Covered"))
        app.buttons["List"].tap()
        XCTAssertTrue(app.buttons["List"].isSelected)

        app.tabBars.buttons["Dashboard"].tap()
        let updatedSetAside = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "Set Aside, $3,575.00"
            )
        ).firstMatch
        XCTAssertTrue(updatedSetAside.waitForExistence(timeout: 5))
        let updatedGoal = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "Savings Goal, A Emergency, 100% saved"
            )
        ).firstMatch
        XCTAssertTrue(updatedGoal.waitForExistence(timeout: 5))
        assertPersistedSummary(contains: [
            "owner=ui-user-a",
            "billSetAside=1000.0",
            "goalAmount=2000.0",
            "planSetAside=275.0"
        ])
        assertNoUnexpectedRequest()
    }

    private var persistedSummary: XCUIElement {
        app.staticTexts["ui-validation-persisted-summary"]
    }

    private func signIn(expectedOwner: String) {
        app.tabBars.buttons["More"].tap()
        let button = app.buttons["Use local development sign-in"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        assertCurrentOwner(expectedOwner)
    }

    private func normalSignOutFromSettings() {
        app.tabBars.buttons["More"].tap()
        let signOut = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@",
                "Sign out of"
            )
        ).firstMatch
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        let confirmation = app.sheets.buttons["Sign Out"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        assertCurrentOwner("signed-out")
    }

    private func assertCurrentOwner(_ owner: String) {
        let label = app.staticTexts["ui-validation-current-owner"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "label == %@", owner)
        expectation(for: predicate, evaluatedWith: label)
        waitForExpectations(timeout: 5)
    }

    private func assertPersistedSummary(contains fragments: [String]) {
        XCTAssertTrue(persistedSummary.waitForExistence(timeout: 5))
        for fragment in fragments {
            XCTAssertTrue(
                persistedSummary.label.contains(fragment),
                "Expected persisted summary to contain \(fragment); got \(persistedSummary.label)"
            )
        }
    }

    private func waitForPersistedSummary(containing fragment: String) {
        XCTAssertTrue(persistedSummary.waitForExistence(timeout: 5))
        let predicate = NSPredicate(
            format: "label CONTAINS %@",
            fragment
        )
        expectation(for: predicate, evaluatedWith: persistedSummary)
        waitForExpectations(timeout: 5)
    }


    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", text)
        ).firstMatch
    }

    private func assertNoUnexpectedRequest() {
        XCTAssertFalse(
            app.staticTexts["ui-validation-unexpected-request"].exists
        )
    }
}
