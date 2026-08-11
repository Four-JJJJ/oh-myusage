import Foundation
import OhMyUsageDomain

enum ProviderCapabilityMetadataCatalog {
    static func capabilities(for provider: ProviderDescriptor) -> ProviderCapabilities {
        let type = ProviderTypeMetadataCatalog.metadata(for: provider.type)
        let relayUsesQuotaCard = provider.isRelay && provider.relayDisplayMode == .quotaPercent
        let officialNonRelayUsesQuotaCard = provider.family == .official && !provider.isRelay
        return ProviderCapabilities(
            supportsBalance: provider.isRelay || provider.family == .thirdParty || provider.type == .openrouterCredits,
            supportsQuotaWindows: officialNonRelayUsesQuotaCard || relayUsesQuotaCard,
            supportsAccountSwitching: provider.family == .official && type.supportsAccountSwitching,
            supportsLocalUsageHistory: provider.family == .official && type.supportsLocalUsageHistory,
            usesPercentageMenuCard: officialNonRelayUsesQuotaCard || provider.type == .kimi || relayUsesQuotaCard
        )
    }
}
