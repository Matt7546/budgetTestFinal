import XCTest
@testable import Caldera_Money

final class DashboardWidgetPreferencesTests: XCTestCase {

    func testDefaultPreferenceUsesDefaultOrder() {
        let preferences = DashboardWidgetPreferences(storedValue: "")

        XCTAssertEqual(
            preferences.visibleKinds,
            DashboardWidgetKind.defaultOrder
        )
        XCTAssertTrue(preferences.hiddenKinds.isEmpty)
        XCTAssertTrue(preferences.isDefault)
    }

    func testHidingWidgetRemovesItFromRenderableOrder() {
        var preferences = DashboardWidgetPreferences()
        preferences.hide(.paymentPlans)

        let renderedKinds = preferences.renderableSnapshots(
            from: collection()
        )
        .map(\.kind)

        XCTAssertFalse(renderedKinds.contains(.paymentPlans))
        XCTAssertTrue(preferences.hiddenKinds.contains(.paymentPlans))
    }

    func testAddingHiddenWidgetRestoresItAtEnd() {
        var preferences = DashboardWidgetPreferences()
        preferences.hide(.bankSync)
        preferences.show(.bankSync)

        XCTAssertEqual(preferences.visibleKinds.last, .bankSync)
        XCTAssertFalse(preferences.hiddenKinds.contains(.bankSync))
    }

    func testMovingWidgetsChangesVisibleOrder() {
        var preferences = DashboardWidgetPreferences()

        preferences.moveUp(.paymentPlans)
        XCTAssertEqual(
            preferences.visibleKinds,
            [
                .setAside,
                .bankSync,
                .reviewUpdates,
                .savingsGoal,
                .paymentPlans,
                .upcomingExpenses,
                .planAhead
            ]
        )

        preferences.moveDown(.paymentPlans)
        XCTAssertEqual(
            preferences.visibleKinds,
            DashboardWidgetKind.defaultOrder
        )
    }

    func testResetRestoresDefaultOrderAndVisibility() {
        var preferences = DashboardWidgetPreferences()
        preferences.hide(.reviewUpdates)
        preferences.moveUp(.planAhead)

        preferences.reset()

        XCTAssertEqual(
            preferences.visibleKinds,
            DashboardWidgetKind.defaultOrder
        )
        XCTAssertTrue(preferences.hiddenKinds.isEmpty)
        XCTAssertTrue(preferences.isDefault)
    }

    func testStoredPreferenceRoundTrips() {
        var preferences = DashboardWidgetPreferences()
        preferences.hide(.savingsGoal)
        preferences.moveUp(.planAhead)

        let decoded = DashboardWidgetPreferences(
            storedValue: preferences.storedValue()
        )

        XCTAssertEqual(decoded, preferences)
    }

    func testUnknownWidgetIDsAreIgnoredAndMissingDefaultsAreAppended() {
        let storedValue = #"{"version":1,"order":["futureWidget","bankSync","setAside"],"hidden":["futureWidget","paymentPlans"]}"#
        let preferences = DashboardWidgetPreferences(
            storedValue: storedValue
        )

        XCTAssertEqual(
            preferences.orderedKinds,
            [
                .bankSync,
                .setAside,
                .reviewUpdates,
                .savingsGoal,
                .upcomingExpenses,
                .paymentPlans,
                .planAhead
            ]
        )
        XCTAssertEqual(preferences.hiddenKinds, [.paymentPlans])
    }

    func testSnapshotHiddenWidgetStillDoesNotRender() {
        let preferences = DashboardWidgetPreferences()
        let renderedKinds = preferences.renderableSnapshots(
            from: collection(hiddenKinds: [.savingsGoal])
        )
        .map(\.kind)

        XCTAssertFalse(renderedKinds.contains(.savingsGoal))
        XCTAssertEqual(
            renderedKinds,
            DashboardWidgetKind.defaultOrder.filter { $0 != .savingsGoal }
        )
    }

    func testSetAsideAndBankSyncEmptyStatesRemainRenderable() {
        let preferences = DashboardWidgetPreferences()
        let hiddenDomainKinds = Set(DashboardWidgetKind.defaultOrder).subtracting(
            [.setAside, .bankSync]
        )
        let rendered = preferences.renderableSnapshots(
            from: collection(
                emptyKinds: [.setAside, .bankSync],
                hiddenKinds: hiddenDomainKinds
            )
        )

        XCTAssertEqual(rendered.map(\.kind), [.setAside, .bankSync])
        XCTAssertTrue(rendered.allSatisfy { $0.contentState == .empty })
    }

    private func collection(
        emptyKinds: Set<DashboardWidgetKind> = [],
        hiddenKinds: Set<DashboardWidgetKind> = []
    ) -> DashboardWidgetSnapshotCollection {
        DashboardWidgetSnapshotCollection(
            orderedSnapshots: DashboardWidgetKind.defaultOrder.map { kind in
                let state: DashboardWidgetContentState

                if hiddenKinds.contains(kind) {
                    state = .hidden
                } else if emptyKinds.contains(kind) {
                    state = .empty
                } else {
                    state = .content
                }

                return DashboardWidgetSnapshot(
                    kind: kind,
                    title: kind.displayName,
                    subtitle: "Context",
                    primaryValue: "$100",
                    secondaryValue: nil,
                    status: nil,
                    progress: nil,
                    categoryRole: kind.categoryRole,
                    destination: nil,
                    contentState: state,
                    items: [],
                    accessibilityLabel: kind.displayName
                )
            }
        )
    }
}
