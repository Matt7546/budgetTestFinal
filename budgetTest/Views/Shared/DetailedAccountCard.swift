import SwiftUI

struct DetailedAccountCard: View {

    let account: PlaidAccount

    private var isLiability: Bool {
        account.isLiabilityDisplayAccount
    }

    private var icon: String {
        if isLiability {
            return "creditcard.fill"
        }

        if account.isSavingsGroupAccount {
            return "lock.shield.fill"
        }

        return "wallet.pass.fill"
    }

    private var iconColor: Color {
        if isLiability {
            return AppColors.obligation
        }

        if account.isSavingsGroupAccount {
            return AppColors.protected
        }

        return AppColors.spendable
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
                    .foregroundColor(AppColors.secondaryText)
                }

                Spacer()
            }

            Divider()

            HStack {

                VStack(alignment: .leading) {

                    Text("Current Balance")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)

                    Text(
                        AppFormatters.currency(
                            account.balances.current
                        )
                    )
                    .font(.title.bold())
                }

                Spacer()

                VStack(alignment: .trailing) {

                    Text("Available")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)

                    Text(
                        AppFormatters.currency(
                            account.balances.available ?? account.balances.current
                        )
                    )
                    .font(.headline)
                }
            }
        }
        .padding(24)
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    iconColor.opacity(0.05),
                    iconColor.opacity(0.04)
                ]
            ),
            shadow: AppShadows.softPanelCompact
        )
    }
}
