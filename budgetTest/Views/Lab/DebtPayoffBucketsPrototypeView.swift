#if DEBUG

import SwiftUI
import SwiftData

struct DebtPayoffBucketsPrototypeView: View {

    @EnvironmentObject private var plaid: PlaidService

    @Query
    private var events: [PlannerEvent]

    @Query
    private var allocations: [EventAllocation]

    @Query
    private var occurrenceStatuses: [ExpenseOccurrenceStatus]

    @State private var protectedAmounts: [String: Double] = [:]
    @State private var amountInputs: [String: String] = [:]
    @State private var targetInputs: [String: String] = [:]

    private var debtAccounts: [PlaidAccount] {
        plaid.accounts.debtAccounts
    }

    private var totalDebtPaymentSetAside: Double {
        protectedAmounts.values.reduce(0, +)
    }

    private var baseSummary: FinancialSummary {
        FinancialSummaryCalculator.calculate(
            accounts: plaid.accounts,
            goals: plaid.savingsGoals,
            reserveBalance: plaid.reserveBalance,
            upcomingExpensesSetAside: activeUpcomingExpensesSetAside,
            debtPaymentsSetAside: totalDebtPaymentSetAside
        )
    }

    private var activeUpcomingExpensesSetAside: Double {
        FinancialSummaryCalculator.activeUpcomingExpensesSetAside(
            allocations: allocations,
            forecastEvents: PlannerForecastCalculator(
                events: events,
                totalAvailable: 0,
                totalGoalAllocated: 0,
                includeFutureIncome: true,
                protectGoals: true,
                inactiveOccurrenceIDs: inactiveOccurrenceIDs
            )
            .forecastEvents
        )
    }

    private var inactiveOccurrenceIDs: Set<String> {
        ExpenseOccurrenceLifecycleResolver.resolvedOccurrenceIDs(
            from: occurrenceStatuses
        )
    }

    var body: some View {
        AppScreen {
            header

            summaryCard

            debtAccountsSection
        }
        .navigationTitle("Debt Payoff")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissToolbar()
    }

    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            Text("Set-Aside Prototype")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            Text("Debt Payoff")
                .font(
                    .system(
                        size: 34,
                        weight: .bold
                    )
                )
                .foregroundColor(AppColors.primaryText)

