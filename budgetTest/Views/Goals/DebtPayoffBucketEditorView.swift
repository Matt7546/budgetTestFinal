import SwiftUI

struct DebtPayoffBucketDraft {
    let debtKind: DebtPayoffKind
    let plaidAccountID: String
    let accountName: String
    let institutionName: String?
    let dueDate: Date
    let paymentTargetAmount: Double
    let protectedAmount: Double
    let manualCurrentBalance: Double?
    let monthlyPayment: Double?
    let originalBalance: Double?
    let interestRate: Double?
    let notes: String?
    let hasPaymentDueDate: Bool?
    let startDate: Date?
    let endDate: Date?
}

struct DebtPayoffBucketEditorView: View {

    private enum CreditCardSource: String, CaseIterable, Identifiable {
        case linked
        case manual

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .linked:
                return "Linked Account"

            case .manual:
                return "Manual Entry"
            }
        }

        var helper: String {
            switch self {
            case .linked:
                return "Use a linked Plaid credit card balance."

            case .manual:
                return "Enter the card and balance yourself."
            }
        }
    }

    let debtAccounts: [PlaidAccount]
    let balanceLastUpdatedText: String?
    let bucket: DebtPayoffBucket?
    let onSave: (DebtPayoffBucketDraft) -> Void
    let onDelete: ((DebtPayoffBucket) -> Void)?

    @Environment(\.dismiss)
    private var dismiss

    @State private var selectedKind: DebtPayoffKind
    @State private var creditCardSource: CreditCardSource
    @State private var hasSelectedDebtType: Bool
    @State private var hasSelectedCreditCardSource: Bool
    @State private var hasConfirmedCreditCardDueDate: Bool
    @State private var selectedAccountID: String
    @State private var linkedNicknameText: String
    @State private var manualNameText: String
    @State private var manualBalanceText: String
    @State private var paymentAmountText: String
    @State private var hasManuallyEditedPaymentTarget: Bool
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var protectedAmountText: String
    @State private var originalBalanceText: String
    @State private var interestRateText: String
    @State private var notesText: String
    @State private var includesStartDate: Bool
    @State private var startDate: Date
    @State private var includesEndDate: Bool
    @State private var endDate: Date
    @State private var showsOptionalTrackingDetails: Bool

    init(
        debtAccounts: [PlaidAccount],
        balanceLastUpdatedText: String? = nil,
        bucket: DebtPayoffBucket?,
        onSave: @escaping (DebtPayoffBucketDraft) -> Void,
        onDelete: ((DebtPayoffBucket) -> Void)? = nil
    ) {
        let linkedCreditAccounts = debtAccounts.creditAccounts

        self.debtAccounts = linkedCreditAccounts
        self.balanceLastUpdatedText = balanceLastUpdatedText
        self.bucket = bucket
        self.onSave = onSave
        self.onDelete = onDelete

        let isEditing = bucket != nil
        let initialKind = bucket?.debtKind ?? .linkedCreditCard
        let initialCreditCardSource = DebtPayoffBucketEditorView.initialCreditCardSource(
            bucket: bucket,
            linkedCreditAccounts: linkedCreditAccounts
        )
        let initialAccountID = bucket?.plaidAccountID ?? ""
        let initialPaymentTarget = DebtPayoffBucketEditorView.initialPaymentTarget(
            bucket: bucket,
            kind: initialKind,
            creditCardSource: initialCreditCardSource,
            accountID: initialAccountID,
            linkedCreditAccounts: linkedCreditAccounts
        )
        let initialStartDate = bucket?.startDate ?? Date()
        let initialEndDate = bucket?.endDate ??
            Calendar.current.date(
                byAdding: .year,
                value: 4,
                to: initialStartDate
            ) ?? initialStartDate

        _selectedKind = State(initialValue: initialKind)
        _creditCardSource = State(initialValue: initialCreditCardSource)
        _hasSelectedDebtType = State(initialValue: isEditing)
        _hasSelectedCreditCardSource = State(initialValue: isEditing && initialKind == .linkedCreditCard)
        _hasConfirmedCreditCardDueDate = State(initialValue: isEditing && initialKind == .linkedCreditCard)
        _selectedAccountID = State(initialValue: initialAccountID)
        _linkedNicknameText = State(initialValue: initialKind == .linkedCreditCard ? bucket?.accountName ?? "" : "")
        _manualNameText = State(
            initialValue: initialKind.isManualInstallmentDebt || initialCreditCardSource == .manual
                ? bucket?.accountName ?? ""
                : ""
        )
        _manualBalanceText = State(initialValue: DebtPayoffBucketEditorView.textValue(bucket?.manualCurrentBalance))
        _paymentAmountText = State(initialValue: DebtPayoffBucketEditorView.textValue(initialPaymentTarget))
        _hasManuallyEditedPaymentTarget = State(
            initialValue: (bucket?.paymentTargetAmount ?? 0) > 0 ||
                (bucket?.monthlyPayment ?? 0) > 0
        )
        _dueDate = State(initialValue: bucket?.dueDate ?? Date())
        _hasDueDate = State(initialValue: bucket?.shouldDisplayDueDate ?? true)
        _protectedAmountText = State(initialValue: DebtPayoffBucketEditorView.textValue(bucket?.protectedAmount))
        _originalBalanceText = State(initialValue: DebtPayoffBucketEditorView.textValue(bucket?.originalBalance))
        _interestRateText = State(initialValue: DebtPayoffBucketEditorView.percentTextValue(bucket?.interestRate))
        _notesText = State(initialValue: bucket?.notes ?? "")
        _includesStartDate = State(initialValue: bucket?.startDate != nil)
        _startDate = State(initialValue: initialStartDate)
        _includesEndDate = State(initialValue: bucket?.endDate != nil)
        _endDate = State(initialValue: initialEndDate)
        _showsOptionalTrackingDetails = State(
            initialValue: bucket?.originalBalance != nil ||
                bucket?.interestRate != nil ||
                bucket?.startDate != nil ||
                bucket?.endDate != nil ||
                !(bucket?.notes ?? "").isEmpty
        )
    }

    private var selectedAccount: PlaidAccount? {
        debtAccounts.first {
            $0.account_id == selectedAccountID
        }
    }

    private var currentBalance: Double {
        parsedAmount(manualBalanceText)
    }

    private var paymentAmount: Double {
        parsedAmount(paymentAmountText)
    }

    private var paymentTargetTextBinding: Binding<String> {
        Binding(
            get: {
                paymentAmountText
            },
            set: { newValue in
                paymentAmountText = newValue
                hasManuallyEditedPaymentTarget = true
            }
        )
    }

    private var protectedAmount: Double {
        parsedAmount(protectedAmountText)
    }

    private var trimmedManualName: String {
        manualNameText
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var optionalOriginalBalance: Double? {
        optionalAmount(originalBalanceText)
    }

    private var optionalInterestRate: Double? {
        optionalPercent(interestRateText)
    }

    private var creditCardBalance: Double {
        selectedAccount?.debtBalanceValue ?? 0
    }

    private var linkedCreditCardBalanceIsKnown: Bool {
        selectedAccount != nil
    }

    private var creditCardPaymentTarget: Double {
        guard selectedKind == .linkedCreditCard else {
            return 0
        }

        if hasManuallyEditedPaymentTarget,
           paymentAmount > 0 {
            return paymentAmount
        }

        switch creditCardSource {
        case .linked:
            return creditCardBalance

        case .manual:
            return currentBalance
        }
    }

    private var creditCardSourceIsReady: Bool {
        guard selectedKind == .linkedCreditCard else {
            return false
        }

        guard hasSelectedCreditCardSource else {
            return false
        }

        switch creditCardSource {
        case .linked:
            return !selectedAccountID.isEmpty

        case .manual:
            return !manualNameText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty &&
                currentBalance > 0
        }
    }

    private var manualDebtDetailsAreReady: Bool {
        selectedKind.isManualInstallmentDebt &&
            !trimmedManualName.isEmpty &&
            currentBalance > 0
    }

    private var paymentTargetIsReady: Bool {
        setAsideTarget > 0
    }

    private var creditCardBalanceIsAvailable: Bool {
        switch creditCardSource {
        case .linked:
            return linkedCreditCardBalanceIsKnown

        case .manual:
            return currentBalance > 0
        }
    }

    private var setAsideTarget: Double {
        if selectedKind == .linkedCreditCard {
            return creditCardPaymentTarget
        }

        guard paymentAmount > 0 else {
            return 0
        }

        return paymentAmount
    }

    private var paymentTargetExceedsCachedBalance: Bool {
        selectedKind == .linkedCreditCard &&
            creditCardSource == .linked &&
            creditCardBalance > 0 &&
            paymentAmount > creditCardBalance
    }

    private var linkedBalanceSyncText: String {
        guard let balanceLastUpdatedText,
              balanceLastUpdatedText != "Not refreshed yet" else {
            return "Balance not refreshed yet"
        }

        return "Balance synced with Plaid · \(balanceLastUpdatedText)"
    }

    private var availableDebtKinds: [DebtPayoffKind] {
        DebtPayoffKind.allCases
    }

    private var canSave: Bool {
        switch selectedKind {
        case .linkedCreditCard:
            return hasSelectedDebtType &&
                creditCardSourceIsReady &&
                hasConfirmedCreditCardDueDate &&
                creditCardBalanceIsAvailable &&
                setAsideTarget > 0 &&
                protectedAmount > 0 &&
                protectedAmount <= setAsideTarget

        case .autoLoan,
             .mortgage,
             .studentLoan,
             .personalLoan,
             .other:
            return hasSelectedDebtType &&
                !manualNameText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty &&
                currentBalance > 0 &&
                paymentAmount > 0 &&
                protectedAmount > 0 &&
                protectedAmount <= paymentAmount &&
                optionalAmountIsValid(originalBalanceText) &&
                optionalPercentIsValid(interestRateText) &&
                optionalDateRangeIsValid
        }
    }

    private var optionalDateRangeIsValid: Bool {
        guard includesStartDate,
              includesEndDate else {
            return true
        }

        return endDate >= startDate
    }

    private var shouldShowValidationFooter: Bool {
        guard hasSelectedDebtType,
              !canSave else {
            return false
        }

        if selectedKind == .linkedCreditCard {
            return hasConfirmedCreditCardDueDate
        }

        return manualDebtDetailsAreReady ||
            !trimmedManualName.isEmpty ||
            !manualBalanceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var title: String {
        bucket == nil
            ? "Add Debt Payoff"
            : "Edit Debt Payoff"
    }

    private var subtitle: String {
        bucket == nil
            ? "Set money aside for card payments, loans, or other debts."
            : "Update payment details and money set aside."
    }

    var body: some View {
        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                backgroundStyle: .staticGradient,
                contentPadding: .all,
                contentSpacing: AppSpacing.regular
            ) {
                ModalHeaderView(
                    eyebrow: "Debt Payoff",
                    title: title,
                    subtitle: subtitle,
                    systemImage: CalderaCategoryStyle.style(for: .debtPayoff).icon,
                    color: CalderaCategoryStyle.style(for: .debtPayoff).primary
                )

                typeSection

                if hasSelectedDebtType {
                    if selectedKind == .linkedCreditCard {
                        creditCardFlowSections
                    } else {
                        debtDetailsSection

                        if manualDebtDetailsAreReady {
                            scheduleSection

                            paymentInfoSection

                            if paymentTargetIsReady {
                                setAsideSection

                                optionalTrackingSection
                            }
                        }
                    }
                }

                if shouldShowValidationFooter {
                    validationFooter
                }

                if let bucket,
                   let onDelete {
                    deleteButton(
                        bucket,
                        onDelete: onDelete
                    )
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                    .accessibilityLabel("Save")
                }
            }
            .keyboardDismissToolbar()
            .onAppear {
                autofillPaymentTargetIfNeeded()
            }
            .onChange(of: selectedAccountID) { _, newValue in
                if selectedKind == .linkedCreditCard,
                   creditCardSource == .linked,
                   hasSelectedCreditCardSource,
                   !newValue.isEmpty {
                    hasConfirmedCreditCardDueDate = false
                }
                autofillPaymentTargetIfNeeded()
            }
            .onChange(of: creditCardBalance) { _, _ in
                autofillPaymentTargetIfNeeded()
            }
            .onChange(of: manualBalanceText) { _, _ in
                autofillPaymentTargetIfNeeded()
            }
        }
    }

    private var typeSection: some View {
        editorCard(
            title: "Debt Type",
            systemImage: "square.grid.2x2.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            VStack(spacing: AppSpacing.small) {
                ForEach(availableDebtKinds) { kind in
                    debtTypeButton(kind)
                }
            }

            Text(typeDescription)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .topLeading)
        }
        .onChange(of: selectedKind) { _, newKind in
            hasSelectedDebtType = true

            if newKind == .linkedCreditCard {
                resetCreditCardFlowAfterTypeChange()
            }

            if newKind.isManualInstallmentDebt {
                hasDueDate = true
                if !hasManuallyEditedPaymentTarget {
                    paymentAmountText = ""
                }
            }
            autofillPaymentTargetIfNeeded()
        }
    }

    private func debtTypeButton(
        _ kind: DebtPayoffKind
    ) -> some View {
        let isSelected = hasSelectedDebtType && selectedKind == kind

        return Button {
            let changedKind = selectedKind != kind
            let wasDebtTypeSelected = hasSelectedDebtType
            selectedKind = kind
            hasSelectedDebtType = true

            if kind == .linkedCreditCard,
               changedKind || !wasDebtTypeSelected {
                resetCreditCardFlowAfterTypeChange()
            }

            if kind.isManualInstallmentDebt {
                hasDueDate = true
                if changedKind,
                   !hasManuallyEditedPaymentTarget {
                    paymentAmountText = ""
                }
            }

            autofillPaymentTargetIfNeeded()
        } label: {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.medium)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: isSelected ? 0.90 : 0.76,
                strokeOpacity: isSelected ? 0.78 : 0.46,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
    }

    @ViewBuilder
    private var creditCardFlowSections: some View {
        creditCardSourceSection

        if hasSelectedCreditCardSource {
            creditCardDetailsSection
        }

        if creditCardSourceIsReady {
            creditCardDueDateSection
        }

        if hasConfirmedCreditCardDueDate {
            creditCardPaymentTargetSection

            if paymentTargetIsReady {
                creditCardSetAsideSection
            }
        }
    }

    private var creditCardSourceSection: some View {
        editorCard(
            title: "Track Debt",
            systemImage: "rectangle.stack.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            VStack(spacing: AppSpacing.small) {
                ForEach(CreditCardSource.allCases) { source in
                    creditCardSourceButton(source)
                }
            }
        }
    }

    private func creditCardSourceButton(
        _ source: CreditCardSource
    ) -> some View {
        Button {
            let changedSource = creditCardSource != source
            creditCardSource = source
            hasSelectedCreditCardSource = true

            if changedSource {
                resetCreditCardFlowAfterSourceChange(to: source)
            }

            autofillPaymentTargetIfNeeded()
        } label: {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: creditCardSource == source ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text(source.helper)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.medium)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: creditCardSource == source ? 0.90 : 0.76,
                strokeOpacity: creditCardSource == source ? 0.78 : 0.46,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source.title)
        .accessibilityHint(source.helper)
    }

    private var creditCardDetailsSection: some View {
        editorCard(
            title: creditCardSource == .linked ? "Linked Account" : "Card Details",
            systemImage: "creditcard.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            if creditCardSource == .linked {
                linkedCreditCardFields
            } else {
                manualCreditCardFields
            }
        }
    }

    private var debtDetailsSection: some View {
        editorCard(
            title: selectedKind == .linkedCreditCard ? "Linked Card" : "Debt Details",
            systemImage: selectedKind == .linkedCreditCard ? "creditcard.fill" : "building.columns.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            if selectedKind == .linkedCreditCard {
                linkedCreditCardFields
            } else {
                manualDebtFields
            }
        }
    }

    @ViewBuilder
    private var linkedCreditCardFields: some View {
        if debtAccounts.isEmpty {
            Text("No linked credit cards are available. Choose Manual Entry to add the card yourself, or refresh bank data in Settings.")
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
                    Text("\(AppFormatters.currency(selectedAccount.debtBalanceValue)) cached balance")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .accessibilityLabel("Cached balance")

                    Text(linkedBalanceSyncText)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Your card balance only changes when the issuer reports a real payment.")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)

                    if selectedAccount.debtBalanceValue <= 0 {
                        Text("Enter a payment target to set aside money for this card.")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(AppColors.secondaryText.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("Balance unavailable. Choose a linked card or refresh bank data in More.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
            }

            labeledTextField(
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
            labeledTextField(
                title: "Card Name",
                placeholder: "Credit Card",
                text: $manualNameText,
                subtitle: "Shown on Debt Payoff cards."
            )

            AmountEntryField(
                title: "Current Balance",
                subtitle: "The amount currently owed. This only changes when your card issuer reports a real payment.",
                placeholder: "0.00",
                text: $manualBalanceText,
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                accessibilityLabel: "Current balance"
            )
        }
    }

    private var creditCardDueDateSection: some View {
        editorCard(
            title: "Due Date",
            systemImage: "calendar",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            DatePicker(
                "Due Date",
                selection: $dueDate,
                displayedComponents: .date
            )
            .accessibilityLabel("Card due date")
            .onChange(of: dueDate) { _, _ in
                hasConfirmedCreditCardDueDate = true
            }

            Text("Used to show when this card payment is coming up.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !hasConfirmedCreditCardDueDate {
                Button {
                    hasConfirmedCreditCardDueDate = true
                } label: {
                    Text("Use this date")
                        .font(.caption.weight(.bold))
                        .foregroundColor(CalderaCategoryStyle.style(for: .debtPayoff).primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.small)
                        .calderaGlassCard(
                            cornerRadius: AppRadii.field,
                            fillOpacity: 0.82,
                            strokeOpacity: 0.62,
                            shadowOpacity: 0.0,
                            shadowRadius: 0,
                            shadowY: 0,
                            darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use this due date")
            }
        }
    }

    private var creditCardPaymentTargetSection: some View {
        editorCard(
            title: "Payment Target",
            systemImage: "dollarsign.circle.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            AmountEntryField(
                title: "Payment Target",
                subtitle: "The payment amount you want to plan for.",
                placeholder: "0.00",
                text: paymentTargetTextBinding,
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                accessibilityLabel: "Payment target"
            )

            if paymentTargetExceedsCachedBalance {
                Text("Payment Target is above the cached card balance. Amount to Set Aside is capped at the card balance.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var creditCardSetAsideSection: some View {
        editorCard(
            title: "Amount to Set Aside",
            systemImage: CalderaCategoryStyle.style(for: .reserve).icon,
            color: CalderaCategoryStyle.style(for: .reserve).primary
        ) {
            amountField(
                title: "Amount to Set Aside",
                text: $protectedAmountText,
                placeholder: "0.00"
            )

            Text("Payment target: \(AppFormatters.currency(setAsideTarget)).")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if protectedAmount > setAsideTarget,
               setAsideTarget > 0 {
                Text(setAsideLimitMessage)
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var manualDebtFields: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            labeledTextField(
                title: manualNameTitle,
                placeholder: selectedKind.title,
                text: $manualNameText,
                subtitle: "Shown on Debt Payoff cards."
            )

            AmountEntryField(
                title: "Current Balance",
                subtitle: "Amount still owed. This only changes when your lender reports a real payment.",
                placeholder: "0.00",
                text: $manualBalanceText,
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                accessibilityLabel: "Current balance"
            )
        }
    }

    private var paymentInfoSection: some View {
        editorCard(
            title: "Payment Target",
            systemImage: "dollarsign.circle.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            AmountEntryField(
                title: "Payment Target",
                subtitle: "The payment amount you want to plan for.",
                placeholder: "0.00",
                text: paymentTargetTextBinding,
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                accessibilityLabel: "Payment target"
            )

            if paymentTargetExceedsCachedBalance {
                Text("Payment Target is above the cached card balance. Set aside is capped at the card balance.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scheduleSection: some View {
        editorCard(
            title: "Due Date",
            systemImage: "calendar",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            if selectedKind == .linkedCreditCard {
                Toggle(
                    "Track due date",
                    isOn: $hasDueDate
                )
                .tint(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                if hasDueDate {
                    DatePicker(
                        "Payment Due Date",
                        selection: $dueDate,
                        displayedComponents: .date
                    )
                        .accessibilityLabel("Payment due date")
                }
            } else {
                DatePicker(
                    "Next Due Date",
                    selection: $dueDate,
                    displayedComponents: .date
                )
                .accessibilityLabel("Next due date")
            }
        }
    }

    private var setAsideSection: some View {
        editorCard(
            title: "Amount to Set Aside",
            systemImage: CalderaCategoryStyle.style(for: .reserve).icon,
            color: CalderaCategoryStyle.style(for: .reserve).primary
        ) {
            amountField(
                title: "Amount to Set Aside",
                text: $protectedAmountText,
                placeholder: "0.00"
            )

            Text("Payment target: \(AppFormatters.currency(setAsideTarget)).")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if protectedAmount > setAsideTarget,
               setAsideTarget > 0 {
                Text(setAsideLimitMessage)
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private var optionalTrackingSection: some View {
        if selectedKind.isManualInstallmentDebt {
            editorCard(
                title: "More Details",
                systemImage: "slider.horizontal.3",
                color: CalderaCategoryStyle.style(for: .debtPayoff).primary
            ) {
                DisclosureGroup(
                    isExpanded: $showsOptionalTrackingDetails
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.small
                    ) {
                        AmountEntryField(
                            title: "Original Balance",
                            subtitle: "Optional. For payoff progress.",
                            placeholder: "0.00",
                            text: $originalBalanceText,
                            style: CalderaCategoryStyle.style(for: .debtPayoff),
                            accessibilityLabel: "Original balance"
                        )

                        percentageField(
                            title: "Interest Rate / APR",
                            placeholder: "Optional APR",
                            text: $interestRateText,
                            subtitle: "Optional payoff detail."
                        )

                        Toggle(
                            "Add start date",
                            isOn: $includesStartDate
                        )
                        .tint(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                        if includesStartDate {
                            DatePicker(
                                "Start Date",
                                selection: $startDate,
                                displayedComponents: .date
                            )
                            .accessibilityLabel("Start date")
                        }

                        Toggle(
                            "Add end date",
                            isOn: $includesEndDate
                        )
                        .tint(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                        if includesEndDate {
                            DatePicker(
                                "End Date",
                                selection: $endDate,
                                displayedComponents: .date
                            )
                            .accessibilityLabel("End date")
                        }

                        if !optionalDateRangeIsValid {
                            Text("End date must be after the start date.")
                                .font(.caption.weight(.medium))
                                .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
                        }

                        notesField
                    }
                    .padding(.top, AppSpacing.small)
                } label: {
                    Text("Optional balance, APR, dates, and notes")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColors.primaryText)
                }
                .tint(CalderaCategoryStyle.style(for: .debtPayoff).primary)
            }
        }
    }

    private var notesField: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text("Notes")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)

            Text("Optional. Add anything useful about this debt.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)

            TextEditor(text: $notesText)
                .frame(minHeight: 72)
                .padding(AppSpacing.small)
                .scrollContentBackground(.hidden)
                .calderaGlassCard(
                    cornerRadius: AppRadii.field,
                    fillOpacity: 0.86,
                    strokeOpacity: 0.68,
                    shadowOpacity: 0.0,
                    shadowRadius: 0,
                    shadowY: 0,
                    darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
                )
                .accessibilityLabel("Notes")
        }
    }

    private var typeDescription: String {
        guard hasSelectedDebtType else {
            return "Choose the debt payment you want to plan for."
        }

        switch selectedKind {
        case .linkedCreditCard:
            return "Set money aside for a card payment."

        case .autoLoan:
            return "Set money aside for an auto loan payment."

        case .mortgage:
            return "Set money aside for a mortgage payment."

        case .studentLoan:
            return "Set money aside for a student loan payment."

        case .personalLoan:
            return "Set money aside for a personal loan payment."

        case .other:
            return "Set money aside for another debt payment."
        }
    }

    private var manualNameTitle: String {
        switch selectedKind {
        case .studentLoan:
            return "Servicer or Loan Name"

        case .mortgage:
            return "Mortgage or Lender Name"

        default:
            return "Lender or Debt Name"
        }
    }

    private var saveDisabledMessage: String {
        switch selectedKind {
        case .linkedCreditCard:
            if !hasSelectedCreditCardSource {
                return "Choose how to track this card."
            }

            if creditCardSource == .linked {
                if selectedAccountID.isEmpty {
                    return "Choose a linked account to continue."
                }

                if !hasConfirmedCreditCardDueDate {
                    return "Choose a due date to continue."
                }
            }

            if setAsideTarget <= 0 {
                return "Add a Payment Target to save."
            }

            if protectedAmount <= 0 {
                return "Add an Amount to Set Aside to save."
            }

            return "Amount to Set Aside cannot be more than the Payment Target."

        case .autoLoan,
             .mortgage,
             .studentLoan,
             .personalLoan,
             .other:
            if trimmedManualName.isEmpty {
                return "Add a name to continue."
            }

            if currentBalance <= 0 {
                return "Add the current balance to continue."
            }

            if paymentAmount <= 0 {
                return "Add a Payment Target to continue."
            }

            if protectedAmount <= 0 {
                return "Add an Amount to Set Aside to save."
            }

            if protectedAmount > paymentAmount {
                return "Amount to Set Aside cannot be more than the Payment Target."
            }

            if !optionalDateRangeIsValid {
                return "End date must be after the start date."
            }

            return "Complete the required fields to save."
        }
    }

    private var setAsideLimitMessage: String {
        if selectedKind == .linkedCreditCard {
            return "Amount to Set Aside is capped at \(AppFormatters.currency(setAsideTarget)) for now."
        }

        return "Amount to Set Aside is capped at the Payment Target for now."
    }

    private var validationFooter: some View {
        Text(saveDisabledMessage)
            .font(.caption.weight(.medium))
            .foregroundColor(AppColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func editorCard<Content: View>(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        CalderaEditorFormCard(
            title: title,
            systemImage: systemImage,
            color: color
        ) {
            content()
        }
    }

    private func labeledTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        subtitle: String? = nil
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            TextField(
                placeholder,
                text: text
            )
            .textInputAutocapitalization(.words)
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
            .accessibilityLabel(title)
        }
    }

    private func percentageField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        subtitle: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)

            TextField(
                placeholder,
                text: text
            )
            .keyboardType(.decimalPad)
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
            .accessibilityLabel(title)
        }
    }

    private func amountField(
        title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        AmountEntryField(
            title: title,
            subtitle: "Money Caldera keeps out of Available to Spend for this payment. This does not make a payment or change your bank balance.",
            placeholder: placeholder,
            text: text,
            style: CalderaCategoryStyle.style(for: .reserve),
            accessibilityLabel: title
        )
    }

    private func deleteButton(
        _ bucket: DebtPayoffBucket,
        onDelete: @escaping (DebtPayoffBucket) -> Void
    ) -> some View {
        DestructiveButton(
            "Delete Debt Payoff",
            systemImage: "trash.fill",
            cornerRadius: AppRadii.button
        ) {
            onDelete(bucket)
            dismiss()
        }
    }

    private func resetCreditCardFlowAfterTypeChange() {
        hasSelectedCreditCardSource = false
        hasConfirmedCreditCardDueDate = false
        selectedAccountID = ""
        linkedNicknameText = ""
        manualNameText = ""
        manualBalanceText = ""
        paymentAmountText = ""
        hasManuallyEditedPaymentTarget = false
    }

    private func resetCreditCardFlowAfterSourceChange(
        to source: CreditCardSource
    ) {
        hasConfirmedCreditCardDueDate = false
        paymentAmountText = ""
        hasManuallyEditedPaymentTarget = false

        switch source {
        case .linked:
            manualNameText = ""
            manualBalanceText = ""

        case .manual:
            selectedAccountID = ""
            linkedNicknameText = ""
        }
    }

    private func autofillPaymentTargetIfNeeded() {
        guard !hasManuallyEditedPaymentTarget,
              selectedKind == .linkedCreditCard else {
            return
        }

        switch creditCardSource {
        case .linked:
            guard creditCardBalance > 0 else {
                return
            }

            paymentAmountText = Self.textValue(creditCardBalance)

        case .manual:
            guard currentBalance > 0 else {
                return
            }

            paymentAmountText = Self.textValue(currentBalance)
        }
    }

    private func save() {
        guard canSave else {
            return
        }

        let selectedCardName = selectedAccount?.name ?? ""
        let nickname = linkedNicknameText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let manualName = manualNameText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = notesText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let savedPaymentTarget = selectedKind == .linkedCreditCard
            ? setAsideTarget
            : paymentAmount
        let isLinkedCreditCard = selectedKind == .linkedCreditCard &&
            creditCardSource == .linked

        onSave(
            DebtPayoffBucketDraft(
                debtKind: selectedKind,
                plaidAccountID: isLinkedCreditCard ? selectedAccountID : "",
                accountName: selectedKind == .linkedCreditCard
                    ? (
                        isLinkedCreditCard
                            ? (nickname.isEmpty ? selectedCardName : nickname)
                            : manualName
                    )
                    : manualName,
                institutionName: isLinkedCreditCard
                    ? selectedAccount?.institution_name
                    : nil,
                dueDate: dueDate,
                paymentTargetAmount: savedPaymentTarget,
                protectedAmount: protectedAmount,
                manualCurrentBalance: selectedKind == .linkedCreditCard
                    ? (
                        isLinkedCreditCard
                            ? nil
                            : currentBalance
                    )
                    : currentBalance,
                monthlyPayment: selectedKind == .linkedCreditCard
                    ? nil
                    : savedPaymentTarget,
                originalBalance: selectedKind.isManualInstallmentDebt
                    ? optionalOriginalBalance
                    : nil,
                interestRate: selectedKind.isManualInstallmentDebt
                    ? optionalInterestRate
                    : nil,
                notes: selectedKind.isManualInstallmentDebt && !notes.isEmpty
                    ? notes
                    : nil,
                hasPaymentDueDate: selectedKind == .linkedCreditCard
                    ? hasDueDate
                    : true,
                startDate: selectedKind.isManualInstallmentDebt && includesStartDate
                    ? startDate
                    : nil,
                endDate: selectedKind.isManualInstallmentDebt && includesEndDate
                    ? endDate
                    : nil
            )
        )
        dismiss()
    }

    private func parsedAmount(
        _ text: String
    ) -> Double {
        let sanitized = sanitizedAmountText(text)

        guard !sanitized.isEmpty else {
            return 0
        }

        return max(Double(sanitized) ?? -1, -1)
    }

    private func optionalAmount(
        _ text: String
    ) -> Double? {
        let sanitized = sanitizedAmountText(text)

        guard !sanitized.isEmpty else {
            return nil
        }

        guard let value = Double(sanitized),
              value > 0 else {
            return nil
        }

        return value
    }

    private func optionalAmountIsValid(
        _ text: String
    ) -> Bool {
        let sanitized = sanitizedAmountText(text)

        guard !sanitized.isEmpty else {
            return true
        }

        guard let value = Double(sanitized) else {
            return false
        }

        return value >= 0
    }

    private func optionalPercent(
        _ text: String
    ) -> Double? {
        let trimmed = sanitizedPercentText(text)

        guard !trimmed.isEmpty else {
            return nil
        }

        guard let value = Double(trimmed),
              value > 0 else {
            return nil
        }

        return value
    }

    private func optionalPercentIsValid(
        _ text: String
    ) -> Bool {
        let trimmed = sanitizedPercentText(text)

        guard !trimmed.isEmpty else {
            return true
        }

        guard let value = Double(trimmed) else {
            return false
        }

        return value >= 0
    }

    private func sanitizedAmountText(
        _ text: String
    ) -> String {
        text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedPercentText(
        _ text: String
    ) -> String {
        text
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func initialPaymentTarget(
        bucket: DebtPayoffBucket?,
        kind: DebtPayoffKind,
        creditCardSource: CreditCardSource,
        accountID: String,
        linkedCreditAccounts: [PlaidAccount]
    ) -> Double? {
        if let bucket {
            if bucket.paymentTargetAmount > 0 {
                return bucket.paymentTargetAmount
            }

            return bucket.monthlyPayment
        }

        guard kind == .linkedCreditCard else {
            return nil
        }

        if creditCardSource == .manual {
            return bucket?.manualCurrentBalance
        }

        return linkedCreditAccounts
            .first { $0.account_id == accountID }?
            .debtBalanceValue
    }

    private static func initialCreditCardSource(
        bucket: DebtPayoffBucket?,
        linkedCreditAccounts: [PlaidAccount]
    ) -> CreditCardSource {
        guard bucket?.debtKind == .linkedCreditCard else {
            return linkedCreditAccounts.isEmpty ? .manual : .linked
        }

        if let bucket,
           bucket.plaidAccountID.isEmpty || bucket.manualCurrentBalance != nil {
            return .manual
        }

        return .linked
    }

    private static func textValue(
        _ value: Double?
    ) -> String {
        guard let value,
              value > 0 else {
            return ""
        }

        return String(
            format: "%.2f",
            value
        )
    }

    private static func percentTextValue(
        _ value: Double?
    ) -> String {
        guard let value,
              value > 0 else {
            return ""
        }

        return String(
            format: "%.2f",
            value
        )
    }
}
