import SwiftUI

struct SnapshotScreen<Content: View>: View {

    let title: String
    let onDone: () -> Void
    let content: Content

    init(
        title: String,
        onDone: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onDone = onDone
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        AppColors.screenGradientTop,
                        AppColors.screenGradientBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.screen) {
                        content
                    }
                    .padding()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button("Done") {
                        onDone()
                    }
                    .accessibilityLabel("Close \(title)")
                }
            }
        }
    }
}

struct SnapshotHeroCard: View {

    let title: String
    let value: Double
    let subtitle: String

    var body: some View {
        let accentColor =
            value >= 0
            ? AppColors.accent
            : AppColors.negative

        VStack(spacing: AppSpacing.small) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.secondaryText)

            MetricValue(
                value,
                font: .system(
                    size: 42,
                    weight: .bold
                ),
                color: value >= 0
                    ? AppColors.primaryText
                    : AppColors.negative,
                minimumScaleFactor: 0.6,
                lineLimit: 1
            )

            Text(subtitle)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.panel)
        .glassCard(
            cornerRadius: AppRadii.panel,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.glassOverlayCyan,
                    AppColors.glassOverlayBlue
                ]
            ),
            accent: accentColor,
            shadow: AppShadows.softPanel
        )
        .accessibilityElement(children: .combine)
    }
}

struct SnapshotPanel<Content: View>: View {

    let alignment: HorizontalAlignment
    let content: Content

    init(
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        VStack(
            alignment: alignment,
            spacing: AppSpacing.medium
        ) {
            content
        }
        .padding()
        .glassCard(
            cornerRadius: AppRadii.field,
            overlay: .gradient(
                colors: [
                    AppColors.glassOverlayWhite,
                    AppColors.glassOverlayCyan,
                    AppColors.glassOverlaySurface
                ]
            ),
            shadow: nil
        )
    }
}
