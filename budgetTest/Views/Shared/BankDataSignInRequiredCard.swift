import AuthenticationServices
import SwiftUI

struct BankDataSignInRequiredCard: View {

    @EnvironmentObject private var auth: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String
    let showsButton: Bool

    init(
        title: String = "Sign in to see bank data",
        message: String = "After Sign in with Apple, you can connect accounts and \(AppBrand.shortName) will show linked balances here.",
        showsButton: Bool = true
    ) {
        self.title = title
        self.message = message
        self.showsButton = showsButton
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(
                alignment: .top,
                spacing: AppSpacing.medium
            ) {
                CalderaGradientIcon(
                    systemImage: "person.crop.circle.badge.checkmark",
                    colors: CalderaVisualStyle.iconGradient(for: AppColors.accent),
                    size: 44,
                    iconSize: 18
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                    Text(message)
                        .font(.caption.weight(.medium))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if showsButton {
                authAction
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.88,
            strokeOpacity: 0.76,
            shadowOpacity: 0.045,
            shadowRadius: 18,
            shadowY: 8,
            darkGlowColor: AppColors.accentSecondary
        )
    }

    @ViewBuilder
    private var authAction: some View {
        switch auth.state {
        case .signingIn:
            HStack(spacing: AppSpacing.small) {
                ProgressView()
                    .tint(AppColors.accent)

                Text("Checking your account…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.xSmall)

        case .signedIn:
            Text("Signed in. You can connect accounts when you’re ready.")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.spendable)

        case .signedOut,
                .failed:
            SignInWithAppleButton(
                .signIn,
                onRequest: auth.configureAppleRequest,
                onCompletion: auth.handleAppleCompletion
            )
            .signInWithAppleButtonStyle(
                colorScheme == .dark ? .white : .black
            )
            .frame(height: 48)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AppRadii.button,
                    style: .continuous
                )
            )
            .accessibilityLabel("Sign in with Apple to see bank data")
        }
    }
}
