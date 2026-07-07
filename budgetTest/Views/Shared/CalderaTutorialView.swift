import SwiftUI

struct CalderaTutorialView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedIndex = 0

    private let onFinish: (() -> Void)?
    private let steps = CalderaTutorialStep.all

    init(
        onFinish: (() -> Void)? = nil
    ) {
        self.onFinish = onFinish
    }

    private var currentStep: CalderaTutorialStep {
        steps[selectedIndex]
    }

    private var isFirstStep: Bool {
        selectedIndex == 0
    }

    private var isLastStep: Bool {
        selectedIndex == steps.count - 1
    }

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            VStack(spacing: 0) {
                tutorialHeader

                ScrollView {
                    VStack(spacing: AppSpacing.screen) {
                        pageContent
                    }
                    .padding(.horizontal, AppSpacing.regular)
                    .padding(.top, AppSpacing.large)
                    .padding(.bottom, AppSpacing.emptyState)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            bottomControls
        }
    }

    private var tutorialHeader: some View {
        HStack(spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("How \(AppBrand.shortName) Works")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)

                Text("A quick guide you can replay anytime.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                finish()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(CalderaVisualStyle.cardFill(colorScheme, lightOpacity: 0.78))
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.70), lineWidth: 1)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tutorial")
        }
        .padding(.horizontal, AppSpacing.regular)
        .padding(.top, AppSpacing.medium)
        .padding(.bottom, AppSpacing.small)
    }

    private var pageContent: some View {
        VStack(spacing: AppSpacing.large) {
            progressIndicator

            CalderaGradientIcon(
                systemImage: currentStep.icon,
                colors: currentStep.colors,
                size: 74,
                iconSize: 30
            )

            VStack(spacing: AppSpacing.small) {
                Text(currentStep.title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)

                Text(currentStep.body)
                    .font(.body.weight(.medium))
                    .foregroundColor(AppColors.primaryText)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.small)
            }

            tutorialVisual(for: currentStep.kind)
        }
        .frame(maxWidth: .infinity)
    }

    private var progressIndicator: some View {
        HStack(spacing: AppSpacing.xSmall) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? AppColors.accent : AppColors.secondaryText.opacity(0.20))
                    .frame(width: index == selectedIndex ? 28 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.22), value: selectedIndex)
            }
        }
        .accessibilityLabel("Step \(selectedIndex + 1) of \(steps.count)")
    }

    @ViewBuilder
    private func tutorialVisual(
        for kind: CalderaTutorialVisualKind
    ) -> some View {
        switch kind {
        case .availableToSpend:
            TutorialEquationCard()

        case .setAside:
            TutorialTokenGrid()

        case .cashCushion:
            TutorialCashCushionCard()

        case .planAhead:
            TutorialUpcomingExpenseCard()

        case .connectAccounts:
            TutorialLinkedAccountCard()

        case .ready:
            TutorialReadyCard()
        }
    }

    private var bottomControls: some View {
        VStack(spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.medium) {
                Button {
                    if isFirstStep {
                        finish()
                    } else {
                        selectedIndex -= 1
                    }
                } label: {
                    Text(isFirstStep ? "Skip" : "Back")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
                                .fill(CalderaVisualStyle.cardFill(colorScheme, lightOpacity: 0.76))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.68), lineWidth: 1)
                        }
                        .contentShape(
                            RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    if isLastStep {
                        finish()
                    } else {
                        selectedIndex += 1
                    }
                } label: {
                    HStack(spacing: AppSpacing.xSmall) {
                        Text(isLastStep ? "Start using \(AppBrand.shortName)" : "Next")

                        if !isLastStep {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(
                        LinearGradient(
                            colors: CalderaVisualStyle.dashboardProgressGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
                    )
                    .contentShape(
                        RoundedRectangle(cornerRadius: AppRadii.button, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .shadow(
                    color: AppColors.accent.opacity(0.18),
                    radius: 14,
                    y: 8
                )
            }
        }
        .padding(.horizontal, AppSpacing.regular)
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.small)
        .background(.ultraThinMaterial)
    }

    private func finish() {
        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }
}

private struct CalderaTutorialStep: Identifiable {

    let id: Int
    let icon: String
    let title: String
    let body: String
    let colors: [Color]
    let kind: CalderaTutorialVisualKind

    static let all: [CalderaTutorialStep] = [
        CalderaTutorialStep(
            id: 0,
            icon: CalderaCategoryStyle.style(for: .safeToSpend).icon,
            title: "Available to Spend",
            body: "This is the cash you can use after \(AppBrand.shortName) subtracts money you’ve set aside.",
            colors: CalderaCategoryStyle.style(for: .safeToSpend).gradient,
            kind: .availableToSpend
        ),
        CalderaTutorialStep(
            id: 1,
            icon: "tray.full.fill",
            title: "Set money aside",
            body: "Set-asides are virtual. Your money stays in your bank account, but \(AppBrand.shortName) treats it as unavailable for everyday spending.",
            colors: CalderaVisualStyle.dashboardProgressGradient,
            kind: .setAside
        ),
        CalderaTutorialStep(
            id: 2,
            icon: CalderaCategoryStyle.style(for: .reserve).icon,
            title: "Cash Cushion",
            body: "Cash Cushion is flexible money kept separate from everyday spending. You can add money or move it back anytime.",
            colors: CalderaCategoryStyle.style(for: .reserve).gradient,
            kind: .cashCushion
        ),
        CalderaTutorialStep(
            id: 3,
            icon: CalderaCategoryStyle.style(for: .upcomingExpense).icon,
            title: "Plan ahead",
            body: "Upcoming Expenses and Debt Payoff help you prepare for subscriptions, planned purchases, and debt payments before they hit.",
            colors: CalderaCategoryStyle.style(for: .upcomingExpense).gradient,
            kind: .planAhead
        ),
        CalderaTutorialStep(
            id: 4,
            icon: CalderaCategoryStyle.style(for: .bankAccount).icon,
            title: "Connect accounts",
            body: "Link accounts so \(AppBrand.shortName) can show balances and estimate what is available. Your set-asides are managed inside \(AppBrand.shortName).",
            colors: CalderaCategoryStyle.style(for: .bankAccount).gradient,
            kind: .connectAccounts
        ),
        CalderaTutorialStep(
            id: 5,
            icon: "checkmark.seal.fill",
            title: "You’re ready",
            body: "Use \(AppBrand.shortName) to check what’s available, set money aside, and stay ahead of upcoming spending.",
            colors: CalderaCategoryStyle.style(for: .covered).gradient,
            kind: .ready
        )
    ]
}

private enum CalderaTutorialVisualKind {
    case availableToSpend
    case setAside
    case cashCushion
    case planAhead
    case connectAccounts
    case ready
}

private struct TutorialEquationCard: View {

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            TutorialExampleBadge("Example breakdown")

            TutorialValueRow(
                title: "Cash Balance",
                value: "$2,400",
                systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
                color: CalderaCategoryStyle.style(for: .bankAccount).primary
            )

            TutorialOperator("minus")

            TutorialValueRow(
                title: "Set Aside",
                value: "$840",
                systemImage: CalderaCategoryStyle.style(for: .reserve).icon,
                color: CalderaCategoryStyle.style(for: .reserve).primary
            )

            TutorialOperator("equals")

            TutorialValueRow(
                title: "Available to Spend",
                value: "$1,560",
                systemImage: CalderaCategoryStyle.style(for: .safeToSpend).icon,
                color: CalderaCategoryStyle.style(for: .safeToSpend).primary
            )
        }
        .tutorialCard()
    }
}

