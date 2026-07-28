import SwiftUI

struct SavingsGoalDetailsCard: View {

    @Binding var draft: SavingsGoalDetailsDraft
    @FocusState.Binding var focusedField: SavingsGoalUpdateFocusedField?

    let isNew: Bool
    let colorScheme: ColorScheme
    let onCancel: () -> Void
    let onDone: () -> Void
    let onDelete: () -> Void

    private var goalStyle: CalderaCategoryStyle {
        CalderaCategoryStyle.style(for: .savingsGoal)
    }

    private var goalAccentGradient: LinearGradient {
        LinearGradient(
            colors: goalStyle.gradient,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var formattedDraftTargetAmount: String {
        guard let amount = MoneyAmountParser.parse(
            draft.targetAmountText
        ),
        amount.isFinite else {
            return "$0.00"
        }

        return AppFormatters.currency(
            max(amount, 0)
        )
    }

    private var defaultTargetDate: Date {
        Calendar.current.date(
            byAdding: .month,
            value: 1,
            to: Date()
        ) ?? Date()
    }

    private var targetDateBinding: Binding<Date> {
        Binding(
            get: {
                draft.saveByDate
                    ?? defaultTargetDate
            },
            set: { draft.saveByDate = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaModalBackground(
                    mood: .savingsGoal
                )

                ScrollView {
                    VStack(spacing: AppSpacing.small) {
                        goalNameField
                        targetAmountField
                        targetDateField
                        pinField

                        if !isNew {
                            deleteButton
                        }
                    }
                    .padding(AppSpacing.screen)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Goal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .disabled(!draft.isValid)
                }
            }
            .keyboardDismissToolbar()
        }
        .calderaTransparentNavigationSurface()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var goalNameField: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "text.cursor")
                .foregroundStyle(goalAccentGradient)

            TextField(
                "Goal name",
                text: $draft.name
            )
            .textInputAutocapitalization(.words)
            .submitLabel(.next)
            .focused($focusedField, equals: .name)
            .onSubmit {
                focusedField = .targetAmount
            }
            .accessibilityLabel("Goal name")
        }
        .goalDetailsFieldSurface(
            colorScheme: colorScheme
        )
    }

    private var targetAmountField: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "target")
                .foregroundStyle(goalAccentGradient)

            TextField(
                "Target amount",
                text: $draft.targetAmountText
            )
            .keyboardType(.decimalPad)
            .focused(
                $focusedField,
                equals: .targetAmount
            )
            .accessibilityLabel("Target amount")

            Text(formattedDraftTargetAmount)
                .font(.caption.weight(.semibold))
                .foregroundColor(
                    CalderaVisualStyle.secondaryText(
                        colorScheme
                    )
                )
                .lineLimit(1)
        }
        .goalDetailsFieldSurface(
            colorScheme: colorScheme
        )
    }

    private var targetDateField: some View {
        HStack(spacing: AppSpacing.small) {
            Image(
                systemName: draft.saveByDate == nil
                    ? "calendar.badge.plus"
                    : "calendar"
            )
            .foregroundStyle(goalAccentGradient)

            if draft.saveByDate != nil {
                DatePicker(
                    "Target date",
                    selection: targetDateBinding,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(goalStyle.primary)
                .accessibilityLabel("Target date")

                Spacer(minLength: AppSpacing.xSmall)

                Button {
                    draft.saveByDate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(
                            CalderaVisualStyle.secondaryText(colorScheme)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove target date")
            } else {
                Button("Add target date") {
                    draft.saveByDate = defaultTargetDate
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(
                    CalderaVisualStyle.primaryText(colorScheme)
                )

                Spacer()
            }
        }
        .goalDetailsFieldSurface(
            colorScheme: colorScheme
        )
    }

    private var pinField: some View {
        HStack(spacing: AppSpacing.medium) {
            IconBadge(
                systemImage: "pin.fill",
                color: goalStyle.primary,
                size: 34,
                iconSize: 14
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("Pin to Set Aside")
                    .font(.subheadline.weight(.semibold))

                Text("Pinned goals stay visible on the Set Aside screen.")
                    .font(.caption)
                    .foregroundColor(
                        CalderaVisualStyle.secondaryText(colorScheme)
                    )
            }

            Spacer()

            Toggle(
                "Pin to Set Aside",
                isOn: $draft.isPinned
            )
            .labelsHidden()
            .tint(goalStyle.primary)
        }
        .goalDetailsFieldSurface(
            colorScheme: colorScheme
        )
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            focusedField = nil
            onDelete()
        } label: {
            Label("Delete Goal", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityLabel("Delete goal")
    }
}

private extension View {

    func goalDetailsFieldSurface(
        colorScheme: ColorScheme
    ) -> some View {
        padding(AppSpacing.regular)
            .frame(minHeight: 52)
            .calderaGlassCard(
                cornerRadius: AppRadii.card,
                fillOpacity: colorScheme == .dark
                    ? 0.58
                    : 0.80,
                strokeOpacity: colorScheme == .dark
                    ? 0.36
                    : 0.52,
                shadowOpacity: 0.04,
                shadowRadius: 12,
                shadowY: 6,
                darkGlowColor: CalderaCategoryStyle
                    .style(for: .savingsGoal)
                    .primary
            )
    }
}
