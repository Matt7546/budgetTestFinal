import SwiftUI

struct NewSavingsGoalCreationInput: Equatable {

    let id: UUID
    var name: String
    var targetAmountText: String
    var saveByDate: Date?

    init(goal: SavingsGoal) {
        id = goal.id
        name = goal.name
        targetAmountText = goal.targetAmount > 0
            ? String(format: "%.2f", goal.targetAmount)
            : ""
        saveByDate = goal.saveByDate
    }

    var goal: SavingsGoal? {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedName.isEmpty,
              let targetAmount = MoneyAmountParser.parse(
                targetAmountText
              ),
              targetAmount.isFinite,
              targetAmount > 0 else {
            return nil
        }

        return SavingsGoal(
            id: id,
            name: trimmedName,
            targetAmount: targetAmount,
            currentAmount: 0,
            isPinned: false,
            saveByDate: saveByDate
        )
    }

    var validationMessage: String? {
        let hasName = !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        let parsedTarget = MoneyAmountParser.parse(
            targetAmountText
        )
        let hasTarget = parsedTarget?.isFinite == true
            && (parsedTarget ?? 0) > 0

        switch (hasName, hasTarget) {
        case (false, false):
            return "Add a goal name and target amount to save."
        case (false, true):
            return "Add a goal name to save."
        case (true, false):
            return "Enter a target amount greater than $0."
        case (true, true):
            return nil
        }
    }
}

enum NewSavingsGoalAmountPresentation {

    static func displayText(for amountText: String) -> String {
        let sanitizedText = MoneyAmountParser.sanitizedText(
            amountText
        )

        guard !sanitizedText.isEmpty else {
            return "0"
        }

        let components = sanitizedText.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let wholeNumberText = String(
            components.first ?? ""
        )
        let wholeNumberDigits = wholeNumberText.filter(
            \.isNumber
        )
        let normalizedWholeNumber = String(
            wholeNumberDigits.drop(
                while: { $0 == "0" }
            )
        )
        let groupedWholeNumber = groupedDigits(
            normalizedWholeNumber.isEmpty
                ? "0"
                : normalizedWholeNumber
        )

        guard sanitizedText.contains(".") else {
            return groupedWholeNumber
        }

        let fractionalText = components.count > 1
            ? String(components[1].filter(\.isNumber))
            : ""

        return "\(groupedWholeNumber).\(fractionalText)"
    }

    private static func groupedDigits(
        _ digits: String
    ) -> String {
        let reversedDigits = Array(digits.reversed())
        var groupedCharacters: [Character] = []

        for (index, digit) in reversedDigits.enumerated() {
            if index > 0,
               index.isMultiple(of: 3) {
                groupedCharacters.append(",")
            }

            groupedCharacters.append(digit)
        }

        return String(groupedCharacters.reversed())
    }
}

struct NewSavingsGoalCreateView: View {

    private enum SavePhase {
        case idle
        case completing
        case success
    }

    private enum FocusedField: Hashable {
        case name
        case targetAmount
    }

    @EnvironmentObject private var plaid: PlaidService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onSaved: (() -> Void)?

    @State private var input: NewSavingsGoalCreationInput
    @State private var dateSelection: Date
    @State private var isShowingDatePicker = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var swipeProgress: CGFloat = 0
    @State private var circleCompletionProgress: CGFloat = 0
    @State private var foregroundOpacity: CGFloat = 1
    @State private var savePhase: SavePhase = .idle
    @State private var saveCompletionTask: Task<Void, Never>?
    @FocusState private var focusedField: FocusedField?

    private let controlWidth: CGFloat = 320

