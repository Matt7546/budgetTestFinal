import SwiftUI

struct AvailableToSpendInsightsSheet: View {

    let summary: FinancialSummary
    let canShowBankData: Bool
    let hasBankAccounts: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private var canShowBreakdown: Bool {
        canShowBankData && hasBankAccounts
    }

    private var totalSetAside: Double {
        summary.reserve +
        summary.savingsGoalsSetAside +
        summary.upcomingExpensesSetAside +
        summary.debtPaymentsSetAside
    }

    private var resultStyle: CalderaCategoryStyle {
        summary.safeToSpend >= 0
            ? CalderaCategoryStyle.style(for: .safeToSpend)
            : CalderaCategoryStyle.style(for: .shortfall)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaVisualStyle.background(.dashboard, colorScheme)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppSpacing.card) {
                        header

                        if canShowBreakdown {
                            resultSummaryCard
                            breakdownCard
                            explanationCard
                        } else {
                            signInRequiredCard
                        }
                    }
                    .padding(.horizontal, AppSpacing.screen)
                    .padding(.top, AppSpacing.card)
                    .padding(.bottom, AppSpacing.emptyState)
                }
            }
            .navigationTitle("Available to Spend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: CalderaCategoryStyle.style(for: .safeToSpend),
                size: 50,
                iconSize: 21
            )

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Available to Spend")
                    .font(.title2.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text("A plain-language look at what shapes today's number.")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Available to Spend is your cash balance minus money you’ve set aside inside \(AppBrand.shortName).")
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var resultSummaryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                CalderaGradientIcon(
                    style: resultStyle,
                    size: 46,
                    iconSize: 19
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(summary.safeToSpend >= 0 ? "Today you can spend" : "Today needs attention")
                        .font(.headline)
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                    Text(summary.safeToSpend >= 0
                         ? "This is what's left after your Set Aside money and Upcoming Expenses."
                         : "Your planned set-aside money is higher than your current available cash.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Text(AppFormatters.currency(summary.safeToSpend))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundColor(resultStyle.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if summary.safeToSpend < 0 {
                Text("Short by \(AppFormatters.currency(abs(summary.safeToSpend)))")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(resultStyle.primary)
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.xSmall)
                    .background(
                        Capsule(style: .continuous)
                            .fill(resultStyle.primary.opacity(colorScheme == .dark ? 0.20 : 0.12))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.91,
            strokeOpacity: 0.78,
            shadowOpacity: 0.04,
            shadowRadius: 18,
            shadowY: 8,
            darkGlowColor: resultStyle.primary
        )
    }

    private var explanationCard: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: resultStyle,
                size: 42,
                iconSize: 17
            )

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(summary.safeToSpend >= 0
                     ? "You have money available after today's plans are covered."
                     : "This does not mean anything broke. It means your Upcoming Expenses and Set Aside money are greater than your cash available right now.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                if summary.safeToSpend < 0 {
                    Text("You can lower what is Set Aside, add cash, or adjust Upcoming Expenses to bring Available to Spend back above zero.")
                        .font(.caption)
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.90,
            strokeOpacity: 0.76,
            shadowOpacity: 0.035,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: resultStyle.primary
        )
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.card) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("What shapes it")
                    .font(.headline)
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text("Start with cash available, then subtract the money you have Set Aside for your Cash Cushion, Goals, Upcoming Expenses, and Debt Payoff.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            AvailableToSpendBreakdownRow(
                title: "Cash available",
                subtitle: "Money in linked cash accounts",
                amount: summary.cash,
                style: CalderaCategoryStyle.style(for: .bankAccount),
                colorScheme: colorScheme
            )

            Divider()

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Set Aside")
                    .font(.caption.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text("Set Aside money stays in your bank account. \(AppBrand.shortName) simply keeps it out of Available to Spend.")
                    .font(.caption)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
            }

            AvailableToSpendBreakdownRow(
                title: "Cash Cushion",
                amountText: negativeCurrency(summary.reserve),
                style: CalderaCategoryStyle.style(for: .reserve),
                colorScheme: colorScheme
            )

            AvailableToSpendBreakdownRow(
                title: "Goals",
                amountText: negativeCurrency(summary.savingsGoalsSetAside),
                style: CalderaCategoryStyle.style(for: .savingsGoal),
                colorScheme: colorScheme
            )

            AvailableToSpendBreakdownRow(
                title: "Upcoming Expenses",
                amountText: negativeCurrency(summary.upcomingExpensesSetAside),
                style: CalderaCategoryStyle.style(for: .upcomingExpense),
                colorScheme: colorScheme
            )

            AvailableToSpendBreakdownRow(
                title: "Debt Payoff",
                amountText: negativeCurrency(summary.debtPaymentsSetAside),
                style: CalderaCategoryStyle.style(for: .debtPayoff),
                colorScheme: colorScheme
            )

            AvailableToSpendBreakdownRow(
                title: "Total Set Aside",
                subtitle: "Cash Cushion, Goals, Upcoming Expenses, and Debt Payoff",
                amountText: negativeCurrency(totalSetAside),
                style: CalderaCategoryStyle.style(for: .reserve),
                isEmphasized: true,
                colorScheme: colorScheme
            )

            Divider()

            AvailableToSpendBreakdownRow(
                title: "Available to Spend",
                subtitle: "Cash available minus Set Aside",
                amount: summary.safeToSpend,
                style: resultStyle,
                isEmphasized: true,
                colorScheme: colorScheme
            )
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.91,
            strokeOpacity: 0.78,
            shadowOpacity: 0.04,
            shadowRadius: 18,
            shadowY: 8,
            darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Cash available \(AppFormatters.currency(summary.cash)). Total set aside \(AppFormatters.currency(totalSetAside)). Available to Spend \(AppFormatters.currency(summary.safeToSpend))."
        )
    }

    private var signInRequiredCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: CalderaCategoryStyle.style(for: .bankAccount),
                size: 46,
                iconSize: 19
            )

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Link accounts to see insights")
                    .font(.headline)
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text("Sign in and link accounts to see what shapes your Available to Spend.")
                    .font(.subheadline)
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.90,
            strokeOpacity: 0.76,
            shadowOpacity: 0.035,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: CalderaCategoryStyle.style(for: .bankAccount).primary
        )
    }

    private func negativeCurrency(
        _ value: Double
    ) -> String {
        let amount = max(value, 0)
        guard amount > 0.005 else {
            return AppFormatters.currency(0)
        }

        return "-\(AppFormatters.currency(amount))"
    }
}

private struct AvailableToSpendBreakdownRow: View {

    let title: String
    var subtitle: String?
    var amount: Double?
    var amountText: String?
    let style: CalderaCategoryStyle
    var isEmphasized = false
    let colorScheme: ColorScheme

    private var displayedAmount: String {
        if let amountText {
            return amountText
        }

        return AppFormatters.currency(amount ?? 0)
    }

    private var amountColor: Color {
        if isEmphasized {
            return (amount ?? 0) >= 0
                ? style.primary
                : CalderaCategoryStyle.style(for: .shortfall).primary
        }

        return CalderaVisualStyle.primaryText(colorScheme)
    }

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: style,
                size: isEmphasized ? 40 : 34,
                iconSize: isEmphasized ? 17 : 14
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(title)
                    .font(isEmphasized ? .headline : .subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                }
            }

            Spacer(minLength: AppSpacing.medium)

            Text(displayedAmount)
                .font(isEmphasized ? .headline.bold() : .subheadline.weight(.bold))
                .foregroundColor(amountColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}
