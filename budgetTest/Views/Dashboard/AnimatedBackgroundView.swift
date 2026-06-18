import SwiftUI

struct AnimatedBackgroundView: View {

    @State private var animate = false

    var body: some View {

        ZStack {

            Color(
                red: 0.96,
                green: 0.97,
                blue: 1.00
            )

            Circle()
                .fill(
                    Color.cyan.opacity(0.18)
                )
                .frame(
                    width: 450,
                    height: 450
                )
                .blur(radius: 70)
                .offset(
                    x: animate ? 140 : -140,
                    y: animate ? -120 : 120
                )

            Circle()
                .fill(
                    Color.blue.opacity(0.15)
                )
                .frame(
                    width: 400,
                    height: 400
                )
                .blur(radius: 80)
                .offset(
                    x: animate ? -120 : 120,
                    y: animate ? 180 : -180
                )

            Circle()
                .fill(
                    Color.green.opacity(0.12)
                )
                .frame(
                    width: 350,
                    height: 350
                )
                .blur(radius: 90)
                .offset(
                    x: animate ? 80 : -80,
                    y: animate ? 250 : -250
                )
        }
        .ignoresSafeArea()
        .onAppear {

            withAnimation(
                .easeInOut(duration: 18)
                .repeatForever(
                    autoreverses: true
                )
            ) {
                animate = true
            }
        }
    }
}
