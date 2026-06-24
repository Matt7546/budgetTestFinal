import SwiftUI

struct WalletAccountCard: View {

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
                        .foregroundColor(AppColors.secondaryText)
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
                    AppFormatters.currency(
                        balance
                    )
                )
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(
                    iconColor
                )

                Text("Current Balance")
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding(22)
        .glassCard(
            cornerRadius: AppRadii.card,
            shadow: AppShadows.softCard
        )
    }
}
