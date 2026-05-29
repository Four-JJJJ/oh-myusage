import Foundation

extension AppViewModel {
    nonisolated static var statusBarDisplayConfigDidChangeNotification: Notification.Name {
        Notification.Name("OhMyUsage.StatusBarDisplayConfigDidChange")
    }
}

@MainActor
extension AppViewModel {
    var statusBarProviderID: String? {
        config.statusBarProviderID
    }

    var statusBarMultiUsageEnabled: Bool {
        config.statusBarMultiUsageEnabled
    }

    var statusBarDisplayStyle: StatusBarDisplayStyle {
        config.statusBarDisplayStyle
    }

    var statusBarAppearanceMode: StatusBarAppearanceMode {
        config.statusBarAppearanceMode
    }

    var showOfficialAccountEmailInMenuBar: Bool {
        config.showOfficialAccountEmailInMenuBar
    }

    var claudeStatusBarDisplaySlotID: CodexSlotID? {
        config.claudeStatusBarDisplaySlotID
    }

    func isStatusBarProvider(providerID: String) -> Bool {
        guard config.providers.first(where: { $0.id == providerID })?.showsInMenuBar == true else {
            return false
        }
        if config.statusBarMultiUsageEnabled {
            return config.statusBarMultiProviderIDs.contains(providerID)
        }
        return config.statusBarProviderID == providerID
    }

