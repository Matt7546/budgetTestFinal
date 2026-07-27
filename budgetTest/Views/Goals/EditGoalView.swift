import SwiftUI
import UIKit

enum SavingsGoalSetAsideChangeMode: String, CaseIterable, Identifiable {
    case add
    case use

    var id: Self { self }

    var title: String {
        switch self {
        case .add:
            return "Add"
        case .use:
            return "Use"
        }
    }

    var heroTitle: String {
        switch self {
        case .add:
            return "Add to Set Aside"
        case .use:
            return "Use Set Aside"
        }
    }
}

struct EditSavingsGoalInput: Equatable {

    let originalGoal: SavingsGoal
    var name: String
    var targetAmountText: String
    var saveByDate: Date?
    var isPinned: Bool
    var setAsideChangeMode: SavingsGoalSetAsideChangeMode = .add
    var setAsideAmountText = ""

    init(goal: SavingsGoal) {
        originalGoal = goal
        name = goal.name
        targetAmountText = Self.amountText(goal.targetAmount)
        saveByDate = goal.saveByDate
        isPinned = goal.isPinned
    }

    var updatedGoal: SavingsGoal? {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedName.isEmpty,
              let targetAmount,
              let projectedSetAsideAmount else {
            return nil
        }

        return SavingsGoal(
            id: originalGoal.id,
            name: trimmedName,
            targetAmount: targetAmount,
            currentAmount: projectedSetAsideAmount,
            isPinned: isPinned,
            saveByDate: saveByDate
        )
    }

    var hasValidChange: Bool {
        guard let updatedGoal else {
            return false
        }

        return updatedGoal != originalGoal
    }

    var targetAmount: Double? {
        guard let amount = MoneyAmountParser.parse(
            targetAmountText
        ),
        amount.isFinite,
        amount > 0 else {
            return nil
        }

        return amount
    }

    var setAsideChangeAmount: Double? {
        let trimmedAmount = setAsideAmountText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedAmount.isEmpty else {
            return 0
        }

        guard let amount = MoneyAmountParser.parse(
            trimmedAmount
        ),
        amount.isFinite,
        amount >= 0 else {
            return nil
        }

        return amount
    }

    var projectedSetAsideAmount: Double? {
        guard let amount = setAsideChangeAmount else {
            return nil
        }

        switch setAsideChangeMode {
        case .add:
            let projectedAmount = originalGoal.currentAmount + amount
            return projectedAmount.isFinite
                ? projectedAmount
                : nil

        case .use:
            guard amount <= originalGoal.currentAmount else {
                return nil
            }

            return max(originalGoal.currentAmount - amount, 0)
        }
    }

    var projectedProgress: Double {
        guard let targetAmount,
              let projectedSetAsideAmount else {
            return originalGoal.progress
        }

        let value = projectedSetAsideAmount / targetAmount
        guard value.isFinite else {
            return originalGoal.progress
        }

        return min(max(value, 0), 1)
    }

    var validationMessage: String? {
        guard !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return "Add a goal name to save."
        }

        guard targetAmount != nil else {
            return "Enter a target amount greater than $0."
        }

        guard let setAsideChangeAmount else {
            return "Enter a valid Set Aside amount."
        }

        if setAsideChangeMode == .use,
           setAsideChangeAmount > originalGoal.currentAmount {
            return "You can use up to \(AppFormatters.currency(originalGoal.currentAmount)) from this goal."
        }

        guard hasValidChange else {
            return "Make a change to save."
        }

        return nil
    }

    private static func amountText(_ amount: Double) -> String {
        String(format: "%.2f", max(amount, 0))
    }
}

enum SavingsGoalDetailsCardTrigger: String, Identifiable {
    case goalName
    case goalContext
    case options

    var id: Self { self }
}

struct SavingsGoalDetailsDraft: Equatable {

    var name: String
    var targetAmountText: String
    var saveByDate: Date?
    var isPinned: Bool

    init(input: EditSavingsGoalInput) {
        name = input.name
        targetAmountText = input.targetAmountText
        saveByDate = input.saveByDate
        isPinned = input.isPinned
    }

    var isValid: Bool {
        guard !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        let amount = MoneyAmountParser.parse(targetAmountText),
        amount.isFinite,
        amount > 0 else {
            return false
        }

        return true
    }
}

enum SavingsGoalDetailsDraftCoordinator {

    static func apply(
        draft: SavingsGoalDetailsDraft,
        to input: inout EditSavingsGoalInput
    ) -> Bool {
        guard draft.isValid else {
            return false
        }

        input.name = draft.name
        input.targetAmountText = draft.targetAmountText
        input.saveByDate = draft.saveByDate
        input.isPinned = draft.isPinned
        return true
    }
}

