import SwiftUI

struct GoalPreviewCard: View {


let goal: SavingsGoal

var body: some View {

    VStack(alignment: .leading, spacing: 18) {

        HStack {

            ZStack {

                Circle()
                    .fill(
                        AppColors.protected.opacity(0.12)
                    )
                    .frame(width: 54, height: 54)

                Image(systemName: "target")
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.protected)
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

                Text("Savings")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()

            Text("\(Int(goal.progress * 100))%")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppColors.protected)
        }

        ProgressView(value: goal.progress)
            .tint(AppColors.protected)
            .scaleEffect(y: 3)

        HStack {

            MetricLabelValue(
                label: "Saved",
                value: goal.currentAmount,
                spacing: 2,
                labelColor: .secondary
            )

            Spacer()

            MetricLabelValue(
                label: "Target",
                value: goal.targetAmount,
                alignment: .trailing,
                spacing: 2,
                labelColor: .secondary
            )
        }
    }
    .padding(22)
    .glassCard(
        cornerRadius: AppRadii.card,
        overlay: .gradient(
            colors: [
                Color.white.opacity(0.10),
                AppColors.protected.opacity(0.05),
                AppColors.protected.opacity(0.02)
            ]
        ),
        shadow: AppShadows.softCard
    )
}


}
