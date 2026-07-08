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

    let debtAccounts: [PlaidAccount]
    let balanceLastUpdatedText: String?
    let bucket: DebtPayoffBucket?
    let onSave: (DebtPayoffBucketDraft) -> Void
    let onDelete: ((DebtPayoffBucket) -> Void)?

    @Environment(\.dismiss)
    private var dismiss

    @State private var selectedKind: DebtPayoffKind
    @State private var creditCardSource: DebtPayoffCreditCardSource
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
    @State private var showsDeleteConfirmation = false

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

        return "Card balance · \(balanceLastUpdatedText)"
    }

    private var availableDebtKinds: [DebtPayoffKind] {
        [
            .linkedCreditCard,
            .other
        ]
    }

    private var isEditing: Bool {
        bucket != nil
    }

    private var canSave: Bool {
        switch selectedKind {
        case .linkedCreditCard:
            return hasSelectedDebtType &&
                (isEditing || (creditCardSourceIsReady && creditCardBalanceIsAvailable)) &&
                setAsideTarget > 0 &&
                protectedAmount >= 0 &&
                protectedAmount <= setAsideTarget

        case .autoLoan,
             .mortgage,
             .studentLoan,
             .personalLoan,
             .other:
            return hasSelectedDebtType &&
                (isEditing ||
                    (!manualNameText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty && currentBalance > 0)) &&
                paymentAmount > 0 &&
                protectedAmount >= 0 &&
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

        if isEditing {
            return true
        }

        if selectedKind == .linkedCreditCard {
            return hasSelectedCreditCardSource
        }

        return manualDebtDetailsAreReady ||
            !trimmedManualName.isEmpty ||
            !manualBalanceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var title: String {
        bucket == nil
            ? "Plan a Payment"
            : "Edit Payment Plan"
    }

    private var subtitle: String {
        bucket == nil
            ? "Plan money for a card or other payment."
            : "Update the due date, Payment Target, and Amount to Set Aside."
    }

    var body: some View {
        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                backgroundStyle: .editorModal(.debtPayoff),
                contentPadding: .all,
                contentSpacing: AppSpacing.regular
            ) {
                ModalHeaderView(
                    eyebrow: "Payment Planning",
                    title: title,
                    subtitle: subtitle,
                    systemImage: CalderaCategoryStyle.style(for: .debtPayoff).icon,
                    color: CalderaCategoryStyle.style(for: .debtPayoff).primary
                )

                if !isEditing {
                    typeSection
                }

                if hasSelectedDebtType {
                    if isEditing {
                        editFlowSections
                    } else {
                        if selectedKind == .linkedCreditCard {
                            creditCardFlowSections
                        } else {
                            debtDetailsSection

                            if manualDebtDetailsAreReady {
                                scheduleSection

                                paymentInfoSection

                                if paymentTargetIsReady {
                                    setAsideSection
                                }
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
            .calderaTransparentNavigationSurface()
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
                    hasConfirmedCreditCardDueDate = true
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
        DebtPayoffEditorTypeSection(
            selectedDisplayKind: displayKind(for: selectedKind),
            hasSelectedDebtType: hasSelectedDebtType,
            availableDebtKinds: availableDebtKinds,
            typeDescription: typeDescription,
            selectKind: selectDebtKind
        )
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

    private func selectDebtKind(
        _ kind: DebtPayoffKind
    ) {
        let nextKind: DebtPayoffKind

        if kind == .other,
           displayKind(for: selectedKind) == .other {
            nextKind = selectedKind
        } else {
            nextKind = kind
        }

        let changedKind = displayKind(for: selectedKind) != displayKind(for: nextKind)
        let wasDebtTypeSelected = hasSelectedDebtType
        selectedKind = nextKind
        hasSelectedDebtType = true

        if nextKind == .linkedCreditCard,
           changedKind || !wasDebtTypeSelected {
            resetCreditCardFlowAfterTypeChange()
        }

        if nextKind.isManualInstallmentDebt {
            hasDueDate = true
            if changedKind,
               !hasManuallyEditedPaymentTarget {
                paymentAmountText = ""
            }
        }

        autofillPaymentTargetIfNeeded()
    }

    private func displayKind(
        for kind: DebtPayoffKind
    ) -> DebtPayoffKind {
        kind == .linkedCreditCard
            ? .linkedCreditCard
            : .other
    }

    @ViewBuilder
    private var creditCardFlowSections: some View {
        creditCardSourceSection

        if hasSelectedCreditCardSource {
            creditCardDetailsSection
        }

        if creditCardSourceIsReady {
            creditCardDueDateSection

            creditCardPaymentTargetSection

            if paymentTargetIsReady {
                creditCardSetAsideSection
            }
        }
    }

    @ViewBuilder
    private var editFlowSections: some View {
        if selectedKind == .linkedCreditCard {
            creditCardDetailsSection

            creditCardDueDateSection

            creditCardPaymentTargetSection

            if paymentTargetIsReady {
                creditCardSetAsideSection
            }
        } else {
            editIdentitySection

            scheduleSection

            paymentInfoSection

            if paymentTargetIsReady {
                setAsideSection
            }
        }
    }

    private var creditCardSourceSection: some View {
        DebtPayoffEditorCreditCardSourceSection(
            selectedSource: creditCardSource,
            selectSource: selectCreditCardSource
        )
    }

    private func selectCreditCardSource(
        _ source: DebtPayoffCreditCardSource
    ) {
        let changedSource = creditCardSource != source
        creditCardSource = source
        hasSelectedCreditCardSource = true

        if changedSource {
            resetCreditCardFlowAfterSourceChange(to: source)
        }

        autofillPaymentTargetIfNeeded()
    }

    private var creditCardDetailsSection: some View {
        DebtPayoffEditorCreditCardDetailsSection(
            source: creditCardSource,
            debtAccounts: debtAccounts,
            selectedAccount: selectedAccount,
            linkedBalanceSyncText: linkedBalanceSyncText,
            allowsIdentityEditing: !isEditing,
            selectedAccountID: $selectedAccountID,
            linkedNicknameText: $linkedNicknameText,
            manualNameText: $manualNameText,
            manualBalanceText: $manualBalanceText,
            paymentTargetText: paymentTargetTextBinding,
            dueDate: $dueDate,
            dueDateChanged: {
                hasConfirmedCreditCardDueDate = true
            }
        )
    }

    private var editIdentitySection: some View {
        DebtPayoffEditorFormCard(
            title: "What are you planning?",
            systemImage: "doc.text.fill",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Manual payment")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)

                Text(trimmedManualName.isEmpty ? "Payment" : trimmedManualName)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(AppColors.ink)

                if currentBalance > 0 {
                    Text("Current balance: \(AppFormatters.currency(currentBalance))")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                }

                Text("To change the payment type or account, create a new payment plan.")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var debtDetailsSection: some View {
        DebtPayoffEditorManualDebtSection(
            manualNameTitle: manualNameTitle,
            manualNameText: $manualNameText,
            manualBalanceText: $manualBalanceText
        )
    }

    private var creditCardDueDateSection: some View {
        DebtPayoffEditorCreditCardDueDateSection(
            dueDate: $dueDate,
            dateChanged: {
                hasConfirmedCreditCardDueDate = true
            }
        )
    }

    private var creditCardPaymentTargetSection: some View {
        DebtPayoffEditorPaymentSection(
            paymentAmountText: paymentTargetTextBinding,
            warningMessage: paymentTargetExceedsCachedBalance
                ? "Payment Target is above the card balance. Amount to Set Aside is capped at the card balance."
                : nil
        )
    }

    private var creditCardSetAsideSection: some View {
        DebtPayoffEditorSetAsideSection(
            protectedAmountText: $protectedAmountText,
            setAsideTarget: setAsideTarget,
            protectedAmount: protectedAmount,
            setAsideLimitMessage: setAsideLimitMessage
        )
    }

    private var paymentInfoSection: some View {
        DebtPayoffEditorPaymentSection(
            paymentAmountText: paymentTargetTextBinding,
            warningMessage: paymentTargetExceedsCachedBalance
                ? "Payment Target is above the card balance. Amount to Set Aside is capped at the current balance."
                : nil
        )
    }

    private var scheduleSection: some View {
        DebtPayoffEditorScheduleSection(
            selectedKind: selectedKind,
            hasDueDate: $hasDueDate,
            dueDate: $dueDate
        )
    }

    private var setAsideSection: some View {
        DebtPayoffEditorSetAsideSection(
            protectedAmountText: $protectedAmountText,
            setAsideTarget: setAsideTarget,
            protectedAmount: protectedAmount,
            setAsideLimitMessage: setAsideLimitMessage
        )
    }

    @ViewBuilder
    private var optionalTrackingSection: some View {
        DebtPayoffEditorOptionalTrackingSection(
            isVisible: selectedKind.isManualInstallmentDebt,
            optionalDateRangeIsValid: optionalDateRangeIsValid,
            showsOptionalTrackingDetails: $showsOptionalTrackingDetails,
            originalBalanceText: $originalBalanceText,
            interestRateText: $interestRateText,
            notesText: $notesText,
            includesStartDate: $includesStartDate,
            startDate: $startDate,
            includesEndDate: $includesEndDate,
            endDate: $endDate
        )
    }

    private var typeDescription: String {
        guard hasSelectedDebtType else {
            return "Choose the payment you want to plan for."
        }

        switch selectedKind {
        case .linkedCreditCard:
            return "Set aside for this card payment."

        case .autoLoan,
             .mortgage,
             .studentLoan,
             .personalLoan,
             .other:
            return "Set aside for this payment."
        }
    }

    private var manualNameTitle: String {
        "Payment Name"
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
            }

            if setAsideTarget <= 0 {
                return "Add a Payment Target to save."
            }

            if protectedAmount < 0 {
                return "Amount to Set Aside cannot be negative."
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

            if protectedAmount < 0 {
                return "Amount to Set Aside cannot be negative."
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

        return "For now, Set Aside is capped at the Payment Target."
    }

    private var validationFooter: some View {
        DebtPayoffEditorValidationFooter(
            message: saveDisabledMessage
        )
    }

    private func deleteButton(
        _ bucket: DebtPayoffBucket,
        onDelete: @escaping (DebtPayoffBucket) -> Void
    ) -> some View {
        DestructiveButton(
            "Delete Payment Plan",
            systemImage: "trash.fill",
            cornerRadius: AppRadii.button
        ) {
            showsDeleteConfirmation = true
        }
        .accessibilityLabel("Delete payment plan")
        .confirmationDialog(
            "Delete payment plan?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Payment Plan", role: .destructive) {
                onDelete(bucket)
                dismiss()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the payment plan from Set Aside. Caldera does not make payments or move money.")
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
        to source: DebtPayoffCreditCardSource
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
        guard !MoneyAmountParser.sanitizedText(text).isEmpty else {
            return 0
        }

        return max(MoneyAmountParser.parse(text) ?? -1, -1)
    }

    private func optionalAmount(
        _ text: String
    ) -> Double? {
        guard let value = MoneyAmountParser.parse(text),
              value > 0 else {
            return nil
        }

        return value
    }

    private func optionalAmountIsValid(
        _ text: String
    ) -> Bool {
        guard !MoneyAmountParser.sanitizedText(text).isEmpty else {
            return true
        }

        guard let value = MoneyAmountParser.parse(text) else {
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

    private func sanitizedPercentText(
        _ text: String
    ) -> String {
        text
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func initialPaymentTarget(
        bucket: DebtPayoffBucket?,
        kind: DebtPayoffKind,
        creditCardSource: DebtPayoffCreditCardSource,
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
    ) -> DebtPayoffCreditCardSource {
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
