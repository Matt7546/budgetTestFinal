import SwiftUI

struct HoldToConfirmActionGate: Equatable {

    private(set) var isHolding = false
    private(set) var didComplete = false
    private(set) var didCancel = false

    mutating func begin() -> Bool {
        guard !isHolding,
              !didComplete,
              !didCancel else {
            return false
        }

        isHolding = true
        return true
    }

    mutating func cancel() {
        guard isHolding,
              !didComplete else {
            return
        }

        isHolding = false
        didCancel = true
    }

    mutating func complete() -> Bool {
        guard isHolding,
              !didComplete else {
            return false
        }

        isHolding = false
        didComplete = true
        return true
    }

    mutating func reset() {
        isHolding = false
        didComplete = false
        didCancel = false
    }
}

struct HoldToCoverInFullButton: View {

    private static let holdDuration: Duration = .milliseconds(900)
    private static let dragCancellationDistance: CGFloat = 14

    @Environment(\.accessibilityVoiceOverEnabled)
    private var voiceOverEnabled

    @Environment(\.accessibilitySwitchControlEnabled)
    private var switchControlEnabled

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.isSensitiveDataHidden)
    private var isSensitiveDataHidden

    let color: Color
    let isCovered: Bool
    let isEnabled: Bool
    let isSaving: Bool
    let accessibilityConfirmationMessage: String
    let onConfirmed: () -> Void

    @State private var fillProgress: CGFloat = 0
    @State private var fillOrigin: CGPoint = .zero
    @State private var actionGate = HoldToConfirmActionGate()
    @State private var holdTask: Task<Void, Never>?
    @State private var isCommitting = false
    @State private var showsAccessibilityConfirmation = false

    private var usesAccessibilityFallback: Bool {
        voiceOverEnabled || switchControlEnabled
    }

    private var canInteract: Bool {
        isEnabled &&
            !isCovered &&
            !isSaving &&
            !isCommitting
    }

    var body: some View {
        Button(action: accessibilityActivate) {
            GeometryReader { proxy in
                buttonContent(size: proxy.size)
            }
            .frame(height: 50)
        }
        .buttonStyle(.plain)
        .disabled(!canInteract)
        .contentShape(Capsule(style: .continuous))
        .simultaneousGesture(holdGesture)
        .accessibilityLabel(
            isCovered
                ? "Fully Covered"
                : CoverInFullPolicy.actionTitle
        )
        .accessibilityValue(
            isSaving || isCommitting
                ? "Saving"
                : ""
        )
        .accessibilityHint(accessibilityHint)
        .confirmationDialog(
            CoverInFullPolicy.actionTitle,
            isPresented: $showsAccessibilityConfirmation,
            titleVisibility: .visible
        ) {
            Button(CoverInFullPolicy.actionTitle) {
                commitConfirmedAction()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                SensitiveValueFormatter.text(
                    accessibilityConfirmationMessage,
                    isHidden: isSensitiveDataHidden
                )
            )
            .privacySensitive()
        }
        .onChange(of: canInteract) { _, canInteract in
            if !canInteract {
                cancelHold()
                actionGate.reset()
            }
        }
        .onDisappear {
            cancelHold()
            actionGate.reset()
        }
    }

    private func buttonContent(
        size: CGSize
    ) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    color.opacity(
                        colorScheme == .dark ? 0.16 : 0.10
                    )
                )

            if fillProgress > 0 {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(0.52),
                                color.opacity(0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(
                        width: fillDiameter(in: size),
                        height: fillDiameter(in: size)
                    )
                    .scaleEffect(max(fillProgress, 0.001))
                    .position(fillOrigin)
                    .allowsHitTesting(false)
            }

            HStack(spacing: AppSpacing.small) {
                if isSaving || isCommitting {
                    ProgressView()
                        .controlSize(.small)

                    Text("Saving…")
                } else if isCovered {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Fully Covered")
                } else {
                    Image(systemName: "hand.tap.fill")
                    Text(CoverInFullPolicy.holdActionTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundColor(
                isCovered
                    ? CalderaCategoryStyle.style(for: .covered).primary
                    : CalderaVisualStyle.primaryText(colorScheme)
            )
            .padding(.horizontal, AppSpacing.regular)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(
                    color.opacity(
                        colorScheme == .dark ? 0.38 : 0.25
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(Capsule(style: .continuous))
        .opacity(isEnabled || isCovered ? 1 : 0.58)
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !usesAccessibilityFallback,
                      canInteract else {
                    return
                }

                let distance = hypot(
                    value.translation.width,
                    value.translation.height
                )
                guard distance <= Self.dragCancellationDistance else {
                    cancelHold()
                    return
                }

                startHoldIfNeeded(at: value.startLocation)
            }
            .onEnded { _ in
                guard !usesAccessibilityFallback else {
                    return
                }

                if actionGate.isHolding {
                    cancelHold()
                }

                if actionGate.didCancel {
                    actionGate.reset()
                }
            }
    }

    private var accessibilityHint: String {
        if isCovered {
            return "The remaining amount is already set aside."
        }

        if usesAccessibilityFallback {
            return "Activates a confirmation before setting aside the remaining amount."
        }

        return "Press and hold to set aside the remaining amount. No money moves."
    }

    private func startHoldIfNeeded(
        at location: CGPoint
    ) {
        guard actionGate.begin() else { return }

        fillOrigin = location
        holdTask?.cancel()

        withAnimation(.linear(duration: 0.9)) {
            fillProgress = 1
        }

        holdTask = Task { @MainActor in
            try? await Task.sleep(for: Self.holdDuration)
            guard !Task.isCancelled,
                  actionGate.complete() else {
                return
            }

            commitConfirmedAction()
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        actionGate.cancel()

        withAnimation(.easeOut(duration: 0.18)) {
            fillProgress = 0
        }
    }

    private func commitConfirmedAction() {
        guard canInteract else {
            resetAfterCommit()
            return
        }

        isCommitting = true
        holdTask = nil

        Task { @MainActor in
            await Task.yield()
            onConfirmed()
            resetAfterCommit()
        }
    }

    private func resetAfterCommit() {
        isCommitting = false
        actionGate.reset()

        withAnimation(.easeOut(duration: 0.20)) {
            fillProgress = 0
        }
    }

    private func fillDiameter(
        in size: CGSize
    ) -> CGFloat {
        let horizontalDistance = max(
            fillOrigin.x,
            size.width - fillOrigin.x
        )
        let verticalDistance = max(
            fillOrigin.y,
            size.height - fillOrigin.y
        )

        return hypot(
            horizontalDistance,
            verticalDistance
        ) * 2
    }

    private func accessibilityActivate() {
        guard usesAccessibilityFallback,
              canInteract else {
            return
        }

        showsAccessibilityConfirmation = true
    }
}
