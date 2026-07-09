import SwiftUI

struct RecurringExpenseRecommendationsView: View {
    let groups: RecurringExpenseRecommendationGroups
    let onAddToPlanAhead: (RecurringExpenseSuggestion) -> Void
    let onNotNow: (RecurringExpenseSuggestion) -> Void
    let onReviewAgain: (RecurringExpenseSuggestion) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                CalderaPageBackground(mood: .timeline)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.screen) {
                        header

                        if groups.totalCount == 0 {
                            EmptyStateView(
                                systemImage: CalderaCategoryStyle.style(for: .upcomingExpense).icon,
                                title: "Nothing to review right now",
                                description: "Refresh Bank Sync after more activity to check again.",
                                color: CalderaCategoryStyle.style(for: .upcomingExpense).primary
                            )
                        }

                        if !groups.needsReview.isEmpty {
                            recommendationSection(
                                title: "Needs review",
                                subtitle: "Patterns that may help you plan ahead.",
                                suggestions: groups.needsReview,
                                mode: .needsReview
                            )
                        }

                        if !groups.added.isEmpty {
                            recommendationSection(
                                title: "Added to Plan Ahead",
                                subtitle: "Already represented in Upcoming Expenses.",
                                suggestions: groups.added,
                                mode: .added
                            )
                        }

                        if !groups.dismissed.isEmpty {
                            recommendationSection(
                                title: "Not now",
                                subtitle: "Suggestions you set aside for later.",
                                suggestions: groups.dismissed,
                                mode: .dismissed
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
                    .padding(.bottom, AppSpacing.floatingTabClearance)
                }
                .scrollContentBackground(.hidden)
            }
            .calderaTopScrollFade(mood: .timeline)
            .navigationTitle("Recommended recurring expenses")
            .navigationBarTitleDisplayMode(.inline)
            .calderaTransparentNavigationSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onClose()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text("Recommended recurring expenses")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Caldera found patterns that may help you plan ahead. Nothing is added unless you choose it.")
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func recommendationSection(
        title: String,
        subtitle: String,
        suggestions: [RecurringExpenseSuggestion],
        mode: RecurringRecommendationCardMode
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(AppColors.primaryText)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppSpacing.medium) {
                ForEach(suggestions) { suggestion in
                    recommendationCard(
                        suggestion,
                        mode: mode
                    )
                }
            }
        }
    }

    private func recommendationCard(
        _ suggestion: RecurringExpenseSuggestion,
        mode: RecurringRecommendationCardMode
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            CalderaGradientIcon(
                style: CalderaCategoryStyle.style(for: .upcomingExpense),
                size: 44,
                iconSize: 18
            )

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text("Suggested upcoming expense")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(suggestion.bodyText)
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if mode == .added {
                    statusPill("Already in Plan Ahead")
                }

                switch mode {
                case .needsReview:
                    needsReviewActions(for: suggestion)

                case .added:
                    EmptyView()

                case .dismissed:
                    Button {
                        onReviewAgain(suggestion)
                    } label: {
                        Text("Review again")
                            .font(.caption.weight(.bold))
                            .foregroundColor(CalderaCategoryStyle.style(for: .upcomingExpense).primary)
                            .padding(.horizontal, AppSpacing.medium)
                            .padding(.vertical, AppSpacing.xSmall)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(CalderaCategoryStyle.style(for: .upcomingExpense).primary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.xxSmall)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.card)
        .calderaGlassCard(
            cornerRadius: AppRadii.card,
            fillOpacity: 0.86,
            strokeOpacity: 0.68,
            shadowOpacity: 0.025,
            shadowRadius: 14,
            shadowY: 7,
            darkGlowColor: CalderaCategoryStyle.style(for: .upcomingExpense).primary
        )
    }

    private func needsReviewActions(
        for suggestion: RecurringExpenseSuggestion
    ) -> some View {
        HStack(spacing: AppSpacing.small) {
            Button {
                onAddToPlanAhead(suggestion)
            } label: {
                Text("Add to Plan Ahead")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.xSmall)
                    .background(
                        LinearGradient(
                            colors: CalderaCategoryStyle.style(for: .upcomingExpense).gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule(style: .continuous)
                    )
            }
            .buttonStyle(.plain)

            Button {
                onNotNow(suggestion)
            } label: {
                Text("Not now")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.xSmall)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColors.secondaryText.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, AppSpacing.xxSmall)
    }

    private func statusPill(
        _ title: String
    ) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundColor(CalderaCategoryStyle.style(for: .covered).primary)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.xxSmall)
            .background(
                Capsule(style: .continuous)
                    .fill(CalderaCategoryStyle.style(for: .covered).primary.opacity(0.12))
            )
    }
}

private enum RecurringRecommendationCardMode {
    case needsReview
    case added
    case dismissed
}
