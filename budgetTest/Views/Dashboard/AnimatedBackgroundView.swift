import SwiftUI

struct AnimatedBackgroundView: View {

    @State private var animate = false

    var body: some View {

        LinearGradient(
            colors: [
                AppColors.screenGradientTop,
                AppColors.screenGradientBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            auroraLayers
        }
        .overlay {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.clear,
                    AppColors.accent.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .ignoresSafeArea()
        .onAppear {

            withAnimation(
                .easeInOut(duration: 28)
                .repeatForever(
                    autoreverses: true
                )
            ) {
                animate = true
            }
        }
    }

    private var auroraLayers: some View {
        ZStack {
            Circle()
                .fill(
                    AppColors.accentSecondary.opacity(0.10)
                )
                .frame(
                    width: 520,
                    height: 520
                )
                .blur(radius: 110)
                .offset(
                    x: animate ? 120 : -110,
                    y: animate ? -90 : 105
                )

            Circle()
                .fill(
                    AppColors.accent.opacity(0.08)
                )
                .frame(
                    width: 500,
                    height: 500
                )
                .blur(radius: 120)
                .offset(
                    x: animate ? -105 : 95,
                    y: animate ? 160 : -120
                )

            Circle()
                .fill(
                    AppColors.protected.opacity(0.06)
                )
                .frame(
                    width: 460,
                    height: 460
                )
                .blur(radius: 125)
                .offset(
                    x: animate ? 85 : -75,
                    y: animate ? 250 : -210
                )
        }
        .allowsHitTesting(false)
    }
}
