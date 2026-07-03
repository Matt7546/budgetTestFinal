import SwiftUI
import UIKit

struct KeyboardDismissModifier: ViewModifier {

    let title: String

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button(title) {
                        UIApplication.shared.dismissKeyboard()
                    }
                    .font(.body.weight(.semibold))
                }
            }
    }
}

struct KeyboardDismissOnBackgroundTapModifier: ViewModifier {

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.dismissKeyboard()
                    }
            }
    }
}

extension View {

    func keyboardDismissToolbar(
        title: String = "Done"
    ) -> some View {
        modifier(
            KeyboardDismissModifier(
                title: title
            )
        )
    }

    func dismissKeyboardOnBackgroundTap() -> some View {
        modifier(KeyboardDismissOnBackgroundTapModifier())
    }
}

extension UIApplication {

    func dismissKeyboard() {
        sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
