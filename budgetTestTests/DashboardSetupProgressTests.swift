import XCTest
@testable import Caldera_Money

@MainActor
final class DashboardSetupProgressTests: XCTestCase {

    func testSignedInNewUserStartsWithDownloadAndSignInComplete() {
        let progress = DashboardSetupProgress(
            isSignedIn: true,
            hasLinkedBanks: false,
            hasConfiguredSpendingAccounts: false,
            hasSetAsideItem: false,
            hasPlanItem: false
        )

        XCTAssertEqual(progress.completedCount, 2)
        XCTAssertEqual(progress.totalCount, 6)
        XCTAssertEqual(progress.nextIncompleteItem?.step, .connectBank)
        XCTAssertEqual(
            progress.nextIncompleteItem?.step.nextMessage,
            "Next: Connect your bank"
        )
    }

    func testDownloadIsAlwaysCompleteAndSignInReflectsAuthentication() {
        let signedOutProgress = DashboardSetupProgress(
            isSignedIn: false,
            hasLinkedBanks: false,
            hasConfiguredSpendingAccounts: false,
            hasSetAsideItem: false,
            hasPlanItem: false
        )

        XCTAssertTrue(signedOutProgress.items[0].isComplete)
        XCTAssertFalse(signedOutProgress.items[1].isComplete)
        XCTAssertEqual(signedOutProgress.completedCount, 1)
        XCTAssertEqual(signedOutProgress.nextIncompleteItem?.step, .signIn)
    }

    func testFirstIncompleteStepFollowsTheRequiredOrder() {
        let progress = DashboardSetupProgress(
            isSignedIn: true,
            hasLinkedBanks: true,
            hasConfiguredSpendingAccounts: false,
            hasSetAsideItem: true,
            hasPlanItem: true
        )

        XCTAssertEqual(
            progress.nextIncompleteItem?.step,
            .chooseSpendingAccounts
        )
        XCTAssertEqual(progress.completedCount, 5)
    }

    func testDefaultVisibleItemsIncludeCompletedAndCurrentStepOnly() {
        let progress = DashboardSetupProgress(
            isSignedIn: true,
            hasLinkedBanks: false,
            hasConfiguredSpendingAccounts: false,
            hasSetAsideItem: true,
            hasPlanItem: true
        )

        XCTAssertEqual(
            progress.visibleItems(showingFutureSteps: false).map(\.step),
            [
                .downloadCaldera,
                .signIn,
                .connectBank,
                .setAside,
                .addToPlan
            ]
        )
        XCTAssertTrue(progress.hasFutureIncompleteSteps)
    }

    func testShowAllStepsIncludesTheFullSetupList() {
        let progress = DashboardSetupProgress(
            isSignedIn: true,
            hasLinkedBanks: true,
            hasConfiguredSpendingAccounts: false,
            hasSetAsideItem: false,
            hasPlanItem: false
        )

        XCTAssertEqual(
            progress.visibleItems(showingFutureSteps: true).map(\.step),
            DashboardSetupStep.allCases
        )
    }

    func testSetAsideAndPlanStepsUseTheirOwnSignals() {
        let setAsideOnly = DashboardSetupProgress(
            isSignedIn: true,
            hasLinkedBanks: true,
            hasConfiguredSpendingAccounts: true,
            hasSetAsideItem: true,
            hasPlanItem: false
        )
        let planOnly = DashboardSetupProgress(
            isSignedIn: true,
            hasLinkedBanks: true,
            hasConfiguredSpendingAccounts: true,
            hasSetAsideItem: false,
            hasPlanItem: true
        )

        XCTAssertTrue(setAsideOnly.items[4].isComplete)
        XCTAssertFalse(setAsideOnly.items[5].isComplete)
        XCTAssertFalse(planOnly.items[4].isComplete)
        XCTAssertTrue(planOnly.items[5].isComplete)
    }

    func testFullyConfiguredProgressHasNoNextStep() {
        let progress = DashboardSetupProgress(
            isSignedIn: true,
            hasLinkedBanks: true,
            hasConfiguredSpendingAccounts: true,
            hasSetAsideItem: true,
            hasPlanItem: true
        )

        XCTAssertEqual(progress.completedCount, 6)
        XCTAssertTrue(progress.isComplete)
        XCTAssertNil(progress.nextIncompleteItem)
    }

    func testManualCompletionAdvancesOnlyTheMarkedCurrentStep() {
        let progress = DashboardSetupProgress(
            isSignedIn: false,
            hasLinkedBanks: false,
            hasConfiguredSpendingAccounts: false,
            hasSetAsideItem: false,
            hasPlanItem: false,
            manuallyCompletedSteps: [.signIn]
        )

        XCTAssertEqual(progress.completedCount, 2)
        XCTAssertTrue(progress.items[1].isComplete)
        XCTAssertFalse(progress.items[2].isComplete)
        XCTAssertEqual(progress.nextIncompleteItem?.step, .connectBank)
    }

    func testManualCompletionCombinesWithDetectedCompletion() {
        let progress = DashboardSetupProgress(
            isSignedIn: true,
            hasLinkedBanks: false,
            hasConfiguredSpendingAccounts: true,
            hasSetAsideItem: false,
            hasPlanItem: true,
            manuallyCompletedSteps: [.connectBank, .setAside]
        )

        XCTAssertEqual(progress.completedCount, 6)
        XCTAssertTrue(progress.isComplete)
        XCTAssertNil(progress.nextIncompleteItem)
    }