struct EditGoalView: View {

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

    @EnvironmentObject private var plaid: PlaidService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isNew: Bool
    private let onSaved: ((Bool) -> Void)?
    private let onDeleted: (() -> Void)?

    @State private var input: EditSavingsGoalInput
    @State private var detailsCardDraft: SavingsGoalDetailsDraft
    @State private var detailsCardTrigger: SavingsGoalDetailsCardTrigger?
    @State private var isShowingDeleteConfirmation = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var swipeProgress: CGFloat = 0
    @State private var circleCompletionProgress: CGFloat = 0
    @State private var foregroundOpacity: CGFloat = 1
    @State private var savePhase: SavePhase = .idle
    @State private var saveCompletionTask: Task<Void, Never>?
    @State private var deleteConfirmationTask: Task<Void, Never>?
    @FocusState private var focusedField: FocusedField?

    private let controlWidth: CGFloat = 320

    init(
        goal: SavingsGoal,
        isNew: Bool = false,
        onSaved: ((Bool) -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        self.isNew = isNew
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _input = State(
            initialValue: EditSavingsGoalInput(
                goal: goal
            )
        )
        _detailsCardDraft = State(
            initialValue: SavingsGoalDetailsDraft(
                input: EditSavingsGoalInput(goal: goal)
            )
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let circleLayout = EditSavingsGoalCircleLayout(
                    size: proxy.size,
                    projectedProgress: input.projectedProgress,
                    swipeProgress: swipeProgress,
                    completionProgress: circleCompletionProgress
                )

                ZStack {
                    CalderaModalBackground(
                        mood: .savingsGoal
                    )

                    EditSavingsGoalConcentricCircles(
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

                        editContent(
                            usesCompactSpacing: proxy.size.height < 740
                        )
                        .padding(
                            .top,
                            proxy.size.height < 740 ? 22 : 38
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
                            accessibilityLabel: "Save goal updates",
                            accessibilityHint: "Swipe up or activate to save these goal updates.",
                            swipeProgress: $swipeProgress,
                            onSaveTriggered: saveGoal
                        )
                        .opacity(foregroundOpacity)
                        .transition(.opacity)
                    }

                    if savePhase == .success {
                        PlanningCreationSuccessOverlay(
                            title: isNew
                                ? "Goal created"
                                : "Goal updated",
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
        .sheet(item: $detailsCardTrigger) { _ in
            goalDetailsCard
        }
        .confirmationDialog(
            "Delete goal?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Goal", role: .destructive) {
                deleteGoal()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the goal from your plan. Money set aside for it will no longer be kept out of Available to Spend.")
        }
        .alert(
            "Couldn't Save Goal",
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
                    ?? "Your goal updates weren't saved. Please try again."
            )
        }
        .onDisappear {
            saveCompletionTask?.cancel()
            deleteConfirmationTask?.cancel()
        }
    }

    private var topControls: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .editSavingsGoalPillControl(
                colorScheme: colorScheme
            )
            .accessibilityLabel("Cancel goal updates")

            Spacer()

            Button {
                presentGoalDetailsCard(from: .options)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(pillSurface)
                    .overlay {
                        Circle()
                            .stroke(
                                Color.white.opacity(
                                    colorScheme == .dark
                                        ? 0.20
                                        : 0.68
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
            .accessibilityLabel("Goal options")
            .accessibilityHint("Opens goal details")
        }
    }

    private func editContent(
        usesCompactSpacing: Bool
    ) -> some View {
        VStack(
            spacing: usesCompactSpacing
                ? AppSpacing.small
                : AppSpacing.regular
        ) {
            goalNamePill
            goalContextPill
            setAsideModePicker
            setAsideAmountHero

            Text(helperMessage)
                .font(.caption.weight(.medium))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )
                .multilineTextAlignment(.center)
                .frame(minHeight: 18)
                .accessibilityLabel(helperMessage)
        }
        .frame(maxWidth: .infinity)
    }

    private var goalNamePill: some View {
        Button {
            presentGoalDetailsCard(from: .goalName)
        } label: {
            ZStack {
                Text(input.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(
                        CalderaVisualStyle.primaryText(colorScheme)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 48)

                HStack {
                    Image(
                        systemName: CalderaCategoryStyle
                            .style(for: .savingsGoal)
                            .icon
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(goalAccentGradient)

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
                Capsule(style: .continuous)
                    .stroke(
                        Color.white.opacity(
                            colorScheme == .dark ? 0.20 : 0.72
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(Capsule(style: .continuous))
            .shadow(
                color: goalStyle.primary.opacity(
                    colorScheme == .dark ? 0.16 : 0.08
                ),
                radius: 14,
                y: 8
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Goal \(input.name)")
        .accessibilityHint("Opens goal details")
    }

    private var goalContextPill: some View {
        Button {
            presentGoalDetailsCard(from: .goalContext)
        } label: {
            VStack(spacing: AppSpacing.xxSmall) {
                HStack(spacing: AppSpacing.xSmall) {
                    Text("Target \(formattedCurrency(displayTargetAmount))")

                    contextDivider

                    Text("Set aside \(formattedCurrency(input.originalGoal.currentAmount))")

                    contextDivider

                    Text("Remaining \(formattedCurrency(displayRemainingAmount))")
                }

                if let saveByDate = input.saveByDate {
                    Label(
                        "By \(saveByDate.formatted(.dateTime.month(.abbreviated).day()))",
                        systemImage: "calendar"
                    )
                    .font(.caption2.weight(.semibold))
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(
                CalderaVisualStyle.secondaryText(colorScheme)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.66)
            .padding(.horizontal, AppSpacing.medium)
            .frame(
                maxWidth: controlWidth,
                minHeight: input.saveByDate == nil ? 38 : 52
            )
            .background(pillSurface.opacity(0.86))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
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
            "Goal target \(formattedCurrency(displayTargetAmount)), \(formattedCurrency(input.originalGoal.currentAmount)) set aside, \(formattedCurrency(displayRemainingAmount)) remaining"
        )
        .accessibilityHint("Opens goal details")
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
            ForEach(SavingsGoalSetAsideChangeMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
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
                            goalAccentGradient.opacity(
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
                                : AnyShapeStyle(goalAccentGradient)
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
                TextField(
                    "",
                    text: $input.setAsideAmountText
                )
                .keyboardType(.decimalPad)
                .focused(
                    $focusedField,
                    equals: .setAsideAmount
                )
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

    private var goalDetailsCard: some View {
        NavigationStack {
            ZStack {
                CalderaModalBackground(
                    mood: .savingsGoal
                )

                ScrollView {
                    VStack(spacing: AppSpacing.small) {
                        HStack(spacing: AppSpacing.small) {
                            Image(systemName: "text.cursor")
                                .foregroundStyle(goalAccentGradient)

                            TextField(
                                "Goal name",
                                text: $detailsCardDraft.name
                            )
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .name)
                            .onSubmit {
                                focusedField = .targetAmount
                            }
                            .accessibilityLabel("Goal name")
                        }
                        .goalDetailsFieldSurface(
                            colorScheme: colorScheme
                        )

                        HStack(spacing: AppSpacing.small) {
                            Image(systemName: "target")
                                .foregroundStyle(goalAccentGradient)

                            TextField(
                                "Target amount",
                                text: $detailsCardDraft.targetAmountText
                            )
                            .keyboardType(.decimalPad)
                            .focused(
                                $focusedField,
                                equals: .targetAmount
                            )
                            .accessibilityLabel("Target amount")

                            Text(
                                formattedDraftTargetAmount
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundColor(
                                CalderaVisualStyle.secondaryText(
                                    colorScheme
                                )
                            )
                            .lineLimit(1)
                        }
                        .goalDetailsFieldSurface(
                            colorScheme: colorScheme
                        )

                        targetDateDetailsField

                        HStack(spacing: AppSpacing.medium) {
                            IconBadge(
                                systemImage: "pin.fill",
                                color: goalStyle.primary,
                                size: 34,
                                iconSize: 14
                            )

                            VStack(
                                alignment: .leading,
                                spacing: AppSpacing.xxSmall
                            ) {
                                Text("Pin to Set Aside")
                                    .font(.subheadline.weight(.semibold))

                                Text("Pinned goals stay visible on the Set Aside screen.")
                                    .font(.caption)
                                    .foregroundColor(
                                        CalderaVisualStyle.secondaryText(colorScheme)
                                    )
                            }

                            Spacer()

                            Toggle(
                                "Pin to Set Aside",
                                isOn: $detailsCardDraft.isPinned
                            )
                            .labelsHidden()
                            .tint(goalStyle.primary)
                        }
                        .goalDetailsFieldSurface(
                            colorScheme: colorScheme
                        )

                        if !isNew {
                            Button(role: .destructive) {
                                focusedField = nil
                                prepareDeleteConfirmation()
                            } label: {
                                Label("Delete Goal", systemImage: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .accessibilityLabel("Delete goal")
                        }
                    }
                    .padding(AppSpacing.screen)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Goal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissGoalDetailsCard()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyGoalDetailsDraft()
                    }
                    .disabled(!detailsCardDraft.isValid)
                }
            }
            .keyboardDismissToolbar()
        }
        .calderaTransparentNavigationSurface()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var targetDateDetailsField: some View {
        HStack(spacing: AppSpacing.small) {
            Image(
                systemName: detailsCardDraft.saveByDate == nil
                    ? "calendar.badge.plus"
                    : "calendar"
            )
            .foregroundStyle(goalAccentGradient)

            if detailsCardDraft.saveByDate != nil {
                DatePicker(
                    "Target date",
                    selection: detailsTargetDateBinding,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(goalStyle.primary)
                .accessibilityLabel("Target date")

                Spacer(minLength: AppSpacing.xSmall)

                Button {
                    detailsCardDraft.saveByDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(
                            CalderaVisualStyle.secondaryText(colorScheme)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove target date")
            } else {
                Button("Add target date") {
                    detailsCardDraft.saveByDate = defaultTargetDate
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(
                    CalderaVisualStyle.primaryText(colorScheme)
                )

                Spacer()
            }
        }
        .goalDetailsFieldSurface(
            colorScheme: colorScheme
        )
    }

    private var goalStyle: CalderaCategoryStyle {
        CalderaCategoryStyle.style(for: .savingsGoal)
    }

    private var goalAccentGradient: LinearGradient {
        LinearGradient(
            colors: goalStyle.gradient,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var pillSurface: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.10))
            : AnyShapeStyle(Color.white.opacity(0.70))
    }

    private var displayTargetAmount: Double {
        input.targetAmount
            ?? input.originalGoal.targetAmount
    }

    private var displayRemainingAmount: Double {
        max(
            displayTargetAmount
                - input.originalGoal.currentAmount,
            0
        )
    }

    private var formattedDraftTargetAmount: String {
        guard let amount = MoneyAmountParser.parse(
            detailsCardDraft.targetAmountText
        ),
        amount.isFinite else {
            return "$0.00"
        }

        return formattedCurrency(
            max(amount, 0)
        )
    }

    private var defaultTargetDate: Date {
        Calendar.current.date(
            byAdding: .month,
            value: 1,
            to: Date()
        ) ?? Date()
    }

    private var detailsTargetDateBinding: Binding<Date> {
        Binding(
            get: {
                detailsCardDraft.saveByDate
                    ?? defaultTargetDate
            },
            set: { detailsCardDraft.saveByDate = $0 }
        )
    }

    private var heroAmountDisplayText: String {
        NewSavingsGoalAmountPresentation.displayText(
            for: input.setAsideAmountText
        )
    }

    private var heroAmountCharacterCount: Int {
        max(heroAmountDisplayText.count, 1)
    }

    private var heroAmountFontSize: CGFloat {
        switch heroAmountCharacterCount {
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

    private var heroCurrencyFontSize: CGFloat {
        max(heroAmountFontSize * 0.54, 28)
    }

    private var projectedTotalText: String {
        let amount = input.projectedSetAsideAmount
            ?? input.originalGoal.currentAmount

        return "New total: \(formattedCurrency(amount)) of \(formattedCurrency(displayTargetAmount))"
    }

    private var helperMessage: String {
        if let validationMessage = input.validationMessage {
            return validationMessage
        }

        if focusedField != nil {
            return "Hide the keyboard when you're ready to save."
        }

        return "Set Aside is virtual planning. No money moves."
    }

    private var isSwipeAffordanceVisible: Bool {
        input.hasValidChange
            && focusedField == nil
            && detailsCardTrigger == nil
            && !isShowingDeleteConfirmation
            && !isSaving
            && savePhase == .idle
    }

    private func swipeAffordanceCenterY(
        layout: EditSavingsGoalCircleLayout,
        size: CGSize
    ) -> CGFloat {
        let circleTop = layout.center.y
            - (layout.innerDiameter / 2)

        return min(
            max(
                circleTop + 154,
                size.height - 145
            ),
            size.height - 124
        )
    }

    private func presentGoalDetailsCard(
        from trigger: SavingsGoalDetailsCardTrigger
    ) {
        focusedField = nil
        detailsCardDraft = SavingsGoalDetailsDraft(
            input: input
        )
        detailsCardTrigger = trigger
    }

    private func dismissGoalDetailsCard() {
        focusedField = nil
        detailsCardTrigger = nil
    }

    private func applyGoalDetailsDraft() {
        guard SavingsGoalDetailsDraftCoordinator.apply(
            draft: detailsCardDraft,
            to: &input
        ) else {
            return
        }

        focusedField = nil
        detailsCardTrigger = nil
    }

    private func prepareDeleteConfirmation() {
        detailsCardTrigger = nil
        deleteConfirmationTask?.cancel()
        deleteConfirmationTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 180_000_000
            )
            guard !Task.isCancelled else { return }

            isShowingDeleteConfirmation = true
        }
    }

    private func saveGoal() {
        guard !isSaving,
              savePhase == .idle,
              input.hasValidChange,
              let goal = input.updatedGoal else {
            return
        }

        focusedField = nil
        isSaving = true

        let didPersist = isNew
            ? plaid.addGoal(goal)
            : plaid.updateGoal(goal)
        let persistenceResult = PlanningCreationPersistenceResult(
            didPersist: didPersist,
            failureMessage: "Your goal updates weren't saved. Please try again."
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

                UIAccessibility.post(
                    notification: .announcement,
                    argument: isNew
                        ? "Goal created"
                        : "Goal updated"
                )
            }

            try? await Task.sleep(
                nanoseconds: reduceMotion
                    ? 560_000_000
                    : 720_000_000
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                onSaved?(isNew)
                dismiss()
            }
        }
    }

    private func deleteGoal() {
        plaid.deleteGoal(input.originalGoal)
        onDeleted?()
        dismiss()
    }

    private func formattedCurrency(_ amount: Double) -> String {
        AppFormatters.currency(amount)
    }
}

private struct EditSavingsGoalCircleLayout {

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
        let middleProgressScale = 0.70
            + (0.30 * visualProgress)
        let innerProgressScale = 0.45
            + (0.55 * visualProgress)
        let mergedMiddleScale = middleProgressScale
            + ((1 - middleProgressScale) * completionProgress)
        let mergedInnerScale = innerProgressScale
            + ((1 - innerProgressScale) * completionProgress)
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
            * mergedMiddleScale
            * completionScale
            * dragScale
        innerDiameter = largestDiameter
            * mergedInnerScale
            * completionScale
            * dragScale
    }
}

private struct EditSavingsGoalConcentricCircles: View {

    @Environment(\.colorScheme) private var colorScheme

    let layout: EditSavingsGoalCircleLayout
    let swipeProgress: CGFloat
    let completionProgress: CGFloat

    private let style = CalderaCategoryStyle.style(
        for: .savingsGoal
    )

    var body: some View {
        ZStack {
            circle(
                colors: [
                    style.gradient[2].opacity(
                        colorScheme == .dark
                            ? 0.22
                                + (0.08 * swipeProgress)
                                + (0.16 * completionProgress)
                            : 0.17
                                + (0.07 * swipeProgress)
                                + (0.14 * completionProgress)
                    ),
                    style.gradient[1].opacity(
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
                    style.gradient[1].opacity(
                        colorScheme == .dark
                            ? 0.27
                                + (0.08 * swipeProgress)
                                + (0.16 * completionProgress)
                            : 0.22
                                + (0.07 * swipeProgress)
                                + (0.14 * completionProgress)
                    ),
                    style.gradient[0].opacity(
                        colorScheme == .dark
                            ? 0.20
                                + (0.06 * swipeProgress)
                                + (0.14 * completionProgress)
                            : 0.16
                                + (0.05 * swipeProgress)
                                + (0.12 * completionProgress)
                    )
                ],
                diameter: layout.middleDiameter,
                center: layout.center
            )

            circle(
                colors: [
                    style.gradient[0].opacity(
                        colorScheme == .dark
                            ? 0.30
                                + (0.08 * swipeProgress)
                                + (0.18 * completionProgress)
                            : 0.24
                                + (0.07 * swipeProgress)
                                + (0.16 * completionProgress)
                    ),
                    style.gradient[2].opacity(
                        colorScheme == .dark
                            ? 0.23
                                + (0.07 * swipeProgress)
                                + (0.16 * completionProgress)
                            : 0.18
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

    func goalDetailsFieldSurface(
        colorScheme: ColorScheme
    ) -> some View {
        padding(AppSpacing.regular)
            .frame(minHeight: 52)
            .calderaGlassCard(
                cornerRadius: AppRadii.card,
                fillOpacity: colorScheme == .dark
                    ? 0.58
                    : 0.80,
                strokeOpacity: colorScheme == .dark
                    ? 0.36
                    : 0.52,
                shadowOpacity: 0.04,
                shadowRadius: 12,
                shadowY: 6,
                darkGlowColor: CalderaCategoryStyle
                    .style(for: .savingsGoal)
                    .primary
            )
    }

    func editSavingsGoalPillControl(
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
