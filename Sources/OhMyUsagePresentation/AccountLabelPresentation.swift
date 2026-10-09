import Foundation

public enum AccountLabelPresentation {
    private static let placeholders: Set<String> = [
        "-", "--", "unknown", "undefined", "null", "nil", "none", "n/a", "na", "(null)", "(unknown)"
    ]

    public static func displayable(_ label: String?) -> String? {
        guard let text = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !placeholders.contains(text.lowercased()) else { return nil }
        return text
    }
}