    func testManualCompletionPreferenceRoundTripsKnownSteps() {
        let storedValue = DashboardSetupManualCompletionPreference.storedValue(
            for: [.addToPlan, .signIn, .connectBank]
        )

        XCTAssertEqual(storedValue, "signIn,connectBank,addToPlan")
        XCTAssertEqual(
            DashboardSetupManualCompletionPreference.steps(from: storedValue),
            [.signIn, .connectBank, .addToPlan]
        )
    }

    func testMarkingManualCompletionPreservesExistingSteps() {
        let storedValue = DashboardSetupManualCompletionPreference.markingCompleted(
            .connectBank,
            in: "signIn"
        )

        XCTAssertEqual(storedValue, "signIn,connectBank")
    }

    func testManualCompletionActionOnlyMarksTheCurrentStep() {
        let progress = DashboardSetupProgress(
            isSignedIn: false,
            hasLinkedBanks: false,
            hasConfiguredSpendingAccounts: false,
            hasSetAsideItem: false,
            hasPlanItem: false,
            manuallyCompletedSteps: [.signIn]
        )

        XCTAssertEqual(
            DashboardSetupManualCompletionPreference.markingCurrentStepCompleted(
                .setAside,
                in: progress,
                storedValue: "signIn"
            ),
            "signIn"
        )
        XCTAssertEqual(
            DashboardSetupManualCompletionPreference.markingCurrentStepCompleted(
                .connectBank,
                in: progress,
                storedValue: "signIn"
            ),
            "signIn,connectBank"
        )
    }

    func testCollapsedChecklistPresentationKeepsOnlyHeaderAndProgressRow() {
        let presentation = DashboardSetupChecklistPresentation(isExpanded: false)

        XCTAssertFalse(presentation.showsProgressSummary)
        XCTAssertTrue(presentation.showsProgressRow)
        XCTAssertFalse(presentation.showsStepDetailsAndActions)
        XCTAssertFalse(presentation.showsManualCompletionAction)
        XCTAssertFalse(presentation.showsPrimaryAction)
    }

    func testExpandedChecklistPresentationShowsSummaryAndSplitActions() {
        let presentation = DashboardSetupChecklistPresentation(isExpanded: true)

        XCTAssertTrue(presentation.showsProgressSummary)
        XCTAssertTrue(presentation.showsProgressRow)
        XCTAssertTrue(presentation.showsStepDetailsAndActions)
        XCTAssertTrue(presentation.showsManualCompletionAction)
        XCTAssertTrue(presentation.showsPrimaryAction)
    }

    func testDestinationsMatchExistingSetupSurfaces() {
        XCTAssertEqual(
            DashboardSetupStep.signIn.destination,
            .signInWithApple
        )
        XCTAssertEqual(
            DashboardSetupStep.connectBank.destination,
            .linkedAccounts
        )
        XCTAssertEqual(
            DashboardSetupStep.chooseSpendingAccounts.destination,
            .linkedAccounts
        )
        XCTAssertEqual(
            DashboardSetupStep.setAside.destination,
            .setAside
        )
        XCTAssertEqual(
            DashboardSetupStep.addToPlan.destination,
            .addUpcomingExpense
        )
        XCTAssertTrue(
            DashboardSetupStep.chooseSpendingAccounts
                .expandsLinkedCashAccountGroups
        )
        XCTAssertFalse(
            DashboardSetupStep.connectBank.expandsLinkedCashAccountGroups
        )
    }

    func testUpcomingExpenseStepPromisesItsDirectDestination() {
        XCTAssertEqual(
            DashboardSetupStep.addToPlan.title,
            "Add an Upcoming Expense"
        )
        XCTAssertEqual(
            DashboardSetupStep.addToPlan.detail,
            "Add a future expense so Caldera can help you plan ahead."
        )
        XCTAssertEqual(
            DashboardSetupStep.addToPlan.nextMessage,
            "Next: Add an Upcoming Expense"
        )
    }

    func testSetAsideStepDoesNotRequireCashCushionSpecifically() {
        XCTAssertEqual(
            DashboardSetupStep.setAside.detail,
            "Create your first Set Aside item."
        )
    }

    func testAccountScopeCompletionRequiresAnExplicitCurrentUserSelection() {
        let selections = [
            AvailableToSpendAccountSelection(
                userID: "user-a",
                plaidAccountID: "cash-a",
                isIncluded: false
            ),
            AvailableToSpendAccountSelection(
                userID: "user-b",
                plaidAccountID: "cash-b",
                isIncluded: true
            )
        ]

        XCTAssertTrue(
            AvailableToSpendAccountScope.hasExplicitSelection(
                userID: "user-a",
                linkedCashAccountIDs: ["cash-a"],
                selections: selections
            )
        )
        XCTAssertFalse(
            AvailableToSpendAccountScope.hasExplicitSelection(
                userID: "user-b",
                linkedCashAccountIDs: ["cash-a"],
                selections: selections
            )
        )
        XCTAssertFalse(
            AvailableToSpendAccountScope.hasExplicitSelection(
                userID: "user-a",
                linkedCashAccountIDs: ["different-account"],
                selections: selections
            )
        )
    }
}
