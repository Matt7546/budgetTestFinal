import SwiftUI

enum PrivacyShieldPreference {
    static let storageKey = "privacyShield.hideSensitiveData"
}

enum SensitiveDataVisibility {
    static func shouldHide(
        manuallyHidden: Bool,
        isSceneCaptured: Bool
    ) -> Bool {
        manuallyHidden || isSceneCaptured
    }
}

enum SensitiveValueFormatter {
    static let hiddenValue = "••••"

    private static let currencyPattern =
        #"(?:(?:-|−)\s*)?(?:(?:\$(?:US)?|(?:US)?\$)\s*[0-9](?:[0-9,.]|\s(?=[0-9]))*|[0-9](?:[0-9,.]|\s(?=[0-9]))*\s*(?:\$(?:US)?|(?:US)?\$))"#

    static func amount(
        _ value: Double,
        isHidden: Bool
    ) -> String {
        isHidden ? hiddenValue : AppFormatters.currency(value)
    }

    static func text(
        _ value: String,
        isHidden: Bool
    ) -> String {
        guard isHidden else {
            return value
        }

        return value.replacingOccurrences(
            of: currencyPattern,
            with: hiddenValue,
            options: .regularExpression
        )
    }

    static func accountMask(
        _ value: String,
        isHidden: Bool
    ) -> String {
        isHidden ? hiddenValue : value
    }
}

extension EnvironmentValues {
    @Entry var isSensitiveDataHidden = false
    @Entry var isSensitiveDataCaptureActive = false
}

struct SensitiveValueText: View {
    @Environment(\.isSensitiveDataHidden)
    private var isSensitiveDataHidden

    let value: String

    init(_ value: String) {
        self.value = value
    }

    private var displayValue: String {
        SensitiveValueFormatter.text(
            value,
            isHidden: isSensitiveDataHidden
        )
    }

    var body: some View {
        Text(displayValue)
            .privacySensitive()
            .accessibilityLabel(displayValue)
    }
}

private struct SensitiveAccessibilityLabelModifier: ViewModifier {
    @Environment(\.isSensitiveDataHidden)
    private var isSensitiveDataHidden

    let label: String

    func body(content: Content) -> some View {
        content.accessibilityLabel(
            SensitiveValueFormatter.text(
                label,
                isHidden: isSensitiveDataHidden
            )
        )
    }
}

private struct SensitiveAccessibilityHintModifier: ViewModifier {
    @Environment(\.isSensitiveDataHidden)
    private var isSensitiveDataHidden

    let hint: String

    func body(content: Content) -> some View {
        content.accessibilityHint(
            SensitiveValueFormatter.text(
                hint,
                isHidden: isSensitiveDataHidden
            )
        )
    }
}

private struct PrivacyShieldedInputModifier: ViewModifier {
    @Environment(\.isSensitiveDataHidden)
    private var isSensitiveDataHidden

    func body(content: Content) -> some View {
        Group {
            if isSensitiveDataHidden {
                content
                    .foregroundStyle(Color.clear)
                    .overlay(alignment: .leading) {
                        Text(SensitiveValueFormatter.hiddenValue)
                            .foregroundColor(AppColors.primaryText)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .accessibilityValue("Hidden")
                    .privacySensitive()
            } else {
                content
            }
        }
    }
}

extension View {
    func sensitiveAccessibilityLabel(
        _ label: String
    ) -> some View {
        modifier(
            SensitiveAccessibilityLabelModifier(label: label)
        )
    }

    func sensitiveAccessibilityHint(
        _ hint: String
    ) -> some View {
        modifier(
            SensitiveAccessibilityHintModifier(hint: hint)
        )
    }

    func privacyShieldedInput() -> some View {
        modifier(PrivacyShieldedInputModifier())
    }
}

struct PrivacyShieldCaptureNotice: View {
    var body: some View {
        Label(
            "Sensitive values are hidden while your screen is being shared.",
            systemImage: "eye.slash.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundColor(AppColors.primaryText)
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .accessibilityAddTraits(.isStaticText)
    }
}
