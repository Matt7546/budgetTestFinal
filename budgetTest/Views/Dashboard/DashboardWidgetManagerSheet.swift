import SwiftUI

struct DashboardWidgetManagerSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @Binding private var storedValue: String
    @State private var preferences: DashboardWidgetPreferences
    @State private var showsResetConfirmation = false

    let unavailableKinds: Set<DashboardWidgetKind>

    init(
        storedValue: Binding<String>,
        unavailableKinds: Set<DashboardWidgetKind>
    ) {
        _storedValue = storedValue
        _preferences = State(
            initialValue: DashboardWidgetPreferences(
                storedValue: storedValue.wrappedValue
            )
        )
        self.unavailableKinds = unavailableKinds
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .dashboard)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.card) {
                        Text("Choose which widgets appear and the order they use on your Dashboard.")
                            .font(.subheadline)
                            .foregroundColor(
                                CalderaVisualStyle.secondaryText(colorScheme)
                            )
                            .fixedSize(horizontal: false, vertical: true)

                        visibleSection

                        if !preferences.hiddenKindsInDefaultOrder.isEmpty {
                            hiddenSection
                        }

                        resetButton
                    }
                    .padding(.horizontal, AppSpacing.regular)
                    .padding(.vertical, AppSpacing.card)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            "Reset Dashboard widgets?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset to Default", role: .destructive) {
                updatePreferences { $0.reset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores every widget, its default timeframe, and the original order.")
        }
    }

    private var visibleSection: some View {
        widgetSection(
            title: "Shown on Dashboard",
            kinds: preferences.visibleKinds
        ) { kind, index in
            visibleRow(kind, index: index)
        }
    }

    private var hiddenSection: some View {
        widgetSection(
            title: "Hidden Widgets",
            kinds: preferences.hiddenKindsInDefaultOrder
        ) { kind, _ in
            hiddenRow(kind)
        }
    }

    private func widgetSection<RowContent: View>(
        title: String,
        kinds: [DashboardWidgetKind],
        @ViewBuilder rowContent: @escaping (DashboardWidgetKind, Int) -> RowContent
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

            VStack(spacing: 0) {
                if kinds.isEmpty {
                    Text("No widgets are currently shown. Add one below.")
                        .font(.subheadline)
                        .foregroundColor(
                            CalderaVisualStyle.secondaryText(colorScheme)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppSpacing.medium)
                } else {
                    ForEach(Array(kinds.enumerated()), id: \.element) { index, kind in
                        rowContent(kind, index)

                        if index < kinds.count - 1 {
                            Divider()
                                .overlay(
                                    CalderaVisualStyle.secondaryText(colorScheme)
                                        .opacity(0.12)
                                )
                                .padding(.leading, 50)
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.medium)
            .calderaGlassCard(
                cornerRadius: AppRadii.card,
                fillOpacity: 0.84,
                strokeOpacity: 0.62,
                shadowOpacity: colorScheme == .dark ? 0.09 : 0.025,
                shadowRadius: 10,
                shadowY: 5,
                darkGlowColor: CalderaCategoryStyle.style(
                    for: .safeToSpend
                ).primary
            )
        }
    }

    private func visibleRow(
        _ kind: DashboardWidgetKind,
        index: Int
    ) -> some View {
        HStack(spacing: AppSpacing.medium) {
            widgetIdentity(kind, isVisible: true)

            Spacer(minLength: AppSpacing.xSmall)

            iconButton(
                systemImage: "arrow.up",
                accessibilityLabel: "Move \(kind.displayName) up",
                isEnabled: preferences.canMoveUp(kind)
            ) {
                updatePreferences { $0.moveUp(kind) }
            }

            iconButton(
                systemImage: "arrow.down",
                accessibilityLabel: "Move \(kind.displayName) down",
                isEnabled: preferences.canMoveDown(kind)
            ) {
                updatePreferences { $0.moveDown(kind) }
            }

            iconButton(
                systemImage: "eye.slash",
                accessibilityLabel: "Remove \(kind.displayName) from Dashboard",
                tint: CalderaVisualStyle.secondaryText(colorScheme)
            ) {
                updatePreferences { $0.hide(kind) }
            }
        }
        .frame(minHeight: 58)
        .accessibilitySortPriority(Double(preferences.visibleKinds.count - index))
    }

    private func hiddenRow(
        _ kind: DashboardWidgetKind
    ) -> some View {
        HStack(spacing: AppSpacing.medium) {
            widgetIdentity(kind, isVisible: false)

            Spacer(minLength: AppSpacing.small)

            iconButton(
                systemImage: "plus.circle.fill",
                accessibilityLabel: "Add \(kind.displayName) to Dashboard",
                tint: CalderaCategoryStyle.style(for: kind.categoryRole).primary
            ) {
                updatePreferences { $0.show(kind) }
            }
        }
        .frame(minHeight: 58)
    }

    private func widgetIdentity(
        _ kind: DashboardWidgetKind,
        isVisible: Bool
    ) -> some View {
        let style = CalderaCategoryStyle.style(for: kind.categoryRole)
        let status: String

        if !isVisible {
            status = "Hidden"
        } else if unavailableKinds.contains(kind) {
            status = "Shown when available"
        } else {
            status = "Visible"
        }

        return HStack(spacing: AppSpacing.small) {
            CalderaGradientIcon(
                systemImage: style.icon,
                colors: style.gradient,
                size: 34,
                iconSize: 13
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(CalderaVisualStyle.primaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(status)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
            }
        }
    }

    private func iconButton(
        systemImage: String,
        accessibilityLabel: String,
        isEnabled: Bool = true,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundColor(
                    tint ?? CalderaCategoryStyle.style(
                        for: .safeToSpend
                    ).primary
                )
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.28)
        .accessibilityLabel(accessibilityLabel)
    }

    private var resetButton: some View {
        Button {
            showsResetConfirmation = true
        } label: {
            Label("Reset to Default", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.medium)
        }
        .buttonStyle(.plain)
        .foregroundColor(
            preferences.isDefault
                ? CalderaVisualStyle.secondaryText(colorScheme)
                : CalderaCategoryStyle.style(for: .safeToSpend).primary
        )
        .disabled(preferences.isDefault)
        .opacity(preferences.isDefault ? 0.55 : 1)
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.78,
            strokeOpacity: 0.55,
            shadowOpacity: 0.02,
            shadowRadius: 8,
            shadowY: 4,
            darkGlowColor: CalderaCategoryStyle.style(
                for: .safeToSpend
            ).primary
        )
    }

    private func updatePreferences(
        _ update: (inout DashboardWidgetPreferences) -> Void
    ) {
        var updated = preferences
        update(&updated)
        preferences = updated
        storedValue = updated.storedValue()
    }
}
