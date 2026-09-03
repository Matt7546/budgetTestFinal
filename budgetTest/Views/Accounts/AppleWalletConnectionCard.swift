import SwiftUI

enum AppleWalletConnectionPresentation {
    static let title = "Apple Card and Savings"
    static let actionTitle = "Connect Apple Wallet"

    static func detail(
        availability: AppleWalletFinanceAvailability,
        authorizationStatus: AppleWalletFinanceAuthorizationStatus,
        isWorking: Bool
    ) -> String {
        if availability != .available {
            switch availability {
            case .setupRequired:
                return "Apple Wallet connection isn’t available in this build yet."
            case .unsupportedDevice:
                return "Apple Wallet connection requires a supported iPhone."
            case .financialDataUnavailable:
                return "No supported Apple Wallet financial data is available on this iPhone."
            case .available:
                break
            }
        }

        if isWorking {
            return "Waiting for Apple Wallet…"
        }

        switch authorizationStatus {
        case .authorized:
            return "Apple Wallet access is connected. Its balances and transactions aren’t included in Available to Spend yet."
        case .denied:
            return "Apple Wallet access is off. You can change access later in Settings."
        case .failed:
            return "Apple Wallet couldn’t be connected. Try again in a little bit."
        case .notDetermined,
             .unavailable:
            return "Allow Caldera to read balances and transactions you choose to share. Caldera does not move money or make payments."
        }
    }

    static func showsConnectAction(
        availability: AppleWalletFinanceAvailability,
        authorizationStatus: AppleWalletFinanceAuthorizationStatus
    ) -> Bool {
        guard availability == .available else {
            return false
        }

        return authorizationStatus == .notDetermined ||
            authorizationStatus == .failed ||
            authorizationStatus == .unavailable
    }
}

struct AppleWalletConnectionCard: View {
    let availability: AppleWalletFinanceAvailability
    let authorizationStatus: AppleWalletFinanceAuthorizationStatus
    let isWorking: Bool
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.small) {
                IconBadge(
                    systemImage: "apple.logo",
                    color: AppColors.primaryText,
                    size: 38,
                    iconSize: 17
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(AppleWalletConnectionPresentation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    Text(
                        AppleWalletConnectionPresentation.detail(
                            availability: availability,
                            authorizationStatus: authorizationStatus,
                            isWorking: isWorking
                        )
                    )
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if AppleWalletConnectionPresentation.showsConnectAction(
                availability: availability,
                authorizationStatus: authorizationStatus
            ) {
                SecondaryButton(
                    isWorking
                        ? "Connecting…"
                        : AppleWalletConnectionPresentation.actionTitle,
                    systemImage: "apple.logo",
                    cornerRadius: AppRadii.button,
                    fillsWidth: true
                ) {
                    connect()
                }
                .disabled(isWorking)
                .accessibilityHint(
                    "Opens Apple Wallet access controls. You choose what to share."
                )
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.88,
            strokeOpacity: 0.72,
            shadowOpacity: 0.026,
            shadowRadius: 12,
            shadowY: 5,
            darkGlowColor: AppColors.accent
        )
    }
}
