import SwiftUI

struct DebtPayoffEditorCreditCardSourceSection: View {

    let selectedSource: DebtPayoffCreditCardSource
    let selectSource: (DebtPayoffCreditCardSource) -> Void

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "How do you want to track it?",
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
    let allowsIdentityEditing: Bool

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
            title: "Payment Details",
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
        if !allowsIdentityEditing {
            readOnlyLinkedCardContext
            cardPaymentDetailsCardIfAvailable
        } else if debtAccounts.isEmpty {
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

    private var readOnlyLinkedCardContext: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Linked card")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            Text(readOnlyLinkedCardName)
                .font(.headline.weight(.semibold))
                .foregroundColor(AppColors.ink)

            if let selectedAccount {
                Text("Current balance: \(AppFormatters.currency(selectedAccount.debtBalanceValue))")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                Text(linkedBalanceSyncText)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This linked card is attached to the payment plan. You can still update the due date, Payment Target, and Amount to Set Aside.")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("To change the linked card, create a new payment plan.")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readOnlyLinkedCardName: String {
        if let selectedAccount {
            return accountLabel(selectedAccount)
        }

        let trimmedNickname = linkedNicknameText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedNickname.isEmpty ? "Linked card" : trimmedNickname
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

                cardPaymentSuggestedUpdatesCard(card)

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
    private func cardPaymentSuggestedUpdatesCard(
        _ card: LinkedCardPaymentDetails
    ) -> some View {
        let suggestions = cardPaymentSuggestions(for: card)

        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Suggested updates")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.ink)

                    Text("Caldera found card details that may help update this plan.")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: AppSpacing.xSmall) {
                    ForEach(suggestions) { suggestion in
                        cardPaymentSuggestionRow(suggestion)
                    }
                }

                Text("These only update your plan. They do not make a payment.")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
    }

    private func cardPaymentSuggestionRow(
        _ suggestion: CardPaymentSuggestedUpdate
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xSmall) {
                Image(systemName: suggestion.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                Text(suggestion.detailText)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            Button {
                applyCardPaymentSuggestion(suggestion)
            } label: {
                HStack(spacing: AppSpacing.xSmall) {
                    Text(suggestion.actionTitle)
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
        .padding(AppSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: AppRadii.field, style: .continuous)
                .fill(AppColors.glassOverlaySurface)
        )
    }

    private func cardPaymentSuggestions(
        for card: LinkedCardPaymentDetails
    ) -> [CardPaymentSuggestedUpdate] {
        var suggestions: [CardPaymentSuggestedUpdate] = []
        var suggestedAmounts: [Double] = []

        appendPaymentTargetSuggestion(
            .statementBalance,
            amount: card.last_statement_balance,
            suggestions: &suggestions,
            suggestedAmounts: &suggestedAmounts
        )

        appendPaymentTargetSuggestion(
            .minimumPayment,
            amount: card.minimum_payment_amount,
            suggestions: &suggestions,
            suggestedAmounts: &suggestedAmounts
        )

        appendPaymentTargetSuggestion(
            .currentBalance,
            amount: card.current_balance,
            suggestions: &suggestions,
            suggestedAmounts: &suggestedAmounts
        )

        if let cardDueDate = parsedCardDueDate(card.next_payment_due_date),
           !Calendar.current.isDate(cardDueDate, inSameDayAs: dueDate) {
            suggestions.append(
                .dueDate(cardDueDate)
            )
        }

        return suggestions
    }

    private func appendPaymentTargetSuggestion(
        _ kind: CardPaymentSuggestedUpdate.Kind,
        amount: Double?,
        suggestions: inout [CardPaymentSuggestedUpdate],
        suggestedAmounts: inout [Double]
    ) {
        guard let amount,
              amount > 0,
              !paymentTargetMatches(amount),
              !suggestedAmounts.contains(where: { moneyValuesMatch($0, amount) }) else {
            return
        }

        suggestions.append(
            CardPaymentSuggestedUpdate(kind: kind, amount: amount)
        )
        suggestedAmounts.append(amount)
    }

    private func paymentTargetMatches(
        _ amount: Double
    ) -> Bool {
        guard let currentPaymentTarget else {
            return false
        }

        return moneyValuesMatch(currentPaymentTarget, amount)
    }

    private var currentPaymentTarget: Double? {
        let sanitized = paymentTargetText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value = Double(sanitized),
              value > 0 else {
            return nil
        }

        return value
    }

    private func moneyValuesMatch(
        _ lhs: Double,
        _ rhs: Double
    ) -> Bool {
        abs(lhs - rhs) < 0.005
    }

    private func applyCardPaymentSuggestion(
        _ suggestion: CardPaymentSuggestedUpdate
    ) {
        switch suggestion {
        case .statementBalance(let amount),
             .minimumPayment(let amount),
             .currentBalance(let amount):
            usePaymentTarget(amount)
        case .dueDate(let date):
            useCardDueDate(date)
        }
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
            if allowsIdentityEditing {
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
            } else {
                readOnlyManualCardContext
            }
        }
    }

    private var readOnlyManualCardContext: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Manual card")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            Text(readOnlyManualCardName)
                .font(.headline.weight(.semibold))
                .foregroundColor(AppColors.ink)

            if let balance = readOnlyManualCardBalance {
                Text("Current balance: \(AppFormatters.currency(balance))")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
            }

            Text("To change the card identity, create a new payment plan.")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readOnlyManualCardName: String {
        let trimmedName = manualNameText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedName.isEmpty ? "Credit Card" : trimmedName
    }

    private var readOnlyManualCardBalance: Double? {
        let sanitized = manualBalanceText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value = Double(sanitized),
              value > 0 else {
            return nil
        }

        return value
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

private enum CardPaymentSuggestedUpdate: Identifiable {
    enum Kind {
        case statementBalance
        case minimumPayment
        case currentBalance
    }

    case statementBalance(Double)
    case minimumPayment(Double)
    case currentBalance(Double)
    case dueDate(Date)

    init(kind: Kind, amount: Double) {
        switch kind {
        case .statementBalance:
            self = .statementBalance(amount)
        case .minimumPayment:
            self = .minimumPayment(amount)
        case .currentBalance:
            self = .currentBalance(amount)
        }
    }

    var id: String {
        switch self {
        case .statementBalance:
            return "statementBalance"
        case .minimumPayment:
            return "minimumPayment"
        case .currentBalance:
            return "currentBalance"
        case .dueDate:
            return "dueDate"
        }
    }

    var systemImage: String {
        switch self {
        case .statementBalance:
            return "doc.text.fill"
        case .minimumPayment:
            return "dollarsign.circle.fill"
        case .currentBalance:
            return "creditcard.fill"
        case .dueDate:
            return "calendar.badge.clock"
        }
    }

    var detailText: String {
        switch self {
        case .statementBalance(let amount):
            return "Statement balance is \(AppFormatters.currency(amount))"
        case .minimumPayment(let amount):
            return "Minimum payment is \(AppFormatters.currency(amount))"
        case .currentBalance(let amount):
            return "Current balance is \(AppFormatters.currency(amount))"
        case .dueDate(let date):
            return "Card due date is \(AppFormatters.abbreviatedMonthDay(date))"
        }
    }

    var actionTitle: String {
        switch self {
        case .statementBalance:
            return "Use statement balance"
        case .minimumPayment:
            return "Use minimum payment"
        case .currentBalance:
            return "Use current balance"
        case .dueDate:
            return "Use card due date"
        }
    }
}
