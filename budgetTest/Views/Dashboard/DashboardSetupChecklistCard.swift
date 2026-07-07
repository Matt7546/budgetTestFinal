import AuthenticationServices
import SwiftUI

struct DashboardSetupChecklistCard: View {

    let isSignedIn: Bool
    let isSigningIn: Bool
    let hasLinkedBanks: Bool
    let hasCashCushion: Bool
    let hasUpcomingExpense: Bool
    let hasGoal: Bool
    let hasDebtPayoff: Bool
    let signInRequest: (ASAuthorizationAppleIDRequest) -> Void
    let signInCompletion: (Result<ASAuthorization, Error>) -> Void
    let connectBanksAction: () -> Void
    let cashCushionAction: () -> Void
    let upcomingExpenseAction: () -> Void
    let goalAction: () -> Void
    let debtPayoffAction: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    private var completedCount: Int {
        checklistItems.filter(\.isComplete).count
    }

    private var nextIncompleteItem: DashboardSetupChecklistItem? {
        checklistItems.first {
            !$0.isComplete
        }
    }

    private var checklistItems: [DashboardSetupChecklistItem] {
        [
            DashboardSetupChecklistItem(
                step: .signIn,
                title: "Sign in with Apple",
                subtitle: "Keep Bank Sync tied to your \(AppBrand.shortName) account.",
                style: CalderaCategoryStyle.style(for: .safeToSpend),
                isComplete: isSignedIn,
                isEnabled: !isSignedIn && !isSigningIn,
                actionTitle: "Sign in"
            ),
            DashboardSetupChecklistItem(
                step: .connectBanks,
                title: "Connect a bank account",
                subtitle: "Connect balances so Available to Spend can use linked cash.",
                style: CalderaCategoryStyle.style(for: .bankAccount),
                isComplete: hasLinkedBanks,
                isEnabled: isSignedIn,
                actionTitle: isSignedIn ? "Connect" : "Sign in first"
            ),
            DashboardSetupChecklistItem(
                step: .cashCushion,
                title: "Create Cash Cushion",
                subtitle: "Set aside flexible money you can move anytime.",
                style: CalderaCategoryStyle.style(for: .reserve),
                isComplete: hasCashCushion,
                isEnabled: true,
                actionTitle: "Open Savings"
            ),
            DashboardSetupChecklistItem(
                step: .upcomingExpense,
                title: "Add Upcoming Expense",
                subtitle: "Add a bill, subscription, or planned payment.",
                style: CalderaCategoryStyle.style(for: .upcomingExpense),
                isComplete: hasUpcomingExpense,
                isEnabled: true,
                actionTitle: "Add expense"
            ),
            DashboardSetupChecklistItem(
                step: .goal,
                title: "Create Savings Goal",
                subtitle: "Name what you're saving for.",
                style: CalderaCategoryStyle.style(for: .savingsGoal),
                isComplete: hasGoal,
                isEnabled: true,
                actionTitle: "Create goal"
            ),
            DashboardSetupChecklistItem(
                step: .debtPayoff,
                title: "Debt Payoff",
                subtitle: "Plan a payment in your spending plan.",
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                isComplete: hasDebtPayoff,
                isEnabled: true,
                actionTitle: "Plan a Payment"
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? AppSpacing.card : AppSpacing.medium) {
            header

            if isExpanded {
                checklistRows
            } else if let nextIncompleteItem {
                compactNextStepRow(nextIncompleteItem)
            }
        }
        .padding(isExpanded ? AppSpacing.card : AppSpacing.regular)
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
        Button {
            isExpanded.toggle()
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: CalderaCategoryStyle.style(for: .safeToSpend),
                    size: isExpanded ? 42 : 38,
                    iconSize: 17
                )

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("Finish setting up \(AppBrand.shortName)")
                        .font(.headline)
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                    Text("Set aside money, add what's coming up, and see what's Available to Spend.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .lineLimit(isExpanded ? nil : 1)
                }

                Spacer(minLength: 0)

                HStack(spacing: AppSpacing.xSmall) {
                    Text("\(completedCount)/\(checklistItems.count)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(CalderaCategoryStyle.style(for: .safeToSpend).primary)
                        .padding(.horizontal, AppSpacing.medium)
                        .padding(.vertical, AppSpacing.xSmall)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CalderaCategoryStyle.style(for: .safeToSpend).primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                        )

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse setup checklist" : "Expand setup checklist")
    }

    private var checklistRows: some View {
        VStack(spacing: AppSpacing.small) {
            checklistRow(checklistItems[0]) {
                signInControl()
            }

            checklistRow(checklistItems[1])
            checklistRow(checklistItems[2])
            checklistRow(checklistItems[3])
            checklistRow(checklistItems[4])
            checklistRow(checklistItems[5])
        }
    }

    @ViewBuilder
    private func signInControl(
        fillsWidth: Bool = false
    ) -> some View {
        Group {
            if isSignedIn {
                completedBadge
            } else if isSigningIn {
                ProgressView()
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
                .frame(
                    maxWidth: fillsWidth ? .infinity : 190
                )
                .frame(
                    width: fillsWidth ? nil : 190,
                    height: fillsWidth ? 50 : 46
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: AppRadii.button,
                        style: .continuous
                    )
                )
                .accessibilityLabel("Sign in with Apple")
            }
        }
    }

    private var completedBadge: some View {
        Image(systemName: CalderaCategoryStyle.style(for: .covered).icon)
            .font(.headline.weight(.bold))
            .foregroundColor(CalderaCategoryStyle.style(for: .covered).primary)
            .accessibilityLabel("Complete")
    }

    @ViewBuilder
    private func checklistRow<Trailing: View>(
        _ item: DashboardSetupChecklistItem,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: item.isComplete
                    ? CalderaCategoryStyle.style(for: .covered)
                    : item.style,
                size: 36,
                iconSize: 15
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .strikethrough(item.isComplete, color: CalderaVisualStyle.secondaryText(colorScheme))

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.small)

            trailing()
        }
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: colorScheme == .dark ? 0.82 : 0.86,
            strokeOpacity: 0.68,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: item.style.primary
        )
        .accessibilityElement(children: .combine)
    }

    private func checklistRow(
        _ item: DashboardSetupChecklistItem
    ) -> some View {
        checklistRow(
            item
        ) {
            if item.isComplete {
                completedBadge
            } else {
                Button {
                    guard item.isEnabled else {
                        return
                    }

                    performAction(for: item)
                } label: {
                    HStack(spacing: AppSpacing.xxSmall) {
                        Text(item.actionTitle)

                        if item.isEnabled {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(
                        item.isEnabled
                            ? item.style.primary
                            : CalderaVisualStyle.secondaryText(colorScheme)
                    )
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.xSmall)
                    .frame(minHeight: 34)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                item.isEnabled
                                    ? item.style.primary.opacity(colorScheme == .dark ? 0.18 : 0.12)
                                    : Color.gray.opacity(colorScheme == .dark ? 0.18 : 0.10)
                            )
                    )
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .accessibilityLabel(item.actionTitle)
            }
        }
    }

    private func compactNextStepRow(
        _ item: DashboardSetupChecklistItem
    ) -> some View {
        Group {
            if item.step == .signIn {
                compactNextStepStackedRow(item)
            } else {
                ViewThatFits(in: .horizontal) {
                    compactNextStepHorizontalRow(item)

                    compactNextStepStackedRow(item)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(AppSpacing.medium)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: colorScheme == .dark ? 0.82 : 0.86,
            strokeOpacity: 0.68,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: item.style.primary
        )
    }

    private func compactNextStepHorizontalRow(
        _ item: DashboardSetupChecklistItem
    ) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: item.style,
                size: 34,
                iconSize: 14
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Next step")
                    .font(.caption.weight(.bold))
                    .foregroundColor(item.style.primary)

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.small)

            compactActionButton(for: item)
        }
    }

    private func compactNextStepStackedRow(
        _ item: DashboardSetupChecklistItem
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: item.style,
                    size: 34,
                    iconSize: 14
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Next step")
                        .font(.caption.weight(.bold))
                        .foregroundColor(item.style.primary)

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if item.step == .signIn {
                signInControl(fillsWidth: true)
            } else {
                compactActionButton(
                    for: item,
                    fillsWidth: true
                )
            }
        }
    }

    private func compactActionButton(
        for item: DashboardSetupChecklistItem,
        fillsWidth: Bool = false
    ) -> some View {
        Button {
            guard item.isEnabled else {
                return
            }

            performAction(for: item)
        } label: {
            HStack(spacing: AppSpacing.xxSmall) {
                Text(item.actionTitle)

                if item.isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
            }
            .font(.caption.weight(.bold))
            .foregroundColor(
                item.isEnabled
                    ? item.style.primary
                    : CalderaVisualStyle.secondaryText(colorScheme)
            )
            .frame(
                maxWidth: fillsWidth ? .infinity : nil,
                alignment: .center
            )
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.xSmall)
            .frame(minHeight: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        item.isEnabled
                            ? item.style.primary.opacity(colorScheme == .dark ? 0.18 : 0.12)
                            : Color.gray.opacity(colorScheme == .dark ? 0.18 : 0.10)
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
    }

    private func performAction(
        for item: DashboardSetupChecklistItem
    ) {
        switch item.step {
        case .signIn:
            break

        case .connectBanks:
            connectBanksAction()

        case .cashCushion:
            cashCushionAction()

        case .upcomingExpense:
            upcomingExpenseAction()

        case .goal:
            goalAction()

        case .debtPayoff:
            debtPayoffAction()
        }
    }
}

private enum DashboardSetupChecklistStep {
    case signIn
    case connectBanks
    case cashCushion
    case upcomingExpense
    case goal
    case debtPayoff
}

private struct DashboardSetupChecklistItem {

    let step: DashboardSetupChecklistStep
    let title: String
    let subtitle: String
    let style: CalderaCategoryStyle
    let isComplete: Bool
    let isEnabled: Bool
    let actionTitle: String
}
