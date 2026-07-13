import AuthenticationServices
import SwiftUI

struct DashboardSetupChecklistCard: View {
    let progress: DashboardSetupProgress
    let isSigningIn: Bool
    let signInRequest: (ASAuthorizationAppleIDRequest) -> Void
    let signInCompletion: (Result<ASAuthorization, Error>) -> Void
    let continueAction: (DashboardSetupStep) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            header

            if isExpanded {
                progressIndicator
                checklistRows
                nextStep

                Button("Collapse") {
                    isExpanded = false
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse Caldera setup")
            } else {
                collapsedActions
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.68,
            shadowOpacity: 0.026,
            shadowRadius: 14,
            shadowY: 6,
            darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
        )
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: CalderaCategoryStyle.style(for: .safeToSpend),
                size: 40,
                iconSize: 16
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Your Caldera setup")
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .accessibilityAddTraits(.isHeader)

                Text(progress.progressAccessibilityValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(
                        CalderaCategoryStyle.style(for: .safeToSpend).primary
                    )
                    .accessibilityHidden(true)
            }

            Spacer(minLength: AppSpacing.small)

            if !isExpanded {
                Button("Show") {
                    isExpanded = true
                }
                .font(.caption.weight(.bold))
                .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
                .buttonStyle(.plain)
                .accessibilityLabel("Show Caldera setup steps")
            }
        }
    }

    private var progressIndicator: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            ProgressView(
                value: Double(progress.completedCount),
                total: Double(progress.totalCount)
            )
            .tint(CalderaCategoryStyle.style(for: .safeToSpend).primary)
            .accessibilityLabel("Caldera setup progress")
            .accessibilityValue(progress.progressAccessibilityValue)

            Text("Each completed step helps Caldera make your plan clearer.")
                .font(.caption)
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var checklistRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(progress.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                }

                checklistRow(item)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func checklistRow(
        _ item: DashboardSetupProgressItem
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Image(
                systemName: item.isComplete
                    ? "checkmark.circle.fill"
                    : item.step.systemImage
            )
            .font(.body.weight(.semibold))
            .foregroundColor(
                item.isComplete
                    ? CalderaCategoryStyle.style(for: .covered).primary
                    : CalderaCategoryStyle.style(for: .safeToSpend).primary
            )
            .frame(width: 22)

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(item.step.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.isComplete ? "Complete" : item.step.detail)
                    .font(.caption)
                    .foregroundColor(
                        item.isComplete
                            ? CalderaCategoryStyle.style(for: .covered).primary
                            : CalderaVisualStyle.secondaryText(colorScheme)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, AppSpacing.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder
    private var nextStep: some View {
        if let nextItem = progress.nextIncompleteItem {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(nextItem.step.nextMessage)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                nextStepControl(for: nextItem)
            }
        }
    }

    @ViewBuilder
    private var collapsedActions: some View {
        if let nextItem = progress.nextIncompleteItem {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(nextItem.step.nextMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                nextStepControl(for: nextItem)
            }
        }
    }

    @ViewBuilder
    private func nextStepControl(
        for item: DashboardSetupProgressItem
    ) -> some View {
        if item.step == .signIn {
            if isSigningIn {
                ProgressView("Signing in…")
                    .font(.footnote.weight(.semibold))
                    .tint(CalderaCategoryStyle.style(for: .safeToSpend).primary)
            } else {
                SignInWithAppleButton(
                    .signIn,
                    onRequest: signInRequest,
                    onCompletion: signInCompletion
                )
                .signInWithAppleButtonStyle(
                    colorScheme == .dark ? .white : .black
                )
                .frame(maxWidth: .infinity)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: AppRadii.button,
                        style: .continuous
                    )
                )
                .accessibilityLabel("Sign in with Apple to continue setup")
            }
        } else {
            Button {
                continueAction(item.step)
            } label: {
                HStack(spacing: AppSpacing.xSmall) {
                    Text("Continue setup")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.footnote.weight(.bold))
                .foregroundColor(item.step == .connectBank
                    ? CalderaCategoryStyle.style(for: .bankAccount).primary
                    : CalderaCategoryStyle.style(for: .safeToSpend).primary)
                .padding(.horizontal, AppSpacing.regular)
                .padding(.vertical, AppSpacing.medium)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            CalderaCategoryStyle.style(for: .safeToSpend).primary
                                .opacity(colorScheme == .dark ? 0.18 : 0.12)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue setup")
            .accessibilityHint(item.step.nextMessage)
        }
    }
}
