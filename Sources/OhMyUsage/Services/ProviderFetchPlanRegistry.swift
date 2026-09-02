import Foundation
import OhMyUsageDomain

/// Central registry of `ProviderFetchPlan` values, one per `ProviderType`
/// (optimization plan §8.3). The plans are compile-time policy derived from the
/// current per-provider refresh behavior (default poll intervals in
/// `OfficialProviderDefaultCatalog` / relay catalogs, request patterns in each
/// `Providers/*.swift`); they are intentionally kept out of user configuration
/// JSON to avoid migration burden.
struct ProviderFetchPlanRegistry {
    private let plans: [ProviderType: ProviderFetchPlan]

    init(plans: [ProviderType: ProviderFetchPlan] = ProviderFetchPlanRegistry.defaultPlans) {
        self.plans = plans
        precondition(
            Set(plans.keys) == Set(ProviderType.allCases),
            "ProviderFetchPlanRegistry must define a plan for every ProviderType"
        )
    }

    func plan(for type: ProviderType) -> ProviderFetchPlan {
        guard let plan = plans[type] else {
            preconditionFailure("Missing fetch plan for \(type)")
        }
        return plan
    }

    /// Default plans, one entry per enabled `ProviderType`.
    ///
    /// TTL anchors:
    /// - `activeTTL` follows the provider's current default `pollIntervalSec`
    ///   (`OfficialProviderDefaultCatalog`, `RelayProviderDefaultCatalog`);
    ///   web-session providers that authenticate with console cookies use a
    ///   deliberately longer 300s per plan §8.4 ("Web-only Provider 使用较长 TTL").
    /// - `backgroundTTL` uses the plan §9.3 scheduler magnitudes (900s, low
    ///   power 1800s for balance/web-session providers).
    /// - `metadataTTL` covers plan/subscription/organization metadata with a
    ///   long TTL (6h default; 24h where metadata is a stable org/plan tier).
    static let defaultPlans: [ProviderType: ProviderFetchPlan] = [
        // OAuth usage (1 request to chatgpt.com/backend-api/wham/usage) plus the
        // web overlay usage request when a manual cookie is stored
        // (`shouldIncludeWebOverlay`). 401 adds at most one refresh + retry.
        .codex: ProviderFetchPlan(
            providerType: .codex,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        // OAuth usage (1 request to api.anthropic.com/api/oauth/usage) plus web
        // overlay: 1 request via sessionKey, or organizations + usage +
        // overage_spend_limit + account (4) on the cookie path. Organization ID
        // metadata uses a long TTL (plan §8.4).
        .claude: ProviderFetchPlan(
            providerType: .claude,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 86_400,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        // loadCodeAssist + retrieveUserQuota are the two required requests
        // (plan §8.4); project-name resolution adds a rare third. Project/plan
        // context from loadCodeAssist is cacheable metadata.
        .gemini: ProviderFetchPlan(
            providerType: .gemini,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // 1 request to api.github.com/copilot_internal/user; token resolved
        // locally (env/keychain/gh CLI).
        .copilot: ProviderFetchPlan(
            providerType: .copilot,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // Two parallel Graph report requests (D7 + D30); token resolved locally.
        .microsoftCopilot: ProviderFetchPlan(
            providerType: .microsoftCopilot,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // Coding Plan quota (1) + optional subscription/list (1, must not hide
        // quota per plan §8.4). Mirror retry can double the worst case.
        .zai: ProviderFetchPlan(
            providerType: .zai,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // 1 request to /api/biz/account/query-customer-account-report; balance
        // changes slowly so both TTLs are longer (catalog poll 300).
        .zaiBalance: ProviderFetchPlan(
            providerType: .zaiBalance,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // 1 request to ampcode.com/api/internal; key from local secrets.json.
        .amp: ProviderFetchPlan(
            providerType: .amp,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // 1 request to cursor.com/api/usage-summary; auth token from local
        // state.vscdb, refresh adds at most one token request.
        .cursor: ProviderFetchPlan(
            providerType: .cursor,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // Local XML parsing only; no network requests.
        .jetbrains: ProviderFetchPlan(
            providerType: .jetbrains,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 0,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // Local kiro-cli + sqlite output only; no network requests.
        .kiro: ProviderFetchPlan(
            providerType: .kiro,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 0,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // 1 request to GetUserStatus; API key from local state.vscdb.
        .windsurf: ProviderFetchPlan(
            providerType: .windsurf,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // 1 request to ide_user_ent_usage; keychain JWT is primary, browser
        // bearer-token candidates only participate on auth recovery.
        .trae: ProviderFetchPlan(
            providerType: .trae,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        // 1 request per OpenRouter channel; API key from keychain.
        .openrouterCredits: ProviderFetchPlan(
            providerType: .openrouterCredits,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        .openrouterAPI: ProviderFetchPlan(
            providerType: .openrouterAPI,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // Web session only: 1 request for the settings HTML. Cookie comes from
        // the stored manual credential or browser auto-import, so browser access
        // is required for a live snapshot; web-only providers use longer TTLs
        // (plan §8.4) to keep console session traffic low.
        .ollamaCloud: ProviderFetchPlan(
            providerType: .ollamaCloud,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: true,
            requiresBrowserAccess: true
        ),
        // Web-first with local sqlite fallback: 1 remote usage request; manual
        // cookie is primary and browser import only runs on interactive force
        // refresh, so browser access is not required.
        .opencodeGo: ProviderFetchPlan(
            providerType: .opencodeGo,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        // Token channel (usage + optional subscription/billing usage) and
        // balance channel run as two independent channels (plan §8.4); two
        // requests is the typical full refresh. Browser credentials are a
        // recovery fallback behind Manual Preferred defaults.
        .relay: ProviderFetchPlan(
            providerType: .relay,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        .open: ProviderFetchPlan(
            providerType: .open,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        .dragon: ProviderFetchPlan(
            providerType: .dragon,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        // Official API usage (1) with a legacy GetUsages fallback (1) via
        // KimiSmartProvider; the legacy path may read browser tokens as a
        // fallback, not as a requirement.
        .kimi: ProviderFetchPlan(
            providerType: .kimi,
            activeTTL: 60,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: false
        ),
        // 1 request to api.moonshot.cn/v1/users/me/balance; balance changes
        // slowly so both TTLs are longer (catalog poll 300).
        .kimiBalance: ProviderFetchPlan(
            providerType: .kimiBalance,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 21_600,
            estimatedRequestCount: 1,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // Billing (1) + best-effort plan name (/v1/settings, 1); OAuth refresh
        // from local ~/.grok/auth.json is rare.
        .grok: ProviderFetchPlan(
            providerType: .grok,
            activeTTL: 120,
            backgroundTTL: 900,
            metadataTTL: 21_600,
            estimatedRequestCount: 2,
            supportsWebOverlay: false,
            requiresBrowserAccess: false
        ),
        // Web session only (no open API): user/info.json (1) + Token Plan usage
        // (1) + subscription (1) + addon/list (1). sec_token/plan metadata is
        // cached with a long TTL (plan §8.4); web-only providers use longer
        // quota TTLs to limit console session traffic.
        .qwen: ProviderFetchPlan(
            providerType: .qwen,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 86_400,
            estimatedRequestCount: 4,
            supportsWebOverlay: true,
            requiresBrowserAccess: true
        ),
        // Web session only: user/info.json (1) + GetBillingAccountAvailableAmount
        // (1); balance changes slowly so both TTLs are longer (catalog poll 300).
        .qwenBalance: ProviderFetchPlan(
            providerType: .qwenBalance,
            activeTTL: 300,
            backgroundTTL: 1_800,
            metadataTTL: 86_400,
            estimatedRequestCount: 2,
            supportsWebOverlay: true,
            requiresBrowserAccess: true
        )
    ]
}
