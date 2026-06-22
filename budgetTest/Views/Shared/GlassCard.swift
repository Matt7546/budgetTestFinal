import SwiftUI

enum GlassCardOverlay {
    case none
    case gradient(colors: [Color])
}

struct GlassCard<Content: View>: View {

    private let cornerRadius: CGFloat
    private let stroke: Color?
    private let strokeWidth: CGFloat
    private let overlay: GlassCardOverlay
    private let accent: Color?
    private let shadow: AppShadow?
    private let content: Content

    init(
        cornerRadius: CGFloat = AppRadii.card,
        stroke: Color? = AppColors.glassStroke,
        strokeWidth: CGFloat = 1,
        overlay: GlassCardOverlay = .none,
        accent: Color? = nil,
        shadow: AppShadow? = AppShadows.softCard,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.overlay = overlay
        self.accent = accent
        self.shadow = shadow
        self.content = content()
    }

    var body: some View {
        content.glassCard(
            cornerRadius: cornerRadius,
            stroke: stroke,
            strokeWidth: strokeWidth,
            overlay: overlay,
            accent: accent,
            shadow: shadow
        )
    }
}

struct GlassCardModifier: ViewModifier {

    let cornerRadius: CGFloat
    let stroke: Color?
    let strokeWidth: CGFloat
    let overlay: GlassCardOverlay
    let accent: Color?
    let shadow: AppShadow?

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                overlayShape
                    .allowsHitTesting(false)
            }
            .overlay {
                accentBloom
                    .allowsHitTesting(false)
            }
            .overlay {
                strokeShape
                    .allowsHitTesting(false)
            }
            .shadow(
                color: shadow?.color ?? .clear,
                radius: shadow?.radius ?? 0,
                x: shadow?.x ?? 0,
                y: shadow?.y ?? 0
            )
    }

    @ViewBuilder
    private var overlayShape: some View {
        switch overlay {
        case .none:
            EmptyView()

        case .gradient(let colors):
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    @ViewBuilder
    private var accentBloom: some View {
        if let accent {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(0.24),
                            accent.opacity(0.10),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 230
                    )
                )
                .blendMode(.plusLighter)
                .opacity(0.72)
                .clipShape(
                    RoundedRectangle(cornerRadius: cornerRadius)
                )
        }
    }

    @ViewBuilder
    private var strokeShape: some View {
        if let accent {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    (stroke ?? AppColors.glassStroke).opacity(0.55),
                    lineWidth: strokeWidth
                )

            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.42),
                            accent.opacity(0.18),
                            AppColors.glassStroke.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: strokeWidth
                )
        } else if let stroke {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    stroke,
                    lineWidth: strokeWidth
                )
        }
    }
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = AppRadii.card,
        stroke: Color? = AppColors.glassStroke,
        strokeWidth: CGFloat = 1,
        overlay: GlassCardOverlay = .none,
        accent: Color? = nil,
        shadow: AppShadow? = AppShadows.softCard
    ) -> some View {
        modifier(
            GlassCardModifier(
                cornerRadius: cornerRadius,
                stroke: stroke,
                strokeWidth: strokeWidth,
                overlay: overlay,
                accent: accent,
                shadow: shadow
            )
        )
    }
}
