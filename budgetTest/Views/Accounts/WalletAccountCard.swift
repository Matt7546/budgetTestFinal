import SwiftUI

struct WalletAccountCard: View {

    let account: PlaidAccount

    private var isLiability: Bool {
        account.type == "credit" || account.type == "loan"
    }

    private var icon: String {
        isLiability
            ? "creditcard.fill"
            : "building.columns.fill"
    }

    private var iconColor: Color {
        isLiability
            ? .red
            : .blue
    }

    private var balance: Double {
        account.balances.current
    }

    var body: some View {

        HStack(spacing: 18) {

            ZStack {

                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 6) {

                Text(account.name)
                    .font(.system(size: 18, weight: .semibold))

                if let subtype = account.subtype {

                    Text(subtype.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(
                    isLiability
                        ? "Liability Account"
                        : "Asset Account"
                )
                .font(.caption)
                .foregroundColor(iconColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {

                Text(
                    balance,
                    format: .currency(code: "USD")
                )
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(
                    isLiability
                        ? .red
                        : .green
                )

                Text("Current Balance")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(22)
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
