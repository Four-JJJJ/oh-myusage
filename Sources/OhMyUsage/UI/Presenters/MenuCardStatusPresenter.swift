import OhMyUsageDomain
import OhMyUsageApplication
import Foundation

struct MenuCardStatusPresentation: Equatable {
    enum Tone: Equatable {
        case normal
        case warning
        case error
    }

    var text: String
    var tone: Tone
}

enum MenuCardStatusPresenter {
    static func planType(for provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> String? {
        if provider.family == .official {
            let showsPlanType = provider.officialConfig?.showPlanTypeInMenuBar
                ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).showPlanTypeInMenuBar
            guard showsPlanType else { return nil }

            return PlanTypeDisplayFormatter.resolvedPlanType(
                providerType: provider.type,
                extrasPlanType: snapshot?.extras["planType"],
                rawPlanType: snapshot?.rawMeta["planType"]
            )
        }

        return PlanTypeDisplayFormatter.normalizedPlanType(
            snapshot?.extras["planType"],
            providerType: provider.type
        ) ?? PlanTypeDisplayFormatter.normalizedPlanType(
            snapshot?.rawMeta["planType"],
            providerType: provider.type
        )
    }

    static func percentageStatus(
        healthPercents: [Double?],
        snapshot: UsageSnapshot?,
        disconnected: Bool,
        language: AppLanguage,
        tightText: String,
        sufficientText: String,
        exhaustedText: String,
        disconnectedText: String
    ) -> MenuCardStatusPresentation {
        degradedCredibilityStatus(
            snapshot: snapshot,
            disconnected: disconnected,
            disconnectedText: disconnectedText,
            language: language
        ) ?? quotaPercentageStatus(
            healthPercents: healthPercents,
            tightText: tightText,
            sufficientText: sufficientText,
            exhaustedText: exhaustedText
        )
    }

    static func amountStatus(
        remaining: Double?,
        snapshot: UsageSnapshot?,
        disconnected: Bool,
        language: AppLanguage,
        tightText: String,
        sufficientText: String,
        exhaustedText: String,
        disconnectedText: String
    ) -> MenuCardStatusPresentation {
        degradedCredibilityStatus(
            snapshot: snapshot,
            disconnected: disconnected,
            disconnectedText: disconnectedText,
            language: language
        ) ?? quotaAmountStatus(
            remaining: remaining,
            tightText: tightText,
            sufficientText: sufficientText,
            exhaustedText: exhaustedText
        )
    }

    /// Status chip for degraded data credibility (doc §10.2). Returns `nil`
    /// for official live data, where the chip falls back to the quota status
    /// (充足 / 紧张 / 耗尽).
    static func degradedCredibilityStatus(
        snapshot: UsageSnapshot?,
        disconnected: Bool,
        disconnectedText: String,
        language: AppLanguage
    ) -> MenuCardStatusPresentation? {
        if disconnected {
            // No usable data on screen and the latest fetch failed.
            guard let snapshot else {
                return MenuCardStatusPresentation(text: disconnectedText, tone: .error)
            }
            return fetchFailureStatus(health: snapshot.fetchHealth, showsStaleData: false, language: language)
        }

        switch MenuDataCredibilityPresenter.credibility(snapshot: snapshot) {
        case .officialLive:
            return nil
        case .pendingRefresh:
            return MenuCardStatusPresentation(
                text: Localizer.text(.menuDataCredibilityPendingRefresh, language: language),
                tone: .normal
            )
        case .localCache:
            return MenuCardStatusPresentation(
                text: Localizer.text(.menuDataCredibilityLocalCache, language: language),
                tone: .warning
            )
        case .localEstimate:
            return MenuCardStatusPresentation(
                text: Localizer.text(.menuDataCredibilityLocalEstimate, language: language),
                tone: .warning
            )
        case .refreshFailed(let showsStaleData):
            guard let snapshot else { return nil }
            return fetchFailureStatus(health: snapshot.fetchHealth, showsStaleData: showsStaleData, language: language)
        }
    }

    /// Chip for a failed fetch: names the concrete anomaly (auth failure,
    /// rate limit, config issue) instead of a generic failure, matching the
    /// settings-page vocabulary (doc §10.1 anomaly summary).
    private static func fetchFailureStatus(
        health: FetchHealth,
        showsStaleData: Bool,
        language: AppLanguage
    ) -> MenuCardStatusPresentation {
        switch health {
        case .authExpired:
            return MenuCardStatusPresentation(
                text: Localizer.text(.menuStatusAuthFailed, language: language),
                tone: .error
            )
        case .endpointMisconfigured:
            return MenuCardStatusPresentation(
                text: Localizer.text(.menuStatusConfigIssue, language: language),
                tone: .error
            )
        case .rateLimited:
            return MenuCardStatusPresentation(
                text: Localizer.text(.menuStatusRateLimited, language: language),
                tone: .warning
            )
        case .unreachable, .ok:
            return MenuCardStatusPresentation(
                text: Localizer.text(
                    showsStaleData ? .menuStatusRefreshFailedStale : .menuStatusRefreshFailed,
                    language: language
                ),
                tone: .error
            )
        }
    }

    private static func quotaPercentageStatus(
        healthPercents: [Double?],
        tightText: String,
        sufficientText: String,
        exhaustedText: String
    ) -> MenuCardStatusPresentation {
        let availableHealthPercents = healthPercents
            .compactMap { $0.map { Int($0.rounded()) } }
        guard let displayedMinimum = availableHealthPercents.min() else {
            return MenuCardStatusPresentation(text: tightText, tone: .warning)
        }
        if displayedMinimum <= 0 {
            return MenuCardStatusPresentation(text: exhaustedText, tone: .error)
        }
        if displayedMinimum > 30 {
            return MenuCardStatusPresentation(text: sufficientText, tone: .normal)
        }
        if displayedMinimum < 10 {
            return MenuCardStatusPresentation(text: tightText, tone: .error)
        }
        return MenuCardStatusPresentation(text: tightText, tone: .warning)
    }

    private static func quotaAmountStatus(
        remaining: Double?,
        tightText: String,
        sufficientText: String,
        exhaustedText: String
    ) -> MenuCardStatusPresentation {
        guard let remaining else {
            return MenuCardStatusPresentation(text: tightText, tone: .warning)
        }
        if remaining > 50 {
            return MenuCardStatusPresentation(text: sufficientText, tone: .normal)
        }
        if remaining > 0 {
            return MenuCardStatusPresentation(text: tightText, tone: .warning)
        }
        return MenuCardStatusPresentation(text: exhaustedText, tone: .error)
    }

    /// Chip text for a snapshot served from cache (doc §10.2): healthy cache
    /// reads as 本地缓存; a failed refresh names the concrete anomaly.
    static func cachedRelayStatus(fetchHealth: FetchHealth, language: AppLanguage) -> MenuCardStatusPresentation {
        guard fetchHealth != .ok else {
            return MenuCardStatusPresentation(
                text: Localizer.text(.menuDataCredibilityLocalCache, language: language),
                tone: .warning
            )
        }
        return fetchFailureStatus(health: fetchHealth, showsStaleData: true, language: language)
    }

    static func cachedFetchHealthStatusText(_ health: FetchHealth, language: AppLanguage) -> String {
        cachedRelayStatus(fetchHealth: health, language: language).text
    }
}
