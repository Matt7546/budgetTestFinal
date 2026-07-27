import SwiftData
import SwiftUI
import UIKit

struct EditPaymentPlanView: View {

    private enum SavePhase {
        case idle
        case completing
        case success
    }

    private enum FocusedField: Hashable {
        case name
        case targetAmount
        case setAsideAmount
    }

    let bucket: DebtPayoffBucket
    let debtAccounts: [PlaidAccount]
    let paymentPlanCycles: [PaymentPlanCycle]
    let balanceLastUpdatedText: String
    let onSave: (DebtPayoffBucketDraft) -> Bool
    let onSaved: (() -> Void)?
    let onDelete: (DebtPayoffBucket) -> Bool
    let onDeleted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var plaid: PlaidService

    @State private var input: EditPaymentPlanInput
    @State private var detailsDraft: PaymentPlanDetailsDraft
    @State private var detailsTrigger: PaymentPlanDetailsCardTrigger?
    @State private var cardDetailsRequestState:
        NewPaymentPlanCardDetailsRequestState = .idle
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingHandleConfirmation = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var swipeProgress: CGFloat = 0
    @State private var circleCompletionProgress: CGFloat = 0
    @State private var foregroundOpacity: CGFloat = 1
    @State private var savePhase: SavePhase = .idle
    @State private var cycleResolutionUndo: PaymentPlanCycleResolutionUndo?
    @State private var confirmationMessage: String?
    @State private var confirmationID = UUID()
    @State private var completionTask: Task<Void, Never>?
    @State private var deferredActionTask: Task<Void, Never>?
    @FocusState private var focusedField: FocusedField?

