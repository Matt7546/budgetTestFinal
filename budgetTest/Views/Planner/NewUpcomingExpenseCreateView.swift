import SwiftData
import SwiftUI
import UIKit

struct NewUpcomingExpenseCreationInput: Equatable {

    let id: UUID
    var name: String
    var amountText: String
    var dueDate: Date
    var frequency: PlannerFrequency
    var accentColorID: String?

    init(
        id: UUID = UUID(),
        name: String = "",
        amountText: String = "",
        dueDate: Date = Date(),
        frequency: PlannerFrequency = .once,
        accentColorID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.amountText = amountText
        self.dueDate = dueDate
        self.frequency = frequency
        self.accentColorID = accentColorID
    }

    var event: PlannerEvent? {
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedName.isEmpty,
              let amount = MoneyAmountParser.parse(
                amountText
              ),
              amount.isFinite,
              amount > 0 else {
            return nil
        }

        return PlannerEvent(
            id: id,
            name: trimmedName,
            amount: amount,
            date: dueDate,
            frequency: frequency,
            type: .expense,
            accentColorID: accentColorID
        )
    }

    var validationMessage: String? {
        let hasName = !name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        let parsedAmount = MoneyAmountParser.parse(
            amountText
        )
        let hasAmount = parsedAmount?.isFinite == true
            && (parsedAmount ?? 0) > 0

        switch (hasName, hasAmount) {
        case (false, false):
            return "Add an expense name and amount to save."
        case (false, true):
            return "Add an expense name to save."
        case (true, false):
            return "Enter an amount greater than $0."
        case (true, true):
            return nil
        }
    }
}

enum NewUpcomingExpenseAmountInput {

    static func acceptedText(
        proposed: String,
        current: String
    ) -> String {
        let sanitized = MoneyAmountParser.sanitizedText(proposed)
        let decimalSeparatorCount = sanitized.reduce(into: 0) {
            count,
            character in
            if character == "." {
                count += 1
            }
        }
        let containsOnlyNumericCharacters = sanitized.allSatisfy {
            $0.isNumber || $0 == "."
        }

        guard containsOnlyNumericCharacters,
              decimalSeparatorCount <= 1 else {
            return current
        }

        return sanitized
    }
}

enum NewUpcomingExpenseAmountPresentation {

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

struct NewUpcomingExpenseCreateView: View {

    private enum SavePhase {
        case idle
        case completing
        case success
    }

    private enum FocusedField: Hashable {
        case name
        case amount
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onSaved: (() -> Void)?

