import SwiftUI

struct SectionHeader: View {


let title: String
@Binding var isExpanded: Bool

var body: some View {

    Button {

        withAnimation(
            .spring(
                response: 0.35,
                dampingFraction: 0.8
            )
        ) {
            isExpanded.toggle()
        }

    } label: {

        HStack {

            Text(title)
                .font(
                    .system(
                        size: 24,
                        weight: .bold
                    )
                )

            Spacer()

            ZStack {

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 36, height: 36)

                Image(
                    systemName:
                        isExpanded
                        ? "chevron.up"
                        : "chevron.down"
                )
                .font(.caption.bold())
            }
        }
        .foregroundColor(
            Color(
                red: 0.10,
                green: 0.14,
                blue: 0.22
            )
        )
    }
    .buttonStyle(.plain)
}


}
