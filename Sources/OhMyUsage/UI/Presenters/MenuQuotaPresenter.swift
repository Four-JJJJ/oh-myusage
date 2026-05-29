import OhMyUsageDomain
import Foundation

struct MenuQuotaLocalization: Equatable {
    var quotaFiveHour: String
    var quotaWeekly: String
    var allModels: String
    var sonnetOnly: String
    var claudeDesign: String
    var session: String
    var monthly: String
    var currentPlan: String
    var totalUsage: String
    var autocomplete: String
    var dollarBalance: String
}

struct MenuQuotaMetric: Identifiable, Equatable {
    var id: String
    var title: String
    var displayPercent: Double
    var healthPercent: Double?
    var resetAt: Date?
    var isAvailable: Bool
    var valueTextOverride: String?
    var detailTextOverride: String? = nil
    var kind: UsageQuotaKind?
}

struct MenuQuotaMetricDisplayPresentation: Identifiable, Equatable {
    enum BarTone: Equatable {
        case clear
        case normal
        case warning
        case error
    }

    var id: String
    var title: String
    var valueText: String
    var resetText: String
    var detailText: String? = nil
    var percent: Double?
    var barTone: BarTone
    var isBlockedByDepletedQuota: Bool
}

enum MenuQuotaPresenter {
    static func quotaMetrics(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        language: AppLanguage,
        localization: MenuQuotaLocalization
    ) -> [MenuQuotaMetric] {
        guard let snapshot, !snapshot.quotaWindows.isEmpty else { return [] }

        if provider.type == .claude {
            return claudeQuotaMetrics(
                provider: provider,
                snapshot: snapshot,
                language: language,
                localization: localization
            )
        }

        let windows = snapshot.quotaWindows.sorted { metricRank($0.kind) < metricRank($1.kind) }
        if provider.relayDisplayMode == .quotaPercent {
            let relayMetadata = RelaySnapshotDisplayMetadata(
                snapshot: snapshot,
                fallbackAdapterID: provider.relayConfig?.adapterID
            )
            return windows.map { window in
                MenuQuotaMetric(
                    id: window.id,
                    title: metricTitle(for: window, provider: provider, language: language, localization: localization),
                    displayPercent: provider.displaysUsedQuota ? clamp(window.usedPercent) : clamp(window.remainingPercent),
                    healthPercent: clamp(window.remainingPercent),
                    resetAt: provider.showsExpirationTimeInMenuBar ? window.resetAt : nil,
                    isAvailable: true,
                    valueTextOverride: quotaValueTextOverride(
                        window: window,
                        provider: provider,
                        relayMetadata: relayMetadata
                    ),
                    detailTextOverride: quotaDetailTextOverride(
                        window: window,
                        provider: provider,
                        relayMetadata: relayMetadata,
                        language: language
                    ),
                    kind: quotaMetricKind(for: window, provider: provider)
                )
            }
        }

        return windows.map { window in
            MenuQuotaMetric(
                id: window.id,
                title: metricTitle(for: window, provider: provider, language: language, localization: localization),
                    displayPercent: provider.displaysUsedQuota ? clamp(window.usedPercent) : clamp(window.remainingPercent),
                    healthPercent: clamp(window.remainingPercent),
                    resetAt: provider.showsExpirationTimeInMenuBar ? window.resetAt : nil,
                    isAvailable: true,
                    valueTextOverride: nil,
                    detailTextOverride: nil,
                    kind: quotaMetricKind(for: window, provider: provider)
                )
            }
    }

    static func visibleMetrics(
        provider: ProviderDescriptor,
        metrics: [MenuQuotaMetric],
        language: AppLanguage,
        localization: MenuQuotaLocalization
    ) -> [MenuQuotaMetric] {
        let source = metrics.isEmpty
            ? placeholderMetrics(provider: provider, language: language, localization: localization)
            : metrics
        return Array(source.prefix(QuotaMetricDisplayFactory.preferredMetricCount(for: provider)))
    }

