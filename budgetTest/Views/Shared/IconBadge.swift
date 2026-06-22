import SwiftUI

struct IconBadge: View {

    let systemImage: String
    let color: Color
    let size: CGFloat
    let iconSize: CGFloat

    init(
        systemImage: String,
        color: Color,
        size: CGFloat = 40,
        iconSize: CGFloat = 17
    ) {
        self.systemImage = systemImage
        self.color = color
        self.size = size
        self.iconSize = iconSize
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: size, height: size)

            Image(systemName: systemImage)
                .font(
                    .system(
                        size: iconSize,
                        weight: .semibold
                    )
                )
                .foregroundColor(color)
        }
        .shadow(
            color: color.opacity(0.16),
            radius: 10,
            y: 4
        )
    }
}
