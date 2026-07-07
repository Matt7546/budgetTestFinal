import SwiftUI

struct SavingsDebtPayoffSection: View {

    let hasDebtPayoffBuckets: Bool
    let visibleBuckets: [DebtPayoffBucket]
    let accountByID: [String: PlaidAccount]
    let balanceLastUpdatedText: String
    let trailing: AnyView
    let addAction: () -> Void
    let editAction: (DebtPayoffBucket) -> Void

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    var body: some View {
        SavingsSectionShell(
            title: "Debt Payoff",
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
            linkedAccount: account
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

        guard display.fundingState != .balanceUnavailable else {
            return "Card balance unavailable · Try refreshing in More"
        }

        guard let balanceLastUpdatedText,
              balanceLastUpdatedText != "Not refreshed yet" else {
            return "Card balance not refreshed yet"
        }

        return "Card balance · \(balanceLastUpdatedText)"
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xSmall
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
                        .lineLimit(1)

                    Text(display.typeLabel)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.small)

                VStack(
                    alignment: .trailing,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(display.setAsideValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(style.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("set aside")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text(display.dueDateValue)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)

                if let plaidSyncLine {
                    Text(plaidSyncLine)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(
                            display.fundingState == .balanceUnavailable
                                ? CalderaCategoryStyle.style(for: .needsMoney).primary
                                : AppColors.secondaryText.opacity(0.86)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                } else if let balanceLine = display.balanceLine {
                    Text(balanceLine)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText.opacity(0.86))
                        .lineLimit(1)
                }
            }

            VStack(spacing: AppSpacing.xxSmall) {
                CalderaProgressBar(
                    progress: clampedProgressValue(display.progressValue),
                    colors: style.gradient
                )
                .accessibilityLabel(display.progressAccessibilityLabel)

                HStack(spacing: AppSpacing.small) {
                    Text(display.progressCaption)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: AppSpacing.small)

                    Text(display.progressTargetValue)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(style.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
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
        .accessibilityLabel(
            "\(display.title), \(display.typeLabel), \(display.progressAccessibilityLabel)"
        )
    }
}
