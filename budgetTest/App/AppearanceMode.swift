import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {

    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .system:
            return "Match System"

        case .light:
            return "Light"

        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil

        case .light:
            return .light

        case .dark:
            return .dark
        }
    }
}
