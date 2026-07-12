import SwiftUI

struct PersonalizationFormView: View {

    let showsPlanningPreferences: Bool

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppPersonalizationKeys.preferredName)
    private var preferredName = ""

    @AppStorage(AppPersonalizationKeys.paySchedulePreset)
    private var payScheduleRawValue = ""

    @AppStorage(AppPersonalizationKeys.focus)
    private var focusRawValue = ""

    init(
        showsPlanningPreferences: Bool = true
    ) {
        self.showsPlanningPreferences = showsPlanningPreferences
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.card
        ) {
            preferredNameField

            if showsPlanningPreferences {
                paySchedulePicker
                focusPicker

                Text("Optional. You can change these later.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var preferredNameField: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xSmall
        ) {
            Text("Preferred name or nickname")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

            Text("Use your first name or nickname.")
                .font(.caption.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                "What should we call you?",
                text: $preferredName
            )
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .font(.headline)
            .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
            .padding(.horizontal, AppSpacing.regular)
            .padding(.vertical, AppSpacing.medium)
            .calderaGlassCard(
                cornerRadius: AppRadii.field,
                fillOpacity: 0.86,
                strokeOpacity: 0.70,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
            )
            .accessibilityLabel("Preferred name")
        }
    }

    private var paySchedulePicker: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xSmall
        ) {
            Text("Pay schedule")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

            Menu {
                Button("Skip for now") {
                    payScheduleRawValue = ""
                }

                Divider()

                ForEach(PaySchedulePreset.allCases) { preset in
                    Button(preset.title) {
                        payScheduleRawValue = preset.rawValue
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.medium) {
                    CalderaGradientIcon(
                        systemImage: "calendar.badge.clock",
                        colors: CalderaVisualStyle.iconGradient(
                            for: CalderaCategoryStyle.style(for: .safeToSpend).primary
                        ),
                        size: 34,
                        iconSize: 14
                    )

                    Text(selectedPayScheduleTitle)
                        .font(.headline)
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: AppSpacing.small)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.vertical, AppSpacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .calderaGlassCard(
                    cornerRadius: AppRadii.field,
                    fillOpacity: 0.86,
                    strokeOpacity: 0.70,
                    shadowOpacity: 0.0,
                    shadowRadius: 0,
                    shadowY: 0,
                    darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pay schedule")
            .accessibilityValue(selectedPayScheduleTitle)
        }
    }

    private var focusPicker: some View {
        VStack(
            alignment: .leading,
            spacing: AppSpacing.xSmall
        ) {
            Text("What are you focused on?")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

            VStack(spacing: AppSpacing.small) {
                ForEach(PersonalizationFocus.allCases) { focus in
                    Button {
                        focusRawValue = focus.rawValue
                    } label: {
                        HStack(spacing: AppSpacing.medium) {
                            Image(
                                systemName: focusRawValue == focus.rawValue
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .font(.body.weight(.semibold))
                            .foregroundColor(
                                focusRawValue == focus.rawValue
                                    ? CalderaCategoryStyle.style(for: .safeToSpend).primary
                                    : CalderaVisualStyle.secondaryText(colorScheme)
                            )

                            Text(focus.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AppSpacing.regular)
                        .padding(.vertical, AppSpacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .calderaGlassCard(
                            cornerRadius: AppRadii.field,
                            fillOpacity: focusRawValue == focus.rawValue ? 0.90 : 0.78,
                            strokeOpacity: focusRawValue == focus.rawValue ? 0.78 : 0.58,
                            shadowOpacity: 0.0,
                            shadowRadius: 0,
                            shadowY: 0,
                            darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(focus.title)
                }
            }
        }
    }

    private var selectedPayScheduleTitle: String {
        AppPersonalization.payScheduleTitle(
            from: payScheduleRawValue
        )
    }
}

struct PersonalizationOnboardingView: View {

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppPersonalizationKeys.hasCompletedPersonalization)
    private var hasCompletedPersonalization = false

    @AppStorage(AppPersonalizationKeys.shouldAutoLaunchTutorial)
    private var shouldAutoLaunchTutorial = false

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.screen) {
                    header

                    VStack(alignment: .leading, spacing: AppSpacing.card) {
                        PersonalizationFormView(
                            showsPlanningPreferences: false
                        )
                    }
                    .padding(AppSpacing.card)
                    .calderaGlassCard(
                        cornerRadius: AppRadii.hero,
                        fillOpacity: 0.90,
                        strokeOpacity: 0.76,
                        shadowOpacity: 0.045,
                        shadowRadius: 22,
                        shadowY: 10,
                        darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
                    )

                    PrimaryButton(
                        "Continue to \(AppBrand.shortName)",
                        systemImage: "sparkles",
                        fillsWidth: true
                    ) {
                        completePersonalization()
                    }

                    Text("You can update this later from More.")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, AppSpacing.screen)
                .padding(.top, AppSpacing.emptyState)
                .padding(.bottom, AppSpacing.emptyState)
                .dismissKeyboardOnBackgroundTap()
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .dismissKeyboardOnBackgroundTap()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .keyboardDismissToolbar()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            CalderaGradientIcon(
                style: CalderaCategoryStyle.style(for: .safeToSpend),
                size: 58,
                iconSize: 25
            )

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("What should we call you?")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .minimumScaleFactor(0.72)
                    .lineLimit(2)

                Text("A name is optional. It helps make your Dashboard feel more personal.")
                    .font(.body.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, AppSpacing.large)
    }

    private func completePersonalization() {
        shouldAutoLaunchTutorial = false
        hasCompletedPersonalization = true
    }
}

struct PersonalizationEditorSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .more)

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: AppSpacing.screen
                    ) {
                        editorHeader

                        VStack(
                            alignment: .leading,
                            spacing: AppSpacing.card
                        ) {
                            PersonalizationFormView()
                        }
                        .padding(AppSpacing.card)
                        .calderaGlassCard(
                            cornerRadius: AppRadii.panel,
                            fillOpacity: 0.88,
                            strokeOpacity: 0.74,
                            shadowOpacity: 0.04,
                            shadowRadius: 18,
                            shadowY: 8,
                            darkGlowColor: CalderaCategoryStyle.style(for: .safeToSpend).primary
                        )
                    }
                    .padding(AppSpacing.screen)
                    .padding(.bottom, AppSpacing.emptyState)
                    .dismissKeyboardOnBackgroundTap()
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollContentBackground(.hidden)
                .dismissKeyboardOnBackgroundTap()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Account Information")
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .keyboardDismissToolbar()
        }
    }

    private var editorHeader: some View {
        HStack(
            alignment: .center,
            spacing: AppSpacing.medium
        ) {
            IconBadge(
                systemImage: "person.crop.circle.badge.checkmark",
                color: CalderaCategoryStyle.style(for: .safeToSpend).primary,
                size: 56,
                iconSize: 22
            )

            VStack(
                alignment: .leading,
                spacing: AppSpacing.xxSmall
            ) {
                Text("Profile")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))

                Text("Account Information")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text("This helps \(AppBrand.shortName) feel more useful. You can change it later.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
