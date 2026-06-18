import SwiftUI

extension PlannerView {


var availableCard: some View {

    ZStack {

        RoundedRectangle(
            cornerRadius: 34
        )
        .fill(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.10),
                    Color.white.opacity(0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )

        VStack {

            HStack {

                Spacer()

                ZStack {

                    RoundedRectangle(
                        cornerRadius: 22
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.blue.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(
                        width: 110,
                        height: 90
                    )

                    RoundedRectangle(
                        cornerRadius: 22
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.blue.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(
                        width: 110,
                        height: 90
                    )
                    .offset(
                        x: 12,
                        y: 10
                    )
                }
                .rotationEffect(
                    .degrees(-12)
                )
                .opacity(0.55)
            }

            Spacer()
        }
        .padding(.top, 18)
        .padding(.trailing, 22)

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            HStack {

                ZStack {

                    Circle()
                        .fill(
                            Color.blue.opacity(0.12)
                        )
                        .frame(
                            width: 34,
                            height: 34
                        )

                    Image(
                        systemName: "wallet.pass.fill"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.blue)
                }

                Text("Available To Spend")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(
                summary.totalAvailable,
                format: .currency(code: "USD")
            )
            .font(
                .system(
                    size: 50,
                    weight: .bold,
                    design: .rounded
                )
            )
            .minimumScaleFactor(0.7)
            .lineLimit(1)

            Spacer()
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
    }
    .frame(height: 180)
    .overlay(
        RoundedRectangle(
            cornerRadius: 34
        )
        .stroke(
            Color.white.opacity(0.8),
            lineWidth: 1
        )
    )
    .clipShape(
        RoundedRectangle(
            cornerRadius: 34
        )
    )
    .shadow(
        color: .blue.opacity(0.08),
        radius: 20,
        y: 10
    )
}

var plannerSummaryCard: some View {

    HStack(spacing: 0) {

        VStack(
            alignment: .leading,
            spacing: 10
        ) {

            Text("Safe To Spend")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(
                safeToSpend,
                format: .currency(code: "USD")
            )
            .font(
                .system(
                    size: 30,
                    weight: .bold,
                    design: .rounded
                )
            )
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(
                safeToSpend >= 0
                ? .green
                : .red
            )

            if let nextExpense {

                Text(
                    "Through \(nextExpense.occurrenceDate.formatted(.dateTime.month(.abbreviated).day()))"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )

        Rectangle()
            .fill(
                Color.gray.opacity(0.12)
            )
            .frame(
                width: 1,
                height: 120
            )

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            Label(
                "Next Expense",
                systemImage: "calendar"
            )
            .font(.headline)
            .foregroundStyle(.secondary)

            if let nextExpense {

                Text(
                    nextExpense.event.name
                )
                .font(.title2.bold())

                Text(
                    nextExpense.event.amount,
                    format: .currency(
                        code: "USD"
                    )
                )
                .font(
                    .system(
                        size: 30,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.red)

                Text(
                    nextExpense.occurrenceDate.formatted(
                        .dateTime
                            .month(.abbreviated)
                            .day()
                            .year()
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }
    .padding(22)
    .background(.ultraThinMaterial)
    .overlay(
        RoundedRectangle(
            cornerRadius: 28
        )
        .stroke(
            Color.white.opacity(0.5),
            lineWidth: 1
        )
    )
    .clipShape(
        RoundedRectangle(
            cornerRadius: 28
        )
    )
}


}