    static func metricDisplays(
        metrics: [MenuQuotaMetric],
        blockageCandidates: [MenuQuotaMetric],
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot?,
        disconnected: Bool,
        language: AppLanguage,
        now: Date
    ) -> [MenuQuotaMetricDisplayPresentation] {
        metrics.map { metric in
            let percent = (disconnected || !metric.isAvailable) ? nil : metric.displayPercent
            let displayPercent = percent.map { Int($0.rounded()) }
            let valueText: String

            if disconnected {
                valueText = "-"
            } else if let valueTextOverride = metric.valueTextOverride {
                valueText = valueTextOverride
            } else if provider.traeDisplaysAmount,
                      let amount = traeAmountText(
                        for: metric,
                        snapshot: snapshot,
                        displaysUsedQuota: provider.displaysUsedQuota
                      ) {
                valueText = amount
            } else {
                valueText = displayPercent.map { "\($0)%" } ?? "-"
            }

            let resetText: String
            if disconnected || !metric.isAvailable {
                resetText = "-"
            } else {
                resetText = CountdownFormatter.text(
                    to: metric.resetAt,
                    now: now,
                    placeholder: "-",
                    language: language
                )
            }

            return MenuQuotaMetricDisplayPresentation(
                id: metric.id,
                title: metric.title,
                valueText: valueText,
                resetText: resetText,
                detailText: (disconnected || !metric.isAvailable) ? nil : metric.detailTextOverride,
                percent: (displayPercent ?? 0) > 0 ? percent : 0,
                barTone: barTone(for: metric.healthPercent),
                isBlockedByDepletedQuota: isBlockedByDepletedWeeklyQuota(
                    metric,
                    in: blockageCandidates,
                    disconnected: disconnected
                )
            )
        }
    }

