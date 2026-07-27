#if DEBUG

import SwiftUI

struct LabGoalCreationSwipeSavePrototypeView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var goalName = "Vacation"
    @State private var amountDigits = ""
    @State private var targetDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 14)
    ) ?? Date()
    @State private var isShowingDatePicker = false
    @State private var swipeProgress: CGFloat = 0
    @State private var isSaved = false
    @State private var circleCompletionProgress: CGFloat = 0
    @State private var foregroundOpacity: CGFloat = 1
    @State private var isShowingSuccess = false
    @State private var saveCompletionTask: Task<Void, Never>?
    @FocusState private var isAmountInputFocused: Bool

    private let maxCircleDragOffset: CGFloat = 120

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                prototypeBackground
                goalMoodShape(in: proxy.size)

                ZStack {
                    topControls
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, AppSpacing.screen)
                        .padding(.top, AppSpacing.medium)

                    goalHero
                        .offset(y: -4 * swipeProgress)
                        .shadow(
                            color: LabGoalSwipeSavePalette.accent.opacity(0.18 * swipeProgress),
                            radius: 18 * swipeProgress,
                            y: 8 * swipeProgress
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, AppSpacing.screen)
                        .padding(.top, heroTopInset)
                }
                .opacity(foregroundOpacity)
                .allowsHitTesting(!isSaved)

                if !isAmountInputFocused && !isSaved {
                    LabSwipeToSaveInteraction(
                        circleCenter: smallestCircleCenter(in: proxy.size),
                        circleDiameter: smallestCircleDiameter(in: proxy.size),
                        affordanceCenter: CGPoint(
                            x: proxy.size.width / 2,
                            y: swipeAffordanceCenterY(in: proxy.size)
                        ),
                        promptText: "Swipe up to save",
                        isEnabled: !isAmountInputFocused && !isSaved,
                        swipeProgress: $swipeProgress,
                        affordanceStyle: AnyShapeStyle(Color.white),
                        onSaveTriggered: savePrototypeGoal
                    )
                        .opacity(foregroundOpacity)
                        .transition(.opacity)
                }

                if isShowingSuccess {
                    LabSwipeSaveSuccessOverlay(
                        successText: "Goal created",
                        isPresented: isShowingSuccess
                    )
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button {
                    isAmountInputFocused = false
                } label: {
                    Label("Done", systemImage: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide numeric keyboard")
            }
        }
        .sheet(isPresented: $isShowingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Target date",
                    selection: $targetDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(AppSpacing.screen)
                .navigationTitle("Target Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isShowingDatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onChange(of: amountDigits) { _, newValue in
            let digitsOnly = newValue.filter(\.isNumber)
            let normalizedDigits = digitsOnly.drop(while: { $0 == "0" })

            if amountDigits != normalizedDigits {
                amountDigits = String(normalizedDigits)
            }
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
            .accessibilityLabel("Close Goal Creation Swipe Save Prototype")
            .swipeSavePillControl(style: .secondary, colorScheme: colorScheme)

            Spacer()
        }
    }

    private var goalHero: some View {
        VStack(spacing: AppSpacing.regular) {
            goalNamePill

            VStack(spacing: AppSpacing.small) {
                targetAmountHero
                datePill
            }
        }
        .padding(.top, 68)
    }

    private var goalNamePill: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Image(systemName: "target")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(goalAccentGradient)

            TextField("Goal name", text: $goalName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .frame(maxWidth: 156)
                .accessibilityLabel("Goal name")
        }
        .padding(.horizontal, AppSpacing.regular)
        .padding(.vertical, AppSpacing.small)
        .background(pillSurface)
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.72), lineWidth: 1)
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(
            color: LabGoalSwipeSavePalette.accent.opacity(colorScheme == .dark ? 0.16 : 0.08),
            radius: 14,
            x: 0,
            y: 8
        )
        .frame(maxWidth: .infinity)
    }

    private var targetAmountHero: some View {
        VStack(spacing: AppSpacing.xSmall) {
            Text("Target amount")
                .font(.caption.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .textCase(.uppercase)

            Button {
                isAmountInputFocused = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$")
                        .font(.system(size: heroCurrencyFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(goalAccentGradient.opacity(amountDigits.isEmpty ? 0.46 : 0.74))

                    Text(formattedHeroAmount)
                        .font(.system(size: heroAmountFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            amountDigits.isEmpty
                                ? AnyShapeStyle(CalderaVisualStyle.secondaryText(colorScheme).opacity(0.42))
                                : AnyShapeStyle(goalAccentGradient)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .padding(.horizontal, AppSpacing.small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Target amount")
            .accessibilityValue("\(formattedHeroAmount) dollars")
            .accessibilityHint("Double tap to enter a whole-dollar amount")
            .background {
                TextField("", text: $amountDigits)
                    .keyboardType(.numberPad)
                    .focused($isAmountInputFocused)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var datePill: some View {
        Button {
            isShowingDatePicker = true
        } label: {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.bold))

                Text(targetDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.small)
            .background(pillSurface)
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.66), lineWidth: 1)
            }
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Target date \(targetDate.formatted(.dateTime.month(.wide).day()))")
        .accessibilityHint("Double tap to choose a target date")
    }

    private func swipeAffordanceCenterY(in size: CGSize) -> CGFloat {
        let circleTop = smallestCircleCenter(in: size).y - (smallestCircleDiameter(in: size) / 2)
        return min(circleTop + 154, size.height - 166)
    }

    private var heroTopInset: CGFloat {
        44
    }

    private func savePrototypeGoal() {
        guard !isSaved else { return }

        isAmountInputFocused = false

        withAnimation(.easeOut(duration: 0.24)) {
            swipeProgress = 1
            isSaved = true
            foregroundOpacity = 0
        }

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        saveCompletionTask?.cancel()
        saveCompletionTask = Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.78)) {
                    circleCompletionProgress = 1
                }
            }

            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.26)) {
                    isShowingSuccess = true
                }

                #if os(iOS)
                UIAccessibility.post(notification: .announcement, argument: "Goal created")
                #endif
            }

            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                dismiss()
            }
        }
    }

    private var prototypeBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.07, green: 0.05, blue: 0.14),
                    Color(red: 0.15, green: 0.08, blue: 0.25),
                    Color(red: 0.10, green: 0.12, blue: 0.25)
                ]
                : [
                    Color(red: 0.95, green: 0.91, blue: 1.00),
                    Color(red: 0.95, green: 0.91, blue: 0.99),
                    Color(red: 0.88, green: 0.94, blue: 1.00)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func goalMoodShape(in size: CGSize) -> some View {
        let center = smallestCircleCenter(in: size)
        let largestDiameter = max(size.height * 1.22, 820)
        let completionScale = 1 + (0.42 * circleCompletionProgress)
        let dragScale = 1 + (0.08 * swipeProgress)

        return ZStack {
            concentricCircle(
                colors: [
                    Color(red: 0.70, green: 0.52, blue: 1.00).opacity(0.23 + (0.06 * swipeProgress) + (0.12 * circleCompletionProgress)),
                    Color(red: 0.95, green: 0.62, blue: 0.88).opacity(0.20 + (0.05 * swipeProgress) + (0.10 * circleCompletionProgress))
                ],
                diameter: largestDiameter * completionScale * dragScale,
                center: center
            )

            concentricCircle(
                colors: [
                    Color(red: 0.94, green: 0.48, blue: 0.80).opacity(0.28 + (0.06 * swipeProgress) + (0.12 * circleCompletionProgress)),
                    Color(red: 0.71, green: 0.40, blue: 0.98).opacity(0.24 + (0.05 * swipeProgress) + (0.10 * circleCompletionProgress))
                ],
                diameter: largestDiameter * (0.82 + (0.18 * circleCompletionProgress)) * completionScale * dragScale,
                center: center
            )

            concentricCircle(
                colors: [
                    Color(red: 0.80, green: 0.28, blue: 0.86).opacity(0.30 + (0.07 * swipeProgress) + (0.13 * circleCompletionProgress)),
                    Color(red: 0.59, green: 0.36, blue: 0.96).opacity(0.26 + (0.06 * swipeProgress) + (0.12 * circleCompletionProgress))
                ],
                diameter: largestDiameter * (0.64 + (0.36 * circleCompletionProgress)) * completionScale * dragScale,
                center: center
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func smallestCircleCenter(in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2,
            y: size.height + 36
                - (maxCircleDragOffset * swipeProgress)
                - (size.height * 0.12 * circleCompletionProgress)
        )
    }

    private func smallestCircleDiameter(in size: CGSize) -> CGFloat {
        let largestDiameter = max(size.height * 1.22, 820)
        let completionScale = 1 + (0.42 * circleCompletionProgress)
        return largestDiameter
            * (0.64 + (0.36 * circleCompletionProgress))
            * completionScale
            * (1 + (0.045 * swipeProgress))
    }

    private func concentricCircle(
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

    private var heroAmountDigitCount: Int {
        max(amountDigits.count, 1)
    }

    private var formattedHeroAmount: String {
        guard !amountDigits.isEmpty else { return "0" }

        var formatted = ""
        for (index, digit) in amountDigits.reversed().enumerated() {
            if index > 0 && index.isMultiple(of: 3) {
                formatted.insert(",", at: formatted.startIndex)
            }
            formatted.insert(digit, at: formatted.startIndex)
        }
        return formatted
    }

    private var heroAmountFontSize: CGFloat {
        switch heroAmountDigitCount {
        case ...3: 88
        case 4...5: 78
        case 6...7: 66
        case 8...9: 56
        default: 48
        }
    }

    private var heroCurrencyFontSize: CGFloat {
        max(heroAmountFontSize * 0.54, 30)
    }

    private var pillSurface: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.10))
            : AnyShapeStyle(Color.white.opacity(0.66))
    }

    private var goalAccentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.53, green: 0.22, blue: 0.96),
                Color(red: 0.94, green: 0.22, blue: 0.72),
                Color(red: 0.70, green: 0.32, blue: 1.00)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private enum LabGoalSwipeSavePalette {
    static let accent = Color(red: 0.70, green: 0.32, blue: 1.00)
}

private enum LabGoalSwipeSavePillStyle {
    case secondary
}

private extension View {
    func swipeSavePillControl(
        style: LabGoalSwipeSavePillStyle,
        colorScheme: ColorScheme
    ) -> some View {
        self
            .font(.subheadline.weight(.bold))
            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.small)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.72))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.68), lineWidth: 1)
            }
    }
}

#endif
