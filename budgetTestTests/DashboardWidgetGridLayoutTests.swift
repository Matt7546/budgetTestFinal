import XCTest
@testable import Caldera_Money

final class DashboardWidgetGridLayoutTests: XCTestCase {

    func testFixedWidgetListPacksSquarePairsBeforeWideRows() {
        let rows = DashboardWidgetGridLayout.rows(
            from: DashboardWidgetKind.defaultOrder.map {
                makeSnapshot($0)
            }
        )
        let actualKinds: [[DashboardWidgetKind]] = rows.map { row in
            row.items.map { $0.snapshot.kind }
        }
        let expectedKinds: [[DashboardWidgetKind]] = [
            [.setAside, .bankSync],
            [.reviewUpdates, .savingsGoal],
            [.upcomingExpenses],
            [.paymentPlans],
            [.planAhead]
        ]
        let actualSizes: [DashboardWidgetTileSize] = rows
            .flatMap { $0.items }
            .map { $0.size }
        let expectedSizes: [DashboardWidgetTileSize] = [
            .square,
            .square,
            .square,
            .square,
            .wide,
            .wide,
            .wide
        ]

        XCTAssertEqual(actualKinds, expectedKinds)
        XCTAssertEqual(actualSizes, expectedSizes)
    }

    func testHiddenWidgetsDoNotLeavePlaceholderCells() {
        let rows = DashboardWidgetGridLayout.rows(
            from: [
                makeSnapshot(.setAside),
                makeSnapshot(.bankSync),
                makeSnapshot(.reviewUpdates, state: .hidden),
                makeSnapshot(.savingsGoal),
                makeSnapshot(.upcomingExpenses),
                makeSnapshot(.paymentPlans, state: .hidden),
                makeSnapshot(.planAhead)
            ]
        )
        let actualKinds: [[DashboardWidgetKind]] = rows.map { row in
            row.items.map { $0.snapshot.kind }
        }
        let expectedKinds: [[DashboardWidgetKind]] = [
            [.setAside, .bankSync],
            [.savingsGoal],
            [.upcomingExpenses],
            [.planAhead]
        ]

        XCTAssertEqual(actualKinds, expectedKinds)
        XCTAssertEqual(rows[1].items.first?.size, .wide)
        XCTAssertTrue(
            rows.allSatisfy { row in
                row.items.count == 2 || row.items.first?.size == .wide
            }
        )
    }

    func testEmptySetAsideAndBankSyncStillRenderTogether() {
        let rows = DashboardWidgetGridLayout.rows(
            from: [
                makeSnapshot(.setAside, state: .empty),
                makeSnapshot(.bankSync, state: .empty),
                makeSnapshot(.reviewUpdates, state: .hidden),
                makeSnapshot(.savingsGoal, state: .hidden),
                makeSnapshot(.upcomingExpenses, state: .hidden),
                makeSnapshot(.paymentPlans, state: .hidden),
                makeSnapshot(.planAhead, state: .hidden)
            ]
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(
            rows[0].items.map { $0.snapshot.kind },
            [DashboardWidgetKind.setAside, .bankSync]
        )
        XCTAssertEqual(
            rows[0].items.map { $0.size },
            [DashboardWidgetTileSize.square, .square]
        )
    }

    func testFixedProductionListDoesNotContainAvailableToSpend() {
        XCTAssertEqual(
            DashboardWidgetKind.defaultOrder,
            [
                .setAside,
                .bankSync,
                .reviewUpdates,
                .savingsGoal,
                .upcomingExpenses,
                .paymentPlans,
                .planAhead
            ]
        )
    }

    private func makeSnapshot(
        _ kind: DashboardWidgetKind,
        state: DashboardWidgetContentState = .content
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
            destination: nil,
            contentState: state,
            items: [],
            accessibilityLabel: kind.rawValue
        )
    }
}
