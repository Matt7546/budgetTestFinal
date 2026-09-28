import Foundation

enum AppPersonalizationKeys {
    static let hasCompletedPersonalization = "personalization.hasCompleted"
    static let hasCompletedTutorial = "tutorial.hasCompleted"
    static let shouldAutoLaunchTutorial = "tutorial.shouldAutoLaunchAfterPersonalization"
    static let preferredName = "personalization.preferredName"
    static let paySchedulePreset = "personalization.paySchedulePreset"
    static let focus = "personalization.focus"
}

struct AppPersonalizationStore {
    static let didChangeNotification = Notification.Name(
        "caldera.personalization-owner-scope-did-change"
    )

    private static let scopedPrefix = "personalization.owner.v1"
    private static let legacyQuarantineMarker =
        "personalization.owner.v1.legacy-quarantined"
    private static let userSpecificKeys = [
        AppPersonalizationKeys.preferredName,
        AppPersonalizationKeys.paySchedulePreset,
        AppPersonalizationKeys.focus,
        DashboardSetupManualCompletionPreference.storageKey
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func string(
        for key: String,
        ownerScopeID: String
    ) -> String {
        quarantineLegacyGlobalValuesIfNeeded()
        return defaults.string(
            forKey: scopedKey(
                key,
                ownerScopeID: ownerScopeID
            )
        ) ?? ""
    }

    func set(
        _ value: String,
        for key: String,
        ownerScopeID: String
    ) {
        quarantineLegacyGlobalValuesIfNeeded()
        defaults.set(
            value,
            forKey: scopedKey(
                key,
                ownerScopeID: ownerScopeID
            )
        )
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil
        )
    }

    func clear(
        ownerScopeID: String
    ) {
        Self.userSpecificKeys.forEach { key in
            defaults.removeObject(
                forKey: scopedKey(
                    key,
                    ownerScopeID: ownerScopeID
                )
            )
        }
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil
        )
    }

    func clearAllScopedValues() {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("\(Self.scopedPrefix).") }
            .forEach(defaults.removeObject)
        Self.userSpecificKeys.forEach(defaults.removeObject)
        defaults.removeObject(forKey: Self.legacyQuarantineMarker)
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil
        )
    }

    func clearLocalDevelopmentValues() {
        Self.userSpecificKeys.forEach { key in
            defaults.removeObject(
                forKey: scopedKey(
                    key,
                    ownerScopeID: PlanningOwnerScope.local
                )
            )
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: Self.legacyQuarantineMarker)
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil
        )
    }

    private func quarantineLegacyGlobalValuesIfNeeded() {
        guard !defaults.bool(forKey: Self.legacyQuarantineMarker) else {
            return
        }

        Self.userSpecificKeys.forEach { key in
            let localKey = scopedKey(
                key,
                ownerScopeID: PlanningOwnerScope.local
            )

            if defaults.object(forKey: localKey) == nil,
               let legacyValue = defaults.object(forKey: key) {
                defaults.set(legacyValue, forKey: localKey)
            }

            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: Self.legacyQuarantineMarker)
    }

    private func scopedKey(
        _ key: String,
        ownerScopeID: String
    ) -> String {
        "\(Self.scopedPrefix).\(ownerScopeID).\(key)"
    }
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
