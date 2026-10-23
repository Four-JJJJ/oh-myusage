import OhMyUsageProviders
import Foundation
import OhMyUsageApplication
import OhMyUsageDomain

/// Owns the Configuration session boundary: list/credential/settings mutation,
/// persist/restart orchestration, and related coordinators.
/// Config / snapshots / credentialLookupVersion remain on AppViewModel/sessionStore
/// so Observation projections keep working.
@MainActor
final class AppConfigurationModel {
    let officialProviderSettingsCoordinator = AppOfficialProviderSettingsCoordinator()
    let providerListMutationCoordinator = AppProviderListMutationCoordinator()
    let providerCredentialCoordinator = AppProviderCredentialCoordinator()
    let credentialLookupCoordinator = AppCredentialLookupCoordinator()
    let relayProviderSettingsCoordinator = AppRelayProviderSettingsCoordinator()
    let relayDescriptorPreviewBuilder = RelayDescriptorPreviewBuilder()
    let statusBarPreferencesCoordinator = AppStatusBarPreferencesCoordinator()
    let configurationMutationCoordinator = AppConfigurationMutationCoordinator()
    let settingsPersistenceFeedbackCoordinator: AppSettingsPersistenceFeedbackCoordinator

    private weak var host: AppViewModel?

    init(settingsPersistenceStatusClearDelaySeconds: TimeInterval = 4) {
        self.settingsPersistenceFeedbackCoordinator = AppSettingsPersistenceFeedbackCoordinator(
            clearDelaySeconds: settingsPersistenceStatusClearDelaySeconds
        )
    }

    /// Bind the host ViewModel after it is fully initialized (before normalize/persist helpers run).
    func bind(host: AppViewModel) {
        self.host = host
    }

    // MARK: - Provider list

    func setEnabled(_ enabled: Bool, providerID: String) {
        let host = requireHost()
        let outcome = providerListMutationCoordinator.setEnabled(
            enabled,
            providerID: providerID,
            config: &host.config
        )
        applyProviderListMutation(outcome)
        prepareSecureStoreForEnabledProviderIfNeeded(enabled: enabled, providerID: providerID)
    }

    /// 首次授权流程（doc 7.5）：用户启用需要凭证的 Provider 时，才发起一次交互式
    /// 准备；vault 已就绪、本次会话已拒绝过、或 Provider 不需要 vault 凭证时不打扰。
    /// 就绪判断只读 vault 准备标志 + 缓存元数据（非交互）。
    private func prepareSecureStoreForEnabledProviderIfNeeded(enabled: Bool, providerID: String) {
        guard enabled else { return }
        let host = requireHost()
        guard !host.keychain.isSecureStoreReady(),
              host.credentialAccessState != .systemAccessRequired else { return }
        guard let provider = host.config.providers.first(where: { $0.id == providerID }),
              Self.providerRequiresVaultCredentials(provider) else { return }
        host.prepareSecureStorageAccess()
    }

    /// 该 Provider 是否依赖应用 vault 凭证（keychain 授权槽位 / 手动 Cookie /
    /// relay 余额凭证）。纯本地文件来源（如 Codex auth.json）不算。
    static func providerRequiresVaultCredentials(_ descriptor: ProviderDescriptor) -> Bool {
        if descriptor.auth.kind != .none,
           descriptor.auth.keychainService != nil,
           descriptor.auth.keychainAccount != nil {
            return true
        }
        if descriptor.officialConfig?.manualCookieAccount != nil {
            return true
        }
        if let balanceAuth = descriptor.relayConfig?.balanceAuth,
           balanceAuth.keychainService != nil,
           balanceAuth.keychainAccount != nil {
            return true
        }
        return false
    }

    func reorderEnabledProviders(
        family: ProviderFamily,
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        let host = requireHost()
        let outcome = providerListMutationCoordinator.reorderEnabledProviders(
            family: family,
            fromOffsets: fromOffsets,
            toOffset: toOffset,
            config: &host.config
        )
        applyProviderListMutation(outcome)
    }

    func commitProviderThreshold(_ value: Double, providerID: String) {
        let host = requireHost()
        let outcome = providerListMutationCoordinator.commitThreshold(
            value,
            providerID: providerID,
            config: &host.config
        )
        applyProviderListMutation(outcome)
    }

    // MARK: - Persist / reset

    @discardableResult
    func persistConfiguration(
        showFeedback: Bool = false,
        successText: String? = nil
    ) -> Bool {
        let host = requireHost()
        return applyConfigurationPersistenceOutcome(
            configurationMutationCoordinator.persistConfiguration(
                host.config,
                repository: host.configurationRepository,
                showFeedback: showFeedback,
                successText: successText ?? host.localizedText("已保存", "Saved"),
                failureText: host.localizedText("保存失败", "Save Failed")
            )
        )
    }

    @discardableResult
    func resetConfiguration(showFeedback: Bool = false) -> Bool {
        let host = requireHost()
        return applyConfigurationPersistenceOutcome(
            configurationMutationCoordinator.resetConfiguration(
                repository: host.configurationRepository,
                showFeedback: showFeedback,
                successText: host.localizedText("已重置", "Reset Complete"),
                failureText: host.localizedText("重置失败", "Reset Failed")
            )
        )
    }

