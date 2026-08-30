import SwiftUI

struct OnboardingView: View {

    @AppStorage("hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    @Environment(\.colorScheme) private var colorScheme

    private let setupSteps: [OnboardingSetupStep] = [
        OnboardingSetupStep(
            number: "1",
            title: "Sign in with Apple",
            description: "Keep your \(AppBrand.shortName) account private and scoped to you.",
            systemImage: "apple.logo",
            colors: [
                Color(red: 0.42, green: 0.24, blue: 1.00),
                Color(red: 0.93, green: 0.18, blue: 0.78)
            ]
        ),
        OnboardingSetupStep(
            number: "2",
            title: "Connect banks securely",
            description: "Connect accounts to show linked balances.",
            systemImage: CalderaCategoryStyle.style(for: .bankAccount).icon,
            colors: CalderaCategoryStyle.style(for: .bankAccount).gradient
        ),
        OnboardingSetupStep(
            number: "3",
            title: "Set money aside",
            description: "For Savings Goals, Upcoming Expenses, and Payment Plans.",
            systemImage: CalderaCategoryStyle.style(for: .reserve).icon,
            colors: CalderaCategoryStyle.style(for: .reserve).gradient
        )
    ]

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.card) {
                    hero
                    setupCard
                    actionButton
                }
                .padding(.horizontal, AppSpacing.screen)
                .padding(.top, AppSpacing.large)
                .padding(.bottom, AppSpacing.regular)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: CalderaCategoryStyle.style(for: .safeToSpend),
                size: 52,
                iconSize: 23
            )

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Welcome to \(AppBrand.shortName)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .minimumScaleFactor(0.72)
                    .lineLimit(2)

                Text("A calmer way to know what is Available to Spend, what is set aside, and what is coming next.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Setup takes a minute")
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text("Start with secure sign-in, then connect accounts when you are ready.")
                    .font(.caption)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppSpacing.regular) {
                ForEach(setupSteps) { step in
                    OnboardingSetupStepRow(step: step)
                }
            }
        }
        .padding(AppSpacing.cardLarge)
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

    private var actionButton: some View {
        VStack(spacing: AppSpacing.small) {
            PrimaryButton(
                "Continue",
                systemImage: "sparkles",
                fillsWidth: true,
                centersTitle: true
            ) {
                completeOnboarding()
            }

            Text("You can finish setup from More or Linked Accounts.")
                .font(.footnote.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
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
                    size: 46,
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
                    .font(.caption)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.medium)
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
