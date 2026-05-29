import Foundation
import OhMyUsageDomain

struct AppRelayProviderSettingsCoordinator {
    func updateOpenProviderSettings(
        draft: RelaySettingsDraft,
        providers: inout [ProviderDescriptor],
        previewBuilder: RelayDescriptorPreviewBuilder = RelayDescriptorPreviewBuilder()
    ) -> AppProviderSettingsMutationOutcome {
        guard let idx = providers.firstIndex(where: { $0.id == draft.providerID }),
              let updated = previewBuilder.build(draft: draft, providers: providers) else {
            return .none
        }

        let previousDisplaysUsedQuota = providers[idx].displaysUsedQuota
        let previousName = providers[idx].name
        providers[idx] = updated
        return AppProviderSettingsMutationOutcome(
            shouldPersistAndRestart: true,
            shouldNotifyDisplayConfigChange: previousDisplaysUsedQuota != updated.displaysUsedQuota
                || previousName != updated.name
        )
    }

    func updateThirdPartyQuotaDisplayMode(
        providerID: String,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        providers: inout [ProviderDescriptor]
    ) -> AppProviderSettingsMutationOutcome {
        guard let idx = providers.firstIndex(where: { $0.id == providerID }),
              providers[idx].isRelay,
              var relayConfig = providers[idx].relayConfig else {
            return .none
        }

        var provider = providers[idx]
        let previousDisplaysUsedQuota = provider.displaysUsedQuota
        relayConfig.quotaDisplayMode = quotaDisplayMode
        provider.relayConfig = relayConfig
        let normalizedProvider = provider.normalized()
        providers[idx] = normalizedProvider
        return AppProviderSettingsMutationOutcome(
            shouldPersistAndRestart: true,
            shouldNotifyDisplayConfigChange: previousDisplaysUsedQuota != normalizedProvider.displaysUsedQuota
        )
    }
}
