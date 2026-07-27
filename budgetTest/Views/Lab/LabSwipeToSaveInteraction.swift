#if DEBUG

import SwiftUI

struct LabSwipeToSaveInteraction: View {

    let circleCenter: CGPoint
    let circleDiameter: CGFloat
    let affordanceCenter: CGPoint
    let promptText: String
    let isEnabled: Bool
    let swipeThreshold: CGFloat
    let affordanceStyle: AnyShapeStyle
    let onProgressChanged: (CGFloat) -> Void
    let onSaveTriggered: () -> Void
    @Binding private var swipeProgress: CGFloat

    init(
        circleCenter: CGPoint,
        circleDiameter: CGFloat,
        affordanceCenter: CGPoint,
        promptText: String = "Swipe up to save",
        isEnabled: Bool = true,
        swipeProgress: Binding<CGFloat>,
        swipeThreshold: CGFloat = 84,
        affordanceStyle: AnyShapeStyle = AnyShapeStyle(Color.white),
        onProgressChanged: @escaping (CGFloat) -> Void = { _ in },
        onSaveTriggered: @escaping () -> Void
    ) {
        self.circleCenter = circleCenter
        self.circleDiameter = circleDiameter
        self.affordanceCenter = affordanceCenter
        self.promptText = promptText
        self.isEnabled = isEnabled
        self._swipeProgress = swipeProgress
        self.swipeThreshold = swipeThreshold
        self.affordanceStyle = affordanceStyle
        self.onProgressChanged = onProgressChanged
        self.onSaveTriggered = onSaveTriggered
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: circleDiameter, height: circleDiameter)
                .contentShape(Circle())
                .position(circleCenter)
                .gesture(swipeGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Save")
                .accessibilityValue("Ready to save")
                .accessibilityHint("Swipe up anywhere in the lower circle or activate to save this Lab prototype.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    onSaveTriggered()
                }

            LabSwipeToSaveAffordance(
                promptText: promptText,
                swipeProgress: swipeProgress,
                style: affordanceStyle
            )
            .position(affordanceCenter)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(isEnabled)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard isEnabled else { return }

                let progress = min(max(-value.translation.height, 0) / swipeThreshold, 1)
                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.88)) {
                    swipeProgress = progress
                    onProgressChanged(progress)
                }
            }
            .onEnded { value in
                guard isEnabled else { return }

                let upwardDistance = max(-value.translation.height, 0)
                if upwardDistance >= swipeThreshold {
                    onSaveTriggered()
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) {
                        swipeProgress = 0
                        onProgressChanged(0)
                    }
                }
            }
    }
}

struct LabSwipeSaveSuccessOverlay: View {

    let successText: String
    let isPresented: Bool
    let showsConfetti: Bool
    let successStyle: AnyShapeStyle
    let confettiColor: Color
    let onAnimationCompleted: (() -> Void)?
    @State private var confettiProgress: CGFloat = 0

    init(
        successText: String,
        isPresented: Bool,
        showsConfetti: Bool = true,
        successStyle: AnyShapeStyle = AnyShapeStyle(Color.white),
        confettiColor: Color = .white,
        onAnimationCompleted: (() -> Void)? = nil
    ) {
        self.successText = successText
        self.isPresented = isPresented
        self.showsConfetti = showsConfetti
        self.successStyle = successStyle
        self.confettiColor = confettiColor
        self.onAnimationCompleted = onAnimationCompleted
    }

    var body: some View {
        ZStack {
            if showsConfetti {
                successConfetti
            }

            VStack(spacing: AppSpacing.regular) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46, weight: .semibold))

                Text(successText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(successStyle)
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(successText)
        .task(id: isPresented) {
            guard isPresented else {
                await MainActor.run {
                    confettiProgress = 0
                }
                return
            }

            await MainActor.run {
                confettiProgress = 0
            }

            if showsConfetti {
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.52)) {
                        confettiProgress = 1
                    }
                }
            }

            try? await Task.sleep(nanoseconds: 640_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                onAnimationCompleted?()
            }
        }
    }

    private var successConfetti: some View {
        ZStack {
            ForEach(LabSwipeToSaveConfettiParticle.particles) { particle in
                RoundedRectangle(cornerRadius: particle.size / 2, style: .continuous)
                    .fill(confettiColor)
                    .frame(width: particle.size * 0.62, height: particle.size * 1.82)
                    .rotationEffect(.degrees(particle.rotation + (120 * confettiProgress)))
                    .scaleEffect(0.72 + (0.28 * confettiProgress))
                    .offset(
                        x: particle.originX + (particle.horizontalTravel * confettiProgress),
                        y: particle.originY + (particle.verticalTravel * confettiProgress)
                    )
                    .opacity(0.92 * (1 - confettiProgress))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LabSwipeToSaveAffordance: View {

    let promptText: String
    let swipeProgress: CGFloat
    let style: AnyShapeStyle

    var body: some View {
        VStack(spacing: 16) {
            Text(promptText)
                .font(.subheadline.weight(.bold))
                .opacity(0.78 + (0.22 * swipeProgress))

            VStack(spacing: 4) {
                Image(systemName: "chevron.up")
                    .font(.title2.weight(.bold))

                Image(systemName: "chevron.up")
                    .font(.title3.weight(.bold))

                Image(systemName: "chevron.up")
                    .font(.body.weight(.bold))
            }
            .opacity(0.66 + (0.34 * swipeProgress))
        }
        .foregroundStyle(style)
        .frame(width: 236)
        .padding(.vertical, AppSpacing.medium)
        .offset(y: -18 * swipeProgress)
        .scaleEffect(1 + (0.04 * swipeProgress))
        .shadow(
            color: Color.black.opacity(0.12 + (0.10 * swipeProgress)),
            radius: 12,
            y: 5
        )
    }
}

private struct LabSwipeToSaveConfettiParticle: Identifiable {
    let id: Int
    let originX: CGFloat
    let originY: CGFloat
    let horizontalTravel: CGFloat
    let verticalTravel: CGFloat
    let size: CGFloat
    let rotation: Double

    static let particles: [LabSwipeToSaveConfettiParticle] = [
        // Origins surround the check/title stack, keeping the label's center clear.
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

#endif
