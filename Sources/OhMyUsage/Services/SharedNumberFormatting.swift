import Foundation

/// Shared number formatting for user-visible usage/quota surfaces.
///
/// Consolidates the per-file `NumberFormatter()` copies that Settings views
/// and usage display paths used to construct on every call, so grouping
/// separators, fraction digits, and percent rounding stay consistent app-wide
/// without duplicating formatter configuration.
///
/// Thread safety: `NumberFormatter` is not thread-safe (mutating instance
/// state such as locale or fraction digits while another thread formats can
/// crash or corrupt output). The cached formatters below are only touched
/// while holding `formatterLock`, which makes every entry point safe to call
/// from the main actor (SwiftUI views) and from background refresh paths
/// (presenter/provider formatting) alike, without per-call allocation. The
/// uncontended lock cost is negligible compared to formatting itself.
enum SharedNumberFormatting {
    /// Formats an integer with grouping separators, e.g. `1234567` → "1,234,567".
    ///
    /// - Parameter localeID: pass `"en_US_POSIX"` to pin comma grouping
    ///   regardless of the user's locale; `nil` keeps the current locale
    ///   (matching what a freshly constructed `NumberFormatter` used to do).
    static func groupedInteger(_ value: Int, localeID: String? = nil) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        configureDecimalStyle(integerFormatter, localeID: localeID)
        integerFormatter.minimumFractionDigits = 0
        integerFormatter.maximumFractionDigits = 0
        return integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Formats a decimal value with fixed fraction digits (0–2 recommended),
    /// e.g. `1234.5` with `2...2` → "1,234.50".
    ///
    /// The `String(format:)` fallback mirrors the previous per-call sites and
    /// only triggers for values `NumberFormatter` refuses (e.g. NaN).
    static func decimal(
        _ value: Double,
        minFractionDigits: Int,
        maxFractionDigits: Int,
        grouping: Bool = true,
        localeID: String? = nil
    ) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        configureDecimalStyle(decimalFormatter, localeID: localeID)
        decimalFormatter.usesGroupingSeparator = grouping
        decimalFormatter.minimumFractionDigits = max(0, minFractionDigits)
        decimalFormatter.maximumFractionDigits = max(0, maxFractionDigits)
        let fallback = String(format: "%.\(max(0, maxFractionDigits))f", value)
        return decimalFormatter.string(from: NSNumber(value: value)) ?? fallback
    }

    /// Formats a fraction (0...1) as a percentage, e.g. `0.1234` → "12.3%".
    ///
    /// Always uses the current locale, matching the previous percent call
    /// sites (percent rendering follows the user's locale settings).
    static func percent(
        _ value: Double,
        minFractionDigits: Int,
        maxFractionDigits: Int
    ) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        percentFormatter.locale = Locale.current
        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = max(0, minFractionDigits)
        percentFormatter.maximumFractionDigits = max(0, maxFractionDigits)
        let fallbackFraction = minFractionDigits > 0
            ? "." + String(repeating: "0", count: minFractionDigits)
            : ""
        return percentFormatter.string(from: NSNumber(value: value)) ?? "0\(fallbackFraction)%"
    }

    // MARK: - Cached formatters

    private static let formatterLock = NSLock()
    private static let integerFormatter = NumberFormatter()
    private static let decimalFormatter = NumberFormatter()
    private static let percentFormatter = NumberFormatter()

    /// Applies the configuration shared by integer/decimal call sites.
    private static func configureDecimalStyle(_ formatter: NumberFormatter, localeID: String?) {
        formatter.locale = localeID.map { Locale(identifier: $0) } ?? Locale.current
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
    }
}
