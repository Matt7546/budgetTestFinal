import SwiftUI

struct PurchaseImpactSheet: View {

    @Environment(\.dismiss) private var dismiss

    let plannerAvailable: Double
    let safeToSpend: Double
    let nextExpense: ForecastEvent?

    @State private var amountText = ""
    @FocusState private var isAmountFocused: Bool

    private var purchaseAmount: Double {
        Double(amountText) ?? 0
    }

    private var hasPurchaseAmount: Bool {
        purchaseAmount > 0
    }

    private var availableAfterPurchase: Double {
        plannerAvailable - purchaseAmount
    }

    private var safeToSpendAfterPurchase: Double {
        safeToSpend - purchaseAmount
    }

    private var createsShortfall: Bool {
        safeToSpendAfterPurchase < 0
    }

    private var shortfallAmount: Double {
        max(abs(safeToSpendAfterPurchase), 0)
    }

    var body: some View {
        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                contentPadding: .all,
                contentSpacing: AppSpacing.regular
            ) {
                PurchaseImpactHeader()

                PurchaseAmountField(
                    amountText: $amountText,
                    isFocused: $isAmountFocused
                )

                if hasPurchaseAmount {
                    PurchaseImpactResultCard(
                        availableAfterPurchase: availableAfterPurchase,
                        safeToSpendAfterPurchase: safeToSpendAfterPurchase,
                        createsShortfall: createsShortfall,
                        shortfallAmount: shortfallAmount,
                        nextExpense: nextExpense
                    )
                } else {
                    EmptyStateView(
                        systemImage: "cart.fill",
                        title: "Check before you buy",
                        description: "See how a purchase affects your Safe To Spend, Savings Reserve, and Next Expense.",
                        primaryActionTitle: "Start Purchase Check",
                        primaryAction: {
                            isAmountFocused = true
                        },
                        color: AppColors.accent
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Close purchase impact")
                }
            }
        }
    }
}
