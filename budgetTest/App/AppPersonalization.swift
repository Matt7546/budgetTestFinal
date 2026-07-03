import Foundation

enum AppPersonalizationKeys {
    static let hasCompletedPersonalization = "personalization.hasCompleted"
    static let hasCompletedTutorial = "tutorial.hasCompleted"
    static let shouldAutoLaunchTutorial = "tutorial.shouldAutoLaunchAfterPersonalization"
    static let preferredName = "personalization.preferredName"
    static let paySchedulePreset = "personalization.paySchedulePreset"
    static let focus = "personalization.focus"
}

enum PaySchedulePreset: String, CaseIterable, Identifiable {
    case weekly
    case everyTwoWeeks
    case twiceAMonth
    case monthly
    case irregular
    case notSureYet
    case preferNotToSay

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .everyTwoWeeks:
            return "Every 2 weeks"
        case .twiceAMonth:
            return "Twice a month"
        case .monthly:
            return "Monthly"
        case .irregular:
            return "Irregular / variable"
        case .notSureYet:
            return "Not sure yet"
        case .preferNotToSay:
            return "Prefer not to say"
        }
    }
}

enum PersonalizationFocus: String, CaseIterable, Identifiable {
    case avoidOverspending
    case buildCashCushion
    case saveForGoals
    case stayAheadOfExpenses
    case payDownDebt
    case understandMoney
    case justExploring

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .avoidOverspending:
            return "Avoid overspending"
        case .buildCashCushion:
            return "Build a Cash Cushion"
        case .saveForGoals:
            return "Save for goals"
        case .stayAheadOfExpenses:
            return "Stay ahead of upcoming expenses"
        case .payDownDebt:
            return "Pay down debt"
        case .understandMoney:
            return "Understand where my money goes"
        case .justExploring:
            return "Just exploring"
        }
    }
}

enum AppPersonalization {
    static func preferredDisplayName(
        from value: String
    ) -> String? {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    static func payScheduleTitle(
        from rawValue: String
    ) -> String {
        guard let preset = PaySchedulePreset(
            rawValue: rawValue
        ) else {
            return "Not set"
        }

        return preset.title
    }

    static func focusTitle(
        from rawValue: String
    ) -> String {
        guard let focus = PersonalizationFocus(
            rawValue: rawValue
        ) else {
            return "Not set"
        }

        return focus.title
    }
}
