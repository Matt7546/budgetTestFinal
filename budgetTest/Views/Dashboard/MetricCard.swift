import SwiftUI

struct MetricCard: View {


let title: String
let value: Double

private var icon: String {
    switch title {
    case "Cash":
        return "wallet.pass.fill"
    case "Debt":
        return "creditcard.fill"
    case "Goals":
        return "target"
    case "Available":
        return "chart.line.uptrend.xyaxis"
    default:
        return "circle.fill"
    }
}

private var iconColor: Color {
    switch title {
    case "Cash":
        return .green
    case "Debt":
        return .red
    case "Goals":
        return .purple
    case "Available":
        return .blue
    default:
        return .gray
    }
}

private var subtitle: String {
    switch title {
    case "Cash":
        return "Available to spend"
    case "Debt":
        return "Total amount owed"
    case "Goals":
        return "Allocated to goals"
    case "Available":
        return "Left after goals"
    default:
        return ""
    }
}

var body: some View {

    VStack(alignment: .leading, spacing: 12) {

        ZStack {

            Circle()
                .fill(iconColor.opacity(0.12))
                .frame(width: 56, height: 56)

            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(iconColor)
        }

        Text(title)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(
                Color(
                    red: 0.10,
                    green: 0.14,
                    blue: 0.22
                )
            )

        Text(
            value,
            format: .currency(code: "USD")
        )
        .font(.system(size: 26, weight: .bold))
        .foregroundColor(
            Color(
                red: 0.10,
                green: 0.14,
                blue: 0.22
            )
        )

        Text(subtitle)
            .font(.caption)
            .foregroundColor(iconColor)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .frame(height: 180)
    .background(
        RoundedRectangle(cornerRadius: 28)
            .fill(.ultraThinMaterial)
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
