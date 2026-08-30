import XCTest
@testable import Caldera_Money

@MainActor
final class DashboardPlanStatusPresentationTests: XCTestCase {

    func testAtAGlanceKeepsFinancialCategoriesDistinctAndOrdered() {
        let items = [
            item(
                id: "total-set-aside",
                title: "Set Aside",
                value: "$1,200.00",
                detail: "Total set aside"
            ),
            item(
                id: "upcoming-expenses",
                title: "Upcoming",
                value: "$350.00",
                detail: "2 due in next 7 days"
            ),
            item(
                id: "payment-plan-targets",
                title: "Payments",
                value: "$500.00",
                detail: "1 Payment Plan target"
            )
        ]

        XCTAssertEqual(
            items.map(\.title),
            ["Set Aside", "Upcoming", "Payments"]
        )
        XCTAssertEqual(Set(items.map(\.id)).count, 3)
    }

    func testAtAGlanceAccessibilityUsesTheMetricValueAndCaption() {
        let upcomingExpenses = item(
            id: "upcoming-expenses",
            title: "Upcoming",
            value: "$350.00",
            detail: "2 due in next 7 days"
        )

        XCTAssertEqual(
            upcomingExpenses.accessibilityLabel,
            "Upcoming. $350.00. 2 due in next 7 days"
        )
        XCTAssertEqual(upcomingExpenses.actionTitle, "Open Plan Ahead")
    }

    func testAtAGlanceSupportsCalmEmptyMetrics() {
        let items = [
            item(
                id: "total-set-aside",
                title: "Set Aside",
                value: "$0.00",
                detail: "Total set aside"
            ),
            item(
                id: "upcoming-expenses",
                title: "Upcoming",
                value: "None",
                detail: "Next 7 days"
            ),
            item(
                id: "payment-plan-targets",
                title: "Payments",
                value: "$0.00",
                detail: "No Payment Plans"
            )
        ]

        XCTAssertEqual(items.map(\.value), ["$0.00", "None", "$0.00"])
        XCTAssertEqual(
            items.map(\.detail),
            ["Total set aside", "Next 7 days", "No Payment Plans"]
        )
    }

    private func item(
        id: String,
        title: String,
        value: String,
        detail: String
    ) -> DashboardPlanStatusItem {
        DashboardPlanStatusItem(
            id: id,
            title: title,
            value: value,
            detail: detail,
            style: CalderaCategoryStyle.style(for: .upcomingExpense),
            systemImage: "calendar",
            actionTitle: "Open Plan Ahead",
            action: {}
        )
    }
}
