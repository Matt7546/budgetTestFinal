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

    #if DEBUG
    @EnvironmentObject private var plaid: PlaidService
    @State private var isRefreshingCardPaymentDetails = false
    #endif

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

            #if DEBUG
            cardPaymentDetailsDiagnostics
            #endif

            DebtPayoffEditorTextField(
                title: "Nickname",
                placeholder: selectedAccount?.name ?? "Optional display name",
                text: $linkedNicknameText,
                subtitle: "Optional. Leave blank to use the card name."
            )
        }
    }

    #if DEBUG
    @ViewBuilder
    private var cardPaymentDetailsDiagnostics: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                Image(systemName: "creditcard.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(
                                CalderaCategoryStyle.style(for: .debtPayoff).primary.opacity(0.12)
                            )
                    )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Card Payment Details")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.ink)

                    Text("Card payment details are read-only in this test build.")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Caldera does not make payments. You control actual payments.")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let card = selectedCardPaymentDetails {
                VStack(spacing: AppSpacing.xxSmall) {
                    cardPaymentDetailRow(
                        title: "Statement balance",
                        value: cardPaymentCurrency(card.last_statement_balance)
                    )
                    cardPaymentDetailRow(
                        title: "Minimum payment",
                        value: cardPaymentCurrency(card.minimum_payment_amount)
                    )
                    cardPaymentDetailRow(
                        title: "Next due date",
                        value: cardPaymentValue(card.next_payment_due_date)
                    )
                    cardPaymentDetailRow(
                        title: "Current balance",
                        value: cardPaymentCurrency(card.current_balance)
                    )
                    cardPaymentDetailRow(
                        title: "Available credit",
                        value: cardPaymentCurrency(card.available_credit)
                    )
                    cardPaymentDetailRow(
                        title: "Last payment",
                        value: cardPaymentLastPayment(card)
                    )
                    cardPaymentDetailRow(
                        title: "Overdue status",
                        value: cardPaymentOverdueStatus(card.is_overdue)
                    )
                    cardPaymentDetailRow(
                        title: "Last refreshed",
                        value: cardPaymentValue(card.last_refreshed_at)
                    )
                }
                .padding(.top, AppSpacing.xxSmall)
            } else {
                Text("No card payment details available for this linked card yet.")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppSpacing.xxSmall)
            }

            SecondaryButton(
                isRefreshingCardPaymentDetails
                    ? "Refreshing Card Payment Details"
                    : "Refresh Card Payment Details",
                systemImage: "arrow.clockwise",
                foregroundColor: CalderaCategoryStyle.style(for: .debtPayoff).primary,
                fillsWidth: true,
                action: refreshCardPaymentDetailsForDebug
            )
            .disabled(isRefreshingCardPaymentDetails)
        }
        .padding(AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.72,
            strokeOpacity: 0.62,
            shadowOpacity: 0.0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
        )
    }

    private var selectedCardPaymentDetails: LinkedCardPaymentDetails? {
        plaid.cardPaymentDetails.first { card in
            card.account_id == selectedAccountID
        }
    }

    private func refreshCardPaymentDetailsForDebug() {
        isRefreshingCardPaymentDetails = true
        plaid.fetchCardPaymentDetails(reason: .debugTool) { _ in
            isRefreshingCardPaymentDetails = false
        }
    }

    private func cardPaymentDetailRow(
        title: String,
        value: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)

            Spacer(minLength: AppSpacing.small)

            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private func cardPaymentCurrency(
        _ value: Double?
    ) -> String {
        guard let value else {
            return "Not available"
        }

        return AppFormatters.currency(value)
    }

    private func cardPaymentValue(
        _ value: String?
    ) -> String {
        guard let value, !value.isEmpty else {
            return "Not available"
        }

        return value
    }

    private func cardPaymentLastPayment(
        _ card: LinkedCardPaymentDetails
    ) -> String {
        let amount = cardPaymentCurrency(card.last_payment_amount)
        let date = cardPaymentValue(card.last_payment_date)

        if amount == "Not available" && date == "Not available" {
            return "Not available"
        }

        if amount == "Not available" {
            return date
        }

        if date == "Not available" {
            return amount
        }

        return "\(amount) on \(date)"
    }

    private func cardPaymentOverdueStatus(
        _ isOverdue: Bool?
    ) -> String {
        guard let isOverdue else {
            return "Not available"
        }

        return isOverdue ? "Overdue" : "Not overdue"
    }
    #endif

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
