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
    @Binding var paymentTargetText: String
    @Binding var dueDate: Date

    let dueDateChanged: () -> Void

    @EnvironmentObject private var plaid: PlaidService
    @State private var cardPaymentActionMessage: String?
    @State private var isLoadingCardPaymentDetails = false
    @State private var cardPaymentDetailsLoadMessage: String?

    #if DEBUG
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

            cardPaymentDetailsCardIfAvailable

            DebtPayoffEditorTextField(
                title: "Nickname",
                placeholder: selectedAccount?.name ?? "Optional display name",
                text: $linkedNicknameText,
                subtitle: "Optional. Leave blank to use the card name."
            )
        }
    }

    @ViewBuilder
    private var cardPaymentDetailsCardIfAvailable: some View {
        if shouldShowCardPaymentDetailsUI {
            if let selectedCardPaymentDetails {
                cardPaymentDetailsCard(selectedCardPaymentDetails)
            } else if shouldShowCardPaymentConsentCard {
                cardPaymentDetailsConsentCard
            } else {
                cardPaymentDetailsLoadCard
            }
        }
    }

    private var shouldShowCardPaymentDetailsUI: Bool {
        source == .linked
            && selectedAccount != nil
            && plaid.backendLiabilitiesEnabled
    }

    private var shouldShowCardPaymentConsentCard: Bool {
        guard selectedCardPaymentDetails == nil,
              plaid.backendLiabilitiesLinkEnabled,
              cardPaymentDetailsConsentRequired,
              let selectedAccount,
              !selectedAccount.account_id.isEmpty,
              let itemID = selectedAccount.item_id,
              !itemID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return true
    }

    private var cardPaymentDetailsConsentRequired: Bool {
        guard let response = plaid.latestCardPaymentDetailsResponse else {
            return false
        }

        return response.consent_required == true
            || response.error == "additional_consent_required"
    }

    private var cardPaymentDetailsConsentCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                Image(systemName: "lock.open.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(
                                CalderaCategoryStyle.style(for: .debtPayoff).primary.opacity(0.12)
                            )
                    )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Add card payment details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.ink)

                    Text("Use statement balance, minimum payment, and due date to help plan this payment.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Caldera does not make payments. You control actual payments.")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let message = plaid.cardPaymentDetailsConsentMessage {
                Text(message)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecondaryButton(
                "Add card payment details",
                systemImage: "creditcard.and.123",
                foregroundColor: CalderaCategoryStyle.style(for: .debtPayoff).primary,
                fillsWidth: true,
                action: addCardPaymentDetailsConsent
            )
        }
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.78,
            strokeOpacity: 0.68,
            shadowOpacity: 0.025,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
        )
    }

    private var cardPaymentDetailsLoadCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            cardPaymentDetailsHeader

            Text("Use linked card details like statement balance, minimum payment, and due date to help plan this payment.")
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let cardPaymentDetailsLoadMessage {
                Text(cardPaymentDetailsLoadMessage)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecondaryButton(
                isLoadingCardPaymentDetails
                    ? "Loading card payment details"
                    : "Load card payment details",
                systemImage: "arrow.down.circle.fill",
                foregroundColor: CalderaCategoryStyle.style(for: .debtPayoff).primary,
                fillsWidth: true,
                action: loadCardPaymentDetails
            )
            .disabled(isLoadingCardPaymentDetails)
        }
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.78,
            strokeOpacity: 0.68,
            shadowOpacity: 0.025,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
        )
    }

    private func cardPaymentDetailsCard(
        _ card: LinkedCardPaymentDetails?
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            cardPaymentDetailsHeader

            if let card {
                VStack(spacing: AppSpacing.small) {
                    HStack(spacing: AppSpacing.small) {
                        cardPaymentPrimaryMetric(
                            title: "Statement balance",
                            value: cardPaymentCurrency(card.last_statement_balance),
                            systemImage: "doc.text.fill"
                        )

                        cardPaymentPrimaryMetric(
                            title: "Minimum payment",
                            value: cardPaymentCurrency(card.minimum_payment_amount),
                            systemImage: "dollarsign.circle.fill"
                        )
                    }

                    cardPaymentDueDateMetric(
                        value: cardPaymentValue(card.next_payment_due_date)
                    )
                }

                cardPaymentActionButtons(card)

                if let cardPaymentActionMessage {
                    Text(cardPaymentActionMessage)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: AppSpacing.xxSmall) {
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
                .padding(AppSpacing.small)
                .calderaGlassCard(
                    cornerRadius: AppRadii.field,
                    fillOpacity: 0.56,
                    strokeOpacity: 0.42,
                    shadowOpacity: 0.0,
                    shadowRadius: 0,
                    shadowY: 0,
                    darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
                )
            } else {
                #if DEBUG
                Text("No card payment details available for this linked card yet.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                #endif
            }

            Text("Caldera does not make payments. You control actual payments.")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            #if DEBUG
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
            #endif
        }
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.78,
            strokeOpacity: 0.68,
            shadowOpacity: 0.025,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
        )
    }

    private var cardPaymentDetailsHeader: some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            Image(systemName: "creditcard.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(
                            CalderaCategoryStyle.style(for: .debtPayoff).primary.opacity(0.12)
                        )
                )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                    Text("Card payment details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.ink)

                    #if DEBUG
                    Text("DEBUG")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
                        .padding(.horizontal, AppSpacing.xSmall)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(
                                    CalderaCategoryStyle.style(for: .debtPayoff).primary.opacity(0.12)
                                )
                        )
                    #endif
                }

                #if DEBUG
                Text("Read-only in this test build.")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                #endif
            }
        }
    }

    private func cardPaymentPrimaryMetric(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            HStack(spacing: AppSpacing.xxSmall) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundColor(AppColors.ink)
                .minimumScaleFactor(0.78)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.7,
            strokeOpacity: 0.52,
            shadowOpacity: 0.0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
        )
    }

    private func cardPaymentDueDateMetric(
        value: String
    ) -> some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "calendar.badge.clock")
                .font(.caption.weight(.bold))
                .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(
                            CalderaCategoryStyle.style(for: .debtPayoff).primary.opacity(0.1)
                        )
                )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Next due date")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(AppColors.ink)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.7,
            strokeOpacity: 0.52,
            shadowOpacity: 0.0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
        )
    }

    @ViewBuilder
    private func cardPaymentActionButtons(
        _ card: LinkedCardPaymentDetails
    ) -> some View {
        let dueDate = parsedCardDueDate(card.next_payment_due_date)

        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text("Plan with card details")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.ink)

            VStack(spacing: AppSpacing.xSmall) {
                if let amount = card.last_statement_balance {
                    cardPaymentActionButton(
                        title: "Use statement balance",
                        systemImage: "doc.text.fill"
                    ) {
                        usePaymentTarget(amount)
                    }
                }

                if let amount = card.minimum_payment_amount {
                    cardPaymentActionButton(
                        title: "Use minimum payment",
                        systemImage: "dollarsign.circle.fill"
                    ) {
                        usePaymentTarget(amount)
                    }
                }

                if let amount = card.current_balance {
                    cardPaymentActionButton(
                        title: "Use current balance",
                        systemImage: "creditcard.fill"
                    ) {
                        usePaymentTarget(amount)
                    }
                }

                if let dueDate {
                    cardPaymentActionButton(
                        title: "Use card due date",
                        systemImage: "calendar.badge.clock"
                    ) {
                        useCardDueDate(dueDate)
                    }
                }
            }
        }
        .padding(AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.58,
            strokeOpacity: 0.44,
            shadowOpacity: 0.0,
            shadowRadius: 0,
            shadowY: 0,
            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
        )
    }

    private func cardPaymentActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))

                Text(title)
                    .font(.caption.weight(.semibold))

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, AppSpacing.small)
            .background(
                Capsule()
                    .fill(
                        CalderaCategoryStyle.style(for: .debtPayoff).primary.opacity(0.1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectedCardPaymentDetails: LinkedCardPaymentDetails? {
        plaid.cardPaymentDetails.first { card in
            card.account_id == selectedAccountID
        }
    }

    private func loadCardPaymentDetails() {
        isLoadingCardPaymentDetails = true
        cardPaymentDetailsLoadMessage = nil

        plaid.fetchCardPaymentDetails { response in
            isLoadingCardPaymentDetails = false

            if selectedCardPaymentDetails == nil,
               response?.consent_required != true,
               response?.error != "additional_consent_required" {
                cardPaymentDetailsLoadMessage = "Card payment details are not available for this linked card yet. You can keep planning manually."
            }
        }
    }

    private func addCardPaymentDetailsConsent() {
        guard let selectedAccount,
              !selectedAccount.account_id.isEmpty,
              let itemID = selectedAccount.item_id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !itemID.isEmpty else {
            cardPaymentDetailsLoadMessage = "Card payment details are not available for this linked card yet. You can keep planning manually."
            return
        }

        cardPaymentDetailsLoadMessage = nil
        plaid.createCardPaymentDetailsUpdateLinkToken(
            itemID: itemID,
            accountID: selectedAccount.account_id
        )
    }

    #if DEBUG
    private func refreshCardPaymentDetailsForDebug() {
        isRefreshingCardPaymentDetails = true
        plaid.fetchCardPaymentDetails(reason: .debugTool) { _ in
            isRefreshingCardPaymentDetails = false
        }
    }
    #endif

    private func usePaymentTarget(
        _ amount: Double
    ) {
        paymentTargetText = cardPaymentAmountInputText(amount)
        cardPaymentActionMessage = "Payment target updated. Review and save when ready."
    }

    private func useCardDueDate(
        _ date: Date
    ) {
        dueDate = date
        dueDateChanged()
        cardPaymentActionMessage = "Due date updated. Review and save when ready."
    }

    private func cardPaymentAmountInputText(
        _ value: Double
    ) -> String {
        String(
            format: "%.2f",
            value
        )
    }

    private func parsedCardDueDate(
        _ value: String?
    ) -> Date? {
        guard let value,
              !value.isEmpty else {
            return nil
        }

        return Self.cardDueDateFormatter.date(from: value)
    }

    private static let cardDueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
