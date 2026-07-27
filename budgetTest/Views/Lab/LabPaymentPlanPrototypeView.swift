#if DEBUG

import SwiftUI

struct LabPaymentPlanPrototypeView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var creationMode: LabPaymentPlanCreationMode = .manual
    @State private var planName = "Platinum Card®"
    @State private var selectedLinkedAccount = "Amex Gold"
    @State private var targetDigits = ""
    @State private var dueDate = Self.amexGoldStatementDueDate
    @State private var targetType: LabPaymentPlanTargetType = .custom
    @State private var dueDateSource: LabPaymentPlanDueDateSource = .custom
    @State private var isShowingDatePicker = false
    @State private var isLinkedAccountPickerExpanded = false
    @State private var isTargetPickerExpanded = false
    @State private var isDueDatePickerExpanded = false
    @State private var swipeProgress: CGFloat = 0
    @State private var isSaved = false
    @State private var circleCompletionProgress: CGFloat = 0
    @State private var foregroundOpacity: CGFloat = 1
    @State private var isShowingSuccess = false
    @State private var saveCompletionTask: Task<Void, Never>?
    @FocusState private var isTargetInputFocused: Bool

    private let linkedAccounts = ["Amex Gold", "Platinum Card®", "Chase Freedom"]
    private let primaryControlWidth: CGFloat = 300
    private let collapsedControlCornerRadius: CGFloat = 24
    private let expandedControlCornerRadius: CGFloat = 30
    private let selectorToControlStackSpacing: CGFloat = 18
    private let controlStackSpacing: CGFloat = 10
    private let stackToAmountSpacing: CGFloat = 24
    private let maxCircleDragOffset: CGFloat = 120
    private static let amexGoldStatementDueDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 14)
    ) ?? Date()
    private static let platinumCardStatementDueDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 15)
    ) ?? Date()
    private static let chaseFreedomStatementDueDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 21)
    ) ?? Date()
    private static let defaultCustomDueDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 20)
    ) ?? Date()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                prototypeBackground
                paymentPlanMoodShape(in: proxy.size)
                    .animation(.easeInOut(duration: 0.32), value: targetEntryGlow)

                VStack(spacing: 0) {
                    topControls
                    paymentPlanHero
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppSpacing.screen)
                .padding(.top, AppSpacing.medium)
                .padding(.bottom, AppSpacing.large)
                .opacity(foregroundOpacity)
                .allowsHitTesting(!isSaved)

                if !isTargetInputFocused && !isSaved {
                    LabSwipeToSaveInteraction(
                        circleCenter: smallestCircleCenter(in: proxy.size),
                        circleDiameter: smallestCircleDiameter(in: proxy.size),
                        affordanceCenter: CGPoint(
                            x: proxy.size.width / 2,
                            y: swipeAffordanceCenterY(in: proxy.size)
                        ),
                        promptText: "Swipe up to save",
                        isEnabled: !isTargetInputFocused && !isSaved,
                        swipeProgress: $swipeProgress,
                        affordanceStyle: AnyShapeStyle(Color.white),
                        onSaveTriggered: savePrototypePlan
                    )
                    .opacity(foregroundOpacity)
                    .transition(.opacity)
                }

                if isShowingSuccess {
                    LabSwipeSaveSuccessOverlay(
                        successText: "Plan created",
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
                    isTargetInputFocused = false
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
                    creationMode == .linked ? "Custom due date" : "Due date",
                    selection: $dueDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(AppSpacing.screen)
                .navigationTitle(creationMode == .linked ? "Custom Date" : "Due Date")
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
        .onChange(of: targetDigits) { _, newValue in
            let digitsOnly = newValue.filter(\.isNumber)
            let normalizedDigits = String(digitsOnly.drop(while: { $0 == "0" }))

            if targetDigits != normalizedDigits {
                targetDigits = normalizedDigits
            }
        }
        .onChange(of: creationMode) { _, newValue in
            isDueDatePickerExpanded = false

            if newValue == .manual {
                isLinkedAccountPickerExpanded = false
                isTargetPickerExpanded = false
                targetType = .custom
                dueDateSource = .custom
            } else {
                if targetType == .custom {
                    targetType = .statement
                }

                dueDateSource = .statement
                dueDate = Self.statementDueDate(for: selectedLinkedAccount)
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
            .accessibilityLabel("Close Payment Plan Prototype")
            .paymentPlanPillControl(style: .secondary, colorScheme: colorScheme)

            Spacer()
        }
    }

    private var paymentPlanHero: some View {
        VStack(spacing: 0) {
            creationModeSelector
                .padding(.bottom, selectorToControlStackSpacing)

            Group {
                if creationMode == .linked {
                    VStack(spacing: controlStackSpacing) {
                        planNamePill
                        targetPicker
                        dueDatePill
                    }
                } else {
                    VStack(spacing: controlStackSpacing) {
                        planNamePill
                        dueDatePill
                    }
                }
            }
            .animation(.easeInOut(duration: 0.22), value: creationMode)

            targetAmountHero
                .padding(.top, stackToAmountSpacing)
        }
        .padding(.top, 58)
    }

    private var creationModeSelector: some View {
        HStack(spacing: 4) {
            ForEach(LabPaymentPlanCreationMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        creationMode = mode
                        if mode == .manual {
                            isLinkedAccountPickerExpanded = false
                            isTargetPickerExpanded = false
                            targetType = .custom
                        } else if targetType == .custom {
                            targetType = .statement
                        }
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(
                            creationMode == mode
                                ? AnyShapeStyle(Color.white)
                                : AnyShapeStyle(CalderaVisualStyle.secondaryText(colorScheme))
                        )
                        .padding(.horizontal, AppSpacing.regular)
                        .padding(.vertical, AppSpacing.xSmall)
                        .background {
                            Capsule(style: .continuous)
                                .fill(
                                    creationMode == mode
                                        ? AnyShapeStyle(paymentPlanAccentGradient)
                                        : AnyShapeStyle(Color.clear)
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.rawValue) payment plan")
                .accessibilityAddTraits(creationMode == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(pillSurface.opacity(colorScheme == .dark ? 0.88 : 0.76))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.66), lineWidth: 1)
        }
        .clipShape(Capsule(style: .continuous))
        .frame(width: primaryControlWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Payment plan type")
    }

    private var planNamePill: some View {
        Group {
            if creationMode == .manual {
                manualPlanNameContent
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .padding(.horizontal, AppSpacing.regular)
                    .paymentPlanControlSurface(
                        cornerRadius: collapsedControlCornerRadius,
                        colorScheme: colorScheme
                    )
                    .frame(width: primaryControlWidth)
            } else {
                linkedAccountSelectionContent
            }
        }
    }

    private var manualPlanNameContent: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Image(systemName: "creditcard.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(paymentPlanAccentGradient)

            TextField("Payment plan name", text: $planName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .multilineTextAlignment(.leading)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Payment plan name")
        }
    }

    private var linkedAccountSelectionContent: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.24)) {
                    isTargetPickerExpanded = false
                    isDueDatePickerExpanded = false
                    isLinkedAccountPickerExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppSpacing.xSmall) {
                    Image(systemName: "creditcard.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(paymentPlanAccentGradient)

                    Text(selectedLinkedAccount)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: AppSpacing.small)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isLinkedAccountPickerExpanded ? 180 : 0))
                }
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 48)
            .padding(.horizontal, AppSpacing.regular)
            .accessibilityLabel("Linked account \(selectedLinkedAccount)")
            .accessibilityHint(
                isLinkedAccountPickerExpanded
                    ? "Double tap to collapse linked accounts"
                    : "Double tap to choose a linked account"
            )

            if isLinkedAccountPickerExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(CalderaVisualStyle.secondaryText(colorScheme).opacity(0.20))

                    ForEach(linkedAccounts.filter { $0 != selectedLinkedAccount }, id: \.self) { account in
                        Button {
                            withAnimation(.easeInOut(duration: 0.24)) {
                                selectedLinkedAccount = account
                                isLinkedAccountPickerExpanded = false
                                dueDateSource = .statement
                                dueDate = Self.statementDueDate(for: account)
                            }
                        } label: {
                            HStack(spacing: AppSpacing.xSmall) {
                                Image(systemName: "creditcard.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(paymentPlanAccentGradient.opacity(0.72))

                                Text(account)
                                    .font(.subheadline.weight(.medium))

                                Spacer(minLength: 0)
                            }
                            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.regular)
                            .frame(height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select linked account \(account)")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .paymentPlanControlSurface(
            cornerRadius: isLinkedAccountPickerExpanded
                ? expandedControlCornerRadius
                : collapsedControlCornerRadius,
            colorScheme: colorScheme
        )
        .frame(width: primaryControlWidth)
        .animation(.easeInOut(duration: 0.24), value: isLinkedAccountPickerExpanded)
    }

    private var targetPicker: some View {
        VStack(spacing: 0) {
            Button {
                guard creationMode == .linked else { return }

                withAnimation(.easeInOut(duration: 0.24)) {
                    isLinkedAccountPickerExpanded = false
                    isDueDatePickerExpanded = false
                    isTargetPickerExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppSpacing.xSmall) {
                    Image(systemName: "creditcard.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(paymentPlanAccentGradient)

                    Text(collapsedTargetTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .layoutPriority(1)

                    Spacer(minLength: AppSpacing.small)

                    Text(collapsedTargetAmount)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if creationMode == .linked {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(isTargetPickerExpanded ? 180 : 0))
                    }
                }
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 48)
            .padding(.horizontal, AppSpacing.regular)
            .accessibilityLabel("Payment target \(targetPickerSummary)")
            .accessibilityHint(
                creationMode == .linked
                    ? (isTargetPickerExpanded
                        ? "Double tap to collapse payment target options"
                        : "Double tap to choose a payment target")
                    : "Custom balance is selected for this manual plan"
            )

            if creationMode == .linked && isTargetPickerExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(CalderaVisualStyle.secondaryText(colorScheme).opacity(0.20))

                    ForEach(availableTargetTypes) { type in
                        Button {
                            withAnimation(.easeInOut(duration: 0.24)) {
                                targetType = type
                                isTargetPickerExpanded = false
                            }
                        } label: {
                            HStack(spacing: AppSpacing.xSmall) {
                                Text(type.rawValue)
                                    .font(.subheadline.weight(.medium))

                                Spacer(minLength: AppSpacing.small)

                                Text(targetPickerDetail(for: type))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)

                                if targetType == type {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                }
                            }
                            .foregroundStyle(
                                targetType == type
                                    ? AnyShapeStyle(paymentPlanAccentGradient)
                                    : AnyShapeStyle(CalderaVisualStyle.primaryText(colorScheme))
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.regular)
                            .frame(height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(type.rawValue), \(targetPickerDetail(for: type))")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .paymentPlanControlSurface(
            cornerRadius: isTargetPickerExpanded
                ? expandedControlCornerRadius
                : collapsedControlCornerRadius,
            colorScheme: colorScheme
        )
        .frame(width: primaryControlWidth)
        .animation(.easeInOut(duration: 0.24), value: isTargetPickerExpanded)
    }

    private var targetAmountHero: some View {
        Button {
            guard targetType == .custom else { return }
            isTargetInputFocused = true
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
                        paymentPlanAccentGradient.opacity(effectiveTargetAmount == 0 ? 0.46 : 0.74)
                    )

                Text(formattedTargetAmount)
                    .font(
                        .system(
                            size: heroAmountFontSize,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        effectiveTargetAmount == 0
                            ? AnyShapeStyle(CalderaVisualStyle.secondaryText(colorScheme).opacity(0.42))
                            : AnyShapeStyle(paymentPlanAccentGradient)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(.horizontal, AppSpacing.small)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Payment target")
        .accessibilityValue("\(formattedTargetAmount) dollars")
        .accessibilityHint(
            targetType == .custom
                ? "Double tap to enter a whole-dollar payment target"
                : "Choose Custom balance to enter a payment target"
        )
        .background {
            TextField("", text: $targetDigits)
                .keyboardType(.numberPad)
                .focused($isTargetInputFocused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    private var dueDatePill: some View {
        Group {
            if creationMode == .linked {
                linkedDueDatePicker
            } else {
                manualDueDatePill
            }
        }
    }

    private var manualDueDatePill: some View {
        Button {
            isShowingDatePicker = true
        } label: {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.bold))

                Text("Due \(formattedDueDate)")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
            .paymentPlanMetadataPill(colorScheme: colorScheme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Due date \(dueDate.formatted(.dateTime.month(.wide).day()))")
        .accessibilityHint("Double tap to choose a due date")
    }

    private var linkedDueDatePicker: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.24)) {
                    isLinkedAccountPickerExpanded = false
                    isTargetPickerExpanded = false
                    isDueDatePickerExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppSpacing.xSmall) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(paymentPlanAccentGradient)

                    Text(dueDateSource.collapsedTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: AppSpacing.small)

                    Text(formattedDueDate)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isDueDatePickerExpanded ? 180 : 0))
                }
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 48)
            .padding(.horizontal, AppSpacing.regular)
            .accessibilityLabel("\(dueDateSource.optionTitle), \(formattedDueDate)")
            .accessibilityHint(
                isDueDatePickerExpanded
                    ? "Double tap to collapse due date options"
                    : "Double tap to choose the due date source"
            )

            if isDueDatePickerExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(CalderaVisualStyle.secondaryText(colorScheme).opacity(0.20))

                    ForEach(LabPaymentPlanDueDateSource.allCases) { source in
                        Button {
                            selectLinkedDueDateSource(source)
                        } label: {
                            HStack(spacing: AppSpacing.xSmall) {
                                Text(source.optionTitle)
                                    .font(.subheadline.weight(.medium))

                                Spacer(minLength: AppSpacing.small)

                                Text(dueDateOptionDetail(for: source))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)

                                if dueDateSource == source {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                }
                            }
                            .foregroundStyle(
                                dueDateSource == source
                                    ? AnyShapeStyle(paymentPlanAccentGradient)
                                    : AnyShapeStyle(CalderaVisualStyle.primaryText(colorScheme))
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.regular)
                            .frame(height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(source.optionTitle), \(dueDateOptionDetail(for: source))")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .paymentPlanControlSurface(
            cornerRadius: isDueDatePickerExpanded
                ? expandedControlCornerRadius
                : collapsedControlCornerRadius,
            colorScheme: colorScheme
        )
        .frame(width: primaryControlWidth)
        .animation(.easeInOut(duration: 0.24), value: isDueDatePickerExpanded)
    }

    private var prototypeBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.14, green: 0.05, blue: 0.09),
                    Color(red: 0.27, green: 0.08, blue: 0.12),
                    Color(red: 0.18, green: 0.06, blue: 0.18)
                ]
                : [
                    Color(red: 1.00, green: 0.91, blue: 0.94),
                    Color(red: 1.00, green: 0.89, blue: 0.91),
                    Color(red: 0.95, green: 0.90, blue: 1.00)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func paymentPlanMoodShape(in size: CGSize) -> some View {
        let center = smallestCircleCenter(in: size)
        let fullGoalDiameter = max(size.height * 1.22, 820)
        let completionScale = 1 + (0.42 * circleCompletionProgress)
        let dragScale = 1 + (0.08 * swipeProgress)

        return ZStack {
            concentricCircle(
                colors: [
                    Color(red: 1.00, green: 0.43, blue: 0.44).opacity(0.24 + (0.05 * targetEntryGlow) + (0.06 * swipeProgress) + (0.12 * circleCompletionProgress)),
                    Color(red: 0.96, green: 0.42, blue: 0.76).opacity(0.20 + (0.04 * targetEntryGlow) + (0.05 * swipeProgress) + (0.10 * circleCompletionProgress))
                ],
                diameter: fullGoalDiameter * completionScale * dragScale,
                center: center
            )

            concentricCircle(
                colors: [
                    Color(red: 1.00, green: 0.27, blue: 0.34).opacity(0.30 + (0.06 * targetEntryGlow) + (0.06 * swipeProgress) + (0.12 * circleCompletionProgress)),
                    Color(red: 0.92, green: 0.24, blue: 0.62).opacity(0.25 + (0.05 * targetEntryGlow) + (0.05 * swipeProgress) + (0.10 * circleCompletionProgress))
                ],
                diameter: fullGoalDiameter * (0.82 + (0.18 * circleCompletionProgress)) * completionScale * dragScale,
                center: center
            )

            concentricCircle(
                colors: [
                    Color(red: 0.95, green: 0.18, blue: 0.43).opacity(0.32 + (0.07 * targetEntryGlow) + (0.07 * swipeProgress) + (0.13 * circleCompletionProgress)),
                    Color(red: 0.74, green: 0.18, blue: 0.64).opacity(0.28 + (0.06 * targetEntryGlow) + (0.06 * swipeProgress) + (0.12 * circleCompletionProgress))
                ],
                diameter: fullGoalDiameter * (0.64 + (0.36 * circleCompletionProgress)) * completionScale * dragScale,
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
        let fullGoalDiameter = max(size.height * 1.22, 820)
        let completionScale = 1 + (0.42 * circleCompletionProgress)
        return fullGoalDiameter
            * (0.64 + (0.36 * circleCompletionProgress))
            * completionScale
            * (1 + (0.045 * swipeProgress))
    }

    private func savePrototypePlan() {
        guard !isSaved else { return }

        isTargetInputFocused = false

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
                UIAccessibility.post(notification: .announcement, argument: "Plan created")
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

    private var targetAmount: Int {
        Int(targetDigits) ?? 0
    }

    private var availableTargetTypes: [LabPaymentPlanTargetType] {
        creationMode == .linked ? LabPaymentPlanTargetType.allCases : [.custom]
    }

    private var effectiveTargetAmount: Int {
        switch targetType {
        case .statement:
            866
        case .minimum:
            203
        case .fullBalance:
            1_042
        case .custom:
            targetAmount
        }
    }

    private var targetPickerSummary: String {
        "\(collapsedTargetTitle) · \(collapsedTargetAmount)"
    }

    private var collapsedTargetTitle: String {
        targetType.rawValue
    }

    private var collapsedTargetAmount: String {
        switch targetType {
        case .custom:
            formattedCurrency(targetAmount)
        default:
            targetPickerDetail(for: targetType)
        }
    }

    private func targetPickerDetail(for type: LabPaymentPlanTargetType) -> String {
        switch type {
        case .statement:
            "$866.04"
        case .minimum:
            "$202.59"
        case .fullBalance:
            "$1,042.17"
        case .custom:
            "Choose amount"
        }
    }

    private var targetEntryGlow: CGFloat {
        effectiveTargetAmount > 0 ? 1 : 0
    }

    private var formattedDueDate: String {
        dueDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private func dueDateOptionDetail(for source: LabPaymentPlanDueDateSource) -> String {
        switch source {
        case .statement:
            Self.statementDueDate(for: selectedLinkedAccount)
                .formatted(.dateTime.month(.abbreviated).day())
        case .custom:
            dueDateSource == .custom
                ? formattedDueDate
                : Self.defaultCustomDueDate.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func selectLinkedDueDateSource(_ source: LabPaymentPlanDueDateSource) {
        withAnimation(.easeInOut(duration: 0.24)) {
            dueDateSource = source
            isDueDatePickerExpanded = false

            if source == .statement {
                dueDate = Self.statementDueDate(for: selectedLinkedAccount)
            } else if Calendar.current.isDate(
                dueDate,
                inSameDayAs: Self.statementDueDate(for: selectedLinkedAccount)
            ) {
                dueDate = Self.defaultCustomDueDate
            }
        }

        if source == .custom {
            isShowingDatePicker = true
        }
    }

    private static func statementDueDate(for account: String) -> Date {
        switch account {
        case "Platinum Card®":
            platinumCardStatementDueDate
        case "Chase Freedom":
            chaseFreedomStatementDueDate
        default:
            amexGoldStatementDueDate
        }
    }

    private var formattedTargetAmount: String {
        formattedCurrency(effectiveTargetAmount, includeCurrencySymbol: false)
    }

    private var heroAmountDigitCount: Int {
        max(String(effectiveTargetAmount).count, 1)
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

    private func formattedCurrency(_ amount: Int, includeCurrencySymbol: Bool = true) -> String {
        let formatted = String(amount).reversed().enumerated().reduce(into: "") { result, element in
            let (index, digit) = element

            if index > 0 && index.isMultiple(of: 3) {
                result.insert(",", at: result.startIndex)
            }

            result.insert(digit, at: result.startIndex)
        }

        return includeCurrencySymbol ? "$\(formatted)" : formatted
    }

    private var pillSurface: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.10))
            : AnyShapeStyle(Color.white.opacity(0.66))
    }

    private var paymentPlanAccentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.94, green: 0.16, blue: 0.35),
                Color(red: 1.00, green: 0.31, blue: 0.29),
                Color(red: 0.79, green: 0.20, blue: 0.70)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private enum LabPaymentPlanCreationMode: String, CaseIterable, Identifiable {
    case manual = "Manual"
    case linked = "Linked Account"

    var id: String { rawValue }
}

private enum LabPaymentPlanTargetType: String, CaseIterable, Identifiable {
    case statement = "Statement balance"
    case minimum = "Minimum balance"
    case fullBalance = "Full balance"
    case custom = "Custom balance"

    var id: String { rawValue }
}

private enum LabPaymentPlanDueDateSource: CaseIterable, Identifiable {
    case statement
    case custom

    var id: Self { self }

    var collapsedTitle: String {
        switch self {
        case .statement:
            "Statement due date"
        case .custom:
            "Custom due date"
        }
    }

    var optionTitle: String {
        switch self {
        case .statement:
            "Statement due date"
        case .custom:
            "Custom due date"
        }
    }
}

private enum LabPaymentPlanPillStyle {
    case primary
    case secondary
}

private extension View {
    func paymentPlanControlSurface(
        cornerRadius: CGFloat,
        colorScheme: ColorScheme
    ) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? AnyShapeStyle(Color.white.opacity(0.10))
                            : AnyShapeStyle(Color.white.opacity(0.66))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color.white.opacity(colorScheme == .dark ? 0.20 : 0.72),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: CalderaCategoryStyle.style(for: .debtPayoff).primary.opacity(
                    colorScheme == .dark ? 0.16 : 0.08
                ),
                radius: 14,
                x: 0,
                y: 8
            )
    }

    func paymentPlanMetadataPill(colorScheme: ColorScheme) -> some View {
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

    func paymentPlanPillControl(
        style: LabPaymentPlanPillStyle,
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
                                        Color(red: 0.94, green: 0.16, blue: 0.35),
                                        Color(red: 0.79, green: 0.20, blue: 0.70)
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