private struct TutorialTokenGrid: View {

    private let tokens: [(String, CalderaFinanceSemanticRole)] = [
        ("Cash Cushion", .reserve),
        ("Goals", .savingsGoal),
        ("Upcoming Expenses", .upcomingExpense),
        ("Debt Payoff", .debtPayoff)
    ]

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            TutorialExampleBadge("Example categories")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.small),
                    GridItem(.flexible(), spacing: AppSpacing.small)
                ],
                spacing: AppSpacing.small
            ) {
                ForEach(tokens, id: \.0) { token in
                    let style = CalderaCategoryStyle.style(for: token.1)

                    VStack(spacing: AppSpacing.xSmall) {
                        CalderaGradientIcon(
                            style: style,
                            size: 42,
                            iconSize: 17
                        )

                        Text(token.0)
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppColors.primaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .padding(AppSpacing.small)
                    .calderaGlassCard(
                        cornerRadius: AppRadii.control,
                        fillOpacity: 0.78,
                        strokeOpacity: 0.62,
                        shadowOpacity: 0.015,
                        shadowRadius: 8,
                        shadowY: 4,
                        darkGlowColor: style.primary
                    )
                }
            }
        }
        .tutorialCard()
    }
}

private struct TutorialCashCushionCard: View {

    var body: some View {
        let style = CalderaCategoryStyle.style(for: .reserve)

        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            TutorialExampleBadge()

            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(style: style, size: 44, iconSize: 18)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Cash Cushion")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)

                    Text("Flexible money kept out of everyday spending.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    CalderaProgressBar(
                        progress: 0.58,
                        colors: style.gradient
                    )
                    .padding(.top, AppSpacing.xSmall)
                }

