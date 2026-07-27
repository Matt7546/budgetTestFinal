import SwiftUI

struct PlanningSwipeToSaveInteraction: View {

    let circleCenter: CGPoint
    let circleDiameter: CGFloat
    let affordanceCenter: CGPoint
    let isEnabled: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    let onSaveTriggered: () -> Void
    @Binding private var swipeProgress: CGFloat

    private let swipeThreshold: CGFloat = 84

    init(
        circleCenter: CGPoint,
        circleDiameter: CGFloat,
        affordanceCenter: CGPoint,
        isEnabled: Bool,
        accessibilityLabel: String = "Save goal",
        accessibilityHint: String =
            "Swipe up or activate to create this goal.",
        swipeProgress: Binding<CGFloat>,
        onSaveTriggered: @escaping () -> Void
    ) {
        self.circleCenter = circleCenter
        self.circleDiameter = circleDiameter
        self.affordanceCenter = affordanceCenter
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        _swipeProgress = swipeProgress
        self.onSaveTriggered = onSaveTriggered
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(
                    width: circleDiameter,
                    height: circleDiameter
                )
                .contentShape(Circle())
                .position(circleCenter)
                .gesture(swipeGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(
                    isEnabled
                        ? "Ready to save"
                        : "Complete the goal name and target amount first"
                )
                .accessibilityHint(accessibilityHint)
                .accessibilityAddTraits(.isButton)
                .disabled(!isEnabled)
                .accessibilityAction {
                    guard isEnabled else { return }
                    onSaveTriggered()
                }

            PlanningSwipeToSaveAffordance(
                swipeProgress: swipeProgress,
                isEnabled: isEnabled
            )
            .position(affordanceCenter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard isEnabled else { return }

                let upwardDistance = max(
                    -value.translation.height,
                    0
                )
                let progress = min(
                    upwardDistance / swipeThreshold,
                    1
                )

                withAnimation(
                    .interactiveSpring(
                        response: 0.24,
                        dampingFraction: 0.88
                    )
                ) {
                    swipeProgress = progress
                }
            }
            .onEnded { value in
                guard isEnabled else { return }

                let upwardDistance = max(
                    -value.translation.height,
                    0
                )

                if upwardDistance >= swipeThreshold {
                    onSaveTriggered()
                } else {
                    withAnimation(
                        .spring(
                            response: 0.34,
                            dampingFraction: 0.82
                        )
                    ) {
                        swipeProgress = 0
                    }
                }
            }
    }
}

struct PlanningCreationSuccessOverlay: View {

    let title: String
    let isPresented: Bool
    let showsConfetti: Bool

    @State private var confettiProgress: CGFloat = 0

    var body: some View {
        ZStack {
            if showsConfetti {
                confetti
            }

            VStack(spacing: AppSpacing.regular) {
                Image(systemName: "checkmark.circle.fill")
                    .font(
                        .system(
                            size: 46,
                            weight: .semibold
                        )
                    )

                Text(title)
                    .font(
                        .system(
                            size: 42,
                            weight: .bold,
                            design: .rounded
                        )
                    )
            }
        }
        .foregroundStyle(Color.white)
        .shadow(
            color: Color.black.opacity(0.18),
            radius: 18,
            y: 8
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .task(id: isPresented) {
            guard isPresented,
                  showsConfetti else {
                confettiProgress = 0
                return
            }

            confettiProgress = 0
            try? await Task.sleep(
                nanoseconds: 60_000_000
            )
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.52)) {
                confettiProgress = 1
            }
        }
    }

