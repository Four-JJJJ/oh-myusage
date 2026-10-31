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
        SharedNumberFormatting.decimal(
            value,
            minFractionDigits: minFractionDigits,
            maxFractionDigits: maxFractionDigits,
            grouping: grouping,
            localeID: "en_US_POSIX"
        )
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
        "-", "--", "unknown", "undefined", "n/a", "na", "none", "null",
        "nil", "unspecified", "(null)", "(unknown)"
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
            if isHiddenPlanValue(cleaned) {
                return nil
            }
            return cleaned
        }

        if isHiddenPlanValue(raw) {
            return nil
        }
        let stripped = stripPlanEnumPrefix(raw)
        if stripped.isEmpty || isHiddenPlanValue(stripped) {
            return nil
        }
        return stripped
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

    private static func isHiddenPlanValue(_ value: String) -> Bool {
        hiddenValues.contains(value.lowercased())
    }

    private static func stripPlanEnumPrefix(_ value: String) -> String {
        let prefixes = [
            "MEMBERSHIP_LEVEL_", "MEMBERSHIP_TYPE_", "MEMBERSHIP_",
            "SUBSCRIPTION_TYPE_", "SUBSCRIPTION_",
            "PLAN_TYPE_", "PLAN_", "TIER_", "LEVEL_"
        ]
        var current = value
        while true {
            let uppercase = current.uppercased()
            var matched = false
            for prefix in prefixes where uppercase.hasPrefix(prefix) {
                current = String(current.dropFirst(prefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "_- "))
                matched = true
                break
            }
            if !matched || current.isEmpty {
                break
            }
        }
        return current
    }

    private static func normalizedDisplayPlanType(_ value: String, providerType: ProviderType) -> String {
        switch providerType {
        case .kimi:
            return normalizedKimiPlanType(value)
        case .cursor:
            return normalizedCursorPlanType(value)
        case .grok, .grokBot:
            return normalizedGrokPlanType(value)
        case .zai, .amp, .microsoftCopilot:
            return value
        case .trae:
            return mappedCommonPlanType(value) ?? value
        default:
            return mappedCommonPlanType(value)
                ?? titleCaseASCIIWords(value.replacingOccurrences(of: "_", with: " "))
        }
    }

    private static func mappedCommonPlanType(_ value: String) -> String? {
        switch compactPlanKey(value) {
        case "FREE", "HOBBY":
            return "Free"
        case "PLUS", "PLUSPLAN", "CHATGPTPLUS":
            return "Plus"
        case "PRO":
            return "Pro"
        case "PROPLUS", "PRO+":
            return "Pro+"
        case "MAX":
            return "Max"
        case "ULTRA":
            return "Ultra"
        case "PREMIUM":
            return "Premium"
        case "SUPER":
            return "Super"
        case "TEAM", "TEAMS":
            return "Teams"
        case "BUSINESS", "BIZ":
            return "Business"
        case "ENTERPRISE":
            return "Enterprise"
        case "STANDARD":
            return "Standard"
        case "LITE":
            return "Lite"
        case "TRIAL":
            return "Trial"
        case "INDIVIDUAL":
            return "Individual"
        default:
            return nil
        }
    }

    private static func compactPlanKey(_ value: String) -> String {
        let uppercase = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let separators = CharacterSet(charactersIn: " _-")
        return uppercase.components(separatedBy: separators).filter { !$0.isEmpty }.joined()
    }

    private static func normalizedCursorPlanType(_ value: String) -> String {
        switch compactPlanKey(value) {
        case "FREE", "HOBBY":
            return "Free"
        case "PRO":
            return "Pro"
        case "PROPLUS", "PRO+":
            return "Pro+"
        case "ULTRA":
            return "Ultra"
        case "PLUS":
            return "Plus"
        case "PREMIUM":
            return "Premium"
        case "SUPER":
            return "Super"
        case "TEAM", "TEAMS":
            return "Teams"
        case "BUSINESS":
            return "Business"
        case "ENTERPRISE":
            return "Enterprise"
        default:
            return titleCaseASCIIWords(value.replacingOccurrences(of: "_", with: " "))
        }
    }

    private static func normalizedGrokPlanType(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch compactPlanKey(trimmed) {
        case "SUPERGROKPLUS", "GROKPLUS", "GROK+", "SUPERGROK+":
            return "SuperGrok Plus"
        case "SUPERGROK", "GROKPRO":
            return "SuperGrok"
        default:
            break
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("cursor") || lower.hasPrefix("supergrok") {
            return trimmed
        }
        return mappedCommonPlanType(trimmed) ?? trimmed
    }

    private static func normalizedKimiPlanType(_ value: String) -> String {
        let normalizedKey = normalizeKimiPlanKey(value)
        // Current `/coding/v1/usages` enums (LEVEL_BASIC / LEVEL_STANDARD / …)
        // plus the older numeric `user_level` codes (10 / 15 / 20 / 25 / 27).
        let mapping: [String: String] = [
            "FREE": "Adagio",
            "10": "Adagio",
            "ADAGIO": "Adagio",
            "BASIC": "Adagio",
            "TRIAL": "Andante",
            "15": "Andante",
            "ANDANTE": "Andante",
            "STANDARD": "Moderato",
            "20": "Moderato",
            "MODERATO": "Moderato",
            "INTERMEDIATE": "Allegretto",
            "25": "Allegretto",
            "ALLEGRETTO": "Allegretto",
            "ADVANCED": "Allegro",
            "27": "Allegro",
            "ALLEGRO": "Allegro",
            "PREMIUM": "Vivace",
            "VIVACE": "Vivace"
        ]
        if let mapped = mapping[normalizedKey] {
            return mapped
        }
        let stripped = strippedKimiPlanLabel(value)
        if stripped == stripped.uppercased(),
           stripped.rangeOfCharacter(from: .letters) != nil {
            return titleCaseASCIIWords(stripped.replacingOccurrences(of: "_", with: " "))
        }
        return value
    }

    private static func strippedKimiPlanLabel(_ value: String) -> String {
        var body = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercase = body.uppercased()
        if uppercase.hasPrefix("MEMBERSHIP_LEVEL_") {
            body = String(body.dropFirst("MEMBERSHIP_LEVEL_".count))
        } else if uppercase.hasPrefix("LEVEL_") {
            body = String(body.dropFirst("LEVEL_".count))
        }
        return body.replacingOccurrences(of: "_", with: " ")
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

    static func responseCountText(_ value: Int, language: AppLanguage) -> String {
        let compact = compactNumber(max(0, value), language: language)
        switch language {
        case .zhHans:
            if let last = compact.last, last == "万" || last == "亿" {
                let number = String(compact.dropLast())
                return "\(number) \(last)次"
            }
            return "\(compact) 次"
        case .en:
            return "\(compact) req"
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
        SharedNumberFormatting.groupedInteger(value, localeID: localeID)
    }
}
