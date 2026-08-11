import Foundation

public enum OfficialValueParser {
    private static let placeholderValues: Set<String> = [
        "-", "--", "unknown", "undefined", "null", "nil", "none", "n/a", "na", "(null)", "(unknown)"
    ]

    public static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    public static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    public static func string(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    public static func nonPlaceholderString(_ value: Any?) -> String? {
        guard let text = string(value) else { return nil }
        return placeholderValues.contains(text.lowercased()) ? nil : text
    }

    public static func isoDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: raw)
    }

    public static func httpDate(_ raw: String?) -> Date? {
        guard let raw = string(raw) else { return nil }
        for format in [
            "EEE',' dd MMM yyyy HH':'mm':'ss zzz", // RFC 1123
            "EEEE',' dd-MMM-yy HH':'mm':'ss zzz", // RFC 850
            "EEE MMM d HH':'mm':'ss yyyy" // ANSI C asctime
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let parsed = formatter.date(from: raw) {
                return parsed
            }
        }
        return nil
    }

    public static func responseServerDate(_ response: HTTPURLResponse) -> Date? {
        httpDate(response.value(forHTTPHeaderField: "Date"))
    }

    public static func clockSkew(response: HTTPURLResponse, localReceiveAt: Date = Date()) -> TimeInterval? {
        guard let serverNow = responseServerDate(response) else { return nil }
        return localReceiveAt.timeIntervalSince(serverNow)
    }

    public static func applyClockSkew(_ date: Date?, skew: TimeInterval?) -> Date? {
        guard let date else { return nil }
        guard let skew else { return date }
        return date.addingTimeInterval(skew)
    }

    public static func epochDate(seconds: Any?) -> Date? {
        if let number = double(seconds) {
            return Date(timeIntervalSince1970: number)
        }
        return nil
    }
}
