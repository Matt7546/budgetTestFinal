import SwiftUI
import UIKit

enum NewPaymentPlanCreationMode: String, CaseIterable, Identifiable {
    case manual = "Manual"
    case linked = "Linked Account"

    var id: String { rawValue }
}

enum NewPaymentPlanDueDateSource: CaseIterable, Identifiable {
    case statement
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .statement:
            return "Statement due date"
        case .custom:
            return "Custom due date"
        }
    }
}

enum NewPaymentPlanTargetPresentation {

    static func title(
        for choice: DebtPayoffLinkedCardPaymentTargetChoice
    ) -> String {
        switch choice {
        case .statementBalance:
            return "Statement balance"
        case .minimumPayment:
            return "Minimum payment"
        case .currentBalance:
            return "Full balance"
        case .customAmount:
            return "Custom balance"
        }
    }
}

enum NewPaymentPlanCardDetailsRequestState: Equatable {
    case idle
    case refreshing
    case updated
    case needsPermission
    case unavailable
}

enum NewPaymentPlanCardDetailsStatus: Equatable {
    case ready
    case refreshing
    case updated
    case needsPermission
    case showingEarlierDetails
    case unavailable

    static func resolve(
        hasDetails: Bool,
        consentRequired: Bool,
        requestState: NewPaymentPlanCardDetailsRequestState
    ) -> Self {
        if requestState == .refreshing {
            return .refreshing
        }

        if consentRequired || requestState == .needsPermission {
            return .needsPermission
        }

        if requestState == .updated, hasDetails {
            return .updated
        }

        if requestState == .unavailable {
            return hasDetails ? .showingEarlierDetails : .unavailable
        }

        return hasDetails ? .ready : .unavailable
    }

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .refreshing:
            return "Refreshing..."
        case .updated:
            return "Updated just now"
        case .needsPermission:
            return "Permission needed"
        case .showingEarlierDetails:
            return "Showing earlier details"
        case .unavailable:
            return "Details unavailable"
        }
    }

    var actionTitle: String {
        switch self {
        case .needsPermission:
            return "Add Card Details"
        case .refreshing:
            return "Refreshing..."
        default:
            return "Refresh Card Details"
        }
    }
}

enum NewPaymentPlanLinkedAccountEligibility {

    static func selectableAccounts(
        from debtAccounts: [PlaidAccount],
        existingPaymentPlans: [DebtPayoffBucket]
    ) -> [PlaidAccount] {
        let plannedAccountIDs: Set<String> = Set(
            existingPaymentPlans.compactMap { plan -> String? in
                guard plan.debtKind == .linkedCreditCard,
                      !plan.plaidAccountID.isEmpty else {
                    return nil
                }

                return plan.plaidAccountID
            }
        )

        return debtAccounts.creditAccounts.filter { account in
            !plannedAccountIDs.contains(account.account_id)
        }
    }
}

struct NewPaymentPlanCreationInput {

    var mode: NewPaymentPlanCreationMode = .manual
    var manualName = ""
    var manualTargetAmountText = ""
    var selectedAccountID = ""
    var linkedTargetChoice: DebtPayoffLinkedCardPaymentTargetChoice?
    var linkedCustomTargetAmountText = ""
    var dueDateSource: NewPaymentPlanDueDateSource = .custom
    var customDueDate = Date()

    func selectedAccount(
        in accounts: [PlaidAccount]
    ) -> PlaidAccount? {
        accounts.first { account in
            account.account_id == selectedAccountID
        }
    }

    func selectedCardPaymentDetails(
        in details: [LinkedCardPaymentDetails]
    ) -> LinkedCardPaymentDetails? {
        details.first { card in
            card.account_id == selectedAccountID
        }
    }

    func targetAmount(
        accounts: [PlaidAccount],
        cardPaymentDetails: [LinkedCardPaymentDetails]
    ) -> Double? {
        switch mode {
        case .manual:
            return positiveAmount(manualTargetAmountText)

        case .linked:
            guard let linkedTargetChoice else {
                return nil
            }

            if linkedTargetChoice == .customAmount {
                return positiveAmount(linkedCustomTargetAmountText)
            }

            let account = selectedAccount(in: accounts)
            let card = selectedCardPaymentDetails(
                in: cardPaymentDetails
            )

            return linkedTargetChoice.suggestedAmount(
                statementBalance: card?.last_statement_balance,
                minimumPayment: card?.minimum_payment_amount,
                currentBalance: account?.debtBalanceValue
            )
        }
    }

    func statementDueDate(
        cardPaymentDetails: [LinkedCardPaymentDetails],
        calendar: Calendar = .current
    ) -> Date? {
        let card = selectedCardPaymentDetails(
            in: cardPaymentDetails
        )

        return PaymentPlanCalendarDate.parse(
            card?.next_payment_due_date,
            calendar: calendar
        )
    }

    func resolvedDueDate(
        cardPaymentDetails: [LinkedCardPaymentDetails],
        calendar: Calendar = .current
    ) -> Date {
        guard mode == .linked,
              dueDateSource == .statement,
              let statementDate = statementDueDate(
                cardPaymentDetails: cardPaymentDetails,
                calendar: calendar
              ) else {
            return customDueDate
        }

        return statementDate
    }

