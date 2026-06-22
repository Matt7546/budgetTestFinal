//
//  SummaryView.swift
//

import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var summary: SummaryViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("Summary Breakdown")
                .font(.largeTitle.bold())
                .padding(.top)

            summaryRow("Cash Accounts", value: summary.totalCash)
            summaryRow("Savings Accounts", value: summary.totalSavings)
            summaryRow("Savings Goals", value: -summary.totalGoalAllocated)
            summaryRow("Savings Reserve", value: -summary.reserveBalance)
            summaryRow("Debt", value: summary.totalDebt)

            Divider().padding(.vertical)

            summaryRow(
                "Safe To Spend",
                value: summary.totalAvailable,
                highlight: true
            )

            Spacer()
        }
        .padding()
        .navigationTitle("Summary")
    }

    private func summaryRow(
        _ title: String,
        value: Double,
        highlight: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .font(highlight ? .title3.bold() : .body)

            Spacer()

            Text(value, format: .currency(code: "USD"))
                .font(highlight ? .title3.bold() : .body)
                .foregroundColor(value >= 0 ? AppColors.spendable : AppColors.negative)
        }
    }
}
