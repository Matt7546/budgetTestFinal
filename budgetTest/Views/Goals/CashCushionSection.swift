import SwiftUI

enum CashCushionAdjustmentMode: String, Identifiable, Equatable {
    case add
    case use

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .add:
            return "Add money"
        case .use:
            return "Use money"
        }
    }

    var amountSubtitle: String {
        switch self {
        case .add:
            return "Amount to set aside in Cash Cushion."
        case .use:
            return "Amount to return to Available to Spend."
        }
    }

    var headerSubtitle: String {
        switch self {
        case .add:
            return "Keep flexible money out of everyday spending."
        case .use:
            return "Move flexible money back into Available to Spend in your plan."
        }
    }
}

struct CashCushionBalanceCard: View {
    let balance: Double
    let addAction: () -> Void
    let useAction: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let style = CalderaCategoryStyle.style(for: .reserve)
    private let presentation = SetAsideSectionPresentation.content(
        for: .cashCushion
    )

    private var currentBalance: Double {
        CashCushionBalancePolicy.normalized(balance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: style,
                    size: 36,
                    iconSize: 15
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(presentation.title)
                        .font(.headline)
                        .foregroundColor(
                            CalderaVisualStyle.primaryText(colorScheme)
                        )
                        .accessibilityAddTraits(.isHeader)

                    Text("\(AppFormatters.currency(currentBalance)) set aside")
                        .font(.title3.weight(.bold))
                        .foregroundColor(style.primary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Text(presentation.purpose)
                .font(.subheadline)
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(colorScheme)
                )
                .fixedSize(horizontal: false, vertical: true)

            actionControls
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.78,
            strokeOpacity: 0.62,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: style.primary
        )
    }

    @ViewBuilder
    private var actionControls: some View {
        if currentBalance > 0 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.small) {
                    adjustmentButton(
                        title: "Add money",
                        systemImage: "plus.circle.fill",
                        isPrimary: true,
                        action: addAction
                    )

                    adjustmentButton(
                        title: "Use money",
                        systemImage: "minus.circle",
                        isPrimary: false,
                        action: useAction
                    )
                }

                VStack(spacing: AppSpacing.small) {
                    adjustmentButton(
                        title: "Add money",
                        systemImage: "plus.circle.fill",
                        isPrimary: true,
                        action: addAction
                    )

                    adjustmentButton(
                        title: "Use money",
                        systemImage: "minus.circle",
                        isPrimary: false,
                        action: useAction
                    )
                }
            }
        } else {
            adjustmentButton(
                title: "Add money",
                systemImage: "plus.circle.fill",
                isPrimary: true,
                action: addAction
            )
        }
    }

    private func adjustmentButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isPrimary ? .white : style.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, AppSpacing.medium)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isPrimary
                                ? style.primary
                                : style.primary.opacity(0.10)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            style.primary.opacity(0.16),
                            lineWidth: 1
                        )
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct CashCushionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: CashCushionAdjustmentMode
    let reserveBalance: Double
    let submitAction: (Double) -> Void

    @State private var amountText = ""
    @FocusState private var isAmountFocused: Bool

    private let style = CalderaCategoryStyle.style(for: .reserve)

    private var currentBalance: Double {
        CashCushionBalancePolicy.normalized(reserveBalance)
    }

    private var amount: Double? {
        guard let value = MoneyAmountParser.parse(amountText),
              value.isFinite,
              value > 0 else {
            return nil
        }

        return value
    }

    private var exceedsCurrentBalance: Bool {
        guard mode == .use,
              let amount else {
            return false
        }

        return amount > currentBalance
    }

    private var canSubmit: Bool {
        amount != nil && !exceedsCurrentBalance
    }

    var body: some View {
        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                backgroundStyle: .editorModal(.savingsGoal),
                contentPadding: .all,
                contentSpacing: AppSpacing.regular
            ) {
                ModalHeaderView(
                    eyebrow: "Cash Cushion",
                    title: mode.title,
                    subtitle: mode.headerSubtitle,
                    systemImage: style.icon,
                    color: style.primary
                )

                currentAmountCard
                amountEntryCard
                helperCard
                actionCard
                validationMessage
            }
            .keyboardDismissToolbar()
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel("Cancel Cash Cushion update")
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isAmountFocused = true
                }
            }
        }
    }

    private var currentAmountCard: some View {
        CalderaEditorFormCard(
            title: "Current Cash Cushion",
            systemImage: style.icon,
            color: style.primary
        ) {
            Text("\(AppFormatters.currency(currentBalance)) set aside")
                .font(
                    .system(
                        size: 34,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundColor(style.primary)
                .minimumScaleFactor(0.68)
                .fixedSize(horizontal: false, vertical: true)

            Text("Flexible money for the unexpected")
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var amountEntryCard: some View {
        CalderaEditorFormCard(
            title: "Amount",
            systemImage: "dollarsign.circle.fill",
            color: style.primary
        ) {
            AmountEntryField(
                title: "Dollar Amount",
                subtitle: mode.amountSubtitle,
                placeholder: "0.00",
                text: $amountText,
                style: style,
                focus: $isAmountFocused,
                accessibilityLabel: "Cash Cushion amount"
            )
        }
    }

    private var helperCard: some View {
        CalderaEditorFormCard(
            title: "How this works",
            systemImage: "info.circle.fill",
            color: style.primary
        ) {
            Text("Set Aside is virtual. This only updates your plan; no money moves.")
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionCard: some View {
        CalderaEditorFormCard(
            title: mode.title,
            systemImage: mode == .add
                ? "plus.circle.fill"
                : "minus.circle.fill",
            color: style.primary
        ) {
            Button(action: submit) {
                Label(
                    mode.title,
                    systemImage: mode == .add
                        ? "plus.circle.fill"
                        : "minus.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, AppSpacing.medium)
                .background(
                    Capsule(style: .continuous)
                        .fill(style.primary)
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.54)
            .accessibilityLabel(mode.title)
        }
    }

    @ViewBuilder
    private var validationMessage: some View {
        if exceedsCurrentBalance {
            Text(
                "Enter an amount no greater than \(AppFormatters.currency(currentBalance))."
            )
            .font(.caption.weight(.medium))
            .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
            .frame(maxWidth: .infinity, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
        } else if amount == nil {
            Text("Enter an amount to update Cash Cushion.")
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func submit() {
        guard canSubmit,
              let amount else {
            return
        }

        submitAction(amount)
        dismiss()
    }
}
