import SwiftUI

struct EmptyStateView: View {

    let systemImage: String
    let title: String
    let description: String
    let primaryActionTitle: String?
    let primaryAction: (() -> Void)?
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?
    let secondaryText: String?
    let color: Color

    init(
        systemImage: String,
        title: String,
        description: String,
        primaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        secondaryText: String? = nil,
        color: Color = AppColors.accent
    ) {
        self.systemImage = systemImage
        self.title = title
        self.description = description
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
        self.secondaryText = secondaryText
        self.color = color
    }

    var body: some View {
        VStack(
            alignment: .center,
            spacing: AppSpacing.small
        ) {
            icon

            VStack(spacing: AppSpacing.small) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 300)
            }

            actions
        }
        .padding(AppSpacing.card)
        .frame(
            maxWidth: .infinity,
            alignment: .center
        )
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.90,
            strokeOpacity: 0.76,
            shadowOpacity: 0.035,
            shadowRadius: 14,
            shadowY: 6,
            darkGlowColor: color
        )
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: 58, height: 58)

            Image(systemName: systemImage)
                .font(
                    .system(
                        size: 24,
                        weight: .semibold
                    )
                )
                .foregroundColor(color)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if primaryActionTitle != nil ||
            secondaryActionTitle != nil ||
            secondaryText != nil {

            VStack(spacing: AppSpacing.small) {
                if let primaryActionTitle,
                   let primaryAction {

                    PrimaryButton(
                        primaryActionTitle,
                        trailingSystemImage: nil,
                        cornerRadius: AppRadii.button,
                        fillsWidth: true,
                        action: primaryAction
                    )
                }

                if let secondaryActionTitle,
                   let secondaryAction {

                    SecondaryButton(
                        secondaryActionTitle,
                        cornerRadius: AppRadii.button,
                        fillsWidth: true,
                        action: secondaryAction
                    )
                }

                if let secondaryText {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, AppSpacing.xSmall)
        }
    }
}
