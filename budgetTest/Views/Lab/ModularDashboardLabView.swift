#if DEBUG

import SwiftUI

struct ModularDashboardLabView: View {
    @State private var widgets = LabDashboardWidgetCatalog.defaultInstances
    @State private var configurationRequest: LabDashboardWidgetConfigurationRequest?

    var body: some View {
        ZStack {
            CalderaPageBackground(mood: .dashboard)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.screen) {
                    LabDashboardAtAGlanceCard()
                    LabDashboardNextActionCard()

                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        HStack(spacing: AppSpacing.medium) {
                            Text("Your dashboard")
                                .font(.title3.weight(.bold))
                                .foregroundColor(AppColors.primaryText)

                            Spacer(minLength: AppSpacing.small)

                            Button(action: presentAddWidget) {
                                Label("Add widget", systemImage: "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(
                                        CalderaCategoryStyle.style(for: .safeToSpend).primary
                                    )
                                    .padding(.horizontal, AppSpacing.medium)
                                    .padding(.vertical, AppSpacing.small)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                CalderaCategoryStyle.style(for: .safeToSpend).primary
                                                    .opacity(0.12)
                                            )
                                    )
                                    .contentShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the Lab widget configuration flow")
                        }

                        LabDashboardWidgetGrid(
                            widgets: widgets,
                            addWidget: presentAddWidget,
                            editWidget: presentEditWidget,
                            removeWidget: removeWidget
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.floatingTabClearance)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $configurationRequest) { request in
            LabDashboardWidgetPickerSheet(editing: request.widget) { widget in
                saveWidget(widget)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func presentAddWidget() {
        configurationRequest = LabDashboardWidgetConfigurationRequest(widget: nil)
    }

    private func presentEditWidget(_ widget: LabDashboardWidgetInstance) {
        configurationRequest = LabDashboardWidgetConfigurationRequest(widget: widget)
    }

    private func saveWidget(_ widget: LabDashboardWidgetInstance) {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            if let index = widgets.firstIndex(where: { $0.id == widget.id }) {
                widgets[index] = widget
            } else {
                widgets.append(widget)
            }
        }
    }

    private func removeWidget(_ widget: LabDashboardWidgetInstance) {
        withAnimation(.easeInOut(duration: 0.22)) {
            widgets.removeAll { $0.id == widget.id }
        }
    }
}

private struct LabDashboardAtAGlanceCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private let style = CalderaCategoryStyle.style(for: .safeToSpend)

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            HStack(spacing: AppSpacing.small) {
                CalderaGradientIcon(
                    style: style,
                    size: 38,
                    iconSize: 15
                )

                Text("At a glance")
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Spacer(minLength: AppSpacing.small)

                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(style.primary)
            }

            HStack(spacing: 0) {
                LabDashboardSummaryMetric(
                    title: "Cash",
                    value: "$4,680",
                    color: CalderaCategoryStyle.style(for: .bankAccount).primary
                )

                LabDashboardMetricDivider()

                LabDashboardSummaryMetric(
                    title: "Set Aside",
                    value: "$2,838",
                    color: CalderaCategoryStyle.style(for: .reserve).primary
                )

                LabDashboardMetricDivider()

                LabDashboardSummaryMetric(
                    title: "Available",
                    value: "$1,842",
                    color: style.primary
                )
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.72,
            shadowOpacity: colorScheme == .dark ? 0.14 : 0.04,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: style.primary
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "At a glance. Cash $4,680. Set Aside $2,838. Available to Spend $1,842."
        )
    }
}

private struct LabDashboardSummaryMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: AppSpacing.xxSmall) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LabDashboardMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.secondaryText.opacity(0.14))
            .frame(width: 1, height: 34)
            .padding(.horizontal, AppSpacing.small)
    }
}

private struct LabDashboardNextActionCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private let style = CalderaCategoryStyle.style(for: .debtPayoff)

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.regular) {
            CalderaGradientIcon(
                systemImage: "creditcard.fill",
                colors: style.gradient,
                size: 48,
                iconSize: 18
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("NEXT ACTION")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(style.primary)

                Text("Set aside $249 for Platinum")
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(2)

                Text("Due Sep 1 · Statement balance")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: AppSpacing.xSmall)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(style.primary)
        }
        .padding(AppSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.72,
            shadowOpacity: colorScheme == .dark ? 0.14 : 0.04,
            shadowRadius: 16,
            shadowY: 7,
            darkGlowColor: style.primary
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Next Action. Set aside $249 for Platinum. Due September 1, Statement balance."
        )
    }
}

#endif
