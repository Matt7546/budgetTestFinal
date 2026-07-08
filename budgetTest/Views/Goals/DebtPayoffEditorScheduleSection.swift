import SwiftUI

struct DebtPayoffEditorCreditCardDueDateSection: View {

    @Binding var dueDate: Date

    let dateChanged: () -> Void

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "When is it needed?",
            systemImage: "calendar",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            DatePicker(
                "Due Date",
                selection: $dueDate,
                displayedComponents: .date
            )
            .accessibilityLabel("Card due date")
            .onChange(of: dueDate) { _, _ in
                dateChanged()
            }

            Text("This date helps Plan Ahead show the payment before it arrives.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DebtPayoffEditorScheduleSection: View {

    let selectedKind: DebtPayoffKind

    @Binding var hasDueDate: Bool
    @Binding var dueDate: Date

    var body: some View {
        DebtPayoffEditorFormCard(
            title: "When is it needed?",
            systemImage: "calendar",
            color: CalderaCategoryStyle.style(for: .debtPayoff).primary
        ) {
            if selectedKind == .linkedCreditCard {
                Toggle(
                    "Track due date",
                    isOn: $hasDueDate
                )
                .tint(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                if hasDueDate {
                    DatePicker(
                        "Payment Due Date",
                        selection: $dueDate,
                        displayedComponents: .date
                    )
                    .accessibilityLabel("Payment due date")
                }
            } else {
                DatePicker(
                    "Next Due Date",
                    selection: $dueDate,
                    displayedComponents: .date
                )
                .accessibilityLabel("Next due date")
            }
        }
    }
}

struct DebtPayoffEditorOptionalTrackingSection: View {

    let isVisible: Bool
    let optionalDateRangeIsValid: Bool

    @Binding var showsOptionalTrackingDetails: Bool
    @Binding var originalBalanceText: String
    @Binding var interestRateText: String
    @Binding var notesText: String
    @Binding var includesStartDate: Bool
    @Binding var startDate: Date
    @Binding var includesEndDate: Bool
    @Binding var endDate: Date

    var body: some View {
        if isVisible {
            DebtPayoffEditorFormCard(
                title: "More Details",
                systemImage: "slider.horizontal.3",
                color: CalderaCategoryStyle.style(for: .debtPayoff).primary
            ) {
                DisclosureGroup(
                    isExpanded: $showsOptionalTrackingDetails
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.small
                    ) {
                        AmountEntryField(
                            title: "Original Balance",
                            subtitle: "Optional planning detail.",
                            placeholder: "0.00",
                            text: $originalBalanceText,
                            style: CalderaCategoryStyle.style(for: .debtPayoff),
                            accessibilityLabel: "Original balance"
                        )

                        DebtPayoffEditorPercentageField(
                            title: "Interest Rate / APR",
                            placeholder: "Optional APR",
                            text: $interestRateText,
                            subtitle: "Optional planning detail."
                        )

                        Toggle(
                            "Add start date",
                            isOn: $includesStartDate
                        )
                        .tint(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                        if includesStartDate {
                            DatePicker(
                                "Start Date",
                                selection: $startDate,
                                displayedComponents: .date
                            )
                            .accessibilityLabel("Start date")
                        }

                        Toggle(
                            "Add end date",
                            isOn: $includesEndDate
                        )
                        .tint(CalderaCategoryStyle.style(for: .debtPayoff).primary)

                        if includesEndDate {
                            DatePicker(
                                "End Date",
                                selection: $endDate,
                                displayedComponents: .date
                            )
                            .accessibilityLabel("End date")
                        }

                        if !optionalDateRangeIsValid {
                            Text("End date must be after the start date.")
                                .font(.caption.weight(.medium))
                                .foregroundColor(CalderaCategoryStyle.style(for: .needsMoney).primary)
                        }

                        notesField
                    }
                    .padding(.top, AppSpacing.small)
                } label: {
                    Text("Optional balance, APR, dates, and notes")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColors.primaryText)
                }
                .tint(CalderaCategoryStyle.style(for: .debtPayoff).primary)
            }
        }
    }

    private var notesField: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xxSmall
        ) {
            Text("Notes")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryText)

            Text("Optional. Add anything useful for this payment plan.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)

            TextEditor(text: $notesText)
                .frame(minHeight: 72)
                .padding(AppSpacing.small)
                .scrollContentBackground(.hidden)
                .calderaGlassCard(
                    cornerRadius: AppRadii.field,
                    fillOpacity: 0.86,
                    strokeOpacity: 0.68,
                    shadowOpacity: 0.0,
                    shadowRadius: 0,
                    shadowY: 0,
                    darkGlowColor: CalderaCategoryStyle.style(for: .debtPayoff).primary
                )
                .accessibilityLabel("Notes")
        }
    }
}
