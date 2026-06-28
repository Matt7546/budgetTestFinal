import SwiftUI

struct DetailedAccountCard: View {

    let account: PlaidAccount
    let lastSyncedText: String

    private var isLiability: Bool {
        account.isLiabilityDisplayAccount
    }

    private var icon: String {
        if isLiability {
            if account.isLoanGroupAccount {
                return "banknote.fill"
            }

            return CalderaCategoryStyle.style(for: .debtPayoff).icon
        }

        if account.isSavingsGroupAccount {
            return "banknote.fill"
        }

        return CalderaCategoryStyle.style(for: .bankAccount).icon
    }

    private var iconColor: Color {
        if isLiability {
            return CalderaCategoryStyle.style(for: .debtPayoff).primary
        }

        return CalderaCategoryStyle.style(for: .bankAccount).primary
    }

    private var iconGradient: [Color] {
        if isLiability {
            return CalderaCategoryStyle.style(for: .debtPayoff).gradient
        }

        return CalderaCategoryStyle.style(for: .bankAccount).gradient
    }

    private var detailText: String {
        let accountType = "\(account.type.capitalized) • \(account.subtype?.capitalized ?? "Account")"

        guard let institutionName = account.institution_name,
              !institutionName.isEmpty else {
            return accountType
        }

        return "\(institutionName) • \(accountType)"
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 18) {

            HStack {

                CalderaGradientIcon(
                    systemImage: icon,
                    colors: iconGradient,
                    size: 56,
                    iconSize: 22
                )

                VStack(alignment: .leading, spacing: 4) {

                    Text(account.name)
                        .font(.headline)

                    Text(detailText)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)

                    HStack(spacing: AppSpacing.xxSmall) {
                        Image(systemName: "clock")
                            .font(.caption2.weight(.semibold))

                        Text(lastSyncedText)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundColor(AppColors.secondaryText.opacity(0.82))
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
                            account.cashBalanceValue
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
                            account.displayAvailableBalance
                        )
                    )
                    .font(.headline)
                }
            }
        }
        .padding(24)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.72,
            shadowOpacity: 0.036,
            shadowRadius: 16,
            shadowY: 8,
            darkGlowColor: iconColor
        )
    }
}
