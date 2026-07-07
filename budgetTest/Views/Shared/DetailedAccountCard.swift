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

    private var displayName: String {
        firstNonEmpty(
            account.official_name,
            account.name
        ) ?? "Linked account"
    }

    private var secondaryName: String? {
        guard let officialName = cleanText(account.official_name),
              officialName.caseInsensitiveCompare(account.name) != .orderedSame else {
            return nil
        }

        return cleanText(account.name)
    }

    private var institutionName: String {
        cleanText(account.institution_name) ?? "Linked institution"
    }

    private var subtypeText: String {
        titleCase(
            account.subtype ?? account.type
        )
    }

    private var maskText: String? {
        guard let mask = cleanText(account.mask) else {
            return nil
        }

        return "••••\(mask)"
    }

    private var detailText: String {
        var parts = [
            institutionName,
            subtypeText
        ]

        if let maskText {
            parts.append(maskText)
        }

        return parts.joined(separator: " • ")
    }

    private var inclusionTitle: String {
        account.isCashTotalAccount
            ? "Included in Available to Spend"
            : "Not included in Available to Spend"
    }

    private var inclusionDescription: String {
        if account.isCashTotalAccount {
            return "Linked cash balances help estimate what you can spend."
        }

        if account.isCreditGroupAccount {
            return "Credit card balances are used for Debt Payoff planning, not spendable cash."
        }

        return "This balance is tracked for context, not spendable cash."
    }

    private var inclusionIcon: String {
        account.isCashTotalAccount
            ? "checkmark.circle.fill"
            : "minus.circle.fill"
    }

    private var inclusionColor: Color {
        account.isCashTotalAccount
            ? CalderaCategoryStyle.style(for: .covered).primary
            : AppColors.secondaryText
    }

    private var currentBalanceLabel: String {
        if account.isCreditGroupAccount {
            return "Current card balance"
        }

        if account.isLoanGroupAccount {
            return "Latest linked balance"
        }

        return "Latest linked balance"
    }

    private var currentBalanceValue: Double {
        if account.isLiabilityDisplayAccount {
            return account.debtBalanceValue
        }

        return account.cashBalanceValue
    }

    private var availableCredit: Double? {
        guard account.isCreditGroupAccount else {
            return nil
        }

        return account.balances.available
    }

    private var creditLimit: Double? {
        guard account.isCreditGroupAccount else {
            return nil
        }

        return account.balances.limit
    }

    private var currencyCode: String? {
        cleanText(account.balances.iso_currency_code) ??
            cleanText(account.balances.unofficial_currency_code)
    }

    private var shouldShowCurrencyCode: Bool {
        guard let currencyCode else {
            return false
        }

        return currencyCode.uppercased() != "USD"
    }

    var body: some View {

        VStack(alignment: .leading, spacing: AppSpacing.large) {

            HStack(alignment: .top, spacing: AppSpacing.medium) {

                CalderaGradientIcon(
                    systemImage: icon,
                    colors: iconGradient,
                    size: 56,
                    iconSize: 22
                )

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {

                    Text(displayName)
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let secondaryName {
                        Text(secondaryName)
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(detailText)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(spacing: AppSpacing.xSmall) {
                    Image(systemName: inclusionIcon)
                        .font(.caption.weight(.semibold))

                    Text(inclusionTitle)
                        .font(.caption.weight(.bold))
                }
                .foregroundColor(inclusionColor)

                Text(inclusionDescription)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(
                    cornerRadius: AppRadii.control,
                    style: .continuous
                )
                .fill(inclusionColor.opacity(0.10))
            )

            Divider()

            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                BalanceMetricRow(
                    label: currentBalanceLabel,
                    value: AppFormatters.currency(currentBalanceValue)
                )

                if account.isCreditGroupAccount {
                    if let availableCredit {
                        BalanceMetricRow(
                            label: "Available credit",
                            value: AppFormatters.currency(availableCredit)
                        )
                    }

                    if let creditLimit {
                        BalanceMetricRow(
                            label: "Credit limit",
                            value: AppFormatters.currency(creditLimit)
                        )
                    }
                } else if let available = account.balances.available,
                          !account.isSavingsGroupAccount {
                    BalanceMetricRow(
                        label: "Available balance",
                        value: AppFormatters.currency(available)
                    )
                }

                if shouldShowCurrencyCode,
                   let currencyCode {
                    Text("Currency: \(currencyCode.uppercased())")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.82))
                }
            }

            Divider()

            HStack(spacing: AppSpacing.xxSmall) {
                Image(systemName: "clock")
                    .font(.caption2.weight(.semibold))

                Text(lastSyncedText)
                    .font(.caption2.weight(.medium))
            }
            .foregroundColor(AppColors.secondaryText.opacity(0.82))
            .accessibilityElement(children: .combine)
        }
        .padding(AppSpacing.cardLarge)
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

    private func cleanText(
        _ value: String?
    ) -> String? {
        guard let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private func firstNonEmpty(
        _ values: String?...
    ) -> String? {
        values.compactMap(cleanText).first
    }

    private func titleCase(
        _ value: String
    ) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .localizedCapitalized
    }
}

private struct BalanceMetricRow: View {

    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)

            Spacer(minLength: AppSpacing.medium)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundColor(AppColors.primaryText)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