    private let controlWidth: CGFloat = 326
    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    init(
        bucket: DebtPayoffBucket,
        debtAccounts: [PlaidAccount],
        paymentPlanCycles: [PaymentPlanCycle],
        balanceLastUpdatedText: String,
        onSave: @escaping (DebtPayoffBucketDraft) -> Bool,
        onSaved: (() -> Void)? = nil,
        onDelete: @escaping (DebtPayoffBucket) -> Bool,
        onDeleted: (() -> Void)? = nil
    ) {
        self.bucket = bucket
        self.debtAccounts = debtAccounts
        self.paymentPlanCycles = paymentPlanCycles
        self.balanceLastUpdatedText = balanceLastUpdatedText
        self.onSave = onSave
        self.onSaved = onSaved
        self.onDelete = onDelete
        self.onDeleted = onDeleted

        let initialInput = EditPaymentPlanInput(bucket: bucket)
        _input = State(initialValue: initialInput)
        _detailsDraft = State(
            initialValue: PaymentPlanDetailsDraft(input: initialInput)
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let circleLayout = EditPaymentPlanCircleLayout(
                    size: proxy.size,
                    projectedProgress: input.projectedProgress,
                    swipeProgress: swipeProgress,
                    completionProgress: circleCompletionProgress
                )

                ZStack {
                    CalderaModalBackground(mood: .debtPayoff)

                    EditPaymentPlanConcentricCircles(
                        layout: circleLayout,
                        swipeProgress: swipeProgress,
                        completionProgress: circleCompletionProgress
                    )
                    .animation(
                        .easeInOut(duration: 0.42),
                        value: input.projectedProgress
                    )

                    VStack(spacing: 0) {
                        topControls
                        updateContent(
                            usesCompactSpacing: proxy.size.height < 740
                        )
                        .padding(
                            .top,
                            proxy.size.height < 740 ? 20 : 34
                        )
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
                    .allowsHitTesting(savePhase == .idle && !isSaving)

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
                            accessibilityLabel: "Save Payment Plan updates",
                            accessibilityHint: "Swipe up or activate to save Set Aside and Payment Plan detail changes.",
                            swipeProgress: $swipeProgress,
                            onSaveTriggered: savePaymentPlan
                        )
                        .opacity(foregroundOpacity)
                        .transition(.opacity)
                    }

                    if savePhase == .success {
                        PlanningCreationSuccessOverlay(
                            title: "Plan updated",
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
        .sheet(item: $detailsTrigger) { _ in
            paymentPlanDetailsCard
        }
        .confirmationDialog(
            "Mark this payment period handled?",
            isPresented: $isShowingHandleConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark as Handled") {
                confirmCycleResolution()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Only continue if you handled this payment outside Caldera. Caldera does not make payments or move money. This will return \(AppFormatters.currency(max(bucket.protectedAmount, 0))) set aside for this payment to Available to Spend in your plan."
            )
        }
        .confirmationDialog(
            "Delete Payment Plan?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Payment Plan", role: .destructive) {
                deletePaymentPlan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the plan and its payment-cycle history. Money set aside for it will no longer be kept out of Available to Spend.")
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
                    ?? "Your Payment Plan update wasn't saved. Please try again."
            )
        }
        .calderaConfirmationOverlay(
            message: confirmationMessage,
            actionTitle: cycleResolutionUndo == nil ? nil : "Undo",
            action: undoCycleResolution
        )
        .onChange(
            of: selectedCardPaymentDetails?.last_refreshed_at
        ) { _, refreshedAt in
            guard refreshedAt != nil,
                  cardDetailsRequestState == .needsPermission else {
                return
            }
            cardDetailsRequestState = .updated
        }
        .onDisappear {
            completionTask?.cancel()
            deferredActionTask?.cancel()
        }
    }

    private var linkedAccount: PlaidAccount? {
        debtAccounts.first { $0.account_id == bucket.plaidAccountID }
    }

    private var activeCycle: PaymentPlanCycle? {
        PaymentPlanCycleStore.activeCycle(
            for: bucket.id,
            in: paymentPlanCycles
        )
    }

    private var latestCycle: PaymentPlanCycle? {
        PaymentPlanCycleStore.latestCycle(
            for: bucket.id,
            in: paymentPlanCycles
        )
    }

    private var likelyPostedPaymentCandidate: PaymentPlanPaymentCandidate? {
        guard let activeCycle else { return nil }
        return plaid.likelyPostedCardPayment(
            for: bucket,
            cycle: activeCycle
        )
    }

    private var usableCardPaymentDetails: [LinkedCardPaymentDetails] {
        plaid.backendLiabilitiesEnabled
            ? plaid.cardPaymentDetails
            : []
    }

    private var selectedCardPaymentDetails: LinkedCardPaymentDetails? {
        usableCardPaymentDetails.first {
            $0.account_id == bucket.plaidAccountID
        }
    }

    private var statementDueDate: Date? {
        PaymentPlanCalendarDate.parse(
            selectedCardPaymentDetails?.next_payment_due_date
        )
    }

    private var cardPaymentDetailsConsentRequired: Bool {
        guard selectedCardPaymentDetails == nil,
              let response = plaid.latestCardPaymentDetailsResponse else {
            return false
        }
        return response.consent_required == true ||
            response.error == "additional_consent_required"
    }

    private var canRequestCardPaymentDetailsConsent: Bool {
        guard plaid.backendLiabilitiesLinkEnabled,
              let itemID = linkedAccount?.item_id?.trimmingCharacters(
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
            consentRequired: cardPaymentDetailsConsentRequired &&
                canRequestCardPaymentDetailsConsent,
            requestState: cardDetailsRequestState
        )
    }

    private var topControls: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .editPaymentPlanPillControl(colorScheme: colorScheme)
                .accessibilityLabel("Cancel Payment Plan updates")

            Spacer()

            Button {
                presentDetails(from: .options)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(pillSurface)
                    .overlay {
                        Circle().stroke(
                            Color.white.opacity(
                                colorScheme == .dark ? 0.20 : 0.68
                            ),
                            lineWidth: 1
                        )
                    }
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundColor(
                CalderaVisualStyle.primaryText(colorScheme)
            )
            .accessibilityLabel("Payment Plan options")
            .accessibilityHint("Opens Payment Plan details")
        }
    }

