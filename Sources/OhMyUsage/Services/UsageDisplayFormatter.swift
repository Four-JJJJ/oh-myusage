import Foundation
import AppKit
import OhMyUsageDomain

enum LocalTrendDisplayMetric: String, CaseIterable, Sendable {
    case tokens
    case responses
}

enum TraeMetricKind: Equatable {
    case dollarBalance
    case autocomplete

    static func detect(id: String, title: String) -> TraeMetricKind? {
        let lowerID = id.lowercased()
        let lowerTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowerID.contains("autocomplete") || lowerTitle.contains("autocomplete") || lowerTitle.contains("自动补全") {
            return .autocomplete
        }
        if lowerID.contains("dollar") || lowerTitle.contains("dollar") || lowerTitle.contains("美元") {
            return .dollarBalance
        }
        return nil
    }
}

enum MetricValueLayoutFormatter {
    static let metricValueMinimumWidth: CGFloat = 46
    static let metricValueReferenceText: String = "900%"
    static let percentageMetricValueReferenceText: String = "100%"
    static var metricValueFont: NSFont { AppFonts.numericNSFont(size: 16, fallbackWeight: .semibold) }

    static var metricValueReferenceTextWidth: CGFloat {
        ceil((metricValueReferenceText as NSString).size(withAttributes: [.font: metricValueFont]).width)
    }

    static var percentageMetricValueReferenceTextWidth: CGFloat {
        ceil((percentageMetricValueReferenceText as NSString).size(withAttributes: [.font: metricValueFont]).width)
    }

    static var metricValueColumnWidth: CGFloat {
        max(metricValueMinimumWidth, metricValueReferenceTextWidth)
    }

    static var percentageMetricValueColumnWidth: CGFloat {
        percentageMetricValueReferenceTextWidth
    }
}

enum TraeValueDisplayFormatter {
    static func format(
        _ value: Double,
        kind: TraeMetricKind,
        maxWidth: CGFloat? = nil,
        font: NSFont? = nil
    ) -> String {
        let candidates = formatCandidates(for: value, kind: kind)
        guard !candidates.isEmpty else { return "-" }
        let deduped = deduplicated(candidates)

        guard let maxWidth else {
            return deduped[0]
        }

        let measureFont = font ?? MetricValueLayoutFormatter.metricValueFont
        for candidate in deduped {
            if measuredWidth(candidate, font: measureFont) <= maxWidth {
                return candidate
            }
        }
        return deduped.last ?? "-"
    }

    private static func formatCandidates(for value: Double, kind: TraeMetricKind) -> [String] {
        switch kind {
        case .dollarBalance:
            return dollarCandidates(value)
        case .autocomplete:
            return autocompleteCandidates(value)
        }
    }

    private static func dollarCandidates(_ value: Double) -> [String] {
        let absValue = abs(value)
        var output: [String] = []
        if absValue < 1 {
            output.append(decimal(value, minFractionDigits: 2, maxFractionDigits: 2, grouping: false))
        } else {
            output.append(decimal(value, minFractionDigits: 0, maxFractionDigits: 2))
        }
        output.append(decimal(value, minFractionDigits: 0, maxFractionDigits: 1))
        output.append(decimal(value, minFractionDigits: 0, maxFractionDigits: 0))
        output.append(compactKOrW(value, maxFractionDigits: 1, fallbackMaxFractionDigits: 0))
        return output
    }

    private static func autocompleteCandidates(_ value: Double) -> [String] {
        let absValue = abs(value)
        if absValue < 1_000 {
            return [
                decimal(value, minFractionDigits: 0, maxFractionDigits: 1, grouping: false),
                decimal(value, minFractionDigits: 0, maxFractionDigits: 0, grouping: false)
            ]
        }
        if absValue < 10_000 {
            return [
                compact(value, divisor: 1_000, suffix: "K", maxFractionDigits: 1),
                compact(value, divisor: 1_000, suffix: "K", maxFractionDigits: 0)
            ]
        }
        return [
            compact(value, divisor: 10_000, suffix: "W", maxFractionDigits: 1),
            compact(value, divisor: 10_000, suffix: "W", maxFractionDigits: 0)
        ]
    }

