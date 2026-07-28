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
    @State private var errorAlertTitle = "Couldn't Save Goal"
    @State private var saveErrorMessage: String?
    @State private var swipeProgress: CGFloat = 0
    @State private var circleCompletionProgress: CGFloat = 0
    @State private var foregroundOpacity: CGFloat = 1
    @State private var savePhase: SavePhase = .idle
    @State private var saveCompletionTask: Task<Void, Never>?
    @State private var deleteConfirmationTask: Task<Void, Never>?
    @FocusState private var focusedField: SavingsGoalUpdateFocusedField?

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
                        SavingsGoalUpdateTopControls(
                            colorScheme: colorScheme,
                            onCancel: { dismiss() },
                            onOptions: {
                                presentGoalDetailsCard(from: .options)
                            }
                        )

                        SavingsGoalContributionContent(
                            input: $input,
                            focusedField: $focusedField,
                            usesCompactSpacing: proxy.size.height < 740,
                            colorScheme: colorScheme,
                            onOpenDetails: presentGoalDetailsCard
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
            SavingsGoalDetailsCard(
                draft: $detailsCardDraft,
                focusedField: $focusedField,
                isNew: isNew,
                colorScheme: colorScheme,
                onCancel: dismissGoalDetailsCard,
                onDone: applyGoalDetailsDraft,
                onDelete: prepareDeleteConfirmation
            )
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
            errorAlertTitle,
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
        errorAlertTitle = "Couldn't Save Goal"
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
        guard !isSaving else { return }

        isSaving = true
        let didPersist = plaid.deleteGoal(input.originalGoal)
        isSaving = false

        guard didPersist else {
            errorAlertTitle = "Couldn't Delete Goal"
            saveErrorMessage =
                "This goal wasn't deleted. Please try again."
            return
        }

        onDeleted?()
        dismiss()
    }

}
