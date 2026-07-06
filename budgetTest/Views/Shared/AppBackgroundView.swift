import SwiftUI

struct AppBackgroundView: View {

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {

        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    AppColors.screenGradientTop,
                    AppColors.screenGradientBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    AppColors.accentSecondary.opacity(colorScheme == .dark ? 0.18 : 0.14),
                    AppColors.accent.opacity(colorScheme == .dark ? 0.12 : 0.09),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 540
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: 90, y: 12)

            RadialGradient(
                colors: [
                    AppColors.protected.opacity(colorScheme == .dark ? 0.10 : 0.07),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 560
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: 110, y: 140)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