    func draft(
        accounts: [PlaidAccount],
        cardPaymentDetails: [LinkedCardPaymentDetails],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DebtPayoffBucketDraft? {
        guard let targetAmount = targetAmount(
            accounts: accounts,
            cardPaymentDetails: cardPaymentDetails
        ),
              targetAmount.isFinite,
              targetAmount > 0 else {
            return nil
        }

        let dueDate = resolvedDueDate(
            cardPaymentDetails: cardPaymentDetails,
            calendar: calendar
        )
        let dueDayAnchor = calendar.component(
            .day,
            from: dueDate
        )

        switch mode {
        case .manual:
            let name = manualName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !name.isEmpty else {
                return nil
            }

            return DebtPayoffBucketDraft(
                debtKind: .linkedCreditCard,
                plaidAccountID: "",
                accountName: name,
                institutionName: nil,
                dueDate: dueDate,
                paymentTargetAmount: targetAmount,
                protectedAmount: 0,
                paymentTargetChoice: nil,
                targetChosenAt: nil,
                targetStatementIssueDate: nil,
                manualCurrentBalance: targetAmount,
                monthlyPayment: nil,
                originalBalance: nil,
                interestRate: nil,
                notes: nil,
                hasPaymentDueDate: true,
                startDate: nil,
                endDate: nil,
                shouldCreateActiveCycle: true,
                cycleDueDayAnchor: dueDayAnchor
            )

        case .linked:
            guard let account = selectedAccount(in: accounts),
                  let linkedTargetChoice else {
                return nil
            }

            let card = selectedCardPaymentDetails(
                in: cardPaymentDetails
            )
            let statementIssueDate = PaymentPlanCalendarDate.anchor(
                for: linkedTargetChoice,
                liveValue: card?.last_statement_issue_date,
                calendar: calendar
            )

            return DebtPayoffBucketDraft(
                debtKind: .linkedCreditCard,
                plaidAccountID: account.account_id,
                accountName: account.name,
                institutionName: account.institution_name,
                dueDate: dueDate,
                paymentTargetAmount: targetAmount,
                protectedAmount: 0,
                paymentTargetChoice: linkedTargetChoice,
                targetChosenAt: now,
                targetStatementIssueDate: statementIssueDate,
                manualCurrentBalance: nil,
                monthlyPayment: nil,
                originalBalance: nil,
                interestRate: nil,
                notes: nil,
                hasPaymentDueDate: true,
                startDate: nil,
                endDate: nil,
                shouldCreateActiveCycle: true,
                cycleDueDayAnchor: dueDayAnchor
            )
        }
    }

    func validationMessage(
        accounts: [PlaidAccount],
        cardPaymentDetails: [LinkedCardPaymentDetails]
    ) -> String? {
        switch mode {
        case .manual:
            let hasName = !manualName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            let hasTarget = targetAmount(
                accounts: accounts,
                cardPaymentDetails: cardPaymentDetails
            ) != nil

            switch (hasName, hasTarget) {
            case (false, false):
                return "Add a payment name and target amount to save."
            case (false, true):
                return "Add a payment name to save."
            case (true, false):
                return "Enter a Payment Target greater than $0."
            case (true, true):
                return nil
            }

        case .linked:
            guard selectedAccount(in: accounts) != nil else {
                return "Choose a linked card to continue."
            }

            guard linkedTargetChoice != nil else {
                return "Choose what you'd like to plan for."
            }

            guard targetAmount(
                accounts: accounts,
                cardPaymentDetails: cardPaymentDetails
            ) != nil else {
                return linkedTargetChoice == .customAmount
                    ? "Enter a Payment Target greater than $0."
                    : "That card amount is not available. Choose another target."
            }

            return nil
        }
    }

    private func positiveAmount(
        _ text: String
    ) -> Double? {
        guard let value = MoneyAmountParser.parse(text),
              value.isFinite,
              value > 0 else {
            return nil
        }

        return value
    }
}

enum NewPaymentPlanAmountPresentation {

    static func displayText(
        for amountText: String
    ) -> String {
        NewUpcomingExpenseAmountPresentation.displayText(
            for: amountText
        )
    }

    static func inputText(
        for amount: Double
    ) -> String {
        String(format: "%.2f", amount)
    }
}

struct NewPaymentPlanCreateView: View {

    private enum SavePhase {
        case idle
        case completing
        case success
    }

    private enum FocusedField: Hashable {
        case name
        case amount
    }

    let debtAccounts: [PlaidAccount]
    let existingPaymentPlans: [DebtPayoffBucket]
    let onSave: (DebtPayoffBucketDraft) -> Bool
    let onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var plaid: PlaidService

    @State private var input = NewPaymentPlanCreationInput()
    @State private var dateSelection = Date()
    @State private var isShowingDatePicker = false
    @State private var isAccountPickerExpanded = false
    @State private var isTargetPickerExpanded = false
    @State private var isDueDatePickerExpanded = false
    @State private var cardDetailsRequestState:
        NewPaymentPlanCardDetailsRequestState = .idle
    @State private var cardDetailsAwaitingUpdateAccountID: String?
    @State private var hasExplicitDueDateChoice = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var swipeProgress: CGFloat = 0
    @State private var circleCompletionProgress: CGFloat = 0
    @State private var foregroundOpacity: CGFloat = 1
    @State private var savePhase: SavePhase = .idle
    @State private var saveCompletionTask: Task<Void, Never>?
    @FocusState private var focusedField: FocusedField?

    private let controlWidth: CGFloat = 320
    private let controlStackSpacing: CGFloat = 10
    private let selectorToStackSpacing: CGFloat = 18
    private let stackToAmountSpacing: CGFloat = 22
    private let linkedAccountOptionsBeforeScrolling = 3
    private let linkedAccountOptionsMaximumHeight: CGFloat = 132
    private let collapsedCornerRadius: CGFloat = 24
    private let expandedCornerRadius: CGFloat = 28

