import SwiftUI

struct CashCushionEditorView: View {

    @Environment(\.dismiss) private var dismiss

    let reserveBalance: Double
    let addAction: (Double) -> Void
    let useAction: (Double) -> Void

    @State private var amountText = ""
    @FocusState private var isAmountFocused: Bool

    private let style = CalderaCategoryStyle.style(for: .reserve)

    private var amount: Double? {
        guard let value = MoneyAmountParser.parse(amountText),
              value > 0 else {
            return nil
        }

        return value
    }

    private var canUseMoney: Bool {
        amount != nil && reserveBalance > 0
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
                    title: "Cash Cushion",
                    subtitle: "Adjust the flexible buffer kept out of Available to Spend.",
                    systemImage: style.icon,
                    color: style.primary
                )

                currentAmountCard

                amountEntryCard

                helperCard

                actionCard

                if amount == nil {
                    Text("Enter an amount to update Cash Cushion.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .keyboardDismissToolbar()
            .navigationTitle("Cash Cushion")
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
            Text(AppFormatters.currency(reserveBalance))
                .font(
                    .system(
                        size: 38,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundColor(style.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text("Flexible buffer kept out of Available to Spend.")
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
                subtitle: "Add to Cash Cushion or use part of it in your plan.",
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
            title: "Update Cash Cushion",
            systemImage: "slider.horizontal.3",
            color: style.primary
        ) {
            VStack(spacing: AppSpacing.small) {
                cashCushionActionButton(
                    title: "Add Money",
                    systemImage: "plus.circle.fill",
                    isPrimary: true,
                    isDisabled: amount == nil,
                    action: addMoney
                )

                cashCushionActionButton(
                    title: "Use Money",
                    systemImage: "minus.circle",
                    isPrimary: false,
                    isDisabled: !canUseMoney,
                    action: useMoney
                )
            }
        }
    }

    private func cashCushionActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isPrimary ? .white : style.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
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
                    .stroke(style.primary.opacity(0.16), lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.54 : 1.0)
        .accessibilityLabel(title)
    }

    private func addMoney() {
        guard let amount else {
            return
        }

        addAction(amount)
        dismiss()
    }

    private func useMoney() {
        guard let amount else {
            return
        }

        useAction(amount)
        dismiss()
    }
}
