import SwiftUI

struct PrimaryButton: View {

    private let title: String
    private let systemImage: String?
    private let trailingSystemImage: String?
    private let cornerRadius: CGFloat
    private let isDisabled: Bool
    private let fillsWidth: Bool
    private let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        trailingSystemImage: String? = "arrow.right",
        cornerRadius: CGFloat = AppRadii.field,
        isDisabled: Bool = false,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingSystemImage = trailingSystemImage
        self.cornerRadius = cornerRadius
        self.isDisabled = isDisabled
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                }

                Text(title)

                if let trailingSystemImage {
                    Spacer()

                    Image(systemName: trailingSystemImage)
                }
            }
            .font(.headline)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .foregroundColor(.white)
            .padding()
            .background(
                LinearGradient(
                    colors: [
                        AppColors.primaryButtonStart,
                        AppColors.primaryButtonEnd
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(cornerRadius)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

struct SecondaryButton: View {

    private let title: String
    private let systemImage: String?
    private let trailingSystemImage: String?
    private let cornerRadius: CGFloat
    private let foregroundColor: Color
    private let shadow: AppShadow?
    private let fillsWidth: Bool
    private let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        trailingSystemImage: String? = nil,
        cornerRadius: CGFloat = AppRadii.control,
        foregroundColor: Color = AppColors.ink,
        shadow: AppShadow? = nil,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingSystemImage = trailingSystemImage
        self.cornerRadius = cornerRadius
        self.foregroundColor = foregroundColor
        self.shadow = shadow
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                }

                Text(title)

                if let trailingSystemImage {
                    Spacer()

                    Image(systemName: trailingSystemImage)
                }
            }
            .font(.headline)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .foregroundColor(foregroundColor)
            .padding()
            .calderaGlassCard(
                cornerRadius: cornerRadius,
                fillOpacity: 0.88,
                strokeOpacity: 0.72,
                shadowOpacity: shadow == nil ? 0 : 0.035,
                shadowRadius: shadow?.radius ?? 0,
                shadowY: shadow?.y ?? 0
            )
        }
    }
}

struct DestructiveButton: View {

    private let title: String
    private let systemImage: String?
    private let cornerRadius: CGFloat
    private let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        cornerRadius: CGFloat = AppRadii.field,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.cornerRadius = cornerRadius
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage {
                    Image(systemName: systemImage)
                }

                Text(title)

                Spacer()
            }
            .font(.headline)
            .foregroundColor(AppColors.negative)
            .padding()
            .calderaGlassCard(
                cornerRadius: cornerRadius,
                fillOpacity: 0.88,
                strokeOpacity: 0.70,
                shadowOpacity: 0,
                shadowRadius: 0,
                shadowY: 0,
                darkGlowColor: AppColors.negative
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.negative.opacity(0.22), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}