    func setStatusBarMultiUsageEnabled(_ enabled: Bool) {
        let outcome = statusBarPreferencesCoordinator.setStatusBarMultiUsageEnabled(
            enabled,
            config: &config,
            visibleClaudeMonitoringSlotIDs: AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(
                profiles: claudeProfiles
            )
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarDisplayStyle(_ style: StatusBarDisplayStyle) {
        let outcome = statusBarPreferencesCoordinator.setStatusBarDisplayStyle(
            style,
            config: &config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarAppearanceMode(_ mode: StatusBarAppearanceMode) {
        let outcome = statusBarPreferencesCoordinator.setStatusBarAppearanceMode(
            mode,
            config: &config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarDisplayEnabled(_ enabled: Bool, providerID: String) {
        let outcome = statusBarPreferencesCoordinator.setStatusBarDisplayEnabled(
            enabled,
            providerID: providerID,
            config: &config,
            visibleClaudeMonitoringSlotIDs: AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(
                profiles: claudeProfiles
            )
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarProvider(providerID: String?) {
        let outcome = statusBarPreferencesCoordinator.setStatusBarProvider(
            providerID: providerID,
            config: &config,
            visibleClaudeMonitoringSlotIDs: AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(
                profiles: claudeProfiles
            )
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setShowOfficialAccountEmailInMenuBar(_ enabled: Bool) {
        let outcome = statusBarPreferencesCoordinator.setShowOfficialAccountEmailInMenuBar(
            enabled,
            config: &config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func showOfficialPlanTypeInMenuBar(providerID: String) -> Bool {
        guard let provider = config.providers.first(where: { $0.id == providerID }) else {
            return true
        }
        guard provider.family == .official else {
            return true
        }
        return provider.officialConfig?.showPlanTypeInMenuBar
            ?? ProviderDescriptor.defaultOfficialConfig(type: provider.type).showPlanTypeInMenuBar
    }

    func setShowOfficialPlanTypeInMenuBar(_ enabled: Bool, providerID: String) {
        let outcome = statusBarPreferencesCoordinator.setShowOfficialPlanTypeInMenuBar(
            enabled,
            providerID: providerID,
            config: &config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func showExpirationTimeInMenuBar(providerID: String) -> Bool {
        guard let provider = config.providers.first(where: { $0.id == providerID }) else {
            return true
        }
        return provider.showsExpirationTimeInMenuBar
    }

    func setShowExpirationTimeInMenuBar(_ enabled: Bool, providerID: String) {
        let outcome = statusBarPreferencesCoordinator.setShowExpirationTimeInMenuBar(
            enabled,
            providerID: providerID,
            config: &config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func claudeStatusBarResolvedDisplaySlotID() -> CodexSlotID? {
        resolvedClaudeStatusBarDisplaySlotID()
    }

    func isClaudeStatusBarDisplaySlot(slotID: CodexSlotID) -> Bool {
        resolvedClaudeStatusBarDisplaySlotID() == slotID
    }

    func setClaudeStatusBarDisplaySlotID(_ slotID: CodexSlotID?) {
        let selectionOutcome = officialProfileDisplayCoordinator.updateClaudeStatusBarDisplaySelection(
            requestedSlotID: slotID,
            configuredSlotID: config.claudeStatusBarDisplaySlotID,
            profiles: claudeProfiles,
            slots: claudeSlots
        )
        guard selectionOutcome.shouldPersist else {
            triggerClaudeStatusBarDisplayPrefetchIfNeeded(
                slotID: selectionOutcome.resolvedDisplaySlotID
            )
            return
        }
        config.claudeStatusBarDisplaySlotID = selectionOutcome.normalizedConfiguredSlotID
        normalizeStatusBarSelections()
        _ = persistConfiguration(showFeedback: true)
        triggerClaudeStatusBarDisplayPrefetchIfNeeded(
            slotID: selectionOutcome.resolvedDisplaySlotID
        )
        if selectionOutcome.shouldNotify {
            notifyStatusBarDisplayConfigChanged()
        }
    }

    func statusBarProvider() -> ProviderDescriptor? {
        if let id = config.statusBarProviderID,
           let selected = config.providers.first(where: { $0.id == id && $0.enabled && $0.showsInMenuBar }) {
            return selected
        }
        guard let fallbackID = AppConfig.defaultStatusBarProviderID(from: config.providers) else {
            return nil
        }
        return config.providers.first(where: { $0.id == fallbackID && $0.enabled && $0.showsInMenuBar })
    }

    func statusBarProvidersForDisplay() -> [ProviderDescriptor] {
        if !config.statusBarMultiUsageEnabled {
            if let provider = statusBarProvider() {
                return [provider]
            }
            return []
        }

        let providersByID = Dictionary(uniqueKeysWithValues: config.providers.map { ($0.id, $0) })
        let selectedProviders = config.statusBarMultiProviderIDs.compactMap { id -> ProviderDescriptor? in
            guard let provider = providersByID[id], provider.enabled, provider.showsInMenuBar else { return nil }
            return provider
        }
        return selectedProviders
    }

    func refreshDisplayedStatusBarProviders(forceRefresh: Bool = false) {
        providerRefreshCoordinator.refreshDisplayedStatusBarProviders(
            providers: statusBarProvidersForDisplay(),
            forceRefresh: forceRefresh
        ) { [weak self] descriptor, forceRefresh in
            await self?.refreshProvider(descriptor, forceRefresh: forceRefresh)
        }
    }

    func applyStatusBarPreferencesMutation(_ outcome: StatusBarPreferencesMutationOutcome) {
        guard outcome != .none else { return }
        if outcome.shouldPersist {
            _ = persistConfiguration(showFeedback: true)
        }
        if outcome.shouldNotifyDisplayConfigChange {
            notifyStatusBarDisplayConfigChanged()
        }
        if outcome.shouldRefreshDisplayedProviders {
            refreshDisplayedStatusBarProviders()
        }
    }

    func normalizeStatusBarSelections() {
        statusBarPreferencesCoordinator.normalizeSelections(
            config: &config,
            visibleClaudeMonitoringSlotIDs: AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(
                profiles: claudeProfiles
            )
        )
    }

    func notifyStatusBarDisplayConfigChanged() {
        NotificationCenter.default.post(
            name: Self.statusBarDisplayConfigDidChangeNotification,
            object: nil
        )
    }
}
