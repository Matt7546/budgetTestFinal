import SwiftUI

struct DetailedAccountCard: View {

    let account: PlaidAccount

    private var isLiability: Bool {
        account.type == "credit" || account.type == "loan"
    }

    private var icon: String {
        if account.type == "credit" {
            return "creditcard.fill"
        }

        if account.subtype?.lowercased() == "savings" {
            return "banknote.fill"
        }

        return "building.columns.fill"
    }

    private var iconColor: Color {
        isLiability ? .red : .blue
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 18) {

            HStack {

                ZStack {

                    Circle()
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {

                    Text(account.name)
                        .font(.headline)

                    Text(
                        "\(account.type.capitalized) • \(account.subtype?.capitalized ?? "Account")"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            HStack {

                VStack(alignment: .leading) {

                    Text("Current Balance")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(
                        account.balances.current,
                        format: .currency(code: "USD")
                    )
                    .font(.title.bold())
                }

                Spacer()

                VStack(alignment: .trailing) {

                    Text("Available")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(
                        account.balances.available ?? account.balances.current,
                        format: .currency(code: "USD")
                    )
                    .font(.headline)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.cyan.opacity(0.05),
                            Color.blue.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(
                    Color.white.opacity(0.85),
                    lineWidth: 1
                )
        )
        .shadow(
            color: .black.opacity(0.05),
            radius: 20,
            y: 10
        )
    }
}
