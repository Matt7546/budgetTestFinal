import SwiftUI

struct GoalPreviewCard: View {


let goal: SavingsGoal

var body: some View {

    VStack(alignment: .leading, spacing: 18) {

        HStack {

            ZStack {

                Circle()
                    .fill(
                        Color.cyan.opacity(0.12)
                    )
                    .frame(width: 54, height: 54)

                Image(systemName: "target")
                    .font(.system(size: 22))
                    .foregroundColor(.cyan)
            }

            VStack(alignment: .leading, spacing: 4) {

                Text(goal.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(
                        Color(
                            red: 0.10,
                            green: 0.14,
                            blue: 0.22
                        )
                    )

                Text("Savings Goal")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(Int(goal.progress * 100))%")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.cyan)
        }

        ProgressView(value: goal.progress)
            .tint(
                Color(
                    red: 0.45,
                    green: 0.75,
                    blue: 1.0
                )
            )
            .scaleEffect(y: 3)

        HStack {

            VStack(alignment: .leading, spacing: 2) {

                Text("Saved")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(
                    goal.currentAmount,
                    format: .currency(code: "USD")
                )
                .font(.headline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {

                Text("Target")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(
                    goal.targetAmount,
                    format: .currency(code: "USD")
                )
                .font(.headline)
            }
        }
    }
    .padding(22)
    .background(
        RoundedRectangle(cornerRadius: 28)
            .fill(.ultraThinMaterial)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 28)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.cyan.opacity(0.04),
                        Color.green.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    )
    .overlay(
        RoundedRectangle(cornerRadius: 28)
            .stroke(
                Color.white.opacity(0.85),
                lineWidth: 1
            )
    )
    .shadow(
        color: .black.opacity(0.04),
        radius: 20,
        y: 10
    )
}


}
