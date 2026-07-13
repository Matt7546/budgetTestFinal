import XCTest
@testable import Caldera_Money

@MainActor
final class DashboardPlanStatusPresentationTests: XCTestCase {

    func testPlanStatusKeepsFinancialCategoriesDistinctAndOrdered() {
        let items = [
            item(
                id: "total-set-aside",
                title: "Total Set Aside",
                value: "$1,200.00",
                detail: "Cash Cushion, Savings Goals, Upcoming Expenses, and Payment Plans."
            ),
            item(
                id: "upcoming-expenses",
                title: "Upcoming Expenses",
                value: "$350.00",
                detail: "2 due in the next 7 days."
            ),
            item(
                id: "payment-plan-targets",
                title: "Payment Plan targets",
                value: "$500.00",
                detail: "1 Payment Plan."
            )
        ]

        XCTAssertEqual(
            items.map(\.title),
            ["Total Set Aside", "Upcoming Expenses", "Payment Plan targets"]
        )
        XCTAssertEqual(Set(items.map(\.id)).count, 3)
    }

    func testPlanStatusAccessibilityUsesOnlyTheRowValueAndDetail() {
        let upcomingExpenses = item(
            id: "upcoming-expenses",
            title: "Upcoming Expenses",
            value: "$350.00",
            detail: "2 due in the next 7 days."
        )

        XCTAssertEqual(
            upcomingExpenses.accessibilityLabel,
            "Upcoming Expenses. $350.00. 2 due in the next 7 days."
        )
        XCTAssertEqual(upcomingExpenses.actionTitle, "Open Plan Ahead")
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