    init(
        goal: SavingsGoal,
        onSaved: (() -> Void)? = nil
    ) {
        self.onSaved = onSaved
        _input = State(
            initialValue: NewSavingsGoalCreationInput(
                goal: goal
            )
        )
        _dateSelection = State(
            initialValue: goal.saveByDate
                ?? Calendar.current.date(
                    byAdding: .month,
                    value: 1,
                    to: Date()
                )
                ?? Date()
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let circleLayout = NewSavingsGoalCircleLayout(
                    size: proxy.size,
                    swipeProgress: swipeProgress,
                    completionProgress: circleCompletionProgress
                )

                ZStack {
                    CalderaModalBackground(
                        mood: .savingsGoal
                    )

                    NewSavingsGoalConcentricCircles(
                        layout: circleLayout,
                        swipeProgress: swipeProgress,
                        completionProgress: circleCompletionProgress
                    )

                    VStack(spacing: 0) {
                        topControls

                        creationContent
                            .padding(.top, 44)

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
                            swipeProgress: $swipeProgress,
                            onSaveTriggered: saveGoal
                        )
                        .opacity(foregroundOpacity)
                        .transition(.opacity)
                    }

                    if savePhase == .success {
                        PlanningCreationSuccessOverlay(
                            title: "Goal created",
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
            targetDatePicker
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
                    ?? "Your goal wasn't saved. Please try again."
            )
        }
        .onDisappear {
            saveCompletionTask?.cancel()
        }
    }

    private var topControls: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .newSavingsGoalPillControl(
                colorScheme: colorScheme
            )
            .accessibilityLabel("Cancel new savings goal")

            Spacer()
        }
    }

    private var creationContent: some View {
        VStack(spacing: AppSpacing.regular) {
            goalNamePill

            targetAmountHero

            optionalDateControl
            .padding(.top, AppSpacing.xSmall)

            Text(input.validationMessage ?? " ")
                .font(.caption.weight(.medium))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(
                        colorScheme
                    )
                )
                .multilineTextAlignment(.center)
                .frame(minHeight: 18)
                .accessibilityHidden(
                    input.validationMessage == nil
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var goalNamePill: some View {
        ZStack {
            TextField(
                "Goal name",
                text: $input.name
            )
            .font(.subheadline.weight(.semibold))
            .foregroundColor(
                CalderaVisualStyle.primaryText(
                    colorScheme
                )
            )
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.82)
            .textInputAutocapitalization(.words)
            .submitLabel(.next)
            .focused(
                $focusedField,
                equals: .name
            )
            .onSubmit {
                focusedField = .targetAmount
            }
            .padding(.horizontal, 48)
            .accessibilityLabel("Goal name")

            HStack {
                Image(
                    systemName: CalderaCategoryStyle
                        .style(for: .savingsGoal)
                        .icon
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(goalAccentGradient)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.regular)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

    private var targetAmountHero: some View {
        VStack(spacing: AppSpacing.xSmall) {
            Text("Target amount")
                .font(.caption.weight(.semibold))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(
                        colorScheme
                    )
                )
                .textCase(.uppercase)

            Button {
                focusedField = .targetAmount
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
                                input.targetAmountText.isEmpty
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
                            input.targetAmountText.isEmpty
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
            .accessibilityLabel("Target amount")
            .accessibilityValue("$\(heroAmountDisplayText)")
            .accessibilityHint(
                "Double tap to enter dollars and cents, like 500.25."
            )
            .background {
                TextField(
                    "",
                    text: $input.targetAmountText
                )
                .keyboardType(.decimalPad)
                .focused(
                    $focusedField,
                    equals: .targetAmount
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var optionalDateControl: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Button {
                focusedField = nil
                dateSelection = input.saveByDate
                    ?? dateSelection
                isShowingDatePicker = true
            } label: {
                HStack(spacing: AppSpacing.small) {
                    Image(
                        systemName: input.saveByDate == nil
                            ? "calendar.badge.plus"
                            : "calendar"
                    )

                    Text(dateControlTitle)
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(
                    CalderaVisualStyle.primaryText(
                        colorScheme
                    )
                )
                .padding(.horizontal, AppSpacing.medium)
                .frame(height: 42)
                .background(pillSurface)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            Color.white.opacity(
                                colorScheme == .dark ? 0.18 : 0.66
                            ),
                            lineWidth: 1
                        )
                }
                .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dateAccessibilityLabel)
            .accessibilityHint("Double tap to choose an optional target date")

            if input.saveByDate != nil {
                Button {
                    input.saveByDate = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(
                            CalderaVisualStyle.secondaryText(
                                colorScheme
                            )
                        )
                        .frame(width: 42, height: 42)
                        .background(pillSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove target date")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var targetDatePicker: some View {
        NavigationStack {
            ZStack {
                CalderaModalBackground(
                    mood: .savingsGoal
                )

                DatePicker(
                    "Target date",
                    selection: $dateSelection,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(goalStyle.primary)
                .padding(AppSpacing.screen)
            }
            .navigationTitle("Target Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingDatePicker = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        input.saveByDate = dateSelection
                        isShowingDatePicker = false
                    }
                }
            }
        }
        .calderaTransparentNavigationSurface()
        .presentationDetents([.medium, .large])
    }

    private var goalStyle: CalderaCategoryStyle {
        CalderaCategoryStyle.style(
            for: .savingsGoal
        )
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

    private var dateControlTitle: String {
        guard let date = input.saveByDate else {
            return "Add target date"
        }

        return date.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
        )
    }

    private var dateAccessibilityLabel: String {
        guard let date = input.saveByDate else {
            return "Add optional target date"
        }

        return "Target date \(date.formatted(.dateTime.month(.wide).day().year()))"
    }

    private var heroAmountDisplayText: String {
        NewSavingsGoalAmountPresentation.displayText(
            for: input.targetAmountText
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

    private var isSwipeAffordanceVisible: Bool {
        input.goal != nil
            && focusedField == nil
            && !isSaving
            && savePhase == .idle
    }

    private func swipeAffordanceCenterY(
        layout: NewSavingsGoalCircleLayout,
        size: CGSize
    ) -> CGFloat {
        let circleTop = layout.center.y
            - (layout.innerDiameter / 2)

        return min(
            circleTop + 154,
            size.height - 124
        )
    }

    private func saveGoal() {
        guard !isSaving,
              savePhase == .idle,
              let goal = input.goal else {
            return
        }

        focusedField = nil
        isSaving = true

        guard plaid.addGoal(goal) else {
            isSaving = false
            saveErrorMessage = "Your goal wasn't saved. Please try again."

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

        isSaving = false
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
                    argument: "Goal created"
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

private struct NewSavingsGoalCircleLayout {

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

private struct NewSavingsGoalConcentricCircles: View {

    @Environment(\.colorScheme) private var colorScheme

    let layout: NewSavingsGoalCircleLayout
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
            .frame(
                width: diameter,
                height: diameter
            )
            .position(center)
    }
}

private extension View {

    func newSavingsGoalPillControl(
        colorScheme: ColorScheme
    ) -> some View {
        font(.subheadline.weight(.bold))
            .foregroundColor(
                CalderaVisualStyle.primaryText(
                    colorScheme
                )
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
