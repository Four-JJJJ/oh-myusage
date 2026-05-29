import Foundation

struct StatusBarPreferencesMutationOutcome: Equatable {
    var shouldPersist: Bool = false
    var shouldNotifyDisplayConfigChange: Bool = false
    var shouldRefreshDisplayedProviders: Bool = false

    static let none = StatusBarPreferencesMutationOutcome()
}

struct AppStatusBarPreferencesCoordinator {
    func normalizeSelections(
        config: inout AppConfig,
        visibleClaudeMonitoringSlotIDs: Set<CodexSlotID>
    ) {
        let enabledProviders = config.providers.filter(\.enabled)
        let visibleProviderIDs = Set(enabledProviders.filter(\.showsInMenuBar).map(\.id))

        if let selectedID = config.statusBarProviderID,
           !visibleProviderIDs.contains(selectedID) {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        } else if config.statusBarProviderID == nil {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        }

        config.statusBarMultiProviderIDs = AppConfig.normalizedStatusBarMultiProviderIDs(
            config.statusBarMultiProviderIDs,
            providers: config.providers
        ).filter { visibleProviderIDs.contains($0) }

        if let selectedSlotID = config.claudeStatusBarDisplaySlotID,
           !visibleClaudeMonitoringSlotIDs.contains(selectedSlotID) {
            config.claudeStatusBarDisplaySlotID = nil
        }
    }

    func setStatusBarMultiUsageEnabled(
        _ enabled: Bool,
        config: inout AppConfig,
        visibleClaudeMonitoringSlotIDs: Set<CodexSlotID>
    ) -> StatusBarPreferencesMutationOutcome {
        guard config.statusBarMultiUsageEnabled != enabled else { return .none }
        config.statusBarMultiUsageEnabled = enabled
        if enabled,
           config.statusBarMultiProviderIDs.isEmpty,
           let selected = config.statusBarProviderID {
            config.statusBarMultiProviderIDs = [selected]
        }
        normalizeSelections(
            config: &config,
            visibleClaudeMonitoringSlotIDs: visibleClaudeMonitoringSlotIDs
        )
        return StatusBarPreferencesMutationOutcome(
            shouldPersist: true,
            shouldNotifyDisplayConfigChange: true,
            shouldRefreshDisplayedProviders: true
        )
    }

    func setStatusBarDisplayStyle(
        _ style: StatusBarDisplayStyle,
        config: inout AppConfig
    ) -> StatusBarPreferencesMutationOutcome {
        guard config.statusBarDisplayStyle != style else { return .none }
        config.statusBarDisplayStyle = style
        return StatusBarPreferencesMutationOutcome(
            shouldPersist: true,
            shouldNotifyDisplayConfigChange: true
        )
    }

    func setStatusBarAppearanceMode(
        _ mode: StatusBarAppearanceMode,
        config: inout AppConfig
    ) -> StatusBarPreferencesMutationOutcome {
        guard config.statusBarAppearanceMode != mode else { return .none }
        config.statusBarAppearanceMode = mode
        return StatusBarPreferencesMutationOutcome(
            shouldPersist: true,
            shouldNotifyDisplayConfigChange: true
        )
    }

    func setStatusBarDisplayEnabled(
        _ enabled: Bool,
        providerID: String,
        config: inout AppConfig,
        visibleClaudeMonitoringSlotIDs: Set<CodexSlotID>
    ) -> StatusBarPreferencesMutationOutcome {
        guard let providerIndex = config.providers.firstIndex(where: { $0.id == providerID }) else { return .none }

        let previousConfig = config
        config.providers[providerIndex].showInMenuBar = enabled

        if config.statusBarMultiUsageEnabled {
            if enabled {
                if !config.statusBarMultiProviderIDs.contains(providerID) {
                    config.statusBarMultiProviderIDs.append(providerID)
                }
                if config.statusBarProviderID == nil {
                    config.statusBarProviderID = providerID
                }
            } else {
                config.statusBarMultiProviderIDs.removeAll { $0 == providerID }
                if config.statusBarProviderID == providerID {
                    config.statusBarProviderID = config.statusBarMultiProviderIDs.first
                        ?? AppConfig.defaultStatusBarProviderID(from: config.providers)
                }
            }
            normalizeSelections(
                config: &config,
                visibleClaudeMonitoringSlotIDs: visibleClaudeMonitoringSlotIDs
            )
            guard config != previousConfig else { return .none }
            return StatusBarPreferencesMutationOutcome(
                shouldPersist: true,
                shouldNotifyDisplayConfigChange: true,
                shouldRefreshDisplayedProviders: true
            )
        }

        if enabled {
            config.statusBarProviderID = providerID
        } else if config.statusBarProviderID == providerID {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        }
        normalizeSelections(
            config: &config,
            visibleClaudeMonitoringSlotIDs: visibleClaudeMonitoringSlotIDs
        )
        guard config != previousConfig else { return .none }
        return StatusBarPreferencesMutationOutcome(
            shouldPersist: true,
            shouldNotifyDisplayConfigChange: true,
            shouldRefreshDisplayedProviders: true
        )
    }

