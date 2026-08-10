import AuthenticationServices
import SwiftUI

struct DashboardSetupChecklistCard: View {
    let progress: DashboardSetupProgress
    let isSigningIn: Bool
    let signInRequest: (ASAuthorizationAppleIDRequest) -> Void
    let signInCompletion: (Result<ASAuthorization, Error>) -> Void
    let continueAction: (DashboardSetupStep) -> Void
    let markCompletedAction: (DashboardSetupStep) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            header

            if presentation.showsProgressRow {
                setupProgressRow
            }

            if presentation.showsStepDetailsAndActions {
                currentStep
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
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(isExpanded ? "Setting up Caldera" : "Finish setting up Caldera")
                    .font(.headline.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .accessibilityAddTraits(.isHeader)

                if presentation.showsProgressSummary {
                    Text(progress.progressAccessibilityValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(
                            CalderaCategoryStyle.style(for: .safeToSpend).primary
                        )
                        .accessibilityHidden(true)
                }
            }

            Spacer(minLength: AppSpacing.small)

            if isExpanded {
                Button {
                    isExpanded = false
                } label: {
                    HStack(spacing: 4) {
                        Text("Collapse")
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.bold))
                    }
                }
                .font(.caption.weight(.bold))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse Caldera setup")
            } else {
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

    private var setupProgressRow: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(Array(progress.items.enumerated()), id: \.element.id) { index, item in
                setupStepMarker(item, index: index)

                if index < progress.items.count - 1 {
                    Capsule(style: .continuous)
                        .stroke(
                            connectorColor(after: item),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                        )
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 17)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, AppSpacing.xxSmall)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Caldera setup progress")
        .accessibilityValue(progress.progressAccessibilityValue)
    }

    private func setupStepMarker(
        _ item: DashboardSetupProgressItem,
        index: Int
    ) -> some View {
        let isCurrent = item.id == progress.nextIncompleteItem?.id

        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(markerFill(for: item, isCurrent: isCurrent))
                    .frame(width: isCurrent ? 36 : 22, height: isCurrent ? 36 : 22)
                    .overlay {
                        Circle()
                            .stroke(
                                markerStroke(for: item, isCurrent: isCurrent),
                                lineWidth: isCurrent ? 1.5 : 1
                            )
                    }

                if item.isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(Color.white)
                } else {
                    Text("\(index + 1)")
                        .font(isCurrent ? .subheadline.weight(.bold) : .caption2.weight(.bold))
                        .foregroundColor(
                            isCurrent
                                ? Color.white
                                : CalderaVisualStyle.secondaryText(colorScheme)
                        )
                }
            }
            .frame(height: 36)

            Text(compactLabel(for: item.step))
                .font(.caption2.weight(isCurrent ? .bold : .semibold))
                .foregroundColor(
                    isCurrent
                        ? CalderaVisualStyle.primaryText(colorScheme)
                        : CalderaVisualStyle.secondaryText(colorScheme)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: 50)
        }
        .frame(width: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stepAccessibilityLabel(item, index: index, isCurrent: isCurrent))
    }

    @ViewBuilder
    private var currentStep: some View {
        if let nextItem = progress.nextIncompleteItem {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(nextItem.step.title)
                    .font(.title3.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                Text(nextItem.step.detail)
                    .font(.subheadline)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                setupActionRow(for: nextItem)
                    .padding(.top, AppSpacing.xxSmall)
            }
            .padding(.top, AppSpacing.xxSmall)
            .accessibilityElement(children: .contain)
        }
    }

    private var presentation: DashboardSetupChecklistPresentation {
        DashboardSetupChecklistPresentation(isExpanded: isExpanded)
    }

    private func compactLabel(for step: DashboardSetupStep) -> String {
        switch step {
        case .downloadCaldera:
            return "Download"
        case .signIn:
            return "Sign in"
        case .connectBank:
            return "Connect"
        case .chooseSpendingAccounts:
            return "Accounts"
        case .setAside:
            return "Set Aside"
        case .addToPlan:
            return "Expense"
        }
    }

    private func markerFill(
        for item: DashboardSetupProgressItem,
        isCurrent: Bool
    ) -> Color {
        if item.isComplete {
            return CalderaCategoryStyle.style(for: .covered).primary
        }

        if isCurrent {
            return CalderaCategoryStyle.style(for: .safeToSpend).primary
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.09)
            : Color.white.opacity(0.68)
    }

    private func markerStroke(
        for item: DashboardSetupProgressItem,
        isCurrent: Bool
    ) -> Color {
        if item.isComplete || isCurrent {
            return Color.white.opacity(colorScheme == .dark ? 0.30 : 0.76)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.16)
            : CalderaVisualStyle.secondaryText(colorScheme).opacity(0.20)
    }

    private func connectorColor(after item: DashboardSetupProgressItem) -> Color {
        item.isComplete
            ? CalderaCategoryStyle.style(for: .covered).primary.opacity(0.54)
            : CalderaVisualStyle.secondaryText(colorScheme).opacity(0.32)
    }

    private func stepAccessibilityLabel(
        _ item: DashboardSetupProgressItem,
        index: Int,
        isCurrent: Bool
    ) -> String {
        let state: String

        if item.isComplete {
            state = "complete"
        } else if isCurrent {
            state = "current"
        } else {
            state = "upcoming"
        }

        return "Step \(index + 1) of \(progress.totalCount), \(item.step.title), \(state). \(item.step.detail)"
    }

    private func setupActionRow(
        for item: DashboardSetupProgressItem
    ) -> some View {
        HStack(spacing: AppSpacing.small) {
            Button {
                markCompletedAction(item.step)
            } label: {
                Text("Mark completed")
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .padding(.horizontal, AppSpacing.small)
                    .padding(.vertical, AppSpacing.medium)
                    .frame(maxWidth: .infinity)
                    .background {
                        Capsule(style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.08)
                                    : Color.white.opacity(0.64)
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(
                                        CalderaVisualStyle.secondaryText(colorScheme)
                                            .opacity(0.18),
                                        lineWidth: 1
                                    )
                            }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(item.step.title) completed")
            .accessibilityHint("Updates setup checklist progress only")

            nextStepControl(for: item)
                .frame(maxWidth: .infinity)
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

struct DashboardSetupChecklistPresentation {
    let isExpanded: Bool

    var showsProgressSummary: Bool {
        isExpanded
    }

    var showsProgressRow: Bool {
        true
    }

    var showsStepDetailsAndActions: Bool {
        isExpanded
    }

    var showsManualCompletionAction: Bool {
        isExpanded
    }

    var showsPrimaryAction: Bool {
        isExpanded
    }
}
