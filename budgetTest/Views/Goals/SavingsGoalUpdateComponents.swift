import SwiftUI

enum SavingsGoalUpdateFocusedField: Hashable {
    case name
    case targetAmount
    case setAsideAmount
}

struct SavingsGoalUpdateTopControls: View {

    let colorScheme: ColorScheme
    let onCancel: () -> Void
    let onOptions: () -> Void

    private var pillSurface: AnyShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.10))
            : AnyShapeStyle(Color.white.opacity(0.70))
    }

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .editSavingsGoalPillControl(
                    colorScheme: colorScheme
                )
                .accessibilityLabel("Cancel goal updates")

            Spacer()

            Button(action: onOptions) {
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
}

struct SavingsGoalContributionContent: View {

    @Binding var input: EditSavingsGoalInput
    @FocusState.Binding var focusedField: SavingsGoalUpdateFocusedField?

    let usesCompactSpacing: Bool
    let colorScheme: ColorScheme
    let showsCoverInFullAction: Bool
    let isCoverInFullCovered: Bool
    let isCoverInFullEnabled: Bool
    let isCoverInFullSaving: Bool
    let coverInFullConfirmationMessage: String
    let onCoverInFull: () -> Void
    let onOpenDetails: (SavingsGoalDetailsCardTrigger) -> Void

    private let controlWidth: CGFloat = 320

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

    var body: some View {
        VStack(
            spacing: usesCompactSpacing
                ? AppSpacing.small
                : AppSpacing.regular
        ) {
            goalNamePill
            goalContextPill
            setAsideModePicker
            setAsideAmountHero

            if showsCoverInFullAction {
                HoldToCoverInFullButton(
                    color: goalStyle.primary,
                    isCovered: isCoverInFullCovered,
                    isEnabled: isCoverInFullEnabled,
                    isSaving: isCoverInFullSaving,
                    accessibilityConfirmationMessage:
                        coverInFullConfirmationMessage,
                    onConfirmed: onCoverInFull
                )
                .frame(maxWidth: controlWidth)
            }

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
            onOpenDetails(.goalName)
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
                    Image(systemName: goalStyle.icon)
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
            onOpenDetails(.goalContext)
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

    private func formattedCurrency(_ amount: Double) -> String {
        AppFormatters.currency(amount)
    }
}

struct EditSavingsGoalCircleLayout {

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

struct EditSavingsGoalConcentricCircles: View {

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
