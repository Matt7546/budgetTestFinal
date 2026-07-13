import SwiftUI

struct SavingsDebtPayoffSection: View {

    let hasDebtPayoffBuckets: Bool
    let visibleBuckets: [DebtPayoffBucket]
    let paymentPlanCycles: [PaymentPlanCycle]
    let accountByID: [String: PlaidAccount]
    let balanceLastUpdatedText: String
    let trailing: AnyView
    let addAction: () -> Void
    let editAction: (DebtPayoffBucket) -> Void

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    var body: some View {
        SavingsSectionShell(
            title: "Payment Plans",
            style: style
        ) {
            trailing
        } content: {
            VStack(spacing: AppSpacing.small) {
                if !hasDebtPayoffBuckets {
                    SavingsEmptyPreviewRow(
                        title: "Nothing planned here yet",
                        subtitle: "Plan a payment when you want it reflected in your spending plan.",
                        style: style
                    )
                } else {
                    SavingsSetAsideExplanationRow(
                        text: "\(AppBrand.shortName) does not make payments. You control actual payments."
                    )

                    ForEach(visibleBuckets) { bucket in
                        debtRow(bucket)
                    }
                }

                SavingsQuickAddButton(
                    title: "Plan a Payment",
                    style: style,
                    accessibilityLabel: "Plan a payment",
                    action: addAction
                )
            }
        }
    }

    private func debtRow(
        _ bucket: DebtPayoffBucket
    ) -> some View {
        let account = accountByID[bucket.plaidAccountID]
        let display = DebtPayoffDisplayModel(
            bucket: bucket,
            linkedAccount: account,
            cycle: PaymentPlanCycleStore.latestCycle(
                for: bucket.id,
                in: paymentPlanCycles
            )
        )
        let rowStyle = debtPayoffCategoryStyle(
            for: bucket,
            account: account
        )

        return DebtPayoffCompactCard(
            display: display,
            style: rowStyle,
            balanceLastUpdatedText: bucket.isLinkedCreditCard
                ? balanceLastUpdatedText
                : nil
        ) {
            editAction(bucket)
        }
    }
}

struct DebtPayoffCompactCard: View {

    let display: DebtPayoffDisplayModel
    let style: CalderaCategoryStyle
    let balanceLastUpdatedText: String?
    let action: () -> Void

    private var plaidSyncLine: String? {
        guard display.isLinkedCreditCard else {
            return nil
        }

        switch display.linkedCardBalanceState {
        case .notLinked:
            return nil

        case .available(let balanceText):
            guard let balanceLastUpdatedText,
                  balanceLastUpdatedText != "Not refreshed yet" else {
                return "Card balance \(balanceText) · Not refreshed yet"
            }

            return "Card balance \(balanceText) · \(balanceLastUpdatedText)"

        case .notFound:
            return "Linked card not found. Reconnect or create a new payment plan."
        }
    }

    private var statusColor: Color {
        display.presentationStatus.isReassuring
            ? CalderaCategoryStyle.style(for: .covered).primary
            : CalderaCategoryStyle.style(for: .needsMoney).primary
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            HStack(
                alignment: .top,
                spacing: AppSpacing.medium
            ) {
                CalderaGradientIcon(
                    style: style,
                    size: 32,
                    iconSize: 13
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(display.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Payment Plan")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer(minLength: AppSpacing.small)

                Text(display.presentationStatusValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(statusColor)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("Planned payment")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                Text(display.plannedPaymentValue)
                    .font(.title3.weight(.bold))
                    .foregroundColor(style.primary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)

                Text(display.plannedPaymentMeaningValue)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)

                Text(display.dueDateValue)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            amountSummary

            Text("Next: \(display.nextActionValue)")
                .font(.caption.weight(.semibold))
                .foregroundColor(statusColor)
                .fixedSize(horizontal: false, vertical: true)

            if let plaidSyncLine {
                Text(plaidSyncLine)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(
                        display.fundingState == .balanceUnavailable
                            ? CalderaCategoryStyle.style(for: .needsMoney).primary
                            : AppColors.secondaryText.opacity(0.86)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            } else if let balanceLine = display.balanceLine {
                Text(balanceLine)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.secondaryText.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .calderaGlassCard(
            cornerRadius: AppRadii.field,
            fillOpacity: 0.80,
            strokeOpacity: 0.60,
            shadowOpacity: 0.012,
            shadowRadius: 8,
            shadowY: 3
        )
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(display.accessibilitySummary)
        .accessibilityHint("Opens this Payment Plan.")
    }

    private var amountSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.small) {
                amountValue(
                    title: "Set aside",
                    value: display.setAsideValue
                )

                amountValue(
                    title: "Still needed",
                    value: display.remainingValue
                )
            }

            VStack(spacing: AppSpacing.xSmall) {
                amountValue(
                    title: "Set aside",
                    value: display.setAsideValue
                )

                amountValue(
                    title: "Still needed",
                    value: display.remainingValue
                )
            }
        }
    }

    private func amountValue(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.secondaryText)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.primaryText)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.small)
        .background(
            RoundedRectangle(
                cornerRadius: AppRadii.field,
                style: .continuous
            )
            .fill(style.primary.opacity(0.07))
        )
    }
}
