import SwiftUI

struct CalderaConfirmationBanner: View {

    let message: String
    var systemImage: String = "checkmark.circle.fill"
    var color: Color = CalderaCategoryStyle.style(for: .covered).primary
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: AppSpacing.xSmall)

            if let actionTitle,
               let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(color)
                    .buttonStyle(.plain)
                    .accessibilityLabel(actionTitle)
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.button,
            fillOpacity: 0.94,
            strokeOpacity: 0.78,
            shadowOpacity: 0.05,
            shadowRadius: 18,
            shadowY: 8,
            darkGlowColor: color
        )
    }
}

extension View {

    func calderaConfirmationOverlay(
        message: String?,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        overlay(alignment: .top) {
            if let message, !message.isEmpty {
                CalderaConfirmationBanner(
                    message: message,
                    actionTitle: actionTitle,
                    action: action
                )
                    .padding(.horizontal, AppSpacing.regular)
                    .padding(.top, AppSpacing.regular)
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                    )
                    .zIndex(50)
            }
        }
        .animation(
            .easeInOut(duration: 0.22),
            value: message
        )
    }
}
