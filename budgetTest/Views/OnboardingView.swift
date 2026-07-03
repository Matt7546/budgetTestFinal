import SwiftUI

struct OnboardingView: View {

    @AppStorage("hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    @Environment(\.colorScheme) private var colorScheme

    private let setupSteps: [OnboardingSetupStep] = [
        OnboardingSetupStep(
            number: "1",
            title: "Sign in with Apple",
            description: "Keep your Caldera account private and scoped to you.",
            systemImage: "apple.logo",
            colors: [
                Color(red: 0.42, green: 0.24, blue: 1.00),
                Color(red: 0.93, green: 0.18, blue: 0.78)
            ]
        ),
        OnboardingSetupStep(
            number: "2",
            title: "Connect banks securely",
            description: "Use Plaid to sync balances for your spending picture.",
            systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
            colors: CalderaCategoryStyle.style(for: .bankAccount).gradient
        ),
        OnboardingSetupStep(
            number: "3",
            title: "Set money aside",
            description: "For goals, bills, Cash Cushion, and debt payoff.",
            systemImage: CalderaCategoryStyle.style(for: .reserve).icon,
            colors: CalderaCategoryStyle.style(for: .reserve).gradient
        )
    ]

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.screen) {
                    hero
                    setupCard
                    reassuranceCard
                    actionButton
                }
                .padding(.horizontal, AppSpacing.screen)
                .padding(.top, AppSpacing.emptyState)
                .padding(.bottom, AppSpacing.emptyState)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            CalderaGradientIcon(
                style: CalderaCategoryStyle.style(for: .safeToSpend),
                size: 58,
                iconSize: 25
            )

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Welcome to Caldera")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .minimumScaleFactor(0.72)
                    .lineLimit(2)

                Text("A calmer way to know what is Available to Spend, what is set aside, and what is coming next.")
                    .font(.body.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, AppSpacing.large)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Setup takes a minute")
                    .font(.title3.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text("Start with secure sign-in, then connect accounts when you are ready.")
                    .font(.subheadline)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppSpacing.regular) {
                ForEach(setupSteps) { step in
                    OnboardingSetupStepRow(step: step)
                }
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.hero,
            fillOpacity: 0.90,
            strokeOpacity: 0.76,
            shadowOpacity: 0.045,
            shadowRadius: 22,
            shadowY: 10,
            darkGlowColor: AppColors.accent
        )
    }

    private var reassuranceCard: some View {
        HStack(alignment: .top, spacing: AppSpacing.regular) {
            CalderaGradientIcon(
                systemImage: "checkmark.seal.fill",
                colors: [
                    AppColors.positive,
                    AppColors.accentSecondary
                ],
                size: 44,
                iconSize: 18
            )

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("You stay in control")
                    .font(.headline)
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text("No bank data appears until you sign in and connect accounts. You can disconnect banks or delete your account from More.")
                    .font(.subheadline)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.86,
            strokeOpacity: 0.70,
            shadowOpacity: 0.035,
            shadowRadius: 18,
            shadowY: 8,
            darkGlowColor: AppColors.positive
        )
    }

    private var actionButton: some View {
        VStack(spacing: AppSpacing.medium) {
            PrimaryButton(
                "Continue",
                systemImage: "sparkles",
                fillsWidth: true
            ) {
                completeOnboarding()
            }

            Text("You can finish setup from More or Linked Accounts.")
                .font(.footnote.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

private struct OnboardingSetupStep: Identifiable {

    let id = UUID()
    let number: String
    let title: String
    let description: String
    let systemImage: String
    let colors: [Color]
}

private struct OnboardingSetupStepRow: View {

    @Environment(\.colorScheme) private var colorScheme

    let step: OnboardingSetupStep

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.regular) {
            ZStack(alignment: .bottomTrailing) {
                CalderaGradientIcon(
                    systemImage: step.systemImage,
                    colors: step.colors,
                    size: 50,
                    iconSize: 20
                )

                Text(step.number)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.42 : 0.28))
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    }
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(step.title)
                    .font(.headline)
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text(step.description)
                    .font(.subheadline)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: 0.84,
            strokeOpacity: 0.68,
            shadowOpacity: 0.025,
            shadowRadius: 12,
            shadowY: 5,
            darkGlowColor: step.colors.first ?? AppColors.accent
        )
    }
}