                Spacer(minLength: AppSpacing.small)

                Text("$350")
                    .font(.headline.bold())
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
            }
        }
        .tutorialCard(darkGlowColor: style.primary)
    }
}

private struct TutorialUpcomingExpenseCard: View {

    var body: some View {
        let style = CalderaCategoryStyle.style(for: .upcomingExpense)

        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            TutorialExampleBadge()

            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(style: style, size: 42, iconSize: 17)

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Rent payment")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppColors.primaryText)

                    Text("Due in 5 days · $900 set aside")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: AppSpacing.small)

                Text("$1,250")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()
            }

            CalderaProgressBar(
                progress: 0.72,
                colors: style.gradient
            )
        }
        .tutorialCard(darkGlowColor: style.primary)
    }
}

private struct TutorialLinkedAccountCard: View {

    var body: some View {
        let style = CalderaCategoryStyle.style(for: .bankAccount)

        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            TutorialExampleBadge()

            HStack(spacing: AppSpacing.medium) {
                CalderaGradientIcon(style: style, size: 44, iconSize: 18)

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Linked checking")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)

                    Text("Updated just now")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.primaryText)
                }

                Spacer(minLength: AppSpacing.small)

                Text("$2,400")
                    .font(.headline.bold())
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
            }
        }
        .tutorialCard(darkGlowColor: style.primary)
    }
}

private struct TutorialReadyCard: View {

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    systemImage: "checkmark",
                    colors: CalderaCategoryStyle.style(for: .covered).gradient,
                    size: 36,
                    iconSize: 15
                )

                Text("Check what’s available")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Spacer()
            }

            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    systemImage: "lock.fill",
                    colors: CalderaCategoryStyle.style(for: .reserve).gradient,
                    size: 36,
                    iconSize: 15
                )

                Text("Set money aside")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Spacer()
            }

            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    systemImage: "calendar",
                    colors: CalderaCategoryStyle.style(for: .upcomingExpense).gradient,
                    size: 36,
                    iconSize: 15
                )

                Text("Stay ahead")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Spacer()
            }
        }
        .tutorialCard()
    }
}

private struct TutorialExampleBadge: View {

    @Environment(\.colorScheme) private var colorScheme

    let text: String

    init(_ text: String = "Example") {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.xxSmall)
            .background(
                Capsule()
                    .fill(CalderaVisualStyle.cardFill(colorScheme, lightOpacity: 0.72))
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.62), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct TutorialValueRow: View {

    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                systemImage: systemImage,
                colors: CalderaVisualStyle.iconGradient(for: color),
                size: 38,
                iconSize: 16
            )

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)

            Spacer(minLength: AppSpacing.small)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
                .monospacedDigit()
        }
    }
}

private struct TutorialOperator: View {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundColor(AppColors.primaryText)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private extension View {

    func tutorialCard(
        darkGlowColor: Color = AppColors.accent
    ) -> some View {
        self
            .padding(AppSpacing.card)
            .frame(maxWidth: .infinity)
            .calderaGlassCard(
                cornerRadius: AppRadii.panel,
                fillOpacity: 0.88,
                strokeOpacity: 0.72,
                shadowOpacity: 0.04,
                shadowRadius: 16,
                shadowY: 8,
                darkGlowColor: darkGlowColor
            )
    }
}
