import Foundation
import OhMyUsageDomain

enum ProviderCapabilityMetadataCatalog {
    static func capabilities(for provider: ProviderDescriptor) -> ProviderCapabilities {
        let type = ProviderTypeMetadataCatalog.metadata(for: provider.type)
        let relayUsesQuotaCard = provider.isRelay && provider.relayDisplayMode == .quotaPercent
        let officialNonRelayUsesQuotaCard = provider.family == .official && !provider.isRelay
        // Z.ai (API) / Kimi (API) / Qwen (API) 是纯金额指标，走余额卡片而非百分比额度卡。
        let isPureBalanceOfficialProvider = provider.type == .zaiBalance || provider.type == .kimiBalance || provider.type == .qwenBalance
        return ProviderCapabilities(
            supportsBalance: provider.isRelay || provider.family == .thirdParty || isPureBalanceOfficialProvider,
            supportsQuotaWindows: officialNonRelayUsesQuotaCard || relayUsesQuotaCard,
            supportsAccountSwitching: provider.family == .official && type.supportsAccountSwitching,
            supportsLocalUsageHistory: provider.family == .official && type.supportsLocalUsageHistory,
            usesPercentageMenuCard: (officialNonRelayUsesQuotaCard && !isPureBalanceOfficialProvider) || provider.type == .kimi || relayUsesQuotaCard
        )
    }
}
