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
            summaryRow("Savings Goals (allocated)", value: -summary.totalGoalAllocated)
            summaryRow("Debt", value: summary.totalDebt)

            Divider().padding(.vertical)

            summaryRow(
                "Total Available",
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
                .foregroundColor(value >= 0 ? .green : .red)
        }
    }
}
