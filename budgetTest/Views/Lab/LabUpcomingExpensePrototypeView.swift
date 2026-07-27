#if DEBUG

import SwiftUI

struct LabUpcomingExpensePrototypeView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var expenseName = "Rent"
    @State private var amountDigits = "1700"
    @State private var dueDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 1)
    ) ?? Date()
    @State private var repeatPeriod: LabExpenseRepeatPeriod = .monthly
    @State private var isShowingDatePicker = false
    @State private var isShowingRepeatPicker = false
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
                expenseMoodShape(in: proxy.size)

                VStack(spacing: 0) {
                    topControls
                    expenseHero
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppSpacing.screen)
                .padding(.top, AppSpacing.medium)
                .padding(.bottom, AppSpacing.large)
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
                        onSaveTriggered: savePrototypeExpense
                    )
                    .opacity(foregroundOpacity)
                    .transition(.opacity)
                }

                if isShowingSuccess {
                    LabSwipeSaveSuccessOverlay(
                        successText: "Expense created",
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
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $isShowingDatePicker) {
            NavigationStack {
                DatePicker(
                    "Due date",
                    selection: $dueDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(AppSpacing.screen)
                .navigationTitle("Due Date")
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
        .confirmationDialog(
            "Repeat",
            isPresented: $isShowingRepeatPicker,
            titleVisibility: .visible
        ) {
            ForEach(LabExpenseRepeatPeriod.allCases) { period in
                Button(period.rawValue) {
                    repeatPeriod = period
                }
            }
        }
        .onChange(of: amountDigits) { _, newValue in
            let digitsOnly = newValue.filter(\.isNumber)
            let normalizedDigits = String(digitsOnly.drop(while: { $0 == "0" }))

            if amountDigits != normalizedDigits {
                amountDigits = normalizedDigits
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
            .accessibilityLabel("Close Upcoming Expense Prototype")
            .expensePillControl(style: .secondary, colorScheme: colorScheme)

            Spacer()
        }
    }

    private var expenseHero: some View {
        VStack(spacing: AppSpacing.regular) {
            expenseNamePill

            VStack(spacing: AppSpacing.small) {
                amountHero

                HStack(spacing: AppSpacing.small) {
                    datePill
                    repeatPill
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 68)
    }

    private var expenseNamePill: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Image(systemName: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(expenseAccentGradient)

            TextField("Expense name", text: $expenseName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .frame(maxWidth: 156)
                .accessibilityLabel("Expense name")
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
            color: CalderaCategoryStyle.style(for: .upcomingExpense).primary.opacity(
                colorScheme == .dark ? 0.16 : 0.08
            ),
            radius: 14,
            x: 0,
            y: 8
        )
        .frame(maxWidth: .infinity)
    }

    private var amountHero: some View {
        VStack(spacing: AppSpacing.xSmall) {
            Text("Amount needed")
                .font(.caption.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .textCase(.uppercase)

            Button {
                isAmountInputFocused = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$")
                        .font(
                            .system(
                                size: heroCurrencyFontSize,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            expenseAccentGradient.opacity(amountDigits.isEmpty ? 0.46 : 0.74)
                        )

                    Text(formattedHeroAmount)
                        .font(
                            .system(
                                size: heroAmountFontSize,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(
                            amountDigits.isEmpty
                                ? AnyShapeStyle(CalderaVisualStyle.secondaryText(colorScheme).opacity(0.42))
                                : AnyShapeStyle(expenseAccentGradient)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .padding(.horizontal, AppSpacing.small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Amount needed")
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

                Text(dueDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
            .metadataPillSurface(colorScheme: colorScheme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Due date \(dueDate.formatted(.dateTime.month(.wide).day()))")
        .accessibilityHint("Double tap to choose a due date")
    }

    private var repeatPill: some View {
        Button {
            isShowingRepeatPicker = true
        } label: {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: "repeat")
                    .font(.caption.weight(.bold))

                Text(repeatPeriod.rawValue)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(expenseAccentGradient)
            .metadataPillSurface(colorScheme: colorScheme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Repeat \(repeatPeriod.rawValue)")
        .accessibilityHint("Double tap to choose a repeat period")
    }

    private var prototypeBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.13, green: 0.07, blue: 0.06),
                    Color(red: 0.25, green: 0.11, blue: 0.07),
                    Color(red: 0.18, green: 0.08, blue: 0.12)
                ]
                : [
                    Color(red: 1.00, green: 0.93, blue: 0.88),
                    Color(red: 1.00, green: 0.91, blue: 0.86),
                    Color(red: 1.00, green: 0.94, blue: 0.90)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func expenseMoodShape(in size: CGSize) -> some View {
        let center = smallestCircleCenter(in: size)
        let largestDiameter = max(size.height * 1.22, 820)
        let completionScale = 1 + (0.42 * circleCompletionProgress)
        let dragScale = 1 + (0.08 * swipeProgress)

        return ZStack {
            concentricCircle(
                colors: [
                    Color(red: 1.00, green: 0.63, blue: 0.39).opacity(0.24 + (0.06 * swipeProgress) + (0.12 * circleCompletionProgress)),
                    Color(red: 1.00, green: 0.45, blue: 0.44).opacity(0.20 + (0.05 * swipeProgress) + (0.10 * circleCompletionProgress))
                ],
                diameter: largestDiameter * completionScale * dragScale,
                center: center
            )

            concentricCircle(
                colors: [
                    Color(red: 1.00, green: 0.43, blue: 0.24).opacity(0.30 + (0.06 * swipeProgress) + (0.12 * circleCompletionProgress)),
                    Color(red: 1.00, green: 0.30, blue: 0.38).opacity(0.25 + (0.05 * swipeProgress) + (0.10 * circleCompletionProgress))
                ],
                diameter: largestDiameter * (0.82 + (0.18 * circleCompletionProgress)) * completionScale * dragScale,
                center: center
            )

            concentricCircle(
                colors: [
                    Color(red: 1.00, green: 0.32, blue: 0.20).opacity(0.32 + (0.07 * swipeProgress) + (0.13 * circleCompletionProgress)),
                    Color(red: 0.95, green: 0.23, blue: 0.35).opacity(0.28 + (0.06 * swipeProgress) + (0.12 * circleCompletionProgress))
                ],
                diameter: largestDiameter * (0.64 + (0.36 * circleCompletionProgress)) * completionScale * dragScale,
                center: center
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func swipeAffordanceCenterY(in size: CGSize) -> CGFloat {
        let circleTop = smallestCircleCenter(in: size).y - (smallestCircleDiameter(in: size) / 2)
        return min(circleTop + 154, size.height - 166)
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

    private func savePrototypeExpense() {
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
                UIAccessibility.post(notification: .announcement, argument: "Expense created")
                #endif
            }

            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                dismiss()
            }
        }
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

    private var formattedHeroAmount: String {
        guard !amountDigits.isEmpty else { return "0" }
        return formattedDigits(amountDigits)
    }

    private var heroAmountDigitCount: Int {
        max(amountDigits.count, 1)
    }

    private var heroAmountFontSize: CGFloat {
        switch heroAmountDigitCount {
        case ...3:
            return 88
        case 4...5:
            return 78
        case 6...7:
            return 66
        case 8...9:
            return 56
        default:
            return 48
        }
    }

    private var heroCurrencyFontSize: CGFloat {
        max(heroAmountFontSize * 0.54, 30)
    }

    private func formattedDigits(_ digits: String) -> String {
        var formatted = ""

        for (index, digit) in digits.reversed().enumerated() {
            if index > 0 && index.isMultiple(of: 3) {
                formatted.insert(",", at: formatted.startIndex)
            }

            formatted.insert(digit, at: formatted.startIndex)
        }

        return formatted
    }

    private var pillSurface: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.10))
            : AnyShapeStyle(Color.white.opacity(0.66))
    }

    private var expenseAccentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.29, blue: 0.18),
                Color(red: 1.00, green: 0.53, blue: 0.19),
                Color(red: 0.96, green: 0.25, blue: 0.43)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private enum LabExpenseRepeatPeriod: String, CaseIterable, Identifiable {
    case oneTime = "One Time"
    case weekly = "Weekly"
    case biWeekly = "Bi-Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"

    var id: String { rawValue }
}

private enum LabExpensePillStyle {
    case primary
    case secondary
}

private extension View {
    func metadataPillSurface(colorScheme: ColorScheme) -> some View {
        self
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.small)
            .background(
                colorScheme == .dark
                    ? AnyShapeStyle(Color.white.opacity(0.10))
                    : AnyShapeStyle(Color.white.opacity(0.66))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.66), lineWidth: 1)
            }
            .clipShape(Capsule(style: .continuous))
    }

    func expensePillControl(
        style: LabExpensePillStyle,
        colorScheme: ColorScheme
    ) -> some View {
        self
            .font(.subheadline.weight(.bold))
            .foregroundColor(
                style == .primary
                    ? Color.white
                    : CalderaVisualStyle.primaryText(colorScheme)
            )
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.small)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        style == .primary
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.96, green: 0.29, blue: 0.18),
                                        Color(red: 0.96, green: 0.25, blue: 0.43)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.72))
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.68), lineWidth: 1)
            }
    }
}

#endif
