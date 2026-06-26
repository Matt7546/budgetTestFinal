import SwiftUI

enum PlannerEventColor: String, CaseIterable, Identifiable {
    case blue
    case purple
    case green
    case orange
    case red
    case gray

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .blue:
            return "Blue"
        case .purple:
            return "Purple"
        case .green:
            return "Green"
        case .orange:
            return "Orange"
        case .red:
            return "Red"
        case .gray:
            return "Gray"
        }
    }

    var color: Color {
        switch self {
        case .blue:
            return AppColors.accent
        case .purple:
            return AppColors.protected
        case .green:
            return AppColors.spendable
        case .orange:
            return AppColors.warning
        case .red:
            return AppColors.negative
        case .gray:
            return AppColors.secondaryText
        }
    }

    static func color(for id: String?) -> Color? {
        guard
            let id,
            let eventColor = PlannerEventColor(rawValue: id)
        else {
            return nil
        }

        return eventColor.color
    }
}