    private func updateContent(
        usesCompactSpacing: Bool
    ) -> some View {
        VStack(
            spacing: usesCompactSpacing
                ? AppSpacing.small
                : AppSpacing.regular
        ) {
            planNamePill
            planContextPill
            setAsideModePicker
            setAsideAmountHero

            if !helperMessage.isEmpty {
                Text(helperMessage)
                    .font(.caption.weight(.medium))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 18)
                    .accessibilityLabel(helperMessage)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var planNamePill: some View {
        Button {
            presentDetails(from: .planName)
        } label: {
            ZStack {
                Text(input.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(
                        CalderaVisualStyle.primaryText(colorScheme)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 48)

                HStack {
                    Image(systemName: style.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(paymentPlanAccentGradient)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(
                            CalderaVisualStyle.secondaryText(colorScheme)
                        )
                }
                .padding(.horizontal, AppSpacing.regular)
            }
            .frame(maxWidth: controlWidth)
            .frame(height: 52)
            .background(pillSurface)
            .overlay {
                Capsule(style: .continuous).stroke(
                    Color.white.opacity(
                        colorScheme == .dark ? 0.20 : 0.72
                    ),
                    lineWidth: 1
                )
            }
            .clipShape(Capsule(style: .continuous))
            .shadow(
                color: style.primary.opacity(
                    colorScheme == .dark ? 0.16 : 0.08
                ),
                radius: 14,
                y: 8
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Payment Plan \(input.name)")
        .accessibilityHint("Opens Payment Plan details")
    }

    private var planContextPill: some View {
        Button {
            presentDetails(from: .planContext)
        } label: {
            VStack(spacing: AppSpacing.xxSmall) {
                HStack(spacing: AppSpacing.xSmall) {
                    Text("Target \(AppFormatters.currency(displayTargetAmount))")
                    contextDivider
                    Text("Set aside \(AppFormatters.currency(input.original.protectedAmount))")
                    contextDivider
                    Text("Remaining \(AppFormatters.currency(displayRemainingAmount))")
                }

                HStack(spacing: AppSpacing.xSmall) {
                    Label(
                        "Due \(AppFormatters.abbreviatedMonthDay(input.dueDate))",
                        systemImage: "calendar"
                    )
                    contextDivider
                    Text(targetBasisTitle)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(
                CalderaVisualStyle.secondaryText(colorScheme)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .padding(.horizontal, AppSpacing.medium)
            .frame(maxWidth: controlWidth, minHeight: 54)
            .background(pillSurface.opacity(0.86))
            .overlay {
                Capsule(style: .continuous).stroke(
                    Color.white.opacity(
                        colorScheme == .dark ? 0.15 : 0.58
                    ),
                    lineWidth: 1
                )
            }
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Payment Target \(AppFormatters.currency(displayTargetAmount)), \(AppFormatters.currency(input.original.protectedAmount)) set aside, \(AppFormatters.currency(displayRemainingAmount)) remaining, due \(AppFormatters.abbreviatedMonthDay(input.dueDate)), \(targetBasisTitle)"
        )
        .accessibilityHint("Opens Payment Plan details")
    }

    private var contextDivider: some View {
        Rectangle()
            .fill(
                CalderaVisualStyle.secondaryText(colorScheme)
                    .opacity(0.28)
            )
            .frame(width: 1, height: 14)
    }

    private var setAsideModePicker: some View {
        Picker(
            "Set Aside change",
            selection: $input.setAsideChangeMode
        ) {
            ForEach(PaymentPlanSetAsideChangeMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 228)
        .accessibilityLabel("Set Aside change")
        .accessibilityValue(input.setAsideChangeMode.title)
    }

    private var setAsideAmountHero: some View {
        VStack(spacing: AppSpacing.xSmall) {
            Text(input.setAsideChangeMode.heroTitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )
                .textCase(.uppercase)

            Button {
                focusedField = .setAsideAmount
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
                                input.setAsideAmountText.isEmpty
                                    ? 0.50
                                    : 0.78
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
                            input.setAsideAmountText.isEmpty
                                ? AnyShapeStyle(
                                    CalderaVisualStyle.secondaryText(
                                        colorScheme
                                    ).opacity(0.42)
                                )
                                : AnyShapeStyle(paymentPlanAccentGradient)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .padding(.horizontal, AppSpacing.small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(input.setAsideChangeMode.heroTitle)
            .accessibilityValue("$\(heroAmountDisplayText)")
            .accessibilityHint("Double tap to enter dollars and cents")
            .background {
                TextField("", text: $input.setAsideAmountText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .setAsideAmount)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)
            }

            Text(projectedTotalText)
                .font(.caption.weight(.medium))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )
                .accessibilityLabel(projectedTotalText)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension EditPaymentPlanView {

    var paymentPlanDetailsCard: some View {
        NavigationStack {
            ZStack {
                CalderaModalBackground(mood: .debtPayoff)

                ScrollView {
                    VStack(spacing: AppSpacing.small) {
                        accountIdentityField
                        planNameField
                        paymentTargetFields
                        dueDateFields

                        if input.isLinkedAccount,
                           linkedAccount != nil,
                           plaid.backendLiabilitiesEnabled {
                            cardDetailsControl
                        }

                        paymentCycleDetails

                        Button(role: .destructive) {
                            prepareDeleteConfirmation()
                        } label: {
                            Label(
                                "Delete Payment Plan",
                                systemImage: "trash"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityLabel("Delete Payment Plan")
                    }
                    .padding(AppSpacing.screen)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Payment Plan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissDetails()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyDetailsDraft()
                    }
                    .disabled(!detailsDraft.isValid)
                }
            }
            .keyboardDismissToolbar()
        }
        .calderaTransparentNavigationSurface()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    var accountIdentityField: some View {
        HStack(spacing: AppSpacing.small) {
            Image(
                systemName: input.isLinkedAccount
                    ? "link.circle.fill"
                    : "creditcard.fill"
            )
            .foregroundStyle(paymentPlanAccentGradient)

            VStack(alignment: .leading, spacing: 2) {
                Text(input.isLinkedAccount ? "Linked Account" : "Manual")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )

                Text(linkedAccount?.name ?? input.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer()

            if input.isLinkedAccount {
                Text(balanceLastUpdatedText)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .paymentPlanDetailsFieldSurface(colorScheme: colorScheme)
        .accessibilityElement(children: .combine)
    }

    var planNameField: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "text.cursor")
                .foregroundStyle(paymentPlanAccentGradient)

            TextField(
                "Payment Plan name",
                text: $detailsDraft.name
            )
            .textInputAutocapitalization(.words)
            .submitLabel(.next)
            .focused($focusedField, equals: .name)
            .onSubmit { focusedField = .targetAmount }
            .accessibilityLabel("Payment Plan name")
        }
        .paymentPlanDetailsFieldSurface(colorScheme: colorScheme)
    }

    @ViewBuilder
    var paymentTargetFields: some View {
        if input.isLinkedAccount {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Payment Target")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )

                ForEach(
                    DebtPayoffLinkedCardPaymentTargetChoice.allCases
                ) { choice in
                    targetChoiceButton(choice)
                }

                if detailsDraft.paymentTargetChoice == .customAmount ||
                    detailsDraft.paymentTargetChoice == nil {
                    targetAmountField
                }
            }
            .paymentPlanDetailsFieldSurface(colorScheme: colorScheme)
        } else {
            targetAmountField
                .paymentPlanDetailsFieldSurface(
                    colorScheme: colorScheme
                )
        }
    }

    var targetAmountField: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "target")
                .foregroundStyle(paymentPlanAccentGradient)

            TextField(
                "Payment Target",
                text: Binding(
                    get: { detailsDraft.paymentTargetAmountText },
                    set: { newValue in
                        detailsDraft.paymentTargetAmountText = newValue
                        if input.isLinkedAccount {
                            detailsDraft.paymentTargetChoice = .customAmount
                            detailsDraft.targetStatementIssueDate = nil
                            detailsDraft.didExplicitlyChooseTarget = true
                        }
                    }
                )
            )
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .targetAmount)
            .accessibilityLabel("Payment Target")

            Text(
                detailsDraft.paymentTargetAmount.map {
                    AppFormatters.currency($0)
                } ?? "Not set"
            )
            .font(.caption.weight(.semibold))
            .foregroundColor(
                CalderaVisualStyle.secondaryText(colorScheme)
            )
            .lineLimit(1)
        }
    }

    func targetChoiceButton(
        _ choice: DebtPayoffLinkedCardPaymentTargetChoice
    ) -> some View {
        let amount = suggestedAmount(for: choice)
        let isAvailable = choice == .customAmount || amount != nil
        let isSelected = detailsDraft.paymentTargetChoice == choice

        return Button {
            selectTargetChoice(choice, suggestedAmount: amount)
        } label: {
            HStack(spacing: AppSpacing.small) {
                Image(
                    systemName: isSelected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(paymentPlanAccentGradient)

                Text(NewPaymentPlanTargetPresentation.title(for: choice))
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(
                    choice == .customAmount
                        ? "Choose balance"
                        : amount.map { AppFormatters.currency($0) }
                            ?? "Not available"
                )
                .font(.caption.weight(.medium))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )
                .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.55)
        .accessibilityLabel(
            "\(NewPaymentPlanTargetPresentation.title(for: choice)), \(choice == .customAmount ? "choose your own" : amount.map { AppFormatters.currency($0) } ?? "not available")"
        )
    }

    var dueDateFields: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Due Date")
                .font(.caption.weight(.semibold))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )

            if let statementDueDate,
               input.isLinkedAccount {
                dueDateSourceButton(
                    .statement,
                    date: statementDueDate
                )
            }

            dueDateSourceButton(
                .custom,
                date: detailsDraft.dueDate
            )

            if detailsDraft.dueDateSource == .custom ||
                statementDueDate == nil {
                DatePicker(
                    "Custom due date",
                    selection: Binding(
                        get: { detailsDraft.dueDate },
                        set: { newDate in
                            detailsDraft.dueDate = newDate
                            detailsDraft.dueDateSource = .custom
                        }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(style.primary)
            }
        }
        .paymentPlanDetailsFieldSurface(colorScheme: colorScheme)
    }

    func dueDateSourceButton(
        _ source: PaymentPlanDueDateDraftSource,
        date: Date
    ) -> some View {
        Button {
            detailsDraft.dueDateSource = source
            if source == .statement,
               let statementDueDate {
                detailsDraft.dueDate = statementDueDate
            }
        } label: {
            HStack(spacing: AppSpacing.small) {
                Image(
                    systemName: detailsDraft.dueDateSource == source
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .foregroundStyle(paymentPlanAccentGradient)

                Text(source.title)
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(AppFormatters.abbreviatedMonthDay(date))
                    .font(.caption.weight(.medium))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(source.title), \(AppFormatters.abbreviatedMonthDay(date))"
        )
    }

    var cardDetailsControl: some View {
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
                            CalderaVisualStyle.secondaryText(colorScheme)
                        )
                }

                Spacer(minLength: AppSpacing.small)

                Text(cardDetailsStatus.actionTitle)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(paymentPlanAccentGradient)
            }
        }
        .buttonStyle(.plain)
        .disabled(cardDetailsStatus == .refreshing)
        .paymentPlanDetailsFieldSurface(colorScheme: colorScheme)
        .accessibilityLabel(
            "Bank Data, \(cardDetailsStatus.title)"
        )
        .accessibilityHint(
            cardDetailsStatus == .needsPermission
                ? "Double tap to add Card Payment Details permission"
                : "Double tap to refresh Card Payment Details"
        )
    }

    @ViewBuilder
    var paymentCycleDetails: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Payment Period")
                .font(.caption.weight(.semibold))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )

            if let activeCycle {
                cycleValueRow(
                    title: "Due",
                    value: AppFormatters.abbreviatedMonthDay(
                        activeCycle.dueDate
                    )
                )
                cycleValueRow(
                    title: "Planned payment",
                    value: AppFormatters.currency(
                        activeCycle.frozenTargetAmount
                    )
                )
                cycleValueRow(
                    title: "Set Aside",
                    value: AppFormatters.currency(
                        max(bucket.protectedAmount, 0)
                    )
                )

                if let candidate = likelyPostedPaymentCandidate {
                    Text(
                        "A payment of \(AppFormatters.currency(candidate.amount)) may have posted after your last Bank Sync."
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
                }

                Button {
                    prepareHandleConfirmation()
                } label: {
                    Label(
                        likelyPostedPaymentCandidate == nil
                            ? "Mark as Handled"
                            : "Review payment",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.bordered)
                .tint(
                    CalderaCategoryStyle.style(for: .covered).primary
                )
                .disabled(input.hasValidChange || !detailsDraft.isValid)

                if input.hasValidChange {
                    Text("Save or cancel your draft before marking this payment handled.")
                        .font(.caption2)
                        .foregroundColor(
                            CalderaVisualStyle.secondaryText(colorScheme)
                        )
                }
            } else if let latestCycle,
                      latestCycle.status == .handled {
                Text("Payment handled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(paymentPlanAccentGradient)

                Text(
                    "\(AppFormatters.currency(latestCycle.releasedSetAsideAmount)) returned to Available to Spend in your plan."
                )
                .font(.caption)
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )

                Button {
                    beginPlanningNextPayment(from: latestCycle)
                } label: {
                    Label(
                        "Plan Next Payment",
                        systemImage: "calendar.badge.plus"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.bordered)
                .tint(style.primary)
                .disabled(!detailsDraft.isValid)
            } else if input.shouldCreateActiveCycle {
                Text("This payment period will begin when you swipe to save.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
            } else {
                Text("This plan does not track a specific payment period yet.")
                    .font(.caption)
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )

                Button {
                    beginTrackingCurrentPayment()
                } label: {
                    Label(
                        "Track this payment",
                        systemImage: "calendar.badge.plus"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.bordered)
                .tint(style.primary)
                .disabled(!detailsDraft.isValid)
            }

            Text("Caldera records what you do outside the app. It does not make payments or move money.")
                .font(.caption2)
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )
        }
        .paymentPlanDetailsFieldSurface(colorScheme: colorScheme)
    }

    func cycleValueRow(
        title: String,
        value: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )
            Spacer()
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
    }
}

private extension EditPaymentPlanView {

    var displayTargetAmount: Double {
        input.paymentTargetAmount ?? input.original.paymentTargetAmount
    }

    var displayRemainingAmount: Double {
        input.remainingAmount
    }

    var targetBasisTitle: String {
        guard let choice = input.paymentTargetChoice else {
            return "Payment target"
        }
        return NewPaymentPlanTargetPresentation.title(for: choice)
    }

    var heroAmountDisplayText: String {
        NewPaymentPlanAmountPresentation.displayText(
            for: input.setAsideAmountText
        )
    }

    var heroAmountFontSize: CGFloat {
        switch max(heroAmountDisplayText.count, 1) {
        case ...4:
            return 82
        case 5...7:
            return 68
        case 8...10:
            return 52
        default:
            return 38
        }
    }

    var heroCurrencyFontSize: CGFloat {
        max(heroAmountFontSize * 0.54, 28)
    }

    var projectedTotalText: String {
        let amount = input.projectedSetAsideAmount
            ?? input.original.protectedAmount
        return "New total: \(AppFormatters.currency(amount)) of \(AppFormatters.currency(displayTargetAmount))"
    }

    var helperMessage: String {
        if let validationMessage = input.validationMessage {
            return validationMessage
        }
        if focusedField != nil {
            return "Hide the keyboard when you're ready to save."
        }
        return ""
    }

    var isSwipeAffordanceVisible: Bool {
        input.hasValidChange &&
            focusedField == nil &&
            detailsTrigger == nil &&
            !isShowingDeleteConfirmation &&
            !isShowingHandleConfirmation &&
            !isSaving &&
            savePhase == .idle
    }

    var paymentPlanAccentGradient: LinearGradient {
        LinearGradient(
            colors: style.gradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var pillSurface: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.72)
    }

    func swipeAffordanceCenterY(
        layout: EditPaymentPlanCircleLayout,
        size: CGSize
    ) -> CGFloat {
        let circleTop = layout.center.y - (layout.innerDiameter / 2)
        return min(
            max(circleTop + 154, size.height - 145),
            size.height - 124
        )
    }

    func presentDetails(
        from trigger: PaymentPlanDetailsCardTrigger
    ) {
        focusedField = nil
        detailsDraft = PaymentPlanDetailsDraft(
            input: input,
            statementDueDate: statementDueDate
        )
        detailsTrigger = trigger
    }

    func dismissDetails() {
        focusedField = nil
        detailsTrigger = nil
    }

    func applyDetailsDraft() {
        guard PaymentPlanDetailsDraftCoordinator.apply(
            draft: detailsDraft,
            to: &input
        ) else {
            return
        }
        focusedField = nil
        detailsTrigger = nil
    }

    func suggestedAmount(
        for choice: DebtPayoffLinkedCardPaymentTargetChoice
    ) -> Double? {
        choice.suggestedAmount(
            statementBalance:
                selectedCardPaymentDetails?.last_statement_balance,
            minimumPayment:
                selectedCardPaymentDetails?.minimum_payment_amount,
            currentBalance: linkedAccount?.debtBalanceValue
        )
    }

    func selectTargetChoice(
        _ choice: DebtPayoffLinkedCardPaymentTargetChoice,
        suggestedAmount: Double?
    ) {
        detailsDraft.paymentTargetChoice = choice
        detailsDraft.didExplicitlyChooseTarget = true
        detailsDraft.targetStatementIssueDate =
            PaymentPlanCalendarDate.anchor(
                for: choice,
                liveValue:
                    selectedCardPaymentDetails?.last_statement_issue_date
            )

        if choice == .customAmount {
            focusedField = .targetAmount
        } else if let suggestedAmount {
            detailsDraft.paymentTargetAmountText =
                EditPaymentPlanInput.amountText(suggestedAmount)
        }
    }

    func refreshCardDetails() {
        guard let linkedAccount else { return }

        if cardPaymentDetailsConsentRequired &&
            canRequestCardPaymentDetailsConsent ||
            cardDetailsRequestState == .needsPermission {
            requestCardPaymentDetailsConsent(for: linkedAccount)
            return
        }

        let requestedAccountID = linkedAccount.account_id
        cardDetailsRequestState = .refreshing

        plaid.fetchCardPaymentDetails { response in
            guard bucket.plaidAccountID == requestedAccountID else {
                return
            }

            if response?.consent_required == true ||
                response?.error == "additional_consent_required" {
                cardDetailsRequestState =
                    canRequestCardPaymentDetailsConsent
                        ? .needsPermission
                        : .unavailable
                return
            }

            let didLoadSelectedCard = response?.cards.contains {
                $0.account_id == requestedAccountID
            } ?? false
            cardDetailsRequestState = didLoadSelectedCard
                ? .updated
                : .unavailable
        }
    }

    func requestCardPaymentDetailsConsent(
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
        plaid.createCardPaymentDetailsUpdateLinkToken(
            itemID: itemID,
            accountID: account.account_id
        )
    }

    func beginPlanningNextPayment(
        from latestCycle: PaymentPlanCycle
    ) {
        guard PaymentPlanLifecycleDraftCoordinator.preparePlanNextPayment(
            draft: detailsDraft,
            latestCycle: latestCycle,
            input: &input
        ) != .blockedInvalidDetails else {
            return
        }

        focusedField = nil
        detailsTrigger = nil
    }

    func beginTrackingCurrentPayment() {
        guard PaymentPlanLifecycleDraftCoordinator.prepareTrackPayment(
            draft: detailsDraft,
            input: &input
        ) != .blockedInvalidDetails else {
            return
        }

        focusedField = nil
        detailsTrigger = nil
    }

    func prepareHandleConfirmation() {
        let preparation =
            PaymentPlanLifecycleDraftCoordinator.prepareMarkAsHandled(
                draft: detailsDraft,
                input: &input
            )

        guard preparation != .blockedInvalidDetails else { return }

        if preparation == .requiresSwipeSave {
            focusedField = nil
            detailsTrigger = nil
            showCycleConfirmation(
                "Swipe to save your Payment Plan changes before marking this payment handled."
            )
            return
        }

        detailsTrigger = nil
        deferredActionTask?.cancel()
        deferredActionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            isShowingHandleConfirmation = true
        }
    }

    func confirmCycleResolution() {
        guard let activeCycle else { return }
        let releasedAmount = max(bucket.protectedAmount, 0)

        guard let undo = PaymentPlanCycleResolutionMutation.apply(
            .paid,
            to: activeCycle,
            bucket: bucket
        ) else {
            return
        }

        do {
            try modelContext.save()
            cycleResolutionUndo = undo
            input.resetBaseline(from: bucket)
            showCycleConfirmation(
                "Payment period handled. \(AppFormatters.currency(releasedAmount)) returned to Available to Spend in your plan.",
                preservesUndo: true
            )
        } catch {
            modelContext.rollback()
            undo.restore()
            showCycleConfirmation(
                "This payment period could not be updated. Try again."
            )
        }
    }

    func undoCycleResolution() {
        guard let cycleResolutionUndo else { return }
        cycleResolutionUndo.restore()
        self.cycleResolutionUndo = nil

        do {
            try modelContext.save()
            input.resetBaseline(from: bucket)
            showCycleConfirmation(
                "Payment period restored. \(AppFormatters.currency(cycleResolutionUndo.priorProtectedAmount)) is counted in Set Aside again."
            )
        } catch {
            modelContext.rollback()
            showCycleConfirmation(
                "The payment period was restored, but saving is still in progress."
            )
        }
    }

    func showCycleConfirmation(
        _ message: String,
        preservesUndo: Bool = false
    ) {
        if !preservesUndo {
            cycleResolutionUndo = nil
        }

        let id = UUID()
        confirmationID = id
        confirmationMessage = message
        let duration: UInt64 = preservesUndo
            ? 6_000_000_000
            : 2_400_000_000

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: duration)
            if confirmationID == id {
                confirmationMessage = nil
                cycleResolutionUndo = nil
            }
        }
    }

    func prepareDeleteConfirmation() {
        detailsTrigger = nil
        deferredActionTask?.cancel()
        deferredActionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            isShowingDeleteConfirmation = true
        }
    }

    func deletePaymentPlan() {
        if onDelete(bucket) {
            onDeleted?()
            dismiss()
        } else {
            saveErrorMessage =
                "This Payment Plan wasn't deleted. Please try again."
        }
    }

    func savePaymentPlan() {
        guard !isSaving,
              savePhase == .idle,
              input.hasValidChange,
              let draft = input.draft(for: bucket) else {
            resetSwipeProgress()
            return
        }

        focusedField = nil
        saveErrorMessage = nil
        isSaving = true
        let didPersist = onSave(draft)
        isSaving = false

        let result = PlanningCreationPersistenceResult(
            didPersist: didPersist,
            failureMessage:
                "Your Payment Plan update wasn't saved. Please try again."
        )
        guard result.startsSuccessFlow else {
            saveErrorMessage = result.errorMessage
            resetSwipeProgress()
            return
        }

        beginSuccessfulSaveAnimation()
    }

    func beginSuccessfulSaveAnimation() {
        savePhase = .completing
        completionTask?.cancel()

        withAnimation(.easeOut(duration: 0.22)) {
            foregroundOpacity = 0
            swipeProgress = 1
        }

        completionTask = Task {
            if reduceMotion {
                try? await Task.sleep(nanoseconds: 140_000_000)
            } else {
                try? await Task.sleep(nanoseconds: 180_000_000)
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

                try? await Task.sleep(nanoseconds: 520_000_000)
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) {
                    savePhase = .success
                }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Payment Plan updated"
                )
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

    func resetSwipeProgress() {
        withAnimation(
            .spring(
                response: 0.34,
                dampingFraction: 0.82
            )
        ) {
            swipeProgress = 0
        }
    }
}

private struct EditPaymentPlanCircleLayout {
    let center: CGPoint
    let outerDiameter: CGFloat
    let middleDiameter: CGFloat
    let innerDiameter: CGFloat

    init(
        size: CGSize,
        projectedProgress: Double,
        swipeProgress: CGFloat,
        completionProgress: CGFloat
    ) {
        let largestDiameter = max(
            size.height * 1.22,
            size.width * 2.10,
            820
        )
        let safeProgress = min(
            max(CGFloat(projectedProgress), 0),
            1
        )
        let visualProgress = safeProgress.squareRoot()
        let middleProgressScale = 0.70 + (0.30 * visualProgress)
        let innerProgressScale = 0.45 + (0.55 * visualProgress)
        let mergedMiddleScale = middleProgressScale +
            ((1 - middleProgressScale) * completionProgress)
        let mergedInnerScale = innerProgressScale +
            ((1 - innerProgressScale) * completionProgress)
        let dragScale = 1 + (0.08 * swipeProgress)
        let completionScale = 1 + (1.08 * completionProgress)

        center = CGPoint(
            x: size.width / 2,
            y: size.height + 36
                - (120 * swipeProgress)
                - (size.height * 0.12 * completionProgress)
        )
        outerDiameter = largestDiameter * completionScale * dragScale
        middleDiameter = largestDiameter * mergedMiddleScale *
            completionScale * dragScale
        innerDiameter = largestDiameter * mergedInnerScale *
            completionScale * dragScale
    }
}

private struct EditPaymentPlanConcentricCircles: View {
    @Environment(\.colorScheme) private var colorScheme

    let layout: EditPaymentPlanCircleLayout
    let swipeProgress: CGFloat
    let completionProgress: CGFloat

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    var body: some View {
        ZStack {
            circle(
                colors: [
                    style.gradient[2].opacity(
                        colorScheme == .dark
                            ? 0.22 + (0.08 * swipeProgress) +
                                (0.16 * completionProgress)
                            : 0.17 + (0.07 * swipeProgress) +
                                (0.14 * completionProgress)
                    ),
                    style.gradient[1].opacity(
                        colorScheme == .dark
                            ? 0.16 + (0.06 * swipeProgress) +
                                (0.14 * completionProgress)
                            : 0.13 + (0.05 * swipeProgress) +
                                (0.12 * completionProgress)
                    )
                ],
                diameter: layout.outerDiameter
            )
            circle(
                colors: [
                    style.gradient[1].opacity(
                        colorScheme == .dark
                            ? 0.27 + (0.08 * swipeProgress) +
                                (0.16 * completionProgress)
                            : 0.22 + (0.07 * swipeProgress) +
                                (0.14 * completionProgress)
                    ),
                    style.gradient[0].opacity(
                        colorScheme == .dark
                            ? 0.20 + (0.06 * swipeProgress) +
                                (0.14 * completionProgress)
                            : 0.16 + (0.05 * swipeProgress) +
                                (0.12 * completionProgress)
                    )
                ],
                diameter: layout.middleDiameter
            )
            circle(
                colors: [
                    style.gradient[0].opacity(
                        colorScheme == .dark
                            ? 0.30 + (0.08 * swipeProgress) +
                                (0.18 * completionProgress)
                            : 0.24 + (0.07 * swipeProgress) +
                                (0.16 * completionProgress)
                    ),
                    style.gradient[2].opacity(
                        colorScheme == .dark
                            ? 0.23 + (0.07 * swipeProgress) +
                                (0.16 * completionProgress)
                            : 0.18 + (0.06 * swipeProgress) +
                                (0.14 * completionProgress)
                    )
                ],
                diameter: layout.innerDiameter
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func circle(
        colors: [Color],
        diameter: CGFloat
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
            .position(layout.center)
    }
}

private extension View {
    func paymentPlanDetailsFieldSurface(
        colorScheme: ColorScheme
    ) -> some View {
        padding(AppSpacing.regular)
            .frame(minHeight: 52)
            .calderaGlassCard(
                cornerRadius: AppRadii.card,
                fillOpacity: colorScheme == .dark ? 0.58 : 0.80,
                strokeOpacity: colorScheme == .dark ? 0.36 : 0.52,
                shadowOpacity: 0.04,
                shadowRadius: 12,
                shadowY: 6,
                darkGlowColor: CalderaCategoryStyle
                    .style(for: .debtPayoff)
                    .primary
            )
    }

    func editPaymentPlanPillControl(
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
