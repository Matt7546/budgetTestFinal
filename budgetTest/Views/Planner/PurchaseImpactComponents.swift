import SwiftUI

struct PurchaseImpactHeader: View {

    var body: some View {
        ModalHeaderView(
            eyebrow: "Purchase Preview",
            title: "Purchase Impact",
            subtitle: "Preview a purchase without changing your balances.",
            systemImage: "cart.fill",
            color: AppColors.accent
        )
    }
}

struct PurchaseAmountField: View {

    @Binding var amountText: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.compact
        ) {
            Text("Purchase Amount")
                .font(.headline)
                .foregroundColor(AppColors.primaryText)

            TextField(
                "0.00",
                text: $amountText
            )
            .keyboardType(.decimalPad)
            .focused(isFocused)
            .padding()
            .glassCard(
                cornerRadius: AppRadii.field,
                shadow: nil
            )
            .accessibilityLabel("Purchase Amount")
        }
    }
}

struct PurchaseImpactResultCard: View {

    let availableAfterPurchase: Double
    let safeToSpendAfterPurchase: Double
    let createsShortfall: Bool
    let shortfallAmount: Double
    let nextExpense: ForecastEvent?

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.large
        ) {
            MetricRow(
                "Timeline Balance After Purchase",
                value: availableAfterPurchase,
                labelFont: .subheadline,
                valueFont: .headline.bold(),
                valueColor: availableAfterPurchase >= 0
                    ? AppColors.spendable
                    : AppColors.negative
            )

            MetricRow(
                "Safe To Spend After Purchase",
                value: safeToSpendAfterPurchase,
                labelFont: .subheadline,
                valueFont: .headline.bold(),
                valueColor: createsShortfall ? AppColors.negative : AppColors.spendable
            )

            Divider()

            PurchaseNextExpenseImpactView(
                nextExpense: nextExpense,
                createsShortfall: createsShortfall,
                shortfallAmount: shortfallAmount
            )

            if createsShortfall {
                Label(
                    "This purchase creates a Safe To Spend shortfall.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.negative)
            }
        }
        .padding(AppSpacing.panel)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.glassOverlayCyan,
                    AppColors.glassOverlayBlue
                ]
            ),
            accent: createsShortfall
                ? AppColors.negative
                : AppColors.accent,
            shadow: AppShadows.softPanel
        )
    }
}

private struct PurchaseNextExpenseImpactView: View {

    let nextExpense: ForecastEvent?
    let createsShortfall: Bool
    let shortfallAmount: Double

    var body: some View {
        if let nextExpense {
            VStack(
                alignment: .leading,
                spacing: AppSpacing.small
            ) {
            Text("Next Expense Impact")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)

                Text(nextExpense.event.name)
                    .font(.headline)
                    .foregroundColor(AppColors.ink)
                    .lineLimit(1)

                HStack {
                    MetricValue(
                        nextExpense.event.amount,
                        font: .headline,
                        color: AppColors.negative,
                        minimumScaleFactor: 0.7,
                        lineLimit: 1
                    )

                    Spacer()

                    Text(
                        AppFormatters.abbreviatedMonthDay(
                            nextExpense.occurrenceDate
                        )
                    )
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                }

                Text(
                    createsShortfall
                    ? "Short by \(AppFormatters.currency(shortfallAmount)) before this expense."
            : "This purchase keeps the next expense covered."
                )
                .font(.caption.weight(.semibold))
                .foregroundColor(createsShortfall ? AppColors.negative : AppColors.spendable)
            }
        } else {
            Text("No next expense to compare against.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
        }
    }
}
