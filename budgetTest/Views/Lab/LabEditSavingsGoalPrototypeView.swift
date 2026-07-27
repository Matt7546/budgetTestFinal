#if DEBUG

import SwiftUI

struct LabEditSavingsGoalPrototypeView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var goalName = "Vacation"
    @State private var contributionDigits = ""
    @State private var targetDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 14)
    ) ?? Date()
    @State private var isShowingDatePicker = false
    @State private var previewContributionAmount = 0
    @State private var previewUpdateTask: Task<Void, Never>?
    @FocusState private var isContributionInputFocused: Bool

    private let targetAmount = 5_000
    private let currentAmount = 3_400

    var body: some View {
        ZStack {
            prototypeBackground
            goalMoodShape

            VStack(spacing: 0) {
                topControls

                goalHero

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.screen)
            .padding(.top, AppSpacing.medium)
            .padding(.bottom, AppSpacing.large)
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button {
                    isContributionInputFocused = false
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
        .onChange(of: contributionDigits) { _, newValue in
            let digitsOnly = newValue.filter(\.isNumber)
            let normalizedDigits = String(digitsOnly.drop(while: { $0 == "0" }))

            guard contributionDigits == normalizedDigits else {
                contributionDigits = normalizedDigits
                return
            }

            scheduleProgressPreview(for: contributionAmount)
        }
        .onDisappear {
            previewUpdateTask?.cancel()
        }
    }

    private var topControls: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Edit Goal Prototype")
            .editGoalPillControl(style: .secondary, colorScheme: colorScheme)

            Spacer()

            Button("Save") {}
                .buttonStyle(.plain)
                .disabled(contributionAmount == 0)
                .accessibilityLabel("Save prototype contribution")
                .accessibilityHint(
                    contributionAmount == 0
                        ? "Enter an amount to add before saving"
                        : "Saving is disabled in this Lab prototype"
                )
                .editGoalPillControl(style: .primary, colorScheme: colorScheme)
                .opacity(contributionAmount == 0 ? 0.48 : 1)
        }
    }

    private var goalHero: some View {
        VStack(spacing: AppSpacing.regular) {
            goalNamePill
            goalContextPill

            VStack(spacing: AppSpacing.small) {
                contributionAmountHero
                datePill

                Text("New total: \(formattedCurrency(newTotal)) of \(formattedCurrency(targetAmount))")
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .opacity(0.84)
                    .accessibilityLabel(
                        "New total \(formattedCurrency(newTotal)) of \(formattedCurrency(targetAmount))"
                    )
            }
        }
        .padding(.top, 58)
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
            color: CalderaCategoryStyle.style(for: .savingsGoal).primary.opacity(
                colorScheme == .dark ? 0.16 : 0.08
            ),
            radius: 14,
            x: 0,
            y: 8
        )
        .frame(maxWidth: .infinity)
    }

    private var goalContextPill: some View {
        HStack(spacing: AppSpacing.small) {
            Text("Target: \(formattedCurrency(targetAmount))")

            Rectangle()
                .fill(CalderaVisualStyle.secondaryText(colorScheme).opacity(0.28))
                .frame(width: 1, height: 16)

            Text("Current: \(formattedCurrency(currentAmount))")
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
        .padding(.horizontal, AppSpacing.regular)
        .padding(.vertical, AppSpacing.xSmall)
        .background(pillSurface.opacity(colorScheme == .dark ? 0.86 : 0.72))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.58), lineWidth: 1)
        }
        .clipShape(Capsule(style: .continuous))
        .accessibilityLabel(
            "Goal target \(formattedCurrency(targetAmount)), currently \(formattedCurrency(currentAmount))"
        )
    }

    private var contributionAmountHero: some View {
        VStack(spacing: AppSpacing.xSmall) {
            Text("Add money")
                .font(.caption.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .textCase(.uppercase)

            Button {
                isContributionInputFocused = true
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
                            goalAccentGradient.opacity(contributionDigits.isEmpty ? 0.46 : 0.74)
                        )

                    Text(formattedContributionAmount)
                        .font(
                            .system(
                                size: heroAmountFontSize,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(
                            contributionDigits.isEmpty
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
            .accessibilityLabel("New contribution amount")
            .accessibilityValue("\(formattedContributionAmount) dollars")
            .accessibilityHint("Double tap to enter a whole-dollar amount to add")
            .background {
                TextField("", text: $contributionDigits)
                    .keyboardType(.numberPad)
                    .focused($isContributionInputFocused)
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

    private var goalMoodShape: some View {
        GeometryReader { proxy in
            let center = CGPoint(
                x: proxy.size.width / 2,
                y: proxy.size.height + 36
            )
            let largestDiameter = max(proxy.size.height * 1.22, 820)

            ZStack {
                concentricCircle(
                    colors: [
                        Color(red: 0.70, green: 0.52, blue: 1.00).opacity(0.23),
                        Color(red: 0.95, green: 0.62, blue: 0.88).opacity(0.20)
                    ],
                    diameter: largestDiameter,
                    center: center
                )

                concentricCircle(
                    colors: [
                        Color(red: 0.94, green: 0.48, blue: 0.80).opacity(0.28),
                        Color(red: 0.71, green: 0.40, blue: 0.98).opacity(0.24)
                    ],
                    diameter: largestDiameter * middleCircleScale,
                    center: center
                )

                concentricCircle(
                    colors: [
                        Color(red: 0.80, green: 0.28, blue: 0.86).opacity(0.30),
                        Color(red: 0.59, green: 0.36, blue: 0.96).opacity(0.26)
                    ],
                    diameter: largestDiameter * innerCircleScale,
                    center: center
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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

    private var contributionAmount: Int {
        Int(contributionDigits) ?? 0
    }

    private var newTotal: Int {
        currentAmount + contributionAmount
    }

    private var previewProjectedProgress: CGFloat {
        min(
            max(
                CGFloat(currentAmount + previewContributionAmount) / CGFloat(targetAmount),
                0
            ),
            1
        )
    }

    private var visualProgress: CGFloat {
        CGFloat(Double(previewProjectedProgress).squareRoot())
    }

    // The rings share one progress value but retain distinct layers until completion.
    private var middleCircleScale: CGFloat {
        interpolatedCircleScale(from: 0.70)
    }

    private var innerCircleScale: CGFloat {
        interpolatedCircleScale(from: 0.45)
    }

    private func interpolatedCircleScale(from minimumScale: CGFloat) -> CGFloat {
        minimumScale + ((1 - minimumScale) * visualProgress)
    }

    private var formattedContributionAmount: String {
        formattedCurrency(contributionAmount, includeCurrencySymbol: false)
    }

    private var heroAmountDigitCount: Int {
        max(contributionDigits.count, 1)
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

    private func scheduleProgressPreview(for amount: Int) {
        previewUpdateTask?.cancel()

        previewUpdateTask = Task { [amount] in
            try? await Task.sleep(nanoseconds: 500_000_000)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.48)) {
                    previewContributionAmount = amount
                }
            }
        }
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

private enum LabEditGoalPillStyle {
    case primary
    case secondary
}

private extension View {
    func editGoalPillControl(
        style: LabEditGoalPillStyle,
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
                                        Color(red: 0.48, green: 0.22, blue: 0.98),
                                        Color(red: 0.90, green: 0.20, blue: 0.72)
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
