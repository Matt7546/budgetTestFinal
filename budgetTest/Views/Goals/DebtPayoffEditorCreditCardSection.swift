import SwiftUI

struct DebtPayoffEditorCreditCardSourceSection: View {

    let selectedSource: DebtPayoffCreditCardSource
    let selectSource: (DebtPayoffCreditCardSource) -> Void

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "Track Payment",
            systemImage: "rectangle.stack.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            VStack(spacing: AppSpacing.small) {
                ForEach(DebtPayoffCreditCardSource.allCases) { source in
                    creditCardSourceButton(source)
                }
            }
        }
    }

    private func creditCardSourceButton(
        _ source: DebtPayoffCreditCardSource
    ) -> some View {
        DebtPayoffEditorChoiceRow(
            title: source.title,
            isSelected: selectedSource == source,
            accessibilityLabel: source.title,
            accessibilityHint: source.helper,
            action: {
                selectSource(source)
            }
        ) {
            Text(source.helper)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DebtPayoffEditorCreditCardDetailsSection: View {

    let source: DebtPayoffCreditCardSource
    let debtAccounts: [PlaidAccount]
    let selectedAccount: PlaidAccount?
    let linkedBalanceSyncText: String

    @Binding var selectedAccountID: String
    @Binding var linkedNicknameText: String
    @Binding var manualNameText: String
    @Binding var manualBalanceText: String

    var body: some View {
        DebtPayoffEditorFormCard(
            title: source == .linked ? "Linked Account" : "Card Details",
            systemImage: "creditcard.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            if source == .linked {
                linkedCreditCardFields
            } else {
                manualCreditCardFields
            }
        }
    }

    @ViewBuilder
    private var linkedCreditCardFields: some View {
        if debtAccounts.isEmpty {
            Text("No linked credit cards are available. Choose Manual Entry to add the card yourself, or try refreshing linked balances in Settings.")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Picker(
                "Linked Credit Card",
                selection: $selectedAccountID
            ) {
                ForEach(debtAccounts) { account in
                    Text(accountLabel(account))
                        .tag(account.account_id)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.86,
                strokeOpacity: 0.68,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
            )
            .accessibilityLabel("Linked credit card")

            if let selectedAccount {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("\(AppFormatters.currency(selectedAccount.debtBalanceValue)) card balance")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .accessibilityLabel("Card balance")

                    Text(linkedBalanceSyncText)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("You control actual payments. Card balances update when linked balances refresh.")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)

                    if selectedAccount.debtBalanceValue <= 0 {
                        Text("Enter a payment target to plan money for this card.")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(AppColors.secondaryText.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("Balance unavailable. Choose a linked card or try refreshing linked balances in More.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
            }

            DebtPayoffEditorTextField(
                title: "Nickname",
                placeholder: selectedAccount?.name ?? "Optional display name",
                text: $linkedNicknameText,
                subtitle: "Optional. Leave blank to use the card name."
            )
        }
    }

    private var manualCreditCardFields: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            DebtPayoffEditorTextField(
                title: "Card Name",
                placeholder: "Credit Card",
                text: $manualNameText,
                subtitle: "Shown in your plan."
            )

            AmountEntryField(
                title: "Current Balance",
                subtitle: "Amount currently owed. You control actual payments outside Caldera.",
                placeholder: "0.00",
                text: $manualBalanceText,
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                accessibilityLabel: "Current balance"
            )
        }
    }

    private func accountLabel(
        _ account: PlaidAccount
    ) -> String {
        if let institution = account.institution_name,
           !institution.isEmpty {
            return "\(account.name) · \(institution)"
        }

        return account.name
    }
}