    private static func placeholderMetrics(
        provider: ProviderDescriptor,
        language: AppLanguage,
        localization: MenuQuotaLocalization
    ) -> [MenuQuotaMetric] {
        switch provider.type {
        case .claude:
            return claudePlaceholderQuotaMetrics(provider: provider, language: language, localization: localization)
        case .codex, .kimi:
            return [
                MenuQuotaMetric(
                    id: "\(provider.id)-placeholder-5h",
                    title: placeholderMetricTitle(localization.quotaFiveHour, provider: provider, language: language),
                    displayPercent: 0,
                    healthPercent: 0,
                    resetAt: nil,
                    isAvailable: true,
                    valueTextOverride: nil,
                    kind: nil
                ),
                MenuQuotaMetric(
                    id: "\(provider.id)-placeholder-weekly",
                    title: placeholderMetricTitle(localization.quotaWeekly, provider: provider, language: language),
                    displayPercent: 0,
                    healthPercent: 0,
                    resetAt: nil,
                    isAvailable: true,
                    valueTextOverride: nil,
                    kind: nil
                )
            ]
        case .gemini:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-pro", title: "Pro", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-flash", title: "Flash", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .copilot:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-premium", title: "Premium", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-chat", title: "Chat", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .microsoftCopilot:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-d7", title: "D7", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-d30", title: "D30", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .zai:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-session", title: placeholderMetricTitle(localization.quotaFiveHour, provider: provider, language: language), displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-weekly", title: placeholderMetricTitle(localization.quotaWeekly, provider: provider, language: language), displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .amp:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-free", title: "Free", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-credits", title: "Credits", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .cursor:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-monthly", title: "Monthly", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-ondemand", title: "On-Demand", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .jetbrains:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-quota", title: "Quota", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .kiro:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-monthly", title: "Credits", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-bonus", title: "Bonus", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .windsurf:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-prompt", title: "Prompt", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-flex", title: "Flex", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .trae:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-dollar", title: localizedTraeMetricTitle("Dollar", language: language, localization: localization), displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-autocomplete", title: localizedTraeMetricTitle("Autocomplete", language: language, localization: localization), displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .openrouterCredits:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-credits", title: "Credits", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .openrouterAPI:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-limit", title: "Limit", displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .ollamaCloud:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-session", title: placeholderMetricTitle(localization.session, provider: provider, language: language), displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-weekly", title: placeholderMetricTitle(localization.quotaWeekly, provider: provider, language: language), displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .opencodeGo:
            return [
                MenuQuotaMetric(id: "\(provider.id)-placeholder-session", title: placeholderMetricTitle(localization.session, provider: provider, language: language), displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-weekly", title: placeholderMetricTitle(localization.quotaWeekly, provider: provider, language: language), displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil),
                MenuQuotaMetric(id: "\(provider.id)-placeholder-monthly", title: placeholderMetricTitle(localization.monthly, provider: provider, language: language), displayPercent: 0, healthPercent: 0, resetAt: nil, isAvailable: true, valueTextOverride: nil, kind: nil)
            ]
        case .relay, .open, .dragon:
            guard provider.relayDisplayMode == .quotaPercent else { return [] }
            return [
                MenuQuotaMetric(
                    id: "\(provider.id)-placeholder-token-plan-total",
                    title: relayTokenPlanMetricTitle("Total Usage", provider: provider, localization: localization),
                    displayPercent: 0,
                    healthPercent: 0,
                    resetAt: nil,
                    isAvailable: true,
                    valueTextOverride: "0 / 0",
                    kind: nil
                )
            ]
        }
    }

    private static func claudePlaceholderQuotaMetrics(
        provider: ProviderDescriptor,
        language: AppLanguage,
        localization: MenuQuotaLocalization
    ) -> [MenuQuotaMetric] {
        [
            MenuQuotaMetric(
                id: "\(provider.id)-placeholder-session",
                title: placeholderMetricTitle(localization.quotaFiveHour, provider: provider, language: language),
                displayPercent: 0,
                healthPercent: 0,
                resetAt: nil,
                isAvailable: true,
                valueTextOverride: nil,
                kind: nil
            ),
            MenuQuotaMetric(
                id: "\(provider.id)-placeholder-weekly-all",
                title: placeholderMetricTitle(localization.allModels, provider: provider, language: language),
                displayPercent: 0,
                healthPercent: 0,
                resetAt: nil,
                isAvailable: true,
                valueTextOverride: nil,
                kind: nil
            ),
            MenuQuotaMetric(
                id: "\(provider.id)-placeholder-weekly-sonnet",
                title: placeholderMetricTitle(localization.sonnetOnly, provider: provider, language: language),
                displayPercent: 0,
                healthPercent: nil,
                resetAt: nil,
                isAvailable: false,
                valueTextOverride: "N/A",
                kind: nil
            ),
            MenuQuotaMetric(
                id: "\(provider.id)-placeholder-weekly-design",
                title: placeholderMetricTitle(localization.claudeDesign, provider: provider, language: language),
                displayPercent: 0,
                healthPercent: nil,
                resetAt: nil,
                isAvailable: false,
                valueTextOverride: "N/A",
                kind: nil
            )
        ]
    }

    private static func claudeQuotaMetrics(
        provider: ProviderDescriptor,
        snapshot: UsageSnapshot,
        language: AppLanguage,
        localization: MenuQuotaLocalization
    ) -> [MenuQuotaMetric] {
        let windows = snapshot.quotaWindows
        return [
            claudeMetric(
                provider: provider,
                id: "\(provider.id)-session",
                title: localization.quotaFiveHour,
                window: windows.first(where: { $0.kind == .session }),
                language: language,
                localization: localization
            ),
            claudeMetric(
                provider: provider,
                id: "\(provider.id)-weekly-all",
                title: localization.allModels,
                window: windows.first(where: { $0.kind == .weekly }),
                language: language,
                localization: localization
            ),
            claudeMetric(
                provider: provider,
                id: "\(provider.id)-weekly-sonnet",
                title: localization.sonnetOnly,
                window: windows.first(where: isClaudeSonnetWindow(_:)),
                language: language,
                localization: localization
            ),
            claudeMetric(
                provider: provider,
                id: "\(provider.id)-weekly-design",
                title: localization.claudeDesign,
                window: windows.first(where: isClaudeDesignWindow(_:)),
                language: language,
                localization: localization
            )
        ]
    }

    private static func claudeMetric(
        provider: ProviderDescriptor,
        id: String,
        title: String,
        window: UsageQuotaWindow?,
        language: AppLanguage,
        localization: MenuQuotaLocalization
    ) -> MenuQuotaMetric {
        let displayTitle = placeholderMetricTitle(title, provider: provider, language: language)
        guard let window else {
            return MenuQuotaMetric(
                id: id,
                title: displayTitle,
                displayPercent: 0,
                healthPercent: nil,
                resetAt: nil,
                isAvailable: false,
                valueTextOverride: "N/A",
                kind: nil
            )
        }

        return MenuQuotaMetric(
            id: id,
            title: displayTitle,
            displayPercent: provider.displaysUsedQuota ? clamp(window.usedPercent) : clamp(window.remainingPercent),
            healthPercent: clamp(window.remainingPercent),
            resetAt: window.resetAt,
            isAvailable: true,
            valueTextOverride: nil,
            kind: window.kind
        )
    }

    private static func quotaMetricKind(for window: UsageQuotaWindow, provider: ProviderDescriptor) -> UsageQuotaKind {
        QuotaBlockagePresenter.normalizedKind(for: window, provider: provider)
    }

    private static func isClaudeSonnetWindow(_ window: UsageQuotaWindow) -> Bool {
        let normalizedID = window.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedID.contains("sonnet") || normalizedTitle.contains("sonnet")
    }

    private static func isClaudeDesignWindow(_ window: UsageQuotaWindow) -> Bool {
        let normalizedID = window.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedID.contains("design") || normalizedTitle.contains("design")
    }

    private static func metricRank(_ kind: UsageQuotaKind) -> Int {
        switch kind {
        case .session: return 0
        case .weekly: return 1
        case .reviews: return 2
        case .modelWeekly: return 3
        case .credits: return 4
        case .extraUsage: return 5
        case .custom: return 6
        }
    }

    private static func metricTitle(
        for window: UsageQuotaWindow,
        provider: ProviderDescriptor,
        language: AppLanguage,
        localization: MenuQuotaLocalization
    ) -> String {
        if provider.type == .trae {
            return localizedTraeMetricTitle(window.title, language: language, localization: localization)
        }

        let baseTitle: String
        switch window.kind {
        case .session:
            baseTitle = provider.type == .ollamaCloud ? localization.session : localization.quotaFiveHour
        case .weekly:
            baseTitle = localization.quotaWeekly
        default:
            if provider.type == .kimi,
               window.kind == .custom,
               window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "overall" {
                baseTitle = localization.quotaWeekly
            } else {
                baseTitle = relayTokenPlanMetricTitle(window.title, provider: provider, localization: localization)
            }
        }

        return placeholderMetricTitle(baseTitle, provider: provider, language: language)
    }

    private static func relayTokenPlanMetricTitle(
        _ rawTitle: String,
        provider: ProviderDescriptor,
        localization: MenuQuotaLocalization
    ) -> String {
        let normalizedAdapterID = provider.relayConfig?.adapterID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let normalizedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedAdapterID == "xiaomimimo-token-plan" else { return rawTitle }
        if normalizedTitle == "current plan" || normalizedTitle == "total usage" {
            return localization.totalUsage
        }
        return rawTitle
    }

    private static func quotaValueTextOverride(
        window: UsageQuotaWindow,
        provider: ProviderDescriptor,
        relayMetadata: RelaySnapshotDisplayMetadata
    ) -> String? {
        guard !provider.usesXiaomimimoTokenPlanQuota else {
            return nil
        }
        return relayMetadata.quotaValueText(for: window.id)
    }

    private static func quotaDetailTextOverride(
        window: UsageQuotaWindow,
        provider: ProviderDescriptor,
        relayMetadata: RelaySnapshotDisplayMetadata,
        language: AppLanguage
    ) -> String? {
        guard provider.usesXiaomimimoTokenPlanQuota,
              window.id == "token-plan-total",
              let remainingTokens = tokenPlanRemainingTokens(from: relayMetadata) else {
            return nil
        }
        let formatted = formattedWholeNumber(remainingTokens)
        switch language {
        case .zhHans:
            return "剩余 \(formatted) tokens"
        case .en:
            return "\(formatted) tokens remaining"
        }
    }

    private static func tokenPlanRemainingTokens(from relayMetadata: RelaySnapshotDisplayMetadata) -> Double? {
        if let remaining = relayMetadata.tokenPlanRemainingTokens {
            return remaining
        }
        guard let used = relayMetadata.tokenPlanUsedTokens,
              let limit = relayMetadata.tokenPlanLimitTokens else {
            return nil
        }
        return max(0, limit - used)
    }

    private static func formattedWholeNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value.rounded()))
    }

    private static func localizedTraeMetricTitle(
        _ rawTitle: String,
        language: AppLanguage,
        localization: MenuQuotaLocalization
    ) -> String {
        let normalized = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("autocomplete") || normalized.contains("自动补全") {
            return localization.autocomplete
        }
        if normalized.contains("dollar") || normalized.contains("美元") {
            return localization.dollarBalance
        }
        return rawTitle
    }

    private static func traeAmountText(
        for metric: MenuQuotaMetric,
        snapshot: UsageSnapshot?,
        displaysUsedQuota: Bool
    ) -> String? {
        guard let snapshot else { return nil }

        let primaryKey: String?
        let fallbackKey: String?
        let kind: TraeMetricKind?
        switch TraeMetricKind.detect(id: metric.id, title: metric.title) {
        case .autocomplete:
            primaryKey = displaysUsedQuota ? "autocompleteUsed" : "autocompleteRemaining"
            fallbackKey = displaysUsedQuota ? "autocompleteRemaining" : nil
            kind = .autocomplete
        case .dollarBalance:
            primaryKey = displaysUsedQuota ? "dollarUsed" : "dollarRemaining"
            fallbackKey = displaysUsedQuota ? "dollarRemaining" : nil
            kind = .dollarBalance
        case .none:
            primaryKey = nil
            fallbackKey = nil
            kind = nil
        }

        guard let key = primaryKey else { return nil }
        let resolvedRaw = snapshot.extras[key] ?? fallbackKey.flatMap { snapshot.extras[$0] }
        guard let raw = resolvedRaw, let value = Double(raw), let kind else { return nil }

        return TraeValueDisplayFormatter.format(
            value,
            kind: kind,
            maxWidth: MetricValueLayoutFormatter.metricValueColumnWidth
        )
    }

    private static func placeholderMetricTitle(
        _ baseTitle: String,
        provider: ProviderDescriptor,
        language: AppLanguage
    ) -> String {
        guard provider.displaysUsedQuota else { return baseTitle }
        switch language {
        case .zhHans:
            return "\(baseTitle)已用"
        case .en:
            return "\(baseTitle) used"
        }
    }

    private static func barTone(for percent: Double?) -> MenuQuotaMetricDisplayPresentation.BarTone {
        guard let percent, percent > 0 else {
            return .clear
        }
        let shownPercent = Int(percent.rounded())
        if shownPercent <= 0 { return .clear }
        if shownPercent < 10 { return .error }
        if shownPercent <= 30 { return .warning }
        return .normal
    }

    private static func isBlockedByDepletedWeeklyQuota(
        _ metric: MenuQuotaMetric,
        in metrics: [MenuQuotaMetric],
        disconnected: Bool
    ) -> Bool {
        guard !disconnected else { return false }

        return QuotaBlockagePresenter.isBlockedByDepletedWeeklyQuota(
            currentKind: metric.kind,
            currentRemainingPercent: metric.healthPercent,
            currentIsAvailable: metric.isAvailable,
            candidateWindows: metrics.map {
                (
                    kind: $0.kind,
                    remainingPercent: $0.healthPercent,
                    isAvailable: $0.isAvailable
                )
            }
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}
