import OhMyUsageDomain
import Foundation

struct StatusBarDisplaySource {
    var provider: ProviderDescriptor
    var snapshot: UsageSnapshot?
    var thirdPartyBarPercent: Double?
}

struct StatusBarDisplayItem: Equatable {
    var provider: ProviderDescriptor
    var name: String
    var valueText: String
    var percent: Double?
}

enum StatusBarDisplayPresenter {
    static func displayItems(
        for sources: [StatusBarDisplaySource],
        style: StatusBarDisplayStyle
    ) -> [StatusBarDisplayItem] {
        sources.map { displayItem(for: $0, style: style) }
    }

    static func displayItem(
        for source: StatusBarDisplaySource,
        style: StatusBarDisplayStyle
    ) -> StatusBarDisplayItem {
        let provider = source.provider
        return StatusBarDisplayItem(
            provider: provider,
            name: displayName(for: provider),
            valueText: valueText(for: source),
            percent: displayPercent(for: source, style: style)
        )
    }

    static func displayName(for provider: ProviderDescriptor) -> String {
        switch provider.type {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .gemini:
            return "Gemini"
        case .copilot:
            return "GitHub Copilot"
        case .microsoftCopilot:
            return "Microsoft Copilot"
        case .zai:
            return "Z.ai"
        case .amp:
            return "Amp"
        case .cursor:
            return "Cursor"
        case .jetbrains:
            return "JetBrains"
        case .kiro:
            return "Kiro"
        case .windsurf:
            return "Windsurf"
        case .kimi:
            return provider.family == .official ? "Kimi Coding" : "Kimi"
        case .trae:
            return "Trae SOLO"
        case .openrouterCredits:
            return "OpenRouter Credits"
        case .openrouterAPI:
            return "OpenRouter API"
        case .ollamaCloud:
            return "Ollama Cloud"
        case .opencodeGo:
            return "OpenCode Go"
        case .relay, .open, .dragon:
            let trimmed = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "API" : trimmed
        }
    }

    static func valueText(for source: StatusBarDisplaySource) -> String {
        let provider = source.provider
        guard let snapshot = source.snapshot else {
            return ""
        }

        if provider.relayDisplayMode == .quotaPercent,
           let percent = preferredPercent(from: snapshot, provider: provider) {
            return "\(Int(percent.rounded()))%"
        }

        if provider.family == .thirdParty {
            if provider.displaysUsedQuota, let used = snapshot.used {
                return formattedAmount(used)
            }
            guard let remaining = snapshot.remaining else { return "" }
            return formattedAmount(remaining)
        }

        if provider.traeDisplaysAmount,
           let amount = traePrimaryAmount(
            snapshot: snapshot,
            displaysUsedQuota: provider.displaysUsedQuota
           ) {
            return formattedAmount(amount)
        }

        if let percent = preferredPercent(from: snapshot, provider: provider) {
            return "\(Int(percent.rounded()))%"
        }
        if provider.displaysUsedQuota, let used = snapshot.used {
            return formattedAmount(used)
        }
        if let remaining = snapshot.remaining {
            return formattedAmount(remaining)
        }
        return ""
    }

    static func displayPercent(
        for source: StatusBarDisplaySource,
        style: StatusBarDisplayStyle
    ) -> Double? {
        let provider = source.provider
        if style == .barNamePercent,
           provider.family == .thirdParty,
           !provider.displaysUsedQuota {
            if let snapshot = source.snapshot,
               let percent = thirdPartyRemainingLimitPercent(from: snapshot) {
                return percent
            }
            if let percent = source.thirdPartyBarPercent {
                return percent
            }
        }
        guard let snapshot = source.snapshot else { return nil }
        return preferredPercent(from: snapshot, provider: provider)
    }

