import Foundation
import OhMyUsageDomain

/// Central registry of `ProviderFetchPlan` values, one per `ProviderType`
/// (optimization plan §8.3). The plans are compile-time policy derived from the
/// current per-provider refresh behavior (default poll intervals and request
/// patterns in each `Providers/*.swift`); each plan is declared by the type's
/// `ProviderModule` (`Providers/Modules/ProviderModule+*.swift`) and is
/// intentionally kept out of user configuration JSON to avoid migration burden.
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

    /// Default plans, one entry per `ProviderModule`.
    ///
    /// TTL anchors:
    /// - `activeTTL` follows the provider's current default `pollIntervalSec`
    ///   (`ProviderModule.defaults`, `RelayProviderDefaultCatalog`);
    ///   web-session providers that authenticate with console cookies use a
    ///   deliberately longer 300s per plan §8.4 ("Web-only Provider 使用较长 TTL").
    /// - `backgroundTTL` uses the plan §9.3 scheduler magnitudes (900s, low
    ///   power 1800s for balance/web-session providers).
    /// - `metadataTTL` covers plan/subscription/organization metadata with a
    ///   long TTL (6h default; 24h where metadata is a stable org/plan tier).
    static let defaultPlans: [ProviderType: ProviderFetchPlan] = Dictionary(
        ProviderModuleRegistry.allModules.map { ($0.type, $0.fetchPlan) },
        uniquingKeysWith: { first, _ in first }
    )
}
