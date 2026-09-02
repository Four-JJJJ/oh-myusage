import Foundation
import OhMyUsageDomain

/// Unified data-credibility states for menu presentations (doc §10.2).
///
/// Every menu card value resolves to exactly one of these states so that
/// official live data can never be confused with cached or locally
/// estimated values.
enum MenuDataCredibility: Equatable {
    /// Live values fetched from the upstream source (API / official web).
    case officialLive
    /// Values served from the local snapshot cache while the source is healthy.
    case localCache
    /// Values derived locally (CLI / IDE / local log parsing), not confirmed by an upstream API.
    case localEstimate
    /// No usable value yet; waiting for the first successful refresh.
    case pendingRefresh
    /// The latest refresh failed. `showsStaleData` tells whether cached values are on screen.
    case refreshFailed(showsStaleData: Bool)
}

enum MenuDataCredibilityPresenter {
    /// Maps a menu snapshot to the unified credibility state (doc §10.2).
    ///
    /// Rules (derived from `UsageSnapshot.valueFreshness` / `.fetchHealth` /
    /// `.sourceLabel`):
    /// - no snapshot → `.pendingRefresh`
    /// - `.empty` + healthy fetch → `.pendingRefresh`
    /// - `.empty` + failed fetch → `.refreshFailed(showsStaleData: false)`
    /// - `.cachedFallback` + healthy fetch → `.localCache`
    /// - `.cachedFallback` + failed fetch → `.refreshFailed(showsStaleData: true)`
    /// - `.live` + locally-derived source (CLI / local / IDE label) → `.localEstimate`
    /// - `.live` + failed fetch (inconsistent, treated conservatively) →
    ///   `.refreshFailed(showsStaleData: true)`
    /// - `.live` + healthy fetch → `.officialLive`
    static func credibility(snapshot: UsageSnapshot?) -> MenuDataCredibility {
        guard let snapshot else { return .pendingRefresh }

        switch snapshot.valueFreshness {
        case .empty:
            return snapshot.fetchHealth == .ok
                ? .pendingRefresh
                : .refreshFailed(showsStaleData: false)
        case .cachedFallback:
            return snapshot.fetchHealth == .ok
                ? .localCache
                : .refreshFailed(showsStaleData: true)
        case .live:
            if isLocalEstimateSource(snapshot.sourceLabel) {
                return .localEstimate
            }
            return snapshot.fetchHealth == .ok
                ? .officialLive
                : .refreshFailed(showsStaleData: true)
        }
    }

    /// Matches the codebase convention in `UsageQuotaWindow` reset-source
    /// inference: source labels containing "cli" / "local" (plus "ide" for
    /// local IDE state readers) mark locally-derived, estimated data.
    static func isLocalEstimateSource(_ sourceLabel: String) -> Bool {
        let label = sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !label.isEmpty else { return false }
        return label.contains("cli") || label.contains("local") || label.contains("ide")
    }

    /// Localized display text for a credibility state (doc §10.2 wording).
    static func label(_ credibility: MenuDataCredibility, language: AppLanguage) -> String {
        switch credibility {
        case .officialLive:
            return Localizer.text(.menuDataCredibilityLive, language: language)
        case .localCache:
            return Localizer.text(.menuDataCredibilityLocalCache, language: language)
        case .localEstimate:
            return Localizer.text(.menuDataCredibilityLocalEstimate, language: language)
        case .pendingRefresh:
            return Localizer.text(.menuDataCredibilityPendingRefresh, language: language)
        case .refreshFailed(let showsStaleData):
            return Localizer.text(
                showsStaleData ? .menuStatusRefreshFailedStale : .menuStatusRefreshFailed,
                language: language
            )
        }
    }

    /// Appends the live-source label ("官方实时" / "Live") to the card
    /// subtitle so the first screen always names the data source (doc
    /// §10.1). Degraded credibility is carried by the status chip instead,
    /// so the subtitle is left untouched there.
    static func liveSourceSubtitle(
        _ base: String?,
        snapshot: UsageSnapshot?,
        language: AppLanguage
    ) -> String? {
        guard credibility(snapshot: snapshot) == .officialLive else { return base }

        let liveLabel = Localizer.text(.menuDataCredibilityLive, language: language)
        guard let base, !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return liveLabel
        }
        return "\(base) · \(liveLabel)"
    }
}