    private static func compactKOrW(
        _ value: Double,
        maxFractionDigits: Int,
        fallbackMaxFractionDigits: Int
    ) -> String {
        let absValue = abs(value)
        if absValue >= 10_000 {
            return compact(value, divisor: 10_000, suffix: "W", maxFractionDigits: maxFractionDigits)
        }
        if absValue >= 1_000 {
            return compact(value, divisor: 1_000, suffix: "K", maxFractionDigits: maxFractionDigits)
        }
        return decimal(value, minFractionDigits: 0, maxFractionDigits: fallbackMaxFractionDigits, grouping: false)
    }

    private static func compact(
        _ value: Double,
        divisor: Double,
        suffix: String,
        maxFractionDigits: Int
    ) -> String {
        guard divisor > 0 else { return "-" }
        let scaled = value / divisor
        return "\(decimal(scaled, minFractionDigits: 0, maxFractionDigits: maxFractionDigits, grouping: false))\(suffix)"
    }

    private static func decimal(
        _ value: Double,
        minFractionDigits: Int,
        maxFractionDigits: Int,
        grouping: Bool = true
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.minimumFractionDigits = max(0, minFractionDigits)
        formatter.maximumFractionDigits = max(0, maxFractionDigits)
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(max(0, maxFractionDigits))f", value)
    }

    private static func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !output.contains(trimmed) {
                output.append(trimmed)
            }
        }
        return output
    }
}

enum PlanTypeDisplayFormatter {
    private static let supportedProviderTypes: Set<ProviderType> = [
        .codex, .claude, .gemini, .copilot, .microsoftCopilot,
        .zai, .amp, .cursor, .windsurf, .trae, .ollamaCloud,
        .kimi, .grok, .grokBot, .qwen, .relay, .open, .dragon
    ]

    private static let hiddenValues: Set<String> = [
        "-", "unknown", "undefined", "n/a", "na", "none", "null"
    ]

    static func supportsPlanType(providerType: ProviderType) -> Bool {
        supportedProviderTypes.contains(providerType)
    }

    static func normalizedPlanType(_ value: String?, providerType: ProviderType? = nil) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        if providerType == .trae {
            let cleaned = stripTraePlanKeyword(raw)
            guard !cleaned.isEmpty else {
                return nil
            }
            if hiddenValues.contains(cleaned.lowercased()) {
                return nil
            }
            return cleaned
        }

