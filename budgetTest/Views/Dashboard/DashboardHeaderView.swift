import SwiftUI

struct DashboardHeaderView: View {

    let greeting: String
    let onSettings: () -> Void

    @AppStorage(AppPersonalizationKeys.preferredName)
    private var preferredName = ""

    init(
        greeting: String,
        onSettings: @escaping () -> Void = {}
    ) {
        self.greeting = greeting
        self.onSettings = onSettings
    }

    var body: some View {
        HStack(alignment: .top) {

            VStack(alignment: .leading, spacing: 4) {

                if let preferredDisplayName {
                    Text(greeting)
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)

                    Text(preferredDisplayName)
                        .font(
                            .system(
                                size: 38,
                                weight: .bold
                            )
                        )
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text(greeting.replacingOccurrences(of: ",", with: ""))
                        .font(
                            .system(
                                size: 34,
                                weight: .bold
                            )
                        )
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Text(
                    Date.now.formatted(
                        .dateTime
                            .weekday(.wide)
                            .month()
                            .day()
                    )
                )
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            Spacer(minLength: 12)

            Button(action: onSettings) {
                ZStack {

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 54, height: 54)
                        .overlay {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.34),
                                            Color.white.opacity(0.12)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                    Circle()
                        .stroke(
                            Color.white.opacity(0.78),
                            lineWidth: 1
                        )
                        .frame(width: 54, height: 54)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                }
            }
            .buttonStyle(.plain)
            .shadow(
                color: AppColors.shadowCompact,
                radius: 14,
                y: 8
            )
            .accessibilityLabel("Open Settings")
        }
    }

    private var preferredDisplayName: String? {
        AppPersonalization.preferredDisplayName(
            from: preferredName
        )
    }
}
