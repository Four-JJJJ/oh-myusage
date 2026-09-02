import Foundation
import OhMyUsageDomain

/// Request-cost metadata for a single provider refresh (optimization plan §8.3).
///
/// The plan is a non-persisted policy value owned by the model layer: it describes
/// how expensive one full refresh of a provider is and how stale its data may get
/// at each refresh tier. It must never be serialized into user configuration JSON;
/// per-provider user settings stay in `ProviderDescriptor` and the fetch plan is
/// supplied by `ProviderFetchPlanRegistry` instead.
///
/// TTL semantics (pinned by `ProviderFetchPlanRegistryTests`):
/// - `activeTTL`: how long a snapshot stays fresh while the provider is actively
///   visible (menu panel open, settings detail on screen). A snapshot younger than
///   this TTL can be reused without any network request.
/// - `backgroundTTL`: the minimum spacing between background scheduler refreshes
///   for the provider while it is not visible. Background refreshes are less
///   frequent, so `backgroundTTL >= activeTTL` (plan §9.3: active 180s vs
///   background 900s magnitudes).
/// - `metadataTTL`: freshness for slowly changing metadata that is cached apart
///   from quota numbers (organization IDs, plan tiers, subscription and project
///   context). Such metadata changes slowest, so `metadataTTL >= backgroundTTL`.
struct ProviderFetchPlan: Equatable, Sendable {
    let providerType: ProviderType
    /// Snapshot freshness while the provider is actively visible.
    let activeTTL: TimeInterval
    /// Minimum spacing between background scheduler refreshes.
    let backgroundTTL: TimeInterval
    /// Freshness for slowly changing metadata cached separately from quota data.
    let metadataTTL: TimeInterval
    /// Typical number of HTTP requests for one successful refresh on the
    /// provider's default (`.auto`) path, counting best-effort enrichment
    /// requests that normally succeed. Rare recovery paths (OAuth token
    /// refreshes, mirror retries, 401 retry once, browser credential recovery)
    /// are not part of the typical count.
    let estimatedRequestCount: Int
    /// Whether a refresh can involve web/browser-derived data: either the
    /// official OAuth usage is merged with a web overlay (Codex, Claude), or the
    /// provider itself sources its data from a web console session (Qwen,
    /// Ollama Cloud, OpenCode Go), or browser-derived credentials participate in
    /// the normal credential resolution (Kimi legacy fallback, Trae recovery,
    /// Relay recovery).
    let supportsWebOverlay: Bool
    /// Whether the provider cannot produce a web-sourced snapshot without
    /// browser-derived credentials when no manual credential has been stored,
    /// i.e. its only data source is a web console session (Qwen, Ollama Cloud).
    /// Providers with a working API/OAuth/local path are `false` even when they
    /// support a browser fallback.
    let requiresBrowserAccess: Bool
}
