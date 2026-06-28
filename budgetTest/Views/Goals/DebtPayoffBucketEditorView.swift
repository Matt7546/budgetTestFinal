import SwiftUI

struct DebtPayoffBucketDraft {
    let plaidAccountID: String
    let dueDate: Date
    let paymentTargetAmount: Double
    let protectedAmount: Double
}

struct DebtPayoffBucketEditorView: View {

    let debtAccounts: [PlaidAccount]
    let bucket: DebtPayoffBucket?
    let onSave: (DebtPayoffBucketDraft) -> Void
    let onDelete: ((DebtPayoffBucket) -> Void)?

    @Environment(\.dismiss)
    private var dismiss

    @State private var selectedAccountID: String
    @State private var dueDate: Date
    @State private var targetAmountText: String
    @State private var protectedAmountText: String

    init(
        debtAccounts: [PlaidAccount],
        bucket: DebtPayoffBucket?,
        onSave: @escaping (DebtPayoffBucketDraft) -> Void,
        onDelete: ((DebtPayoffBucket) -> Void)? = nil
    ) {
        self.debtAccounts = debtAccounts
        self.bucket = bucket
        self.onSave = onSave
        self.onDelete = onDelete

        let initialAccountID = bucket?.plaidAccountID ?? debtAccounts.first?.account_id ?? ""

        _selectedAccountID = State(initialValue: initialAccountID)
        _dueDate = State(initialValue: bucket?.dueDate ?? Date())
        _targetAmountText = State(initialValue: DebtPayoffBucketEditorView.textValue(bucket?.paymentTargetAmount))
        _protectedAmountText = State(initialValue: DebtPayoffBucketEditorView.textValue(bucket?.protectedAmount))
    }

    private var selectedAccount: PlaidAccount? {
        debtAccounts.first {
            $0.account_id == selectedAccountID
        }
    }

    private var targetAmount: Double {
        parsedAmount(targetAmountText)
    }

    private var protectedAmount: Double {
        parsedAmount(protectedAmountText)
    }

    private var canSave: Bool {
        !selectedAccountID.isEmpty &&
        targetAmount >= 0 &&
        protectedAmount >= 0
    }

    private var title: String {
        bucket == nil
            ? "New Debt Payoff"
            : "Edit Debt Payoff"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: AppSpacing.large
                ) {
                    accountSection

                    paymentSection

                    if let bucket,
                       let onDelete {
                        deleteButton(
                            bucket,
                            onDelete: onDelete
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.screen)
                .padding(.top, AppSpacing.large)
                .padding(.bottom, AppSpacing.large)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(bucket == nil ? "Add" : "Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .keyboardDismissToolbar()
            .background(AppColors.background.ignoresSafeArea())
        }
    }

    private var accountSection: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            Text("Debt Account")
                .font(.headline)
                .foregroundColor(AppColors.primaryText)

            if debtAccounts.isEmpty {
                Text("Link a credit card or loan account to create a debt payoff bucket.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker(
                    "Debt Account",
                    selection: $selectedAccountID
                ) {
                    ForEach(debtAccounts) { account in
                        Text(accountLabel(account))
                            .tag(account.account_id)
                    }
                }
                .pickerStyle(.menu)
                .padding(AppSpacing.medium)
                .glassCard(
                    cornerRadius: AppRadii.field,
                    shadow: nil
                )

                if let selectedAccount {
                    Text("\(AppFormatters.currency(selectedAccount.debtBalanceValue)) current balance")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
        .padding(AppSpacing.card)
        .glassCard(cornerRadius: AppRadii.panel)
    }

    private var paymentSection: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.medium
        ) {
            Text("Payment Plan")
                .font(.headline)
                .foregroundColor(AppColors.primaryText)

            DatePicker(
                "Due Date",
                selection: $dueDate,
                displayedComponents: .date
            )

            amountField(
                title: "Payment Target",
                text: $targetAmountText,
                placeholder: "Optional target"
            )

            amountField(
                title: "Protected Amount",
                text: $protectedAmountText,
                placeholder: "Amount set aside"
            )

            PrimaryButton(
                bucket == nil ? "Add Debt Payoff" : "Save Debt Payoff",
                systemImage: "checkmark.circle.fill",
                trailingSystemImage: nil,
                cornerRadius: AppRadii.button,
                isDisabled: !canSave,
                fillsWidth: true,
                action: save
            )
        }
        .padding(AppSpacing.card)
        .glassCard(cornerRadius: AppRadii.panel)
    }

    private func amountField(
        title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            TextField(
                placeholder,
                text: text
            )
            .keyboardType(.decimalPad)
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.medium)
            .glassCard(
                cornerRadius: AppRadii.field,
                shadow: nil
            )
        }
    }

    private func deleteButton(
        _ bucket: DebtPayoffBucket,
        onDelete: @escaping (DebtPayoffBucket) -> Void
    ) -> some View {
        DestructiveButton(
            "Delete Debt Payoff",
            systemImage: "trash.fill",
            cornerRadius: AppRadii.button
        ) {
            onDelete(bucket)
            dismiss()
        }
    }

    private func save() {
        guard canSave else {
            return
        }

        onSave(
            DebtPayoffBucketDraft(
                plaidAccountID: selectedAccountID,
                dueDate: dueDate,
                paymentTargetAmount: targetAmount,
                protectedAmount: protectedAmount
            )
        )
        dismiss()
    }

    private func parsedAmount(
        _ text: String
    ) -> Double {
        let sanitized = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitized.isEmpty else {
            return 0
        }

        return max(Double(sanitized) ?? -1, -1)
    }

    private func accountLabel(
        _ account: PlaidAccount
    ) -> String {
        if let institution = account.institution_name,
           !institution.isEmpty {
            return "\(account.name) · \(institution)"
        }

        return account.name
    }

    private static func textValue(
        _ value: Double?
    ) -> String {
        guard let value,
              value > 0 else {
            return ""
        }

        return String(
            format: "%.2f",
            value
        )
    }
}
