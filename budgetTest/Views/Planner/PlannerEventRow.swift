import SwiftUI

struct PlannerEventRow: View {

    let event: PlannerEvent
    let occurrenceDate: Date
    let projectedAvailable: Double
    let onModify: () -> Void

    private var statusText: String {

        if projectedAvailable < 0 {
            return "Shortfall Expected"
        }

        if projectedAvailable < 500 {
            return "Watch Spending"
        }

        return "On Track"
    }

    private var statusColor: Color {

        if projectedAvailable < 0 {
            return .red
        }

        if projectedAvailable < 500 {
            return .orange
        }

        return .green
    }

    private var iconColor: Color {

        switch event.type {

        case .expense:
            return .red

        case .income:
            return .green
        }
    }

    private var monthText: String {

        occurrenceDate.formatted(
            .dateTime.month(.abbreviated)
        )
        .uppercased()
    }

    private var dayText: String {

        occurrenceDate.formatted(
            .dateTime.day()
        )
    }

    var body: some View {

        Button {

            onModify()

        } label: {

            HStack(spacing: 16) {

                VStack(spacing: 2) {

                    Text(monthText)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Text(dayText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
                .frame(width: 50)

                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {

                    Text(event.name)
                        .font(.headline)

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(statusColor)

                    Text(
                        "After Event: \(projectedAvailable.formatted(.currency(code: "USD")))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(
                    alignment: .trailing,
                    spacing: 6
                ) {

                    Text(
                        event.amount,
                        format: .currency(
                            code: "USD"
                        )
                    )
                    .font(.headline.bold())
                    .foregroundColor(iconColor)

                    if event.frequency != .once {

                        Text(event.frequency.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(
                                        Color.blue.opacity(0.12)
                                    )
                            )
                    }
                }
            }
            .padding(20)
            .background {


            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .fill(.ultraThinMaterial)


            }
            .overlay {


            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )


            }
            .overlay {


            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.75),
                        Color.white.opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )


            }
            .shadow(
            color: Color.white.opacity(0.35),
            radius: 2,
            y: -1
            )
            .shadow(
            color: Color.black.opacity(0.06),
            radius: 24,
            y: 12
            )

        }
        .buttonStyle(.plain)
    }
}
