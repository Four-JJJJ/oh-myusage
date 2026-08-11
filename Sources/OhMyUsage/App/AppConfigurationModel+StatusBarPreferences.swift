import Foundation

@MainActor
extension AppConfigurationModel {
    // MARK: - Status bar preferences

    func setStatusBarMultiUsageEnabled(_ enabled: Bool) {
        let host = requireHost()
        let outcome = statusBarPreferencesCoordinator.setStatusBarMultiUsageEnabled(
            enabled,
            config: &host.config,
            visibleClaudeMonitoringSlotIDs: visibleClaudeMonitoringSlotIDs()
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarDisplayStyle(_ style: StatusBarDisplayStyle) {
        let host = requireHost()
        let outcome = statusBarPreferencesCoordinator.setStatusBarDisplayStyle(
            style,
            config: &host.config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarAppearanceMode(_ mode: StatusBarAppearanceMode) {
        let host = requireHost()
        let outcome = statusBarPreferencesCoordinator.setStatusBarAppearanceMode(
            mode,
            config: &host.config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarDisplayEnabled(_ enabled: Bool, providerID: String) {
        let host = requireHost()
        let outcome = statusBarPreferencesCoordinator.setStatusBarDisplayEnabled(
            enabled,
            providerID: providerID,
            config: &host.config,
            visibleClaudeMonitoringSlotIDs: visibleClaudeMonitoringSlotIDs()
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setStatusBarProvider(providerID: String?) {
        let host = requireHost()
        let outcome = statusBarPreferencesCoordinator.setStatusBarProvider(
            providerID: providerID,
            config: &host.config,
            visibleClaudeMonitoringSlotIDs: visibleClaudeMonitoringSlotIDs()
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setShowOfficialAccountEmailInMenuBar(_ enabled: Bool) {
        let host = requireHost()
        let outcome = statusBarPreferencesCoordinator.setShowOfficialAccountEmailInMenuBar(
            enabled,
            config: &host.config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setShowOfficialPlanTypeInMenuBar(_ enabled: Bool, providerID: String) {
        let host = requireHost()
        let outcome = statusBarPreferencesCoordinator.setShowOfficialPlanTypeInMenuBar(
            enabled,
            providerID: providerID,
            config: &host.config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func setShowExpirationTimeInMenuBar(_ enabled: Bool, providerID: String) {
        let host = requireHost()
        let outcome = statusBarPreferencesCoordinator.setShowExpirationTimeInMenuBar(
            enabled,
            providerID: providerID,
            config: &host.config
        )
        applyStatusBarPreferencesMutation(outcome)
    }

    func applyStatusBarPreferencesMutation(_ outcome: StatusBarPreferencesMutationOutcome) {
        guard outcome != .none else { return }
        let host = requireHost()
        if outcome.shouldPersist {
            _ = persistConfiguration(showFeedback: true)
        }
        if outcome.shouldNotifyDisplayConfigChange {
            host.notifyStatusBarDisplayConfigChanged()
        }
        if outcome.shouldRefreshDisplayedProviders {
            host.refreshDisplayedStatusBarProviders()
        }
    }

    func normalizeStatusBarSelections() {
        let host = requireHost()
        statusBarPreferencesCoordinator.normalizeSelections(
            config: &host.config,
            visibleClaudeMonitoringSlotIDs: visibleClaudeMonitoringSlotIDs()
        )
    }

    private func visibleClaudeMonitoringSlotIDs() -> Set<CodexSlotID> {
        let host = requireHost()
        return AppOfficialProfileStateCoordinator.visibleClaudeMonitoringSlotIDs(
            profiles: host.claudeProfiles
        )
    }
}
