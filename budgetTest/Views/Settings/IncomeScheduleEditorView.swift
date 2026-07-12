import SwiftData
import SwiftUI

struct IncomeScheduleEditorView: View {
    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    let ownerScopeID: String
    let editingSchedule: IncomeSchedule?

    @State
    private var draft: IncomeScheduleDraft

    @State
    private var confirmation: IncomeScheduleConfirmation?

    @State
    private var saveErrorMessage: String?

    @State
    private var isSaving = false

    private let today: Date
    private let calendar: Calendar

    init(
        ownerScopeID: String,
        editingSchedule: IncomeSchedule?,
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.ownerScopeID = ownerScopeID
        self.editingSchedule = editingSchedule
        self.today = today
        self.calendar = calendar

        _draft = State(
            initialValue: editingSchedule.map {
                IncomeScheduleDraft(
                    schedule: $0,
                    today: today,
                    calendar: calendar
                )
            } ?? IncomeScheduleDraft(
                lastPayday: today,
                explicitNextPayday: calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: today
                ) ?? today
            )
        )
    }

    var body: some View {
        NavigationStack {
            AppScreen(
                usesNavigationStack: false,
                backgroundStyle: .editorModal(.general),
                contentPadding: .all,
                contentSpacing: AppSpacing.regular
            ) {
                if let confirmation {
                    confirmationContent(confirmation)
                } else {
                    editorContent
                }
            }
            .navigationTitle(
                confirmation == nil
                    ? "Expected Income"
                    : "Confirm Expected Income"
            )
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .keyboardDismissToolbar()
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        ModalHeaderView(
            eyebrow: "Planning",
            title: "Expected income",
            subtitle: "Plan for payday without counting it as cash yet.",
            systemImage: "banknote.fill",
            color: incomeColor
        )

        trustCard

        CalderaEditorFormCard(color: incomeColor) {
            AmountEntryField(
                title: "Typical take-home per paycheck",
                subtitle: "What usually lands in your bank account?",
                text: $draft.takeHomeAmountText,
                style: CalderaCategoryStyle.style(for: .income)
            )
        }

        frequencyCard

        paydayCard

        if let validationMessage {
            Text(validationMessage)
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }

        PrimaryButton(
            "Review expected income",
            systemImage: "checkmark.circle.fill",
            fillsWidth: true
        ) {
            reviewExpectedIncome()
        }
        .disabled(currentConfirmation == nil)
        .opacity(currentConfirmation == nil ? 0.6 : 1)
        .accessibilityIdentifier("incomeSchedule.review")
    }

    private var trustCard: some View {
        GlassFormCard(color: incomeColor) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                IconBadge(
                    systemImage: "info.circle.fill",
                    color: incomeColor,
                    size: 34,
                    iconSize: 14
                )

                Text("Expected income is a planning estimate. It won’t change Available to Spend until money arrives in a linked account.")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var frequencyCard: some View {
        CalderaEditorFormCard(
            title: "How often are you paid?",
            systemImage: "repeat",
            color: incomeColor
        ) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: AppSpacing.small
            ) {
                ForEach(IncomeScheduleFrequency.allCases) { frequency in
                    Button {
                        draft.frequency = frequency
                    } label: {
                        Text(frequency.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(
                                draft.frequency == frequency
                                    ? incomeColor
                                    : AppColors.secondaryText
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, AppSpacing.small)
                            .padding(.vertical, 11)
                            .background(
                                Capsule()
                                    .fill(
                                        draft.frequency == frequency
                                            ? incomeColor.opacity(0.12)
                                            : AppColors.secondaryText.opacity(0.10)
                                    )
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        draft.frequency == frequency
                                            ? incomeColor.opacity(0.30)
                                            : AppColors.glassSubtleHighlight,
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(frequency.title)
                    .accessibilityAddTraits(
                        draft.frequency == frequency ? .isSelected : []
                    )
                }
            }
        }
    }

    private var paydayCard: some View {
        CalderaEditorFormCard(
            title: "Payday",
            systemImage: "calendar",
            color: incomeColor
        ) {
            DatePicker(
                "Last payday",
                selection: $draft.lastPayday,
                in: ...today,
                displayedComponents: .date
            )
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("incomeSchedule.lastPayday")

            if draft.frequency.requiresExplicitNextPayday {
                Divider()

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    DatePicker(
                        "Next expected payday",
                        selection: $draft.explicitNextPayday,
                        in: earliestExplicitNextPayday...,
                        displayedComponents: .date
                    )
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("incomeSchedule.nextPayday")

                    Text("Choose the next date you expect this pay to land.")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let nextDate = currentConfirmation.flatMap({
                IncomeScheduleCalendar.date(
                    from: $0.nextExpectedPaydayDateKey,
                    calendar: calendar
                )
            }) {
                Divider()

                HStack(spacing: AppSpacing.medium) {
                    IconBadge(
                        systemImage: "calendar.badge.checkmark",
                        color: incomeColor,
                        size: 34,
                        iconSize: 14
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                        Text("Next expected payday")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.primaryText)

                        Text(fullDate(nextDate))
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func confirmationContent(
        _ confirmation: IncomeScheduleConfirmation
    ) -> some View {
        ModalHeaderView(
            eyebrow: "Review",
            title: "Confirm expected income",
            subtitle: "Check the amount and next date before saving.",
            systemImage: "checkmark.circle.fill",
            color: incomeColor
        )

        GlassFormCard(color: incomeColor) {
            Text("Expected deposit")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)

            Text(AppFormatters.currency(confirmation.takeHomeAmount))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(incomeColor)
                .monospacedDigit()

            if let nextDate = IncomeScheduleCalendar.date(
                from: confirmation.nextExpectedPaydayDateKey,
                calendar: calendar
            ) {
                Text("Expected \(fullDate(nextDate))")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
            }

            Text(confirmationDetail(confirmation))
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }

        GlassFormCard(color: incomeColor) {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                IconBadge(
                    systemImage: "shield.lefthalf.filled",
                    color: incomeColor,
                    size: 34,
                    iconSize: 14
                )

                Text("Planning only — this does not add to Available to Spend.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let saveErrorMessage {
            Text(saveErrorMessage)
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.warning)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }

        PrimaryButton(
            isSaving ? "Saving…" : "Save expected income",
            systemImage: "checkmark.circle.fill",
            fillsWidth: true
        ) {
            save(confirmation)
        }
        .disabled(isSaving)
        .accessibilityIdentifier("incomeSchedule.save")

        SecondaryButton(
            "Back",
            systemImage: "chevron.left",
            fillsWidth: true
        ) {
            self.confirmation = nil
            saveErrorMessage = nil
        }
        .disabled(isSaving)
    }

    private var currentConfirmation: IncomeScheduleConfirmation? {
        draft.confirmation(
            ownerScopeID: ownerScopeID,
            sourceLabel: editingSchedule?.sourceLabel ?? "Paycheck",
            sortOrder: editingSchedule?.sortOrder ?? 0,
            today: today,
            calendar: calendar
        )
    }

    private var validationMessage: String? {
        if IncomeScheduleMoney.cents(from: draft.takeHomeAmountText) == nil {
            return "Enter a take-home amount greater than zero."
        }

        if !IncomeScheduleCalendar.isValidLastPayday(
            draft.lastPayday,
            today: today,
            calendar: calendar
        ) {
            return "Last payday can’t be in the future."
        }

        if draft.frequency.requiresExplicitNextPayday,
           !IncomeScheduleCalendar.isValidExplicitNextPayday(
            draft.explicitNextPayday,
            lastPayday: draft.lastPayday,
            today: today,
            calendar: calendar
           ) {
            return "Choose a next expected payday after the last payday."
        }

        return nil
    }

    private var earliestExplicitNextPayday: Date {
        let dayAfterLast = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: draft.lastPayday)
        ) ?? today

        return max(
            calendar.startOfDay(for: today),
            dayAfterLast
        )
    }

    private var incomeColor: Color {
        CalderaCategoryStyle.style(for: .income).primary
    }

    private func reviewExpectedIncome() {
        confirmation = currentConfirmation
        saveErrorMessage = nil
    }

    private func save(
        _ confirmation: IncomeScheduleConfirmation
    ) {
        guard !isSaving else { return }

        isSaving = true
        saveErrorMessage = nil

        do {
            try IncomeScheduleSaveCoordinator.save(
                confirmation,
                editing: editingSchedule,
                in: modelContext
            )
            dismiss()
        } catch {
            modelContext.rollback()
            isSaving = false
            saveErrorMessage = "Couldn’t save expected income. Try again."
        }
    }

    private func confirmationDetail(
        _ confirmation: IncomeScheduleConfirmation
    ) -> String {
        guard let lastDate = IncomeScheduleCalendar.date(
            from: confirmation.lastPaydayDateKey,
            calendar: calendar
        ) else {
            return confirmation.frequency.title
        }

        switch confirmation.dateBasis {
        case .calculated:
            return "\(confirmation.frequency.title), calculated from your last payday on \(fullDate(lastDate))."
        case .explicit:
            return "\(confirmation.frequency.title). You chose this next expected payday."
        }
    }

    private func fullDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
        )
    }
}
