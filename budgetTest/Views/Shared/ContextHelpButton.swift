import SwiftUI

struct ContextHelpButton: View {

    let title: String
    let bodyText: String
    let breakdownItems: [String]
    let footnote: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var showsHelp = false

    init(
        title: String,
        bodyText: String,
        breakdownItems: [String] = [],
        footnote: String? = nil
    ) {
        self.title = title
        self.bodyText = bodyText
        self.breakdownItems = breakdownItems
        self.footnote = footnote
    }

    var body: some View {
        Button {
            showsHelp = true
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Learn about \(title)")
        .sheet(isPresented: $showsHelp) {
            CalderaHelpSheet(
                title: title,
                bodyText: bodyText,
                breakdownItems: breakdownItems,
                footnote: footnote
            )
        }
    }
}

private struct CalderaHelpSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let bodyText: String
    let breakdownItems: [String]
    let footnote: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .more)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.large) {
                        header

                        Text(bodyText)
                            .font(.body.weight(.medium))
                            .foregroundColor(AppColors.primaryText)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        if !breakdownItems.isEmpty {
                            breakdownCard
                        }

                        if let footnote,
                           !footnote.isEmpty {
                            footnoteCard(footnote)
                        }
                    }
                    .padding(AppSpacing.regular)
                    .padding(.bottom, AppSpacing.emptyState)
                }
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
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
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                systemImage: "questionmark.circle.fill",
                colors: CalderaVisualStyle.dashboardProgressGradient,
                size: 48,
                iconSize: 20
            )

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Quick help")
                    .font(.caption.weight(.bold))
                    .foregroundColor(CalderaVisualStyle.secondaryText(colorScheme))

                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.88,
            strokeOpacity: 0.72,
            shadowOpacity: 0.04,
            shadowRadius: 16,
            shadowY: 8,
            darkGlowColor: AppColors.accent
        )
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            ForEach(Array(breakdownItems.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.panel,
            fillOpacity: 0.86,
            strokeOpacity: 0.66,
            shadowOpacity: 0.025,
            shadowRadius: 12,
            shadowY: 6,
            darkGlowColor: AppColors.accent
        )
        .accessibilityElement(children: .combine)
    }

    private func footnoteCard(
        _ text: String
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            Image(systemName: "info.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.accent)
                .padding(.top, 2)

            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.primaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.control,
            fillOpacity: 0.80,
            strokeOpacity: 0.60,
            shadowOpacity: 0.018,
            shadowRadius: 10,
            shadowY: 4,
            darkGlowColor: AppColors.accent
        )
    }
}