    init(
        debtAccounts: [PlaidAccount],
        existingPaymentPlans: [DebtPayoffBucket],
        onSave: @escaping (DebtPayoffBucketDraft) -> Bool,
        onSaved: (() -> Void)? = nil
    ) {
        self.debtAccounts = debtAccounts
        self.existingPaymentPlans = existingPaymentPlans
        self.onSave = onSave
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let circleLayout = NewPaymentPlanCircleLayout(
                    size: proxy.size,
                    swipeProgress: swipeProgress,
                    completionProgress: circleCompletionProgress
                )

                ZStack {
                    CalderaModalBackground(mood: .debtPayoff)

                    NewPaymentPlanConcentricCircles(
                        layout: circleLayout,
                        swipeProgress: swipeProgress,
                        completionProgress: circleCompletionProgress
                    )

                    VStack(spacing: 0) {
                        topControls

                        creationContent
                            .padding(.top, 34)

                        Spacer(minLength: AppSpacing.screen)
                    }
                    .padding(.horizontal, AppSpacing.regular)
                    .padding(.top, AppSpacing.medium)
                    .padding(.bottom, AppSpacing.panel)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                    .dismissKeyboardOnBackgroundTap()
                    .opacity(foregroundOpacity)
                    .allowsHitTesting(
                        savePhase == .idle && !isSaving
                    )

                    if isSwipeAffordanceVisible {
                        PlanningSwipeToSaveInteraction(
                            circleCenter: circleLayout.center,
                            circleDiameter: circleLayout.innerDiameter,
                            affordanceCenter: CGPoint(
                                x: proxy.size.width / 2,
                                y: swipeAffordanceCenterY(
                                    layout: circleLayout,
                                    size: proxy.size
                                )
                            ),
                            isEnabled: true,
                            accessibilityLabel: "Save payment plan",
                            accessibilityHint:
                                "Swipe up or activate to create this plan.",
                            swipeProgress: $swipeProgress,
                            onSaveTriggered: savePlan
                        )
                        .opacity(foregroundOpacity)
                        .transition(.opacity)
                    }

                    if savePhase == .success {
                        PlanningCreationSuccessOverlay(
                            title: "Plan created",
                            isPresented: true,
                            showsConfetti: !reduceMotion
                        )
                        .transition(
                            .opacity.combined(
                                with: .scale(scale: 0.94)
                            )
                        )
                    }
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button {
                        focusedField = nil
                    } label: {
                        Label(
                            "Done",
                            systemImage: "keyboard.chevron.compact.down"
                        )
                    }
                    .accessibilityLabel("Hide keyboard")
                }
            }
        }
        .calderaTransparentNavigationSurface()
        .sheet(isPresented: $isShowingDatePicker) {
            dueDatePicker
        }
        .alert(
            "Couldn't Save Payment Plan",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        saveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                saveErrorMessage
                    ?? "Your Payment Plan wasn't saved. Please try again."
            )
        }
        .onChange(of: input.mode) { _, newMode in
            focusedField = nil
            closeInlinePickers()
            cardDetailsRequestState = .idle
            cardDetailsAwaitingUpdateAccountID = nil
            hasExplicitDueDateChoice = false

            if newMode == .manual {
                input.dueDateSource = .custom
            } else if !input.selectedAccountID.isEmpty {
                updateDueDateSourceForSelectedAccount()
            }
        }
        .onChange(
            of: selectedCardPaymentDetails?.last_refreshed_at
        ) { _, refreshedAt in
            guard refreshedAt != nil,
                  cardDetailsAwaitingUpdateAccountID
                    == input.selectedAccountID else {
                return
            }

            cardDetailsAwaitingUpdateAccountID = nil
            cardDetailsRequestState = .updated
            adoptStatementDueDateIfAppropriate()
        }
        .onDisappear {
            saveCompletionTask?.cancel()
        }
    }

    private var eligibleLinkedAccounts: [PlaidAccount] {
        NewPaymentPlanLinkedAccountEligibility.selectableAccounts(
            from: debtAccounts,
            existingPaymentPlans: existingPaymentPlans
        )
    }

    private var allLinkedCardsAlreadyPlanned: Bool {
        !debtAccounts.creditAccounts.isEmpty
            && eligibleLinkedAccounts.isEmpty
    }

    private var usableCardPaymentDetails: [LinkedCardPaymentDetails] {
        plaid.backendLiabilitiesEnabled
            ? plaid.cardPaymentDetails
            : []
    }

    private var selectedAccount: PlaidAccount? {
        input.selectedAccount(
            in: eligibleLinkedAccounts
        )
    }

    private var selectedCardPaymentDetails: LinkedCardPaymentDetails? {
        input.selectedCardPaymentDetails(
            in: usableCardPaymentDetails
        )
    }

    private var cardPaymentDetailsConsentRequired: Bool {
        guard selectedCardPaymentDetails == nil,
              let response = plaid.latestCardPaymentDetailsResponse else {
            return false
        }

        return response.consent_required == true
            || response.error == "additional_consent_required"
    }

    private var canRequestCardPaymentDetailsConsent: Bool {
        guard plaid.backendLiabilitiesLinkEnabled,
              let account = selectedAccount,
              !account.account_id.isEmpty,
              let itemID = account.item_id?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              !itemID.isEmpty else {
            return false
        }

        return true
    }

    private var cardDetailsStatus: NewPaymentPlanCardDetailsStatus {
        NewPaymentPlanCardDetailsStatus.resolve(
            hasDetails: selectedCardPaymentDetails != nil,
            consentRequired: cardPaymentDetailsConsentRequired
                && canRequestCardPaymentDetailsConsent,
            requestState: cardDetailsRequestState
        )
    }

    private var shouldShowCardDetailsControl: Bool {
        input.mode == .linked
            && selectedAccount != nil
            && plaid.backendLiabilitiesEnabled
    }

    private var topControls: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .newPaymentPlanPillControl(
                colorScheme: colorScheme
            )
            .accessibilityLabel("Cancel new payment plan")

            Spacer()
        }
    }

    private var creationContent: some View {
        VStack(spacing: 0) {
            modeSelector
                .padding(.bottom, selectorToStackSpacing)

            VStack(spacing: controlStackSpacing) {
                if input.mode == .manual {
                    manualNameControl
                    manualDueDateControl
                } else {
                    linkedAccountControl
                    if shouldShowCardDetailsControl {
                        cardDetailsControl
                    }
                    linkedTargetControl
                    linkedDueDateControl
                }
            }
            .animation(
                .easeInOut(duration: 0.22),
                value: input.mode
            )

            amountHero
                .padding(.top, stackToAmountSpacing)

            Text(validationMessage ?? " ")
                .font(.caption.weight(.medium))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(
                        colorScheme
                    )
                )
                .multilineTextAlignment(.center)
                .frame(minHeight: 18)
                .padding(.top, AppSpacing.xSmall)
                .accessibilityHidden(validationMessage == nil)
        }
        .frame(maxWidth: .infinity)
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(NewPaymentPlanCreationMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        input.mode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(
                            input.mode == mode
                                ? AnyShapeStyle(Color.white)
                                : AnyShapeStyle(
                                    CalderaVisualStyle.secondaryText(
                                        colorScheme
                                    )
                                )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if input.mode == mode {
                                Capsule(style: .continuous)
                                    .fill(paymentPlanAccentGradient)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.rawValue)
                .accessibilityAddTraits(
                    input.mode == mode ? .isSelected : []
                )
            }
        }
        .padding(4)
        .frame(width: controlWidth)
        .background(pillSurface)
        .clipShape(Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    Color.white.opacity(
                        colorScheme == .dark ? 0.20 : 0.68
                    ),
                    lineWidth: 1
                )
        }
    }

    private var manualNameControl: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Image(systemName: paymentPlanStyle.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(paymentPlanAccentGradient)

            TextField(
                "Payment plan name",
                text: $input.manualName
            )
            .font(.subheadline.weight(.semibold))
            .foregroundColor(
                CalderaVisualStyle.primaryText(colorScheme)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .textInputAutocapitalization(.words)
            .submitLabel(.next)
            .focused($focusedField, equals: .name)
            .onSubmit {
                focusedField = .amount
            }
            .accessibilityLabel("Payment plan name")
        }
        .padding(.horizontal, AppSpacing.regular)
        .frame(width: controlWidth, height: 48)
        .newPaymentPlanControlSurface(
            cornerRadius: collapsedCornerRadius,
            colorScheme: colorScheme
        )
    }

    private var linkedAccountControl: some View {
        VStack(spacing: 0) {
            Button {
                focusedField = nil
                withAnimation(.easeInOut(duration: 0.24)) {
                    isTargetPickerExpanded = false
                    isDueDatePickerExpanded = false
                    isAccountPickerExpanded.toggle()
                }
            } label: {
                controlRow(
                    icon: paymentPlanStyle.icon,
                    title: selectedAccount?.name
                        ?? "Choose linked card",
                    value: selectedAccount.flatMap(accountSuffix),
                    isExpanded: isAccountPickerExpanded
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                selectedAccount.map {
                    "Linked card \(accountLabel($0))"
                } ?? "Choose linked card"
            )
            .accessibilityHint(
                isAccountPickerExpanded
                    ? "Double tap to collapse linked cards"
                    : "Double tap to choose a linked card"
            )

            if isAccountPickerExpanded {
                Divider()
                    .overlay(
                        CalderaVisualStyle.secondaryText(
                            colorScheme
                        ).opacity(0.20)
                    )

                if eligibleLinkedAccounts.isEmpty {
                    linkedAccountEmptyState
                } else {
                    linkedAccountOptions
                }
            }
        }
        .frame(width: controlWidth)
        .newPaymentPlanControlSurface(
            cornerRadius: isAccountPickerExpanded
                ? expandedCornerRadius
                : collapsedCornerRadius,
            colorScheme: colorScheme
        )
        .animation(
            .easeInOut(duration: 0.24),
            value: isAccountPickerExpanded
        )
    }

    @ViewBuilder
    private var linkedAccountOptions: some View {
        if shouldScrollLinkedAccountOptions {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    linkedAccountOptionRows
                }
            }
            .frame(height: linkedAccountOptionsMaximumHeight)
            .scrollIndicators(.hidden)
            .accessibilityLabel("Linked card options")
        } else {
            VStack(spacing: 0) {
                linkedAccountOptionRows
            }
        }
    }

    @ViewBuilder
    private var linkedAccountOptionRows: some View {
        ForEach(eligibleLinkedAccounts) { account in
            optionButton(
                title: account.name,
                detail: accountSuffix(account),
                isSelected: input.selectedAccountID == account.account_id,
                isEnabled: true
            ) {
                selectLinkedAccount(account)
            }
        }
    }

    private var shouldScrollLinkedAccountOptions: Bool {
        eligibleLinkedAccounts.count > linkedAccountOptionsBeforeScrolling
            || dynamicTypeSize > .large
    }

    private var linkedAccountEmptyState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text(
                allLinkedCardsAlreadyPlanned
                    ? "All linked cards already have Payment Plans."
                    : "No linked credit cards are available."
            )
            .font(.caption.weight(.semibold))

            Text(
                allLinkedCardsAlreadyPlanned
                    ? "Edit an existing plan or choose Manual."
                    : "Refresh Bank Sync or choose Manual."
            )
            .font(.caption2)
            .foregroundColor(
                CalderaVisualStyle.secondaryText(colorScheme)
            )
        }
        .foregroundColor(
            CalderaVisualStyle.primaryText(colorScheme)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.regular)
        .accessibilityElement(children: .combine)
    }

    private var linkedTargetControl: some View {
        VStack(spacing: 0) {
            Button {
                guard selectedAccount != nil else { return }
                focusedField = nil

                withAnimation(.easeInOut(duration: 0.24)) {
                    isAccountPickerExpanded = false
                    isDueDatePickerExpanded = false
                    isTargetPickerExpanded.toggle()
                }
            } label: {
                controlRow(
                    icon: "dollarsign.circle.fill",
                    title: collapsedTargetTitle,
                    value: collapsedTargetValue,
                    isExpanded: isTargetPickerExpanded
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedAccount == nil)
            .accessibilityLabel(
                "Payment target \(collapsedTargetTitle) \(collapsedTargetValue ?? "")"
            )
            .accessibilityHint(
                selectedAccount == nil
                    ? "Choose a linked card first"
                    : isTargetPickerExpanded
                        ? "Double tap to collapse target choices"
                        : "Double tap to choose a payment target"
            )

            if isTargetPickerExpanded {
                Divider()
                    .overlay(
                        CalderaVisualStyle.secondaryText(
                            colorScheme
                        ).opacity(0.20)
                    )

                ForEach(
                    DebtPayoffLinkedCardPaymentTargetChoice.allCases
                ) { choice in
                    let amount = suggestedAmount(for: choice)
                    optionButton(
                        title: NewPaymentPlanTargetPresentation.title(
                            for: choice
                        ),
                        detail: targetDetail(
                            for: choice,
                            amount: amount
                        ),
                        isSelected:
                            input.linkedTargetChoice == choice,
                        isEnabled:
                            choice == .customAmount || amount != nil
                    ) {
                        selectTargetChoice(choice)
                    }
                }
            }
        }
        .frame(width: controlWidth)
        .newPaymentPlanControlSurface(
            cornerRadius: isTargetPickerExpanded
                ? expandedCornerRadius
                : collapsedCornerRadius,
            colorScheme: colorScheme
        )
        .animation(
            .easeInOut(duration: 0.24),
            value: isTargetPickerExpanded
        )
    }

    private var cardDetailsControl: some View {
        Button(action: refreshCardDetails) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(
                    systemName: cardDetailsStatus == .needsPermission
                        ? "creditcard.and.123"
                        : "arrow.clockwise"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(paymentPlanAccentGradient)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Bank Data")
                        .font(.caption.weight(.semibold))

                    Text(cardDetailsStatus.title)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(
                            CalderaVisualStyle.secondaryText(
                                colorScheme
                            )
                        )
                }

                Spacer(minLength: AppSpacing.small)

                Text(cardDetailsStatus.actionTitle)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(paymentPlanAccentGradient)
            }
            .padding(.horizontal, AppSpacing.regular)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: controlWidth)
        .newPaymentPlanControlSurface(
            cornerRadius: collapsedCornerRadius,
            colorScheme: colorScheme
        )
        .disabled(cardDetailsStatus == .refreshing)
        .accessibilityLabel(
            "Bank Data, \(cardDetailsStatus.title)"
        )
        .accessibilityHint(
            cardDetailsStatus == .needsPermission
                ? "Double tap to add Card Payment Details permission"
                : "Double tap to refresh Card Payment Details"
        )
    }

    private var manualDueDateControl: some View {
        Button {
            presentCustomDueDatePicker()
        } label: {
            controlRow(
                icon: "calendar",
                title: "Custom due date",
                value: formattedDate(input.customDueDate),
                isExpanded: nil
            )
        }
        .buttonStyle(.plain)
        .frame(width: controlWidth)
        .newPaymentPlanControlSurface(
            cornerRadius: collapsedCornerRadius,
            colorScheme: colorScheme
        )
        .accessibilityLabel(
            "Custom due date \(accessibleDate(input.customDueDate))"
        )
        .accessibilityHint("Double tap to choose a due date")
    }

    private var linkedDueDateControl: some View {
        VStack(spacing: 0) {
            Button {
                guard selectedAccount != nil else { return }
                focusedField = nil

                withAnimation(.easeInOut(duration: 0.24)) {
                    isAccountPickerExpanded = false
                    isTargetPickerExpanded = false
                    isDueDatePickerExpanded.toggle()
                }
            } label: {
                controlRow(
                    icon: "calendar",
                    title: input.dueDateSource.title,
                    value: formattedDate(resolvedDueDate),
                    isExpanded: isDueDatePickerExpanded
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedAccount == nil)
            .accessibilityLabel(
                "\(input.dueDateSource.title) \(accessibleDate(resolvedDueDate))"
            )
            .accessibilityHint(
                selectedAccount == nil
                    ? "Choose a linked card first"
                    : isDueDatePickerExpanded
                        ? "Double tap to collapse due date choices"
                        : "Double tap to choose the due date source"
            )

            if isDueDatePickerExpanded {
                Divider()
                    .overlay(
                        CalderaVisualStyle.secondaryText(
                            colorScheme
                        ).opacity(0.20)
                    )

                let statementDate = input.statementDueDate(
                    cardPaymentDetails: usableCardPaymentDetails
                )
                optionButton(
                    title: NewPaymentPlanDueDateSource.statement.title,
                    detail: statementDate.map(formattedDate)
                        ?? "Not available",
                    isSelected: input.dueDateSource == .statement,
                    isEnabled: statementDate != nil
                ) {
                    input.dueDateSource = .statement
                    hasExplicitDueDateChoice = true
                    withAnimation(.easeInOut(duration: 0.24)) {
                        isDueDatePickerExpanded = false
                    }
                }

                optionButton(
                    title: NewPaymentPlanDueDateSource.custom.title,
                    detail: formattedDate(input.customDueDate),
                    isSelected: input.dueDateSource == .custom,
                    isEnabled: true
                ) {
                    input.dueDateSource = .custom
                    hasExplicitDueDateChoice = true
                    withAnimation(.easeInOut(duration: 0.24)) {
                        isDueDatePickerExpanded = false
                    }
                    presentCustomDueDatePicker()
                }
            }
        }
        .frame(width: controlWidth)
        .newPaymentPlanControlSurface(
            cornerRadius: isDueDatePickerExpanded
                ? expandedCornerRadius
                : collapsedCornerRadius,
            colorScheme: colorScheme
        )
        .animation(
            .easeInOut(duration: 0.24),
            value: isDueDatePickerExpanded
        )
    }

    private func controlRow(
        icon: String,
        title: String,
        value: String?,
        isExpanded: Bool?
    ) -> some View {
        HStack(spacing: AppSpacing.xSmall) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(paymentPlanAccentGradient)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .layoutPriority(1)

            Spacer(minLength: AppSpacing.small)

            if let value,
               !value.isEmpty {
                Text(value)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            if let isExpanded {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .rotationEffect(
                        .degrees(isExpanded ? 180 : 0)
                    )
            }
        }
        .foregroundColor(
            CalderaVisualStyle.primaryText(colorScheme)
        )
        .padding(.horizontal, AppSpacing.regular)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    private func optionButton(
        title: String,
        detail: String?,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Spacer(minLength: AppSpacing.small)

                if let detail {
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .truncationMode(.tail)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(
                isEnabled
                    ? isSelected
                        ? AnyShapeStyle(paymentPlanAccentGradient)
                        : AnyShapeStyle(
                            CalderaVisualStyle.primaryText(
                                colorScheme
                            )
                        )
                    : AnyShapeStyle(
                        CalderaVisualStyle.secondaryText(
                            colorScheme
                        ).opacity(0.58)
                    )
            )
            .padding(.horizontal, AppSpacing.regular)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.small)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(
            "\(title), \(detail ?? "")"
        )
        .accessibilityValue(
            isEnabled ? (isSelected ? "Selected" : "") : "Unavailable"
        )
    }

    private var amountHero: some View {
        Button {
            guard isHeroAmountEditable else { return }
            closeInlinePickers()
            focusedField = .amount
        } label: {
            HStack(
                alignment: .firstTextBaseline,
                spacing: AppSpacing.xSmall
            ) {
                Text("$")
                    .font(
                        .system(
                            size: heroCurrencyFontSize,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        paymentPlanAccentGradient.opacity(
                            currentAmountText.isEmpty ? 0.50 : 0.80
                        )
                    )

                Text(heroAmountDisplayText)
                    .font(
                        .system(
                            size: heroAmountFontSize,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        currentAmountText.isEmpty
                            ? AnyShapeStyle(
                                CalderaVisualStyle.secondaryText(
                                    colorScheme
                                ).opacity(0.42)
                            )
                            : AnyShapeStyle(paymentPlanAccentGradient)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.42)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(.horizontal, AppSpacing.small)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Payment Target")
        .accessibilityValue("$\(heroAmountDisplayText)")
        .accessibilityHint(heroAmountAccessibilityHint)
        .background {
            TextField(
                "",
                text: heroAmountBinding
            )
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .amount)
            .disabled(!isHeroAmountEditable)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private var dueDatePicker: some View {
        NavigationStack {
            ZStack {
                CalderaModalBackground(mood: .debtPayoff)

                DatePicker(
                    "Custom due date",
                    selection: $dateSelection,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(paymentPlanStyle.primary)
                .padding(AppSpacing.screen)
            }
            .navigationTitle("Custom Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingDatePicker = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        input.customDueDate = dateSelection
                        input.dueDateSource = .custom
                        hasExplicitDueDateChoice = true
                        isShowingDatePicker = false
                    }
                }
            }
        }
        .calderaTransparentNavigationSurface()
        .presentationDetents([.medium, .large])
    }

    private var paymentPlanStyle: CalderaCategoryStyle {
        CalderaCategoryStyle.style(for: .debtPayoff)
    }

    private var paymentPlanAccentGradient: LinearGradient {
        LinearGradient(
            colors: paymentPlanStyle.gradient,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var pillSurface: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.10))
            : AnyShapeStyle(Color.white.opacity(0.70))
    }

    private var validationMessage: String? {
        input.validationMessage(
            accounts: eligibleLinkedAccounts,
            cardPaymentDetails: usableCardPaymentDetails
        )
    }

    private var currentDraft: DebtPayoffBucketDraft? {
        input.draft(
            accounts: eligibleLinkedAccounts,
            cardPaymentDetails: usableCardPaymentDetails
        )
    }

    private var currentAmountText: String {
        switch input.mode {
        case .manual:
            return input.manualTargetAmountText

        case .linked:
            guard let choice = input.linkedTargetChoice else {
                return ""
            }

            if choice == .customAmount {
                return input.linkedCustomTargetAmountText
            }

            guard let amount = suggestedAmount(for: choice) else {
                return ""
            }

            return NewPaymentPlanAmountPresentation.inputText(
                for: amount
            )
        }
    }

    private var heroAmountBinding: Binding<String> {
        Binding(
            get: { currentAmountText },
            set: { newValue in
                switch input.mode {
                case .manual:
                    input.manualTargetAmountText = newValue
                case .linked:
                    guard input.linkedTargetChoice == .customAmount else {
                        return
                    }
                    input.linkedCustomTargetAmountText = newValue
                }
            }
        )
    }

    private var isHeroAmountEditable: Bool {
        input.mode == .manual
            || input.linkedTargetChoice == .customAmount
    }

    private var heroAmountAccessibilityHint: String {
        if isHeroAmountEditable {
            return "Double tap to enter dollars and cents."
        }

        return input.linkedTargetChoice == nil
            ? "Choose a Payment Target first."
            : "Choose Custom balance to enter a different target."
    }

    private var heroAmountDisplayText: String {
        NewPaymentPlanAmountPresentation.displayText(
            for: currentAmountText
        )
    }

    private var heroAmountFontSize: CGFloat {
        switch max(heroAmountDisplayText.count, 1) {
        case ...4:
            return 80
        case 5...7:
            return 66
        case 8...10:
            return 50
        default:
            return 36
        }
    }

    private var heroCurrencyFontSize: CGFloat {
        max(heroAmountFontSize * 0.54, 28)
    }

    private var collapsedTargetTitle: String {
        input.linkedTargetChoice.map {
            NewPaymentPlanTargetPresentation.title(for: $0)
        }
            ?? "Choose payment target"
    }

    private var collapsedTargetValue: String? {
        guard let choice = input.linkedTargetChoice else {
            return nil
        }

        if choice == .customAmount {
            let amount = input.targetAmount(
                accounts: eligibleLinkedAccounts,
                cardPaymentDetails: usableCardPaymentDetails
            )
            if let amount {
                return AppFormatters.currency(amount)
            }

            return "Choose balance"
        }

        guard let amount = suggestedAmount(for: choice) else {
            return nil
        }

        return AppFormatters.currency(amount)
    }

    private var resolvedDueDate: Date {
        input.resolvedDueDate(
            cardPaymentDetails: usableCardPaymentDetails
        )
    }

    private var isSwipeAffordanceVisible: Bool {
        currentDraft != nil
            && focusedField == nil
            && !isSaving
            && savePhase == .idle
    }

    private func suggestedAmount(
        for choice: DebtPayoffLinkedCardPaymentTargetChoice
    ) -> Double? {
        choice.suggestedAmount(
            statementBalance:
                selectedCardPaymentDetails?.last_statement_balance,
            minimumPayment:
                selectedCardPaymentDetails?.minimum_payment_amount,
            currentBalance: selectedAccount?.debtBalanceValue
        )
    }

    private func targetDetail(
        for choice: DebtPayoffLinkedCardPaymentTargetChoice,
        amount: Double?
    ) -> String {
        if choice == .customAmount {
            return "Choose balance"
        }

        guard let amount else {
            return "Not available"
        }

        return AppFormatters.currency(amount)
    }

    private func selectLinkedAccount(
        _ account: PlaidAccount
    ) {
        input.selectedAccountID = account.account_id
        input.linkedTargetChoice = nil
        input.linkedCustomTargetAmountText = ""
        cardDetailsRequestState = .idle
        cardDetailsAwaitingUpdateAccountID = nil
        hasExplicitDueDateChoice = false
        updateDueDateSourceForSelectedAccount()

        withAnimation(.easeInOut(duration: 0.24)) {
            isAccountPickerExpanded = false
        }
    }

    private func selectTargetChoice(
        _ choice: DebtPayoffLinkedCardPaymentTargetChoice
    ) {
        input.linkedTargetChoice = choice

        withAnimation(.easeInOut(duration: 0.24)) {
            isTargetPickerExpanded = false
        }

        if choice == .customAmount {
            Task { @MainActor in
                focusedField = .amount
            }
        }
    }

    private func updateDueDateSourceForSelectedAccount() {
        if input.statementDueDate(
            cardPaymentDetails: usableCardPaymentDetails
        ) != nil {
            input.dueDateSource = .statement
        } else {
            input.dueDateSource = .custom
        }
    }

    private func adoptStatementDueDateIfAppropriate() {
        guard !hasExplicitDueDateChoice,
              input.statementDueDate(
                cardPaymentDetails: usableCardPaymentDetails
              ) != nil else {
            return
        }

        input.dueDateSource = .statement
    }

    private func refreshCardDetails() {
        guard let account = selectedAccount else {
            return
        }

        if cardPaymentDetailsConsentRequired
            && canRequestCardPaymentDetailsConsent
            || cardDetailsRequestState == .needsPermission {
            requestCardPaymentDetailsConsent(for: account)
            return
        }

        let requestedAccountID = account.account_id
        cardDetailsRequestState = .refreshing
        cardDetailsAwaitingUpdateAccountID = requestedAccountID

        plaid.fetchCardPaymentDetails { response in
            guard input.selectedAccountID == requestedAccountID else {
                return
            }

            if response?.consent_required == true
                || response?.error == "additional_consent_required" {
                cardDetailsRequestState =
                    canRequestCardPaymentDetailsConsent
                        ? .needsPermission
                        : .unavailable
                cardDetailsAwaitingUpdateAccountID = nil
                return
            }

            let didLoadSelectedCard = response?.cards.contains {
                $0.account_id == requestedAccountID
            } ?? false

            cardDetailsRequestState = didLoadSelectedCard
                ? .updated
                : .unavailable
            cardDetailsAwaitingUpdateAccountID = nil

            if didLoadSelectedCard {
                adoptStatementDueDateIfAppropriate()
            }
        }
    }

    private func requestCardPaymentDetailsConsent(
        for account: PlaidAccount
    ) {
        guard canRequestCardPaymentDetailsConsent,
              let itemID = account.item_id?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              !itemID.isEmpty else {
            cardDetailsRequestState = .unavailable
            return
        }

        cardDetailsRequestState = .needsPermission
        cardDetailsAwaitingUpdateAccountID = account.account_id
        plaid.createCardPaymentDetailsUpdateLinkToken(
            itemID: itemID,
            accountID: account.account_id
        )
    }

    private func presentCustomDueDatePicker() {
        focusedField = nil
        closeInlinePickers()
        dateSelection = input.customDueDate
        isShowingDatePicker = true
    }

    private func closeInlinePickers() {
        withAnimation(.easeInOut(duration: 0.20)) {
            isAccountPickerExpanded = false
            isTargetPickerExpanded = false
            isDueDatePickerExpanded = false
        }
    }

    private func accountLabel(
        _ account: PlaidAccount
    ) -> String {
        if let suffix = accountSuffix(account) {
            return "\(account.name), \(suffix)"
        }

        return account.name
    }

    private func accountSuffix(
        _ account: PlaidAccount
    ) -> String? {
        if let mask = account.mask,
           !mask.isEmpty {
            return "•••• \(mask)"
        }

        if let institution = account.institution_name,
           !institution.isEmpty {
            return institution
        }

        return nil
    }

    private func formattedDate(
        _ date: Date
    ) -> String {
        date.formatted(
            .dateTime.month(.abbreviated).day()
        )
    }

    private func accessibleDate(
        _ date: Date
    ) -> String {
        date.formatted(
            .dateTime.month(.wide).day().year()
        )
    }

    private func swipeAffordanceCenterY(
        layout: NewPaymentPlanCircleLayout,
        size: CGSize
    ) -> CGFloat {
        let circleTop = layout.center.y
            - (layout.innerDiameter / 2)

        return min(
            circleTop + 154,
            size.height - 124
        )
    }

    private func savePlan() {
        guard !isSaving,
              savePhase == .idle,
              let draft = currentDraft else {
            return
        }

        focusedField = nil
        saveErrorMessage = nil
        isSaving = true

        let persistenceResult = PlanningCreationPersistenceResult(
            didPersist: onSave(draft),
            failureMessage:
                "Your Payment Plan wasn't saved. Please try again."
        )
        isSaving = false

        guard persistenceResult.startsSuccessFlow else {
            saveErrorMessage = persistenceResult.errorMessage

            withAnimation(
                .spring(
                    response: 0.34,
                    dampingFraction: 0.82
                )
            ) {
                swipeProgress = 0
            }
            return
        }

        beginSuccessfulSaveAnimation()
    }

    private func beginSuccessfulSaveAnimation() {
        savePhase = .completing
        saveCompletionTask?.cancel()

        withAnimation(.easeOut(duration: 0.22)) {
            foregroundOpacity = 0
            swipeProgress = 1
        }

        saveCompletionTask = Task {
            if reduceMotion {
                try? await Task.sleep(
                    nanoseconds: 140_000_000
                )
            } else {
                try? await Task.sleep(
                    nanoseconds: 180_000_000
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(
                        .spring(
                            response: 0.62,
                            dampingFraction: 0.80
                        )
                    ) {
                        circleCompletionProgress = 1
                    }
                }

                try? await Task.sleep(
                    nanoseconds: 520_000_000
                )
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) {
                    savePhase = .success
                }

                #if os(iOS)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Plan created"
                )
                #endif
            }

            try? await Task.sleep(
                nanoseconds: reduceMotion
                    ? 560_000_000
                    : 720_000_000
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                onSaved?()
                dismiss()
            }
        }
    }
}

private struct NewPaymentPlanCircleLayout {

    let center: CGPoint
    let outerDiameter: CGFloat
    let middleDiameter: CGFloat
    let innerDiameter: CGFloat

    init(
        size: CGSize,
        swipeProgress: CGFloat,
        completionProgress: CGFloat
    ) {
        let largestDiameter = max(
            size.height * 1.22,
            size.width * 2.10,
            820
        )
        let dragScale = 1 + (0.08 * swipeProgress)
        let completionScale = 1
            + (1.08 * completionProgress)

        center = CGPoint(
            x: size.width / 2,
            y: size.height + 36
                - (120 * swipeProgress)
                - (size.height * 0.12 * completionProgress)
        )
        outerDiameter = largestDiameter
            * completionScale
            * dragScale
        middleDiameter = largestDiameter
            * (0.82 + (0.18 * completionProgress))
            * completionScale
            * dragScale
        innerDiameter = largestDiameter
            * (0.64 + (0.36 * completionProgress))
            * completionScale
            * dragScale
    }
}

private struct NewPaymentPlanConcentricCircles: View {

    @Environment(\.colorScheme) private var colorScheme

    let layout: NewPaymentPlanCircleLayout
    let swipeProgress: CGFloat
    let completionProgress: CGFloat

    private let style = CalderaCategoryStyle.style(
        for: .debtPayoff
    )

    var body: some View {
        ZStack {
            circle(
                colors: [
                    style.gradient[1].opacity(
                        colorScheme == .dark
                            ? 0.22
                                + (0.08 * swipeProgress)
                                + (0.16 * completionProgress)
                            : 0.17
                                + (0.07 * swipeProgress)
                                + (0.14 * completionProgress)
                    ),
                    style.gradient[2].opacity(
                        colorScheme == .dark
                            ? 0.16
                                + (0.06 * swipeProgress)
                                + (0.14 * completionProgress)
                            : 0.13
                                + (0.05 * swipeProgress)
                                + (0.12 * completionProgress)
                    )
                ],
                diameter: layout.outerDiameter,
                center: layout.center
            )

            circle(
                colors: [
                    style.gradient[0].opacity(
                        colorScheme == .dark
                            ? 0.28
                                + (0.08 * swipeProgress)
                                + (0.16 * completionProgress)
                            : 0.23
                                + (0.07 * swipeProgress)
                                + (0.14 * completionProgress)
                    ),
                    style.gradient[2].opacity(
                        colorScheme == .dark
                            ? 0.22
                                + (0.06 * swipeProgress)
                                + (0.14 * completionProgress)
                            : 0.18
                                + (0.05 * swipeProgress)
                                + (0.12 * completionProgress)
                    )
                ],
                diameter: layout.middleDiameter,
                center: layout.center
            )

            circle(
                colors: [
                    style.gradient[2].opacity(
                        colorScheme == .dark
                            ? 0.34
                                + (0.08 * swipeProgress)
                                + (0.18 * completionProgress)
                            : 0.28
                                + (0.07 * swipeProgress)
                                + (0.16 * completionProgress)
                    ),
                    Color(red: 0.73, green: 0.14, blue: 0.48).opacity(
                        colorScheme == .dark
                            ? 0.27
                                + (0.07 * swipeProgress)
                                + (0.16 * completionProgress)
                            : 0.21
                                + (0.06 * swipeProgress)
                                + (0.14 * completionProgress)
                    )
                ],
                diameter: layout.innerDiameter,
                center: layout.center
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func circle(
        colors: [Color],
        diameter: CGFloat,
        center: CGPoint
    ) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: diameter, height: diameter)
            .position(center)
    }
}

private extension View {

    func newPaymentPlanControlSurface(
        cornerRadius: CGFloat,
        colorScheme: ColorScheme
    ) -> some View {
        background {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .fill(
                colorScheme == .dark
                    ? Color.white.opacity(0.10)
                    : Color.white.opacity(0.70)
            )
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(
                    colorScheme == .dark ? 0.20 : 0.70
                ),
                lineWidth: 1
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
        .shadow(
            color: CalderaCategoryStyle.style(
                for: .debtPayoff
            ).primary.opacity(
                colorScheme == .dark ? 0.16 : 0.08
            ),
            radius: 14,
            y: 8
        )
    }

    func newPaymentPlanPillControl(
        colorScheme: ColorScheme
    ) -> some View {
        font(.subheadline.weight(.bold))
            .foregroundColor(
                CalderaVisualStyle.primaryText(colorScheme)
            )
            .frame(minWidth: 76, minHeight: 44)
            .padding(.horizontal, AppSpacing.small)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.10)
                            : Color.white.opacity(0.72)
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        Color.white.opacity(
                            colorScheme == .dark ? 0.20 : 0.68
                        ),
                        lineWidth: 1
                    )
            }
    }
}
