import SwiftUI

struct OnboardingView: View {

    @AppStorage("hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    @State private var selectedPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Take Control of Your Money",
            description: "See what you can safely spend, protect savings goals, and plan ahead with confidence.",
            systemImage: "wallet.pass.fill",
            color: AppColors.spendable
        ),
        OnboardingPage(
            title: "Protect What Matters",
            description: "Separate everyday cash from savings, reserve funds, and future goals.",
            systemImage: "lock.shield.fill",
            color: AppColors.protected
        ),
        OnboardingPage(
            title: "Plan Before You Spend",
            description: "Plan around bills, income, and purchase impact before money gets tight.",
            systemImage: "calendar.badge.exclamationmark",
            color: AppColors.warning
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppColors.screenGradientTop,
                    AppColors.screenGradientBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: AppSpacing.large) {
                header

                TabView(selection: $selectedPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageCard(
                            page: pages[index]
                        )
                        .padding(.horizontal, AppSpacing.regular)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                controls
            }
            .padding(AppSpacing.regular)
        }
    }

    private var header: some View {
        HStack {
            Spacer()

            Button("Skip") {
                completeOnboarding()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppColors.secondaryText)
        }
    }

    private var controls: some View {
        VStack(spacing: AppSpacing.medium) {
            pageIndicators

            PrimaryButton(
                selectedPage == pages.count - 1
                ? "Get Started"
                : "Continue",
                systemImage: selectedPage == pages.count - 1
                ? "checkmark.circle.fill"
                : nil,
                fillsWidth: true
            ) {
                advance()
            }
        }
    }

    private var pageIndicators: some View {
        HStack(spacing: AppSpacing.xSmall) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(
                        index == selectedPage
                        ? pages[selectedPage].color
                        : AppColors.secondaryText.opacity(0.25)
                    )
                    .frame(
                        width: index == selectedPage ? 24 : 8,
                        height: 8
                    )
            }
        }
        .animation(
            .spring(
                response: 0.30,
                dampingFraction: 0.75
            ),
            value: selectedPage
        )
    }

    private func advance() {
        if selectedPage == pages.count - 1 {
            completeOnboarding()
        } else {
            withAnimation(
                .spring(
                    response: 0.35,
                    dampingFraction: 0.85
                )
            ) {
                selectedPage += 1
            }
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

private struct OnboardingPage {

    let title: String
    let description: String
    let systemImage: String
    let color: Color
}

private struct OnboardingPageCard: View {

    let page: OnboardingPage

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Spacer(minLength: AppSpacing.large)

            icon

            VStack(spacing: AppSpacing.medium) {
                Text(page.title)
                    .font(
                        .system(
                            size: 36,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundColor(AppColors.primaryText)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)

                Text(page.description)
                    .font(.body)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 320)
            }

            Spacer(minLength: AppSpacing.large)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.panel)
        .glassCard(
            cornerRadius: AppRadii.hero,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    page.color.opacity(0.08),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: AppShadows.softPanel
        )
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(page.color.opacity(0.14))
                .frame(width: 112, height: 112)

            Circle()
                .stroke(
                    AppColors.glassHighlight,
                    lineWidth: 1
                )
                .frame(width: 112, height: 112)

            Image(systemName: page.systemImage)
                .font(
                    .system(
                        size: 42,
                        weight: .semibold
                    )
                )
                .foregroundColor(page.color)
        }
    }
}
