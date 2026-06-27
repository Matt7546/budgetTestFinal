import SwiftUI

struct SplashView: View {

    @State private var isVisible = false

    var body: some View {
        ZStack {
            AnimatedAuroraBackground()

            Text("C")
                .font(
                    .system(
                        size: 156,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .scaleEffect(isVisible ? 1 : 0.94)
                .opacity(isVisible ? 1 : 0)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeOut(duration: 0.55)
            ) {
                isVisible = true
            }
        }
    }
}

struct AnimatedAuroraBackground: View {

    @State private var animate = false

    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.02, blue: 0.30),
                Color(red: 0.19, green: 0.04, blue: 0.50),
                Color(red: 0.12, green: 0.03, blue: 0.38)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            ZStack {
                orb(
                    color: Color(red: 0.97, green: 0.33, blue: 0.82),
                    width: 430,
                    height: 430,
                    blur: 72,
                    x: animate ? 80 : -84,
                    y: animate ? -118 : 24,
                    scale: animate ? 1.15 : 0.92,
                    opacity: animate ? 0.76 : 0.60,
                    duration: 3.8
                )

                orb(
                    color: Color(red: 0.93, green: 0.06, blue: 0.58),
                    width: 540,
                    height: 540,
                    blur: 98,
                    x: animate ? -110 : 74,
                    y: animate ? 185 : 286,
                    scale: animate ? 0.95 : 1.14,
                    opacity: animate ? 0.58 : 0.76,
                    duration: 4.5
                )

                orb(
                    color: Color(red: 0.45, green: 0.09, blue: 0.95),
                    width: 520,
                    height: 580,
                    blur: 86,
                    x: animate ? -176 : -56,
                    y: animate ? -232 : -108,
                    scale: animate ? 1.10 : 0.88,
                    opacity: animate ? 0.70 : 0.52,
                    duration: 4.2
                )

                orb(
                    color: Color(red: 0.22, green: 0.13, blue: 0.84),
                    width: 440,
                    height: 520,
                    blur: 92,
                    x: animate ? 150 : -132,
                    y: animate ? 326 : 210,
                    scale: animate ? 0.92 : 1.12,
                    opacity: animate ? 0.48 : 0.66,
                    duration: 4.9
                )

                orb(
                    color: Color(red: 0.16, green: 0.44, blue: 1.0),
                    width: 380,
                    height: 380,
                    blur: 64,
                    x: animate ? -132 : 156,
                    y: animate ? 318 : 166,
                    scale: animate ? 1.18 : 0.90,
                    opacity: animate ? 0.72 : 0.52,
                    duration: 3.6
                )

                orb(
                    color: Color(red: 0.05, green: 0.26, blue: 0.96),
                    width: 420,
                    height: 360,
                    blur: 78,
                    x: animate ? 174 : 26,
                    y: animate ? 218 : 372,
                    scale: animate ? 0.92 : 1.20,
                    opacity: animate ? 0.42 : 0.62,
                    duration: 4.4
                )

                orb(
                    color: Color(red: 1.0, green: 0.55, blue: 0.26),
                    width: 330,
                    height: 330,
                    blur: 68,
                    x: animate ? 166 : 54,
                    y: animate ? -62 : -188,
                    scale: animate ? 1.08 : 0.90,
                    opacity: animate ? 0.56 : 0.36,
                    duration: 5.1
                )

                orb(
                    color: Color(red: 1.0, green: 0.30, blue: 0.34),
                    width: 460,
                    height: 460,
                    blur: 98,
                    x: animate ? 36 : 154,
                    y: animate ? 316 : 172,
                    scale: animate ? 0.94 : 1.12,
                    opacity: animate ? 0.36 : 0.52,
                    duration: 4.7
                )

                orb(
                    color: Color(red: 0.28, green: 0.18, blue: 1.0),
                    width: 620,
                    height: 400,
                    blur: 115,
                    x: animate ? -12 : -150,
                    y: animate ? 408 : 318,
                    scale: animate ? 1.08 : 0.96,
                    opacity: animate ? 0.38 : 0.50,
                    duration: 5.4
                )
            }
        }
        .overlay {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 4.8)
                .repeatForever(autoreverses: true)
            ) {
                animate = true
            }
        }
    }

    private func orb(
        color: Color,
        width: CGFloat,
        height: CGFloat,
        blur: CGFloat,
        x: CGFloat,
        y: CGFloat,
        scale: CGFloat,
        opacity: Double,
        duration: Double
    ) -> some View {
        Ellipse()
            .fill(color.opacity(opacity))
            .frame(width: width, height: height)
            .scaleEffect(scale)
            .blur(radius: blur)
            .offset(x: x, y: y)
            .blendMode(.screen)
            .allowsHitTesting(false)
            .animation(
                .easeInOut(duration: duration)
                .repeatForever(autoreverses: true),
                value: animate
            )
    }
}
