#if DEBUG

import SwiftUI
import Combine

/// The current Lab-only animated dashboard color field.
struct LabDashboardAmbientBlobView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var accumulatedAnimationDuration: TimeInterval = 0
    @State private var animationBeganAt: Date?
    @State private var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    let isVisible: Bool

    init(isVisible: Bool = true) {
        self.isVisible = isVisible
    }

    /// Rendering at final size avoids a larger offscreen texture being downscaled every frame.
    private let renderScale: CGFloat = 0.55
    private let layerDurations: [Double] = [7.3, 6.0, 6.2, 6.8, 7.4, 8.0, 6.1, 6.6, 7.9, 6.3, 7.0, 6.4, 7.7]
    private let layerDelays: [Double] = [0.0, 0.15, 0.70, 0.35, 1.10, 0.55, 0.90, 0.25, 0.80, 0.45, 0.65, 1.00, 0.40]
    private let driftDuration = 7.5
    private let echoLayers: [LabAmbientEcho] = [
        .init(phaseIndex: 0, width: 1.053, height: 1.053, x: 0.45, y: 0.38, blur: 42, hue: 14, colors: [.pink.opacity(0.20), .purple.opacity(0.18), .blue.opacity(0.14)]),
        .init(phaseIndex: 1, width: 1.053, height: 1.008, x: 0.50, y: 0.56, blur: 48, hue: 12, colors: [.pink.opacity(0.34), .purple.opacity(0.42), .indigo.opacity(0.38)]),
        .init(phaseIndex: 2, width: 1.053, height: 1.008, x: 0.54, y: 0.52, blur: 48, hue: 16, colors: [.purple.opacity(0.38), .indigo.opacity(0.44), .blue.opacity(0.40)]),
        .init(phaseIndex: 7, width: 0.78, height: 0.72, x: 0.44, y: 0.45, blur: 40, hue: 16, colors: [.pink.opacity(0.34), .purple.opacity(0.38), .indigo.opacity(0.26)]),
        .init(phaseIndex: 8, width: 0.80, height: 0.76, x: 0.57, y: 0.58, blur: 42, hue: 18, colors: [.purple.opacity(0.34), .indigo.opacity(0.42), .blue.opacity(0.32)]),
        .init(phaseIndex: 9, width: 0.76, height: 0.78, x: 0.62, y: 0.67, blur: 40, hue: 20, colors: [.indigo.opacity(0.32), .blue.opacity(0.42), .purple.opacity(0.28)]),
        .init(phaseIndex: 10, width: 0.90, height: 0.86, x: 0.52, y: 0.52, blur: 49, hue: 12, colors: [.pink.opacity(0.26), .purple.opacity(0.38), .indigo.opacity(0.34)]),
        .init(phaseIndex: 11, width: 0.84, height: 0.80, x: 0.54, y: 0.60, blur: 47, hue: 18, colors: [.purple.opacity(0.30), .indigo.opacity(0.40), .blue.opacity(0.34)])
    ]

    var body: some View {
        GeometryReader { proxy in
            let unscaledBlobWidth = proxy.size.width * 0.90
            let unscaledBlobHeight = min(
                proxy.size.height * 0.72,
                unscaledBlobWidth * 1.48
            )
            let blobWidth = unscaledBlobWidth * renderScale
            let blobHeight = unscaledBlobHeight * renderScale

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimate)) { context in
                let elapsed = animationElapsed(at: context.date)

                ZStack {
                referenceField(
                    colors: [
                        Color(red: 0.88, green: 0.34, blue: 0.92).opacity(0.24),
                        Color(red: 1.00, green: 0.16, blue: 0.58).opacity(0.20),
                        Color(red: 0.70, green: 0.10, blue: 1.00).opacity(0.18),
                        Color(red: 0.51, green: 0.38, blue: 1.00).opacity(0.14),
                        .clear
                    ],
                    width: blobWidth * 0.94,
                    height: blobHeight * 0.94,
                    x: 0.43,
                    y: 0.40,
                    blur: 40,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: -10, to: 20, progress: layerPhase(at: 0, elapsed: elapsed))))
                .saturation(interpolate(from: 0.90, to: 1.35, progress: layerPhase(at: 0, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.55, to: 0.82, progress: layerPhase(at: 0, elapsed: elapsed)))
                .offset(layerDrift(at: 0, width: blobWidth * 0.94, height: blobHeight * 0.94, elapsed: elapsed))

                ForEach(echoLayers.indices, id: \.self) { index in
                    echoLayer(
                        echoLayers[index],
                        blobWidth: blobWidth,
                        blobHeight: blobHeight,
                        phase: layerPhase(at: echoLayers[index].phaseIndex, elapsed: elapsed),
                        drift: layerDrift(
                            at: index + 13,
                            width: blobWidth * echoLayers[index].width,
                            height: blobHeight * echoLayers[index].height,
                            elapsed: elapsed
                        )
                    )
                }

                referenceTransitionField(
                    colors: [
                        Color(red: 0.96, green: 0.12, blue: 0.80).opacity(0.88),
                        Color(red: 0.91, green: 0.10, blue: 0.90).opacity(0.90),
                        Color(red: 0.58, green: 0.14, blue: 1.00).opacity(0.86),
                        Color(red: 0.34, green: 0.20, blue: 1.00).opacity(0.78)
                    ],
                    width: blobWidth * 0.94,
                    height: blobHeight * 0.90,
                    x: 0.52,
                    y: 0.54,
                    blur: 46,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: 8, to: -10, progress: layerPhase(at: 1, elapsed: elapsed))))
                .saturation(interpolate(from: 1.05, to: 1.24, progress: layerPhase(at: 1, elapsed: elapsed)))
                .opacity(layerOpacity(from: 1.00, to: 0.15, progress: layerPhase(at: 1, elapsed: elapsed)))
                .offset(layerDrift(at: 1, width: blobWidth * 0.94, height: blobHeight * 0.90, elapsed: elapsed))

                referenceTransitionField(
                    colors: [
                        Color(red: 0.91, green: 0.10, blue: 0.90).opacity(0.76),
                        Color(red: 0.58, green: 0.12, blue: 1.00).opacity(0.92),
                        Color(red: 0.34, green: 0.20, blue: 1.00).opacity(0.90),
                        Color(red: 0.38, green: 0.18, blue: 1.00).opacity(0.82)
                    ],
                    width: blobWidth * 0.94,
                    height: blobHeight * 0.90,
                    x: 0.52,
                    y: 0.54,
                    blur: 46,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: -10, to: 16, progress: layerPhase(at: 2, elapsed: elapsed))))
                .saturation(interpolate(from: 1.05, to: 1.30, progress: layerPhase(at: 2, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.05, to: 1.00, progress: layerPhase(at: 2, elapsed: elapsed)))
                .offset(layerDrift(at: 2, width: blobWidth * 0.94, height: blobHeight * 0.90, elapsed: elapsed))

                referenceTransitionField(
                    colors: [
                        Color(red: 0.96, green: 0.12, blue: 0.80).opacity(0.56),
                        Color(red: 0.70, green: 0.10, blue: 1.00).opacity(0.62),
                        Color(red: 0.34, green: 0.20, blue: 1.00).opacity(0.56),
                        Color(red: 0.38, green: 0.18, blue: 1.00).opacity(0.48)
                    ],
                    width: blobWidth * 0.90,
                    height: blobHeight * 0.86,
                    x: 0.50,
                    y: 0.54,
                    blur: 47,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: 8, to: -10, progress: layerPhase(at: 10, elapsed: elapsed))))
                .saturation(interpolate(from: 1.02, to: 1.28, progress: layerPhase(at: 10, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.325, to: 0.675, progress: layerPhase(at: 10, elapsed: elapsed)))
                .offset(layerDrift(at: 10, width: blobWidth * 0.90, height: blobHeight * 0.86, elapsed: elapsed))

                referenceTransitionField(
                    colors: [
                        Color(red: 0.94, green: 0.10, blue: 0.86).opacity(0.46),
                        Color(red: 0.58, green: 0.12, blue: 1.00).opacity(0.58),
                        Color(red: 0.22, green: 0.26, blue: 1.00).opacity(0.60),
                        Color(red: 0.02, green: 0.46, blue: 1.00).opacity(0.54),
                        Color(red: 0.85, green: 0.12, blue: 0.96).opacity(0.38)
                    ],
                    width: blobWidth * 0.84,
                    height: blobHeight * 0.80,
                    x: 0.56,
                    y: 0.58,
                    blur: 45,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: -12, to: 26, progress: layerPhase(at: 11, elapsed: elapsed))))
                .saturation(interpolate(from: 1.04, to: 1.54, progress: layerPhase(at: 11, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.24, to: 0.52, progress: layerPhase(at: 11, elapsed: elapsed)))
                .offset(layerDrift(at: 11, width: blobWidth * 0.84, height: blobHeight * 0.80, elapsed: elapsed))

                referenceField(
                    colors: [
                        Color(red: 0.85, green: 0.12, blue: 0.96).opacity(0.48),
                        Color(red: 0.50, green: 0.16, blue: 1.00).opacity(0.50),
                        Color(red: 0.22, green: 0.26, blue: 1.00).opacity(0.44),
                        .clear
                    ],
                    width: blobWidth * 0.78,
                    height: blobHeight * 0.74,
                    x: 0.47,
                    y: 0.55,
                    blur: 44,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: 10, to: -8, progress: layerPhase(at: 12, elapsed: elapsed))))
                .saturation(interpolate(from: 1.02, to: 1.26, progress: layerPhase(at: 12, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.24, to: 0.50, progress: layerPhase(at: 12, elapsed: elapsed)))
                .offset(layerDrift(at: 12, width: blobWidth * 0.78, height: blobHeight * 0.74, elapsed: elapsed))

                referenceField(
                    colors: [
                        Color(red: 1.00, green: 0.16, blue: 0.60).opacity(0.42),
                        Color(red: 0.96, green: 0.12, blue: 0.80).opacity(0.40),
                        Color(red: 0.85, green: 0.12, blue: 0.96).opacity(0.44),
                        Color(red: 0.58, green: 0.14, blue: 1.00).opacity(0.38),
                        .clear
                    ],
                    width: blobWidth * 0.72,
                    height: blobHeight * 0.68,
                    x: 0.47,
                    y: 0.51,
                    blur: 42,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: 10, to: -18, progress: layerPhase(at: 3, elapsed: elapsed))))
                .saturation(interpolate(from: 1.00, to: 1.45, progress: layerPhase(at: 3, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.32, to: 0.58, progress: layerPhase(at: 3, elapsed: elapsed)))
                .offset(layerDrift(at: 3, width: blobWidth * 0.72, height: blobHeight * 0.68, elapsed: elapsed))

                referenceTransitionField(
                    colors: [
                        Color(red: 0.94, green: 0.10, blue: 0.86).opacity(0.42),
                        Color(red: 0.85, green: 0.12, blue: 0.96).opacity(0.50),
                        Color(red: 0.58, green: 0.14, blue: 1.00).opacity(0.56),
                        Color(red: 0.34, green: 0.20, blue: 1.00).opacity(0.52),
                        Color(red: 0.10, green: 0.42, blue: 1.00).opacity(0.48)
                    ],
                    width: blobWidth * 0.75,
                    height: blobHeight * 0.70,
                    x: 0.55,
                    y: 0.58,
                    blur: 43,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: -10, to: 16, progress: layerPhase(at: 4, elapsed: elapsed))))
                .saturation(interpolate(from: 1.00, to: 1.42, progress: layerPhase(at: 4, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.28, to: 0.56, progress: layerPhase(at: 4, elapsed: elapsed)))
                .offset(layerDrift(at: 4, width: blobWidth * 0.75, height: blobHeight * 0.70, elapsed: elapsed))

                referenceField(
                    colors: [
                        Color(red: 0.50, green: 0.16, blue: 1.00).opacity(0.46),
                        Color(red: 0.70, green: 0.10, blue: 1.00).opacity(0.44),
                        Color(red: 0.10, green: 0.43, blue: 1.00).opacity(0.44),
                        Color(red: 0.02, green: 0.46, blue: 1.00).opacity(0.40),
                        .clear
                    ],
                    width: blobWidth * 0.62,
                    height: blobHeight * 0.72,
                    x: 0.61,
                    y: 0.63,
                    blur: 42,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: -14, to: 24, progress: layerPhase(at: 5, elapsed: elapsed))))
                .saturation(interpolate(from: 1.02, to: 1.48, progress: layerPhase(at: 5, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.30, to: 0.60, progress: layerPhase(at: 5, elapsed: elapsed)))
                .offset(layerDrift(at: 5, width: blobWidth * 0.62, height: blobHeight * 0.72, elapsed: elapsed))

                referenceTransitionField(
                    colors: [
                        Color(red: 0.72, green: 0.14, blue: 1.00).opacity(0.30),
                        Color(red: 0.58, green: 0.12, blue: 1.00).opacity(0.42),
                        Color(red: 0.22, green: 0.26, blue: 1.00).opacity(0.50),
                        Color(red: 0.10, green: 0.43, blue: 1.00).opacity(0.58),
                        Color(red: 0.02, green: 0.46, blue: 1.00).opacity(0.62)
                    ],
                    width: blobWidth * 0.68,
                    height: blobHeight * 0.60,
                    x: 0.62,
                    y: 0.64,
                    blur: 39,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: 14, to: -18, progress: layerPhase(at: 6, elapsed: elapsed))))
                .saturation(interpolate(from: 1.04, to: 1.55, progress: layerPhase(at: 6, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.34, to: 0.62, progress: layerPhase(at: 6, elapsed: elapsed)))
                .offset(layerDrift(at: 6, width: blobWidth * 0.68, height: blobHeight * 0.60, elapsed: elapsed))

                referenceField(
                    colors: [
                        Color(red: 1.00, green: 0.12, blue: 0.55).opacity(0.74),
                        Color(red: 0.96, green: 0.12, blue: 0.80).opacity(0.72),
                        Color(red: 0.95, green: 0.07, blue: 0.84).opacity(0.60),
                        Color(red: 0.70, green: 0.10, blue: 1.00).opacity(0.52),
                        .clear
                    ],
                    width: blobWidth * 0.78,
                    height: blobHeight * 0.72,
                    x: 0.42,
                    y: 0.47,
                    blur: 38,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: 12, to: -24, progress: layerPhase(at: 7, elapsed: elapsed))))
                .saturation(interpolate(from: 1.05, to: 1.55, progress: layerPhase(at: 7, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.68, to: 0.92, progress: layerPhase(at: 7, elapsed: elapsed)))
                .offset(layerDrift(at: 7, width: blobWidth * 0.78, height: blobHeight * 0.72, elapsed: elapsed))

                referenceField(
                    colors: [
                        Color(red: 0.70, green: 0.10, blue: 1.00).opacity(0.72),
                        Color(red: 0.58, green: 0.12, blue: 1.00).opacity(0.70),
                        Color(red: 0.34, green: 0.20, blue: 1.00).opacity(0.64),
                        Color(red: 0.10, green: 0.43, blue: 1.00).opacity(0.58),
                        .clear
                    ],
                    width: blobWidth * 0.80,
                    height: blobHeight * 0.76,
                    x: 0.55,
                    y: 0.60,
                    blur: 40,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: -12, to: 22, progress: layerPhase(at: 8, elapsed: elapsed))))
                .saturation(interpolate(from: 1.08, to: 1.60, progress: layerPhase(at: 8, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.64, to: 0.94, progress: layerPhase(at: 8, elapsed: elapsed)))
                .offset(layerDrift(at: 8, width: blobWidth * 0.80, height: blobHeight * 0.76, elapsed: elapsed))

                referenceBlueFlow(
                    width: blobWidth * 0.76,
                    height: blobHeight * 0.78,
                    x: 0.64,
                    y: 0.65,
                    blur: 38,
                    containerWidth: blobWidth,
                    containerHeight: blobHeight
                )
                .hueRotation(.degrees(interpolate(from: 16, to: -22, progress: layerPhase(at: 9, elapsed: elapsed))))
                .saturation(interpolate(from: 1.10, to: 1.70, progress: layerPhase(at: 9, elapsed: elapsed)))
                .opacity(layerOpacity(from: 0.66, to: 1.00, progress: layerPhase(at: 9, elapsed: elapsed)))
                .offset(layerDrift(at: 9, width: blobWidth * 0.76, height: blobHeight * 0.78, elapsed: elapsed))
                }
                .frame(width: blobWidth, height: blobHeight)
                .compositingGroup()
                .opacity(0.72)
                .position(
                    x: proxy.size.width - blobWidth * 0.62,
                    y: blobHeight * 0.60 + 25
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            synchronizeAnimationState(isActive: shouldAnimate)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSProcessInfoPowerStateDidChange
            )
        ) { _ in
            isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: shouldAnimate) { _, shouldAnimate in
            synchronizeAnimationState(isActive: shouldAnimate)
        }
    }

    private func referenceField(
        colors: [Color],
        width: CGFloat,
        height: CGFloat,
        x: CGFloat,
        y: CGFloat,
        blur: CGFloat,
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: colors,
                    center: .center,
                    startRadius: 0,
                    endRadius: max(width, height) * 0.54
                )
            )
            .frame(width: width, height: height)
            .blur(radius: blur * renderScale)
            .offset(
                x: containerWidth * (x - 0.5),
                y: containerHeight * (y - 0.5)
            )
    }

    private func echoLayer(
        _ echo: LabAmbientEcho,
        blobWidth: CGFloat,
        blobHeight: CGFloat,
        phase: Double,
        drift: CGSize
    ) -> some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: echo.colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: blobWidth * echo.width, height: blobHeight * echo.height)
            .blur(radius: echo.blur * renderScale)
            .offset(
                x: blobWidth * (echo.x - 0.5),
                y: blobHeight * (echo.y - 0.5)
            )
            .hueRotation(.degrees(interpolate(from: echo.hue * 0.45, to: -echo.hue, progress: phase)))
            .saturation(interpolate(from: 1.02, to: 1.28, progress: phase))
            .opacity(layerOpacity(from: echo.opacity(0.11), to: echo.opacity(0.22), progress: phase))
            .offset(drift)
    }

    private func referenceBlueFlow(
        width: CGFloat,
        height: CGFloat,
        x: CGFloat,
        y: CGFloat,
        blur: CGFloat,
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) -> some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        Color(red: 0.85, green: 0.12, blue: 0.96).opacity(0.44),
                        Color(red: 0.20, green: 0.32, blue: 1.00).opacity(0.54),
                        Color(red: 0.00, green: 0.39, blue: 1.00).opacity(0.78),
                        Color(red: 0.50, green: 0.16, blue: 1.00).opacity(0.66),
                        Color(red: 0.18, green: 0.15, blue: 1.00).opacity(0.68),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: width, height: height)
            .blur(radius: blur * renderScale)
            .offset(
                x: containerWidth * (x - 0.5),
                y: containerHeight * (y - 0.5)
            )
    }

    private func referenceTransitionField(
        colors: [Color],
        width: CGFloat,
        height: CGFloat,
        x: CGFloat,
        y: CGFloat,
        blur: CGFloat,
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) -> some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: width, height: height)
            .blur(radius: blur * renderScale)
            .offset(
                x: containerWidth * (x - 0.5),
                y: containerHeight * (y - 0.5)
            )
    }

    private var shouldAnimate: Bool {
        isVisible &&
            scenePhase == .active &&
            !reduceMotion &&
            !isLowPowerModeEnabled
    }

    private func synchronizeAnimationState(isActive: Bool) {
        let now = Date()

        if isActive {
            guard animationBeganAt == nil else { return }
            animationBeganAt = now
        } else if let animationBeganAt {
            accumulatedAnimationDuration += now.timeIntervalSince(animationBeganAt)
            self.animationBeganAt = nil
        }
    }

    private func animationElapsed(at date: Date) -> TimeInterval {
        // Keep using the most recent timeline date during the state transition into
        // a pause, then persist that exact elapsed value in synchronizeAnimationState.
        guard let animationBeganAt else {
            return accumulatedAnimationDuration
        }

        return accumulatedAnimationDuration + date.timeIntervalSince(animationBeganAt)
    }

    private func layerPhase(at index: Int, elapsed: TimeInterval) -> Double {
        let delayedElapsed = max(0, elapsed - layerDelays[index])
        let fullCycle = layerDurations[index] * 2
        let cycleProgress = (delayedElapsed.truncatingRemainder(dividingBy: fullCycle)) / layerDurations[index]
        let triangleProgress = cycleProgress <= 1 ? cycleProgress : 2 - cycleProgress

        return 0.5 - (0.5 * cos(.pi * triangleProgress))
    }

    private func interpolate(from: Double, to: Double, progress: Double) -> Double {
        from + ((to - from) * progress)
    }

    private func layerOpacity(from: Double, to: Double, progress: Double) -> Double {
        min(0.40, interpolate(from: from, to: to, progress: progress))
    }

    private func layerDrift(
        at index: Int,
        width: CGFloat,
        height: CGFloat,
        elapsed: TimeInterval
    ) -> CGSize {
        let segment = Int((elapsed / driftDuration).rounded(.down))
        let segmentProgress = (elapsed.truncatingRemainder(dividingBy: driftDuration)) / driftDuration
        let easedProgress = segmentProgress * segmentProgress * (3 - (2 * segmentProgress))
        let start = driftTarget(for: index, segment: segment)
        let end = driftTarget(for: index, segment: segment + 1)
        let x = interpolate(from: Double(start.x), to: Double(end.x), progress: easedProgress)
        let y = interpolate(from: Double(start.y), to: Double(end.y), progress: easedProgress)

        return CGSize(width: width * CGFloat(x), height: height * CGFloat(y))
    }

    private func driftTarget(for layer: Int, segment: Int) -> LabAmbientDrift {
        let seed = Double((layer + 1) * 1_009 + (segment + 1) * 7_919)
        let angle = pseudoRandom(seed) * 2 * .pi
        let distance = pseudoRandom(seed + 31.7) * 0.15

        return LabAmbientDrift(
            x: CGFloat(cos(angle) * distance),
            y: CGFloat(sin(angle) * distance)
        )
    }

    private func pseudoRandom(_ seed: Double) -> Double {
        let value = sin((seed * 12.9898) + 78.233) * 43_758.5453
        return value - value.rounded(.down)
    }
}

private struct LabAmbientEcho {
    let phaseIndex: Int
    let width: CGFloat
    let height: CGFloat
    let x: CGFloat
    let y: CGFloat
    let blur: CGFloat
    let hue: Double
    let colors: [Color]

    /// The largest echo layers form the blob's soft perimeter and dissolve into the page background.
    func opacity(_ value: Double) -> Double {
        max(width, height) >= 0.90 ? value * 0.95 : value
    }
}

private struct LabAmbientDrift: Equatable {
    let x: CGFloat
    let y: CGFloat
}

#endif
