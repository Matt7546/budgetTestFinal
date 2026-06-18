import SwiftUI

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.12, blue: 0.18),
                        Color(red: 0.06, green: 0.07, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 28)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(
                        Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: .black.opacity(0.25),
                radius: 20,
                y: 10
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
