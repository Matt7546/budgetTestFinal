import SwiftUI

struct DetailedAccountCard: View {

    let account: PlaidAccount
    let lastSyncedText: String

    @EnvironmentObject private var plaid: PlaidService
    @State private var draftIsIncluded = true
    @State private var accountScopeStatusMessage: String?

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
        savedIsIncluded
            ? "Included in Available to Spend"
            : "Not included in Available to Spend"
    }

    private var inclusionDescription: String {
        if account.isCashTotalAccount && savedIsIncluded {
            return "Linked cash balances help estimate what you can spend."
        }

        if account.isCashTotalAccount {
            return "This account stays linked and visible, but its balance is not counted in Available to Spend."
        }

        if account.isCreditGroupAccount {
            return "Credit card balances help with Payment Plans, not Available to Spend."
        }

        return "This balance is tracked for context, not spendable cash."
    }

    private var inclusionIcon: String {
        savedIsIncluded
            ? "checkmark.circle.fill"
            : "minus.circle.fill"
    }

    private var inclusionColor: Color {
        savedIsIncluded
            ? CalderaCategoryStyle.style(for: .covered).primary
            : AppColors.secondaryText
    }

    private var savedIsIncluded: Bool {
        plaid.isAccountIncludedInAvailableToSpend(account)
    }

    private var hasUnsavedAccountScopeChange: Bool {
        account.isCashTotalAccount &&
        draftIsIncluded != savedIsIncluded
    }

    private var accountScopePreviewText: String? {
        guard hasUnsavedAccountScopeChange else {
            return nil
        }

        let delta = draftIsIncluded
            ? account.cashBalanceValue
            : -account.cashBalanceValue

        if delta > 0.005 {
            return "Available to Spend will increase by \(AppFormatters.currency(delta))."
        }

        if delta < -0.005 {
            return "Available to Spend will decrease by \(AppFormatters.currency(abs(delta)))."
        }

        return "Available to Spend will not change at the current balance."
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

            if account.isCashTotalAccount {
                availableToSpendAccountControl
            } else {
                accountInclusionContext
            }

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
        .onAppear {
            draftIsIncluded = savedIsIncluded
        }
        .onChange(of: savedIsIncluded) { oldValue, newValue in
            if draftIsIncluded == oldValue {
                draftIsIncluded = newValue
            }
        }
    }

    private var accountInclusionContext: some View {
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
    }

    private var availableToSpendAccountControl: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Toggle(
                "Count in Available to Spend",
                isOn: $draftIsIncluded
            )
            .font(.subheadline.weight(.bold))
            .tint(CalderaCategoryStyle.style(for: .safeToSpend).primary)
            .disabled(!plaid.canManageAvailableToSpendAccountScope)

            Text("Excluded accounts stay linked and visible, but their balance is not counted in Available to Spend.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let accountScopePreviewText {
                Text(accountScopePreviewText)
                    .font(.caption.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasUnsavedAccountScopeChange {
                PrimaryButton(
                    "Save",
                    systemImage: "checkmark",
                    trailingSystemImage: nil,
                    cornerRadius: AppRadii.button,
                    fillsWidth: true
                ) {
                    saveAvailableToSpendAccountSetting()
                }
            }

            if let accountScopeStatusMessage {
                Text(accountScopeStatusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: AppRadii.control,
                style: .continuous
            )
            .fill(
                CalderaCategoryStyle.style(for: .safeToSpend).primary.opacity(0.10)
            )
        )
    }

    private func saveAvailableToSpendAccountSetting() {
        let didSave = plaid.setAccountIncludedInAvailableToSpend(
            accountID: account.account_id,
            isIncluded: draftIsIncluded
        )

        accountScopeStatusMessage = didSave
            ? "Available to Spend account setting updated."
            : "Couldn’t update this setting. Try again."

        if !didSave {
            draftIsIncluded = savedIsIncluded
        }
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