    @discardableResult
    func applyConfigurationPersistenceOutcome(
        _ outcome: AppConfigurationPersistenceOutcome
    ) -> Bool {
        let host = requireHost()
        return settingsPersistenceFeedbackCoordinator.apply(outcome) { [weak host] state, errorMessage in
            host?.settingsPersistenceStatus = state
            host?.settingsPersistenceErrorMessage = errorMessage
        }
    }

    func pruneThirdPartyBalanceBaselines() {
        let host = requireHost()
        let previousEntries = host.thirdPartyBalanceBaselineTracker.snapshotEntries()
        let validProviderIDs = Set(
            host.config.providers
                .filter { $0.family == .thirdParty }
                .map(\.id)
        )
        host.providerRefreshModel.mutateProviderState { state in
            state.thirdPartyBalanceBaselineTracker.prune(
                keepingProviderIDs: validProviderIDs,
                maxEntries: RuntimeDiagnosticsLimits.thirdPartyBalanceBaselineCacheMaxEntries
            )
        }
        persistThirdPartyBalanceBaselinesIfChanged(previousEntries: previousEntries)
    }

    // MARK: - Provider lookups

    func descriptor(for id: String) -> ProviderDescriptor? {
        requireHost().config.providers.first(where: { $0.id == id })
    }

    func displayNameForDiscovery(_ descriptor: ProviderDescriptor) -> String {
        switch descriptor.type {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .gemini:
            return "Gemini"
        case .copilot:
            return "GitHub Copilot"
        case .microsoftCopilot:
            return "Microsoft Copilot"
        case .zai:
            return "Z.ai"
        case .zaiBalance:
            return "Z.ai (API)"
        case .amp:
            return "Amp"
        case .cursor:
            return "Cursor"
        case .grokBot:
            return "Grok Bot"
        case .jetbrains:
            return "JetBrains"
        case .kiro:
            return "Kiro"
        case .windsurf:
            return "Windsurf"
        case .kimi:
            return "Kimi"
        case .kimiBalance:
            return "Kimi (API)"
        case .trae:
            return "Trae SOLO"
        case .openrouterCredits:
            return "OpenRouter Credits"
        case .openrouterAPI:
            return "OpenRouter API"
        case .ollamaCloud:
            return "Ollama Cloud"
        case .opencodeGo:
            return "OpenCode Go"
        case .qwen:
            return "Qwen"
        case .qwenBalance:
            return "Qwen (API)"
        case .grok:
            return "Grok"
        case .relay, .open, .dragon:
            return descriptor.name
        }
    }

    // MARK: - Private orchestration

    func persistAndRestart() {
        let host = requireHost()
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
        _ = persistConfiguration(showFeedback: true)
        host.restartPolling()
        host.syncClaudeProfilesCurrentState()
        host.officialProfileLifecycleCoordinator.scheduleClaudePrefetchIfNeeded(
            descriptor: host.claudeOfficialProviderDescriptor(),
            profiles: host.claudeDisplayableProfiles(),
            slots: host.claudeSlots,
            runtime: host.claudeOfficialProfileRefreshRuntime
        ) { [weak host] profile, descriptor in
            guard let host else { return .skipped }
            return await host.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
        }
    }

    private func applyProviderListMutation(_ outcome: AppProviderListMutationOutcome) {
        guard outcome != .none else { return }
        let host = requireHost()
        if !outcome.removedThirdPartyBaselineProviderIDs.isEmpty {
            host.providerRefreshModel.mutateProviderState { state in
                for providerID in outcome.removedThirdPartyBaselineProviderIDs {
                    state.thirdPartyBalanceBaselineTracker.remove(providerID: providerID)
                }
            }
            persistThirdPartyBalanceBaselines()
        }
        if outcome.shouldPersistAndRestart {
            persistAndRestart()
        }
        if outcome.shouldNotifyDisplayConfigChange {
            host.notifyStatusBarDisplayConfigChanged()
        }
        if outcome.shouldRefreshDisplayedProviders {
            host.refreshDisplayedStatusBarProviders()
        }
    }

    private func persistThirdPartyBalanceBaselinesIfChanged(
        previousEntries: [String: ThirdPartyBalanceBaselineTracker.Entry]
    ) {
        let host = requireHost()
        let latestEntries = host.thirdPartyBalanceBaselineTracker.snapshotEntries()
        guard latestEntries != previousEntries else { return }
        host.thirdPartyBalanceBaselineStore.save(latestEntries)
    }

    func persistThirdPartyBalanceBaselines() {
        let host = requireHost()
        host.thirdPartyBalanceBaselineStore.save(host.thirdPartyBalanceBaselineTracker.snapshotEntries())
    }

    func requireHost() -> AppViewModel {
        guard let host else {
            preconditionFailure("AppConfigurationModel.bind must be called before use")
        }
        return host
    }
}