            Text("Set aside cash toward future debt payments without reducing the debt balance yet.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryCard: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.medium) {
                IconBadge(
                    systemImage: "shield.lefthalf.filled",
                    color: AppColors.protected,
                    size: 42,
                    iconSize: 18
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text("Prototype Set-Aside Summary")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)

                    Text("Debt payoff reduces Available to Spend only inside this Lab screen.")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            VStack(spacing: AppSpacing.small) {
                summaryRow(
                    "Cash Cushion",
                    value: baseSummary.reserve
                )

                summaryRow(
                    "Savings goals set aside",
                    value: baseSummary.savingsGoalsSetAside
                )

                summaryRow(
                    "Upcoming expenses set aside",
                    value: baseSummary.upcomingExpensesSetAside
                )

                summaryRow(
                    "Debt payments set aside",
                    value: baseSummary.debtPaymentsSetAside,
                    color: AppColors.liability
                )

                Divider()

                summaryRow(
                    "Total set aside",
                    value: baseSummary.protectedMoney,
                    color: AppColors.protected,
                    isStrong: true
                )

                summaryRow(
                    "Available after debt payments",
                    value: baseSummary.safeToSpend,
                    color: baseSummary.safeToSpend >= 0
                        ? AppColors.spendable
                        : AppColors.negative,
                    isStrong: true
                )
            }
        }
        .padding(AppSpacing.card)
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.protected.opacity(0.06),
                    AppColors.glassOverlaySurface
                ]
            ),
            accent: AppColors.protected,
            shadow: AppShadows.softPanelCompact
        )
    }

    private var debtAccountsSection: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.small) {
                IconBadge(
                    systemImage: "creditcard.fill",
                    color: AppColors.liability,
                    size: 34,
                    iconSize: 14
                )

                Text("Debt Accounts")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)

                Spacer()
            }

            if debtAccounts.isEmpty {
                emptyState
            } else {
                VStack(spacing: AppSpacing.small) {
                    ForEach(debtAccounts) { account in
                        debtBucketCard(
                            account
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: AppSpacing.medium) {
            IconBadge(
                systemImage: "creditcard.trianglebadge.exclamationmark",
                color: AppColors.liability,
                size: 38,
                iconSize: 15
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("No Plaid debt accounts found")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)

                Text("Link a credit card or loan to test debt payoff plans with real account data.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.medium)
        .glassCard(
            cornerRadius: AppRadii.field,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.liability.opacity(0.04),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: nil
        )
    }

    private func debtBucketCard(
        _ account: PlaidAccount
    ) -> some View {
        let protectedAmount = protectedAmount(
            for: account
        )
        let target = paymentTarget(
            for: account
        )
        let progress = progress(
            protectedAmount: protectedAmount,
            target: target
        )

        return VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            HStack(spacing: AppSpacing.medium) {
                IconBadge(
                    systemImage: debtIcon(for: account),
                    color: AppColors.liability,
                    size: 40,
                    iconSize: 17
                )

                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(account.name)
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Text(account.institution_name ?? "Debt account")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                VStack(
                    alignment: .trailing,
                    spacing: AppSpacing.xxSmall
                ) {
                    Text(AppFormatters.currency(account.debtBalanceValue))
                        .font(.headline.weight(.bold))
                        .foregroundColor(AppColors.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("current debt")
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            HStack(spacing: AppSpacing.medium) {
                metricPill(
                    title: "Set Aside",
                    value: AppFormatters.currency(protectedAmount),
                    color: AppColors.protected
                )

                metricPill(
                    title: "Target",
                    value: AppFormatters.currency(target),
                    color: AppColors.liability
                )
            }

            ProgressView(value: progress)
                .tint(AppColors.protected)

            VStack(spacing: AppSpacing.small) {
                TextField(
                    "Payment target optional",
                    text: targetInputBinding(
                        for: account
                    )
                )
                .keyboardType(.decimalPad)
                .padding(.horizontal, AppSpacing.regular)
                .padding(.vertical, AppSpacing.medium)
                .glassCard(
                    cornerRadius: AppRadii.field,
                    shadow: nil
                )
                .accessibilityLabel("Payment target for \(account.name)")

                TextField(
                    "Amount to set aside",
                    text: amountInputBinding(
                        for: account
                    )
                )
                .keyboardType(.decimalPad)
                .padding(.horizontal, AppSpacing.regular)
                .padding(.vertical, AppSpacing.medium)
                .glassCard(
                    cornerRadius: AppRadii.field,
                    shadow: nil
                )
                .accessibilityLabel("Amount to set aside for \(account.name)")

                HStack(spacing: AppSpacing.medium) {
                    SecondaryButton(
                        "Remove",
                        systemImage: "minus.circle",
                        cornerRadius: AppRadii.button,
                        foregroundColor: AppColors.liability,
                        fillsWidth: true
                    ) {
                        removeProtectedAmount(
                            for: account
                        )
                    }

                    PrimaryButton(
                        "Add",
                        systemImage: "plus.circle.fill",
                        trailingSystemImage: nil,
                        cornerRadius: AppRadii.button,
                        fillsWidth: true
                    ) {
                        addProtectedAmount(
                            for: account
                        )
                    }
                }
            }

            Text("Prototype only: this sets cash aside for a future payment. It does not lower the Plaid debt balance.")
                .font(.caption2)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.card)
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.liability.opacity(0.05),
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: AppShadows.softPanelCompact
        )
    }

    private func summaryRow(
        _ title: String,
        value: Double,
        color: Color = AppColors.primaryText,
        isStrong: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .font(isStrong ? .subheadline.weight(.semibold) : .caption)
                .foregroundColor(AppColors.secondaryText)

            Spacer()

            Text(AppFormatters.currency(value))
                .font(isStrong ? .headline.weight(.bold) : .subheadline.weight(.semibold))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func metricPill(
        title: String,
        value: String,
        color: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xxSmall) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.medium)
        .padding(.horizontal, AppSpacing.small)
        .glassCard(
            cornerRadius: AppRadii.field,
            shadow: nil
        )
    }

    private func protectedAmount(
        for account: PlaidAccount
    ) -> Double {
        protectedAmounts[account.account_id] ?? 0
    }

    private func paymentTarget(
        for account: PlaidAccount
    ) -> Double {
        let target = parsedAmount(
            targetInputs[account.account_id]
        )

        guard target > 0 else {
            return account.debtBalanceValue
        }

        return target
    }

    private func addProtectedAmount(
        for account: PlaidAccount
    ) {
        let amount = parsedAmount(
            amountInputs[account.account_id]
        )

        guard amount > 0 else {
            return
        }

        protectedAmounts[account.account_id, default: 0] += amount
        amountInputs[account.account_id] = ""
    }

    private func removeProtectedAmount(
        for account: PlaidAccount
    ) {
        let amount = parsedAmount(
            amountInputs[account.account_id]
        )

        guard amount > 0 else {
            return
        }

        let current = protectedAmounts[account.account_id] ?? 0
        protectedAmounts[account.account_id] = max(
            current - amount,
            0
        )
        amountInputs[account.account_id] = ""
    }

    private func amountInputBinding(
        for account: PlaidAccount
    ) -> Binding<String> {
        Binding(
            get: {
                amountInputs[account.account_id] ?? ""
            },
            set: {
                amountInputs[account.account_id] = $0
            }
        )
    }

    private func targetInputBinding(
        for account: PlaidAccount
    ) -> Binding<String> {
        Binding(
            get: {
                targetInputs[account.account_id] ?? ""
            },
            set: {
                targetInputs[account.account_id] = $0
            }
        )
    }

    private func parsedAmount(
        _ text: String?
    ) -> Double {
        guard let text else {
            return 0
        }

        let cleaned = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return max(
            Double(cleaned) ?? 0,
            0
        )
    }

    private func progress(
        protectedAmount: Double,
        target: Double
    ) -> Double {
        guard target > 0 else {
            return 0
        }

        let value = protectedAmount / target
        guard value.isFinite else {
            return 0
        }

        return min(
            max(value, 0),
            1
        )
    }

    private func debtIcon(
        for account: PlaidAccount
    ) -> String {
        account.isLoanGroupAccount
            ? "building.columns.fill"
            : "creditcard.fill"
    }
}

#endif