        if hiddenValues.contains(raw.lowercased()) {
            return nil
        }
        return raw
    }

    static func resolvedPlanType(
        providerType: ProviderType,
        extrasPlanType: String?,
        rawPlanType: String?
    ) -> String? {
        guard supportsPlanType(providerType: providerType) else {
            return nil
        }
        guard let resolved = normalizedPlanType(extrasPlanType, providerType: providerType)
            ?? normalizedPlanType(rawPlanType, providerType: providerType) else {
            return nil
        }
        return normalizedDisplayPlanType(resolved, providerType: providerType)
    }

    private static func normalizedDisplayPlanType(_ value: String, providerType: ProviderType) -> String {
        switch providerType {
        case .codex, .claude, .gemini, .copilot, .ollamaCloud:
            return titleCaseASCIIWords(value)
        case .cursor:
            return normalizedCursorPlanType(value)
        case .kimi:
            return normalizedKimiPlanType(value)
        default:
            return value
        }
    }

    private static func normalizedCursorPlanType(_ value: String) -> String {
        switch normalizeCursorPlanKey(value) {
        case "FREE", "HOBBY":
            return "Free"
        case "PRO":
            return "Pro"
        case "PROPLUS", "PRO+":
            return "Pro+"
        case "ULTRA":
            return "Ultra"
        case "TEAM", "TEAMS":
            return "Teams"
        case "BUSINESS":
            return "Business"
        case "ENTERPRISE":
            return "Enterprise"
        default:
            return titleCaseASCIIWords(value)
        }
    }

    private static func normalizeCursorPlanKey(_ value: String) -> String {
        let uppercase = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let separators = CharacterSet(charactersIn: " _-")
        return uppercase.components(separatedBy: separators).filter { !$0.isEmpty }.joined()
    }

    private static func normalizedKimiPlanType(_ value: String) -> String {
        let normalizedKey = normalizeKimiPlanKey(value)
        let mapping: [String: String] = [
            "FREE": "Adagio",
            "10": "Adagio",
            "ADAGIO": "Adagio",
            "TRIAL": "Andante",
            "15": "Andante",
            "ANDANTE": "Andante",
            "BASIC": "Moderato",
            "20": "Moderato",
            "MODERATO": "Moderato",
            "INTERMEDIATE": "Allegretto",
            "25": "Allegretto",
            "ALLEGRETTO": "Allegretto",
            "ADVANCED": "Allegro",
            "27": "Allegro",
            "ALLEGRO": "Allegro"
        ]
        return mapping[normalizedKey] ?? value
    }

    private static func normalizeKimiPlanKey(_ value: String) -> String {
        let uppercase = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if uppercase.hasPrefix("LEVEL_") {
            return normalizeKimiPlanKey(String(uppercase.dropFirst("LEVEL_".count)))
        }
        if uppercase.hasPrefix("MEMBERSHIP_LEVEL_") {
            return normalizeKimiPlanKey(String(uppercase.dropFirst("MEMBERSHIP_LEVEL_".count)))
        }
        let separators = CharacterSet(charactersIn: " _-")
        let pieces = uppercase.components(separatedBy: separators).filter { !$0.isEmpty }
        return pieces.joined()
    }

    private static func titleCaseASCIIWords(_ value: String) -> String {
        guard value.unicodeScalars.allSatisfy(\.isASCII) else {
            return value
        }

        var output = ""
        var shouldUppercase = true
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if shouldUppercase {
                    output += String(scalar).uppercased()
                    shouldUppercase = false
                } else {
                    output.append(Character(scalar))
                }
            } else {
                output.append(Character(scalar))
                shouldUppercase = scalar == " " || scalar == "-" || scalar == "_" || scalar == "/"
            }
        }
        return output
    }

    private static func stripTraePlanKeyword(_ value: String) -> String {
        let removedKeyword = value.replacingOccurrences(
            of: "plan",
            with: "",
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        let collapsedWhitespace = removedKeyword.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsedWhitespace.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: "-_|/:"))
        )
    }
}

enum LocalTrendValueFormatter {
    static func compactNumber(_ value: Int, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return compactZh(value)
        case .en:
            return compactEn(value)
        }
    }

    static func metricValueText(
        value: Int,
        metric: LocalTrendDisplayMetric,
        language: AppLanguage
    ) -> String {
        let compactValue = compactNumber(max(0, value), language: language)
        switch (metric, language) {
        case (.tokens, .zhHans), (.tokens, .en):
            return "\(compactValue) tokens"
        case (.responses, .zhHans):
            return "\(compactValue)次"
        case (.responses, .en):
            return "\(compactValue) req"
        }
    }

    private static func compactZh(_ value: Int) -> String {
        let safeValue = max(0, value)
        if safeValue >= 100_000_000 {
            return "\(compactDecimal(Double(safeValue) / 100_000_000))亿"
        }
        if safeValue >= 10_000 {
            return "\(compactDecimal(Double(safeValue) / 10_000))万"
        }
        return "\(safeValue)"
    }

    private static func compactEn(_ value: Int) -> String {
        let safeValue = max(0, value)
        if safeValue >= 1_000_000_000 {
            return "\(compactDecimal(Double(safeValue) / 1_000_000_000))B"
        }
        if safeValue >= 1_000_000 {
            return "\(compactDecimal(Double(safeValue) / 1_000_000))M"
        }
        if safeValue >= 1_000 {
            return "\(compactDecimal(Double(safeValue) / 1_000))K"
        }
        return groupedInteger(safeValue, localeID: "en_US_POSIX")
    }

    private static func compactDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.000_1 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    private static func groupedInteger(_ value: Int, localeID: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeID)
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