    func setStatusBarProvider(
        providerID: String?,
        config: inout AppConfig,
        visibleClaudeMonitoringSlotIDs: Set<CodexSlotID>
    ) -> StatusBarPreferencesMutationOutcome {
        let normalized: String?
        if let providerID,
           let index = config.providers.firstIndex(where: { $0.id == providerID }) {
            config.providers[index].showInMenuBar = true
            normalized = providerID
        } else {
            normalized = AppConfig.defaultStatusBarProviderID(from: config.providers)
        }

        if config.statusBarProviderID == normalized {
            guard normalized != nil else { return .none }
            normalizeSelections(
                config: &config,
                visibleClaudeMonitoringSlotIDs: visibleClaudeMonitoringSlotIDs
            )
            return StatusBarPreferencesMutationOutcome(shouldPersist: true)
        }

        config.statusBarProviderID = normalized
        normalizeSelections(
            config: &config,
            visibleClaudeMonitoringSlotIDs: visibleClaudeMonitoringSlotIDs
        )
        return StatusBarPreferencesMutationOutcome(
            shouldPersist: true,
            shouldNotifyDisplayConfigChange: true,
            shouldRefreshDisplayedProviders: true
        )
    }

    func setShowOfficialAccountEmailInMenuBar(
        _ enabled: Bool,
        config: inout AppConfig
    ) -> StatusBarPreferencesMutationOutcome {
        guard config.showOfficialAccountEmailInMenuBar != enabled else { return .none }
        config.showOfficialAccountEmailInMenuBar = enabled
        return StatusBarPreferencesMutationOutcome(
            shouldPersist: true,
            shouldNotifyDisplayConfigChange: true
        )
    }

    func setShowOfficialPlanTypeInMenuBar(
        _ enabled: Bool,
        providerID: String,
        config: inout AppConfig
    ) -> StatusBarPreferencesMutationOutcome {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }),
              config.providers[idx].family == .official else {
            return .none
        }

        var provider = config.providers[idx]
        var official = provider.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type)
        guard official.showPlanTypeInMenuBar != enabled else { return .none }
        official.showPlanTypeInMenuBar = enabled
        provider.officialConfig = official
        config.providers[idx] = provider
        return StatusBarPreferencesMutationOutcome(
            shouldPersist: true,
            shouldNotifyDisplayConfigChange: true
        )
    }

    func setShowExpirationTimeInMenuBar(
        _ enabled: Bool,
        providerID: String,
        config: inout AppConfig
    ) -> StatusBarPreferencesMutationOutcome {
        guard let idx = config.providers.firstIndex(where: { $0.id == providerID }) else {
            return .none
        }

        var provider = config.providers[idx]
        if provider.isRelay {
            guard var relayConfig = provider.relayConfig else { return .none }
            guard relayConfig.showExpirationTimeInMenuBar != enabled else { return .none }
            relayConfig.showExpirationTimeInMenuBar = enabled
            provider.relayConfig = relayConfig
        } else if provider.family == .official {
            var official = provider.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type)
            guard official.showExpirationTimeInMenuBar != enabled else { return .none }
            official.showExpirationTimeInMenuBar = enabled
            provider.officialConfig = official
        } else {
            return .none
        }

        config.providers[idx] = provider.normalized()
        return StatusBarPreferencesMutationOutcome(
            shouldPersist: true,
            shouldNotifyDisplayConfigChange: true
        )
    }
}