    private static func thirdPartyRemainingLimitPercent(from snapshot: UsageSnapshot) -> Double? {
        guard let remaining = snapshot.remaining,
              let limit = snapshot.limit,
              remaining.isFinite,
              limit.isFinite,
              limit > 0 else {
            return nil
        }
        let ratio = (remaining / limit) * 100
        guard ratio.isFinite else { return nil }
        return min(max(ratio, 0), 100)
    }

    static func preferredPercent(
        from snapshot: UsageSnapshot,
        provider: ProviderDescriptor
    ) -> Double? {
        if provider.type == .trae,
           let percent = traePrimaryPercent(
            snapshot: snapshot,
            displaysUsedQuota: provider.displaysUsedQuota
           ) {
            return percent
        }
        if let percent = fiveHourPercent(from: snapshot, displaysUsedQuota: provider.displaysUsedQuota) {
            return percent
        }
        if let window = snapshot.quotaWindows.first {
            return provider.displaysUsedQuota ? window.usedPercent : window.remainingPercent
        }
        if snapshot.unit == "%" {
            if provider.displaysUsedQuota,
               let used = snapshot.used,
               used >= 0, used <= 100 {
                return used
            }
            if let remaining = snapshot.remaining, remaining >= 0, remaining <= 100 {
                return remaining
            }
        }
        return nil
    }

    static func traePrimaryPercent(
        snapshot: UsageSnapshot,
        displaysUsedQuota: Bool = false
    ) -> Double? {
        let primaryWindow = snapshot.quotaWindows.first(where: isTraeDollarWindow) ?? snapshot.quotaWindows.first
        if let primaryWindow {
            return displaysUsedQuota ? primaryWindow.usedPercent : primaryWindow.remainingPercent
        }
        if snapshot.unit == "%" {
            if displaysUsedQuota,
               let used = snapshot.used,
               used >= 0, used <= 100 {
                return used
            }
            if let remaining = snapshot.remaining,
               remaining >= 0, remaining <= 100 {
                return remaining
            }
        }
        return nil
    }

    static func fiveHourPercent(
        from snapshot: UsageSnapshot,
        displaysUsedQuota: Bool = false
    ) -> Double? {
        if let session = snapshot.quotaWindows.first(where: { $0.kind == .session }) {
            return displaysUsedQuota ? session.usedPercent : session.remainingPercent
        }
        if let titled = snapshot.quotaWindows.first(where: { window in
            let lower = window.title.lowercased()
            return lower.contains("5h") || lower.contains("session")
        }) {
            return displaysUsedQuota ? titled.usedPercent : titled.remainingPercent
        }
        return nil
    }

    private static func isTraeDollarWindow(_ window: UsageQuotaWindow) -> Bool {
        let identifier = window.id.lowercased()
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return identifier.contains("dollar")
            || title.contains("dollar")
            || title.contains("美元")
    }

    private static func traePrimaryAmount(
        snapshot: UsageSnapshot,
        displaysUsedQuota: Bool
    ) -> Double? {
        let primaryKey = displaysUsedQuota ? "dollarUsed" : "dollarRemaining"
        if let raw = snapshot.extras[primaryKey], let value = Double(raw) {
            return value
        }
        if displaysUsedQuota,
           let fallbackRaw = snapshot.extras["dollarRemaining"],
           let fallback = Double(fallbackRaw) {
            return fallback
        }
        if let window = snapshot.quotaWindows.first(where: isTraeDollarWindow) ?? snapshot.quotaWindows.first {
            let displayPercent = displaysUsedQuota
                ? max(0, min(100, window.usedPercent))
                : max(0, min(100, window.remainingPercent))
            if let raw = snapshot.extras["dollarLimit"], let limit = Double(raw) {
                return max(0, limit * displayPercent / 100)
            }
        }
        return nil
    }

    private static func formattedAmount(_ value: Double) -> String {
        let normalizedValue = value == 0 ? 0 : value
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: normalizedValue)) ?? String(format: "%.2f", normalizedValue)
    }
}
