import Foundation

/// Parses user-entered money text into a `Double`, tolerating the dollar
/// sign, thousands-separator commas, and surrounding whitespace so amount
/// fields across Cash Cushion, Goals, Upcoming Expenses, and Payment Plans
/// accept the same input formats.
///
/// This only recognizes plain US-style formatting. It intentionally does
/// not attempt locale-aware number parsing.
enum MoneyAmountParser {

    /// Removes characters that are safe to ignore in money input: dollar
    /// signs, thousands-separator commas, and surrounding whitespace.
    static func sanitizedText(
        _ text: String
    ) -> String {
        text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses sanitized money text into a `Double`. Returns `nil` when the
    /// text is empty (after sanitizing) or cannot be parsed as a number.
    /// Callers decide whether zero, negative, or missing values are
    /// acceptable for their field.
    static func parse(
        _ text: String
    ) -> Double? {
        let sanitized = sanitizedText(text)

        guard !sanitized.isEmpty else {
            return nil
        }

        return Double(sanitized)
    }
}