    @State private var input: NewUpcomingExpenseCreationInput
    @State private var dateSelection: Date
    @State private var isShowingDatePicker = false
    @State private var isShowingFrequencyPicker = false
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
        input: NewUpcomingExpenseCreationInput = .init(),
        onSaved: (() -> Void)? = nil
    ) {
        self.onSaved = onSaved
        _input = State(initialValue: input)
        _dateSelection = State(initialValue: input.dueDate)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let circleLayout = NewUpcomingExpenseCircleLayout(
                    size: proxy.size,
                    swipeProgress: swipeProgress,
                    completionProgress: circleCompletionProgress
                )

                ZStack {
                    CalderaModalBackground(
                        mood: .upcomingExpense
                    )

                    NewUpcomingExpenseConcentricCircles(
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
                            accessibilityLabel: "Save upcoming expense",
                            accessibilityHint:
                                "Swipe up or activate to create this expense.",
                            swipeProgress: $swipeProgress,
                            onSaveTriggered: saveExpense
                        )
                        .opacity(foregroundOpacity)
                        .transition(.opacity)
                    }

                    if savePhase == .success {
                        PlanningCreationSuccessOverlay(
                            title: "Expense created",
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
        .confirmationDialog(
            "Repeat",
            isPresented: $isShowingFrequencyPicker,
            titleVisibility: .visible
        ) {
            ForEach(PlannerFrequency.allCases) { option in
                Button {
                    input.frequency = option
                } label: {
                    if option == input.frequency {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
                .accessibilityAddTraits(
                    option == input.frequency ? .isSelected : []
                )
            }

            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Couldn't Save Expense",
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
                    ?? "Your expense wasn't saved. Please try again."
            )
        }
        .onDisappear {
            saveCompletionTask?.cancel()
        }
        .accessibilityAddTraits(.isModal)
    }

    private var topControls: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .newUpcomingExpensePillControl(
                colorScheme: colorScheme
            )
            .accessibilityLabel("Cancel new upcoming expense")

            Spacer()
        }
    }

    private var creationContent: some View {
        VStack(spacing: AppSpacing.regular) {
            expenseNamePill

            amountHero

            HStack(spacing: AppSpacing.small) {
                dueDateControl
                repeatControl
            }
            .padding(.top, AppSpacing.xSmall)
            .frame(maxWidth: .infinity)

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

    private var expenseNamePill: some View {
        ZStack {
            TextField(
                "Expense name",
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
                focusedField = .amount
            }
            .padding(.horizontal, 48)
            .accessibilityLabel("Expense name")

            HStack {
                Image(systemName: expenseStyle.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(expenseAccentGradient)

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
            color: expenseStyle.primary.opacity(
                colorScheme == .dark ? 0.16 : 0.08
            ),
            radius: 14,
            y: 8
        )
    }

    private var amountHero: some View {
        VStack(spacing: AppSpacing.xSmall) {
            Text("Amount needed")
                .font(.caption.weight(.semibold))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(
                        colorScheme
                    )
                )
                .textCase(.uppercase)

            ZStack {
                TextField(
                    "Amount needed",
                    text: amountTextBinding
                )
                .keyboardType(.decimalPad)
                .focused(
                    $focusedField,
                    equals: .amount
                )
                .font(
                    .system(
                        size: heroAmountFontSize,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundColor(.clear)
                .multilineTextAlignment(.center)
                .frame(
                    maxWidth: .infinity,
                    minHeight: heroAmountFontSize + AppSpacing.regular
                )
                .contentShape(Rectangle())
                .accessibilityLabel("Amount needed")
                .accessibilityValue("$\(heroAmountDisplayText)")
                .accessibilityHint(
                    "Enter dollars and cents, like 500.25."
                )

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
                            expenseAccentGradient.opacity(
                                input.amountText.isEmpty
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
                            input.amountText.isEmpty
                                ? AnyShapeStyle(
                                    CalderaVisualStyle.secondaryText(
                                        colorScheme
                                    ).opacity(0.42)
                                )
                                : AnyShapeStyle(expenseAccentGradient)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppSpacing.small)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var dueDateControl: some View {
        Button {
            focusedField = nil
            dateSelection = input.dueDate
            isShowingDatePicker = true
        } label: {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.bold))

                Text(
                    input.dueDate.formatted(
                        .dateTime
                            .month(.abbreviated)
                            .day()
                    )
                )
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
        .accessibilityLabel(
            "Due date \(input.dueDate.formatted(.dateTime.month(.wide).day().year()))"
        )
        .accessibilityHint("Double tap to choose a due date")
    }

    private var repeatControl: some View {
        Button {
            focusedField = nil
            isShowingFrequencyPicker = true
        } label: {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: "repeat")
                    .font(.caption.weight(.bold))

                Text(input.frequency.rawValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(expenseAccentGradient)
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
        .accessibilityLabel("Repeat")
        .accessibilityValue(input.frequency.rawValue)
        .accessibilityHint("Double tap to choose a repeat period")
    }

    private var dueDatePicker: some View {
        NavigationStack {
            ZStack {
                CalderaModalBackground(
                    mood: .upcomingExpense
                )

                DatePicker(
                    "Due date",
                    selection: $dateSelection,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(expenseStyle.primary)
                .padding(AppSpacing.screen)
            }
            .navigationTitle("Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingDatePicker = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        input.dueDate = dateSelection
                        isShowingDatePicker = false
                    }
                }
            }
        }
        .calderaTransparentNavigationSurface()
        .presentationDetents([.medium, .large])
        .accessibilityAddTraits(.isModal)
    }

    private var expenseStyle: CalderaCategoryStyle {
        CalderaCategoryStyle.style(
            for: .upcomingExpense
        )
    }

    private var expenseAccentGradient: LinearGradient {
        LinearGradient(
            colors: expenseStyle.gradient,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var pillSurface: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.10))
            : AnyShapeStyle(Color.white.opacity(0.70))
    }

    private var heroAmountDisplayText: String {
        NewUpcomingExpenseAmountPresentation.displayText(
            for: input.amountText
        )
    }

    private var amountTextBinding: Binding<String> {
        Binding(
            get: { input.amountText },
            set: { proposedText in
                input.amountText = NewUpcomingExpenseAmountInput.acceptedText(
                    proposed: proposedText,
                    current: input.amountText
                )
            }
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
        input.event != nil
            && focusedField == nil
            && !isSaving
            && savePhase == .idle
    }

    private func swipeAffordanceCenterY(
        layout: NewUpcomingExpenseCircleLayout,
        size: CGSize
    ) -> CGFloat {
        let circleTop = layout.center.y
            - (layout.innerDiameter / 2)

        return min(
            circleTop + 154,
            size.height - 124
        )
    }

    private func saveExpense() {
        guard !isSaving,
              savePhase == .idle,
              let event = input.event else {
            return
        }

        focusedField = nil
        saveErrorMessage = nil
        isSaving = true
        modelContext.insert(event)

        let persistenceResult: PlanningCreationPersistenceResult
        do {
            try modelContext.save()
            persistenceResult = .saved
        } catch {
            modelContext.rollback()
            persistenceResult = .failed(
                message: "Your expense wasn't saved. Please try again."
            )
        }

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
                    argument: "Expense created"
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

struct NewUpcomingExpenseCircleLayout {

    let center: CGPoint
    let outerDiameter: CGFloat
    let middleDiameter: CGFloat
    let innerDiameter: CGFloat

    init(
        size: CGSize,
        projectedProgress: Double? = nil,
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
        let middleBaseScale: CGFloat
        let innerBaseScale: CGFloat

        if let projectedProgress {
            let safeProgress = min(
                max(CGFloat(projectedProgress), 0),
                1
            )
            let visualProgress = safeProgress.squareRoot()
            middleBaseScale = 0.70 + (0.30 * visualProgress)
            innerBaseScale = 0.45 + (0.55 * visualProgress)
        } else {
            middleBaseScale = 0.82
            innerBaseScale = 0.64
        }

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
            * (
                middleBaseScale
                    + ((1 - middleBaseScale) * completionProgress)
            )
            * completionScale
            * dragScale
        innerDiameter = largestDiameter
            * (
                innerBaseScale
                    + ((1 - innerBaseScale) * completionProgress)
            )
            * completionScale
            * dragScale
    }
}

struct NewUpcomingExpenseConcentricCircles: View {

    @Environment(\.colorScheme) private var colorScheme

    let layout: NewUpcomingExpenseCircleLayout
    let swipeProgress: CGFloat
    let completionProgress: CGFloat

    private let style = CalderaCategoryStyle.style(
        for: .upcomingExpense
    )

    var body: some View {
        ZStack {
            circle(
                colors: [
                    style.gradient[0].opacity(
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
                    style.gradient[2].opacity(
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
                    style.gradient[2].opacity(
                        colorScheme == .dark
                            ? 0.30
                                + (0.08 * swipeProgress)
                                + (0.18 * completionProgress)
                            : 0.24
                                + (0.07 * swipeProgress)
                                + (0.16 * completionProgress)
                    ),
                    style.gradient[1].opacity(
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

    func newUpcomingExpensePillControl(
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