    private var confetti: some View {
        ZStack {
            ForEach(
                PlanningCreationConfettiParticle.particles
            ) { particle in
                RoundedRectangle(
                    cornerRadius: particle.size / 2,
                    style: .continuous
                )
                .fill(Color.white)
                .frame(
                    width: particle.size * 0.62,
                    height: particle.size * 1.82
                )
                .rotationEffect(
                    .degrees(
                        particle.rotation
                            + (120 * confettiProgress)
                    )
                )
                .scaleEffect(
                    0.72 + (0.28 * confettiProgress)
                )
                .offset(
                    x: particle.originX
                        + (particle.horizontalTravel * confettiProgress),
                    y: particle.originY
                        + (particle.verticalTravel * confettiProgress)
                )
                .opacity(
                    0.92 * (1 - confettiProgress)
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PlanningSwipeToSaveAffordance: View {

    let swipeProgress: CGFloat
    let isEnabled: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Swipe up to save")
                .font(.subheadline.weight(.bold))

            VStack(spacing: 4) {
                Image(systemName: "chevron.up")
                    .font(.title2.weight(.bold))

                Image(systemName: "chevron.up")
                    .font(.title3.weight(.bold))

                Image(systemName: "chevron.up")
                    .font(.body.weight(.bold))
            }
        }
        .foregroundStyle(Color.white)
        .frame(width: 236)
        .padding(.vertical, AppSpacing.medium)
        .offset(y: -18 * swipeProgress)
        .scaleEffect(1 + (0.04 * swipeProgress))
        .opacity(
            isEnabled
                ? 0.78 + (0.22 * swipeProgress)
                : 0.42
        )
        .shadow(
            color: Color.black.opacity(
                0.12 + (0.10 * swipeProgress)
            ),
            radius: 12,
            y: 5
        )
    }
}

private struct PlanningCreationConfettiParticle: Identifiable {

    let id: Int
    let originX: CGFloat
    let originY: CGFloat
    let horizontalTravel: CGFloat
    let verticalTravel: CGFloat
    let size: CGFloat
    let rotation: Double

    static let particles: [PlanningCreationConfettiParticle] = [
        .init(id: 0, originX: -78, originY: -72, horizontalTravel: -68, verticalTravel: -66, size: 8, rotation: -30),
        .init(id: 1, originX: -32, originY: -92, horizontalTravel: -34, verticalTravel: -76, size: 7, rotation: 24),
        .init(id: 2, originX: 32, originY: -92, horizontalTravel: 34, verticalTravel: -76, size: 7, rotation: -52),
        .init(id: 3, originX: 78, originY: -72, horizontalTravel: 68, verticalTravel: -66, size: 8, rotation: 36),
        .init(id: 4, originX: -142, originY: -22, horizontalTravel: -72, verticalTravel: -30, size: 9, rotation: -18),
        .init(id: 5, originX: 142, originY: -22, horizontalTravel: 72, verticalTravel: -30, size: 9, rotation: 48),
        .init(id: 6, originX: -152, originY: 34, horizontalTravel: -76, verticalTravel: 12, size: 8, rotation: -42),
        .init(id: 7, originX: 152, originY: 34, horizontalTravel: 76, verticalTravel: 12, size: 8, rotation: 16),
        .init(id: 8, originX: -110, originY: 82, horizontalTravel: -54, verticalTravel: 48, size: 7, rotation: -34),
        .init(id: 9, originX: 110, originY: 82, horizontalTravel: 54, verticalTravel: 48, size: 7, rotation: 26),
        .init(id: 10, originX: -102, originY: -108, horizontalTravel: -54, verticalTravel: -62, size: 8, rotation: 42),
        .init(id: 11, originX: 102, originY: -108, horizontalTravel: 54, verticalTravel: -62, size: 8, rotation: -24),
        .init(id: 12, originX: -174, originY: 4, horizontalTravel: -62, verticalTravel: -8, size: 7, rotation: 30),
        .init(id: 13, originX: 174, originY: 4, horizontalTravel: 62, verticalTravel: -8, size: 7, rotation: -40),
        .init(id: 14, originX: -72, originY: 112, horizontalTravel: -34, verticalTravel: 42, size: 8, rotation: 18),
        .init(id: 15, originX: 72, originY: 112, horizontalTravel: 34, verticalTravel: 42, size: 8, rotation: -28)
    ]
}
