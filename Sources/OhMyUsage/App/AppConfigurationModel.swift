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

    // MARK: - Credential lookup

    func hasToken(for descriptor: ProviderDescriptor) -> Bool {
        let host = requireHost()
        return credentialLookupCoordinator.credentialExists(
            for: descriptor,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    func savedTokenLength(for descriptor: ProviderDescriptor) -> Int? {
        let host = requireHost()
        return credentialLookupCoordinator.savedCredentialLength(
            for: descriptor,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    func hasToken(auth: AuthConfig) -> Bool {
        let host = requireHost()
        return credentialLookupCoordinator.credentialExists(
            auth: auth,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    func savedTokenLength(auth: AuthConfig) -> Int? {
        let host = requireHost()
        return credentialLookupCoordinator.savedCredentialLength(
            auth: auth,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    func hasOfficialManualCookie(for provider: ProviderDescriptor) -> Bool {
        let host = requireHost()
        return credentialLookupCoordinator.manualCookieExists(
            for: provider,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    func savedOfficialManualCookieLength(for provider: ProviderDescriptor) -> Int? {
        let host = requireHost()
        return credentialLookupCoordinator.savedManualCookieLength(
            for: provider,
            secureStorageReady: host.secureStorageReady,
            lookupVersion: host.credentialLookupVersion,
            credentialAccessService: host.credentialAccessService
        ) { [weak host] in
            host?.credentialLookupVersion &+= 1
        }
    }

    // MARK: - Credential mutation

    func saveToken(_ token: String, for descriptor: ProviderDescriptor) -> Bool {
        let host = requireHost()
        let outcome = providerCredentialCoordinator.saveToken(
            token,
            descriptor: descriptor,
            normalize: { token, kind in
                self.normalizedCredential(token, kind: kind)
            },
            saveCredential: { value, service, account in
                host.credentialAccessService.saveCredential(value, service: service, account: account)
            }
        )
        applyCredentialMutationOutcome(outcome)
        return outcome.didPersistCredential
    }

    @discardableResult
    func saveTokenAndRestart(_ token: String, for descriptor: ProviderDescriptor) -> Bool {
        let host = requireHost()
        let ok = saveToken(token, for: descriptor)
        if ok {
            host.restartPolling()
        }
        return ok
    }

    func saveToken(_ token: String, auth: AuthConfig) -> Bool {
        let host = requireHost()
        let outcome = providerCredentialCoordinator.saveToken(
            token,
            auth: auth,
            normalize: { token, kind in
                self.normalizedCredential(token, kind: kind)
            },
            saveCredential: { value, service, account in
                host.credentialAccessService.saveCredential(value, service: service, account: account)
            }
        )
        applyCredentialMutationOutcome(outcome)
        return outcome.didPersistCredential
    }

    @discardableResult
    func saveTokenAndRestart(_ token: String, auth: AuthConfig) -> Bool {
        let host = requireHost()
        let ok = saveToken(token, auth: auth)
        if ok {
            host.restartPolling()
        }
        return ok
    }

    func saveOfficialManualCookie(_ value: String, providerID: String) -> Bool {
        let host = requireHost()
        let outcome = providerCredentialCoordinator.saveOfficialManualCookie(
            value,
            providerID: providerID,
            providers: host.config.providers,
            saveCredential: { value, service, account in
                host.credentialAccessService.saveCredential(value, service: service, account: account)
            }
        )
        applyCredentialMutationOutcome(outcome)
        return outcome.didPersistCredential
    }

    @discardableResult
    func saveOfficialManualCookieAndRestart(_ value: String, providerID: String) -> Bool {
        let host = requireHost()
        let ok = saveOfficialManualCookie(value, providerID: providerID)
        if ok {
            host.restartPolling()
        }
        return ok
    }

    func invalidateCredentialLookupCache() {
        let host = requireHost()
        applyCredentialMutationOutcome(
            providerCredentialCoordinator.invalidateLookupCache {
                host.credentialAccessService.invalidateLookupCache()
            }
        )
    }

    // MARK: - Relay / open providers

    @discardableResult
    func addRelaySiteDraft(
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        userID: String,
        credentialInput: String? = nil,
        balanceCredentialMode: RelayCredentialMode = .browserPreferred
    ) -> ProviderDescriptor? {
        let host = requireHost()
        let normalizedBaseURL = ProviderDescriptor.normalizeRelayBaseURL(baseURL)
        guard !normalizedBaseURL.isEmpty else { return nil }

        let trimmedAdapterID = preferredAdapterID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAdapterID = (trimmedAdapterID?.isEmpty == false) ? trimmedAdapterID : nil
        let baseProvider = ProviderDescriptor.makeOpenRelay(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: normalizedBaseURL,
            preferredAdapterID: resolvedAdapterID
        )

        var draft = RelaySettingsDraft(provider: baseProvider, preferredAdapterID: resolvedAdapterID)
        draft.name = name
        draft.baseURL = normalizedBaseURL
        draft.balanceCredentialMode = balanceCredentialMode
        draft.userID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.quotaDisplayMode = .remaining

        let provider = relayDescriptorPreviewBuilder.build(
            draft: draft,
            providers: host.config.providers + [baseProvider]
        ) ?? baseProvider

        host.config.providers.append(provider)
        if host.config.statusBarProviderID == nil {
            host.config.statusBarProviderID = provider.id
        }

        if let credentialInput {
            let trimmedCredential = credentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCredential.isEmpty, let balanceAuth = provider.relayConfig?.balanceAuth {
                _ = saveToken(trimmedCredential, auth: balanceAuth)
            }
        }

        persistAndRestart()
        host.notifyStatusBarDisplayConfigChanged()
        host.refreshDisplayedStatusBarProviders()
        return provider
    }

    func addOpenRelay(name: String, baseURL: String, preferredAdapterID: String? = nil) {
        let host = requireHost()
        let provider = ProviderDescriptor.makeOpenRelay(
            name: name,
            baseURL: baseURL,
            preferredAdapterID: preferredAdapterID
        )
        host.config.providers.append(provider)
        if host.config.statusBarProviderID == nil {
            host.config.statusBarProviderID = provider.id
        }
        persistAndRestart()
        host.notifyStatusBarDisplayConfigChanged()
        host.refreshDisplayedStatusBarProviders()
    }

    func removeProvider(providerID: String) {
        let host = requireHost()
        host.config.providers.removeAll { $0.id == providerID }
        if host.config.statusBarProviderID == providerID {
            host.config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: host.config.providers)
        }
        host.providerRefreshModel.mutateProviderState { state in
            state.thirdPartyBalanceBaselineTracker.remove(providerID: providerID)
            state.snapshots.removeValue(forKey: providerID)
            state.errors.removeValue(forKey: providerID)
            state.consecutiveFailures.removeValue(forKey: providerID)
            state.activeAlerts.remove("low:\(providerID)")
            state.activeAlerts.remove("fail:\(providerID)")
            state.activeAlerts.remove("auth:\(providerID)")
        }
        persistThirdPartyBalanceBaselines()
        persistAndRestart()
        host.notifyStatusBarDisplayConfigChanged()
        host.refreshDisplayedStatusBarProviders()
    }

    func updateOpenProviderSettings(
        providerID: String,
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        balanceCredentialMode: RelayCredentialMode = .manualPreferred,
        tokenUsageEnabled: Bool,
        accountEnabled: Bool,
        authHeader: String,
        authScheme: String,
        userID: String,
        userIDHeader: String,
        endpointPath: String,
        remainingJSONPath: String,
        usedJSONPath: String,
        limitJSONPath: String,
        successJSONPath: String,
        unit: String,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil
    ) {
        let host = requireHost()
        let existingRelayConfig = host.config.providers.first(where: { $0.id == providerID })?.relayConfig
        let resolvedQuotaDisplayMode = host.config.providers.first(where: { $0.id == providerID })?.relayConfig?.quotaDisplayMode
            ?? quotaDisplayMode
            ?? .remaining
        let resolvedShowExpirationTime = existingRelayConfig?.showExpirationTimeInMenuBar ?? true
        let outcome = relayProviderSettingsCoordinator.updateOpenProviderSettings(
            draft: RelaySettingsDraft(
                providerID: providerID,
                name: name,
                baseURL: baseURL,
                preferredAdapterID: preferredAdapterID ?? "",
                balanceCredentialMode: balanceCredentialMode,
                tokenUsageEnabled: tokenUsageEnabled,
                accountEnabled: accountEnabled,
                authHeader: authHeader,
                authScheme: authScheme,
                userID: userID,
                userIDHeader: userIDHeader,
                endpointPath: endpointPath,
                remainingJSONPath: remainingJSONPath,
                usedJSONPath: usedJSONPath,
                limitJSONPath: limitJSONPath,
                successJSONPath: successJSONPath,
                unit: unit,
                quotaDisplayMode: resolvedQuotaDisplayMode,
                showExpirationTimeInMenuBar: resolvedShowExpirationTime
            ),
            providers: &host.config.providers,
            previewBuilder: relayDescriptorPreviewBuilder
        )
        applyGenericProviderSettingsMutation(outcome)
    }

    func saveRelayDraft(_ draft: RelaySettingsDraft) {
        let host = requireHost()
        let outcome = relayProviderSettingsCoordinator.updateOpenProviderSettings(
            draft: draft,
            providers: &host.config.providers,
            previewBuilder: relayDescriptorPreviewBuilder
        )
        applyGenericProviderSettingsMutation(outcome)
    }

    func relayDescriptorForPreview(
        providerID: String,
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        balanceCredentialMode: RelayCredentialMode = .manualPreferred,
        tokenUsageEnabled: Bool,
        accountEnabled: Bool,
        authHeader: String,
        authScheme: String,
        userID: String,
        userIDHeader: String,
        endpointPath: String,
        remainingJSONPath: String,
        usedJSONPath: String,
        limitJSONPath: String,
        successJSONPath: String,
        unit: String,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil
    ) -> ProviderDescriptor? {
        let host = requireHost()
        let existingRelayConfig = host.config.providers.first(where: { $0.id == providerID })?.relayConfig
        let resolvedQuotaDisplayMode = host.config.providers.first(where: { $0.id == providerID })?.relayConfig?.quotaDisplayMode
            ?? quotaDisplayMode
            ?? .remaining
        let resolvedShowExpirationTime = existingRelayConfig?.showExpirationTimeInMenuBar ?? true
        return relayDescriptorPreviewBuilder.build(
            draft: RelaySettingsDraft(
                providerID: providerID,
                name: name,
                baseURL: baseURL,
                preferredAdapterID: preferredAdapterID ?? "",
                balanceCredentialMode: balanceCredentialMode,
                tokenUsageEnabled: tokenUsageEnabled,
                accountEnabled: accountEnabled,
                authHeader: authHeader,
                authScheme: authScheme,
                userID: userID,
                userIDHeader: userIDHeader,
                endpointPath: endpointPath,
                remainingJSONPath: remainingJSONPath,
                usedJSONPath: usedJSONPath,
                limitJSONPath: limitJSONPath,
                successJSONPath: successJSONPath,
                unit: unit,
                quotaDisplayMode: resolvedQuotaDisplayMode,
                showExpirationTimeInMenuBar: resolvedShowExpirationTime
            ),
            providers: host.config.providers
        )
    }

    func relayDescriptorForPreview(draft: RelaySettingsDraft) -> ProviderDescriptor? {
        let host = requireHost()
        return relayDescriptorPreviewBuilder.build(draft: draft, providers: host.config.providers)
    }

    func testRelayDraft(_ draft: RelaySettingsDraft) async -> RelayDiagnosticResult {
        let host = requireHost()
        guard let descriptor = relayDescriptorForPreview(draft: draft) else {
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: draft.preferredAdapterID,
                resolvedAuthSource: nil,
                message: host.text(.error),
                snapshotPreview: nil
            )
        }
        return await testRelayConnection(descriptor: descriptor)
    }

    func importRelayDraftFromBrowser(_ draft: RelaySettingsDraft) async -> RelayDiagnosticResult {
        var importDraft = draft
        importDraft.balanceCredentialMode = .browserPreferred
        let host = requireHost()
        guard let descriptor = relayDescriptorForPreview(draft: importDraft) else {
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: draft.preferredAdapterID,
                resolvedAuthSource: nil,
                message: host.text(.error),
                snapshotPreview: nil
            )
        }
        return await testRelayConnection(descriptor: descriptor)
    }

    func updateThirdPartyQuotaDisplayMode(
        providerID: String,
        quotaDisplayMode: OfficialQuotaDisplayMode
    ) {
        let host = requireHost()
        let outcome = relayProviderSettingsCoordinator.updateThirdPartyQuotaDisplayMode(
            providerID: providerID,
            quotaDisplayMode: quotaDisplayMode,
            providers: &host.config.providers
        )
        applyGenericProviderSettingsMutation(outcome)
    }

    func relayAdapterName(for provider: ProviderDescriptor) -> String? {
        provider.relayManifest?.displayName
    }

    func relayAuthSource(for providerID: String) -> String? {
        let host = requireHost()
        return RelaySnapshotDisplayMetadata(snapshot: host.snapshots[providerID]).authSource
    }

    func relayFetchHealth(for providerID: String) -> FetchHealth? {
        let host = requireHost()
        return host.snapshots[providerID]?.fetchHealth
    }

    func relayValueFreshness(for providerID: String) -> ValueFreshness? {
        let host = requireHost()
        return host.snapshots[providerID]?.valueFreshness
    }

    func testRelayConnection(providerID: String) async -> RelayDiagnosticResult {
        let host = requireHost()
        guard let descriptor = descriptor(for: providerID), descriptor.isRelay else {
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: "unknown",
                resolvedAuthSource: nil,
                message: host.text(.error),
                snapshotPreview: nil
            )
        }

        return await testRelayConnection(descriptor: descriptor)
    }

    func testRelayConnection(descriptor: ProviderDescriptor) async -> RelayDiagnosticResult {
        let host = requireHost()
        let provider = host.providerFactory.makeProvider(for: descriptor)
        do {
            let snapshot = try await provider.fetch(forceRefresh: true)
            host.providerRefreshModel.mutateProviderState { state in
                state.snapshots[descriptor.id] = host.boundedSnapshot(snapshot)
                state.errors.removeValue(forKey: descriptor.id)
                state.lastUpdatedAt = Date()
            }
            host.notifyStatusBarDisplayConfigChanged()
            let relayMetadata = RelaySnapshotDisplayMetadata(
                snapshot: snapshot,
                fallbackAdapterID: descriptor.relayManifest?.id ?? descriptor.relayConfig?.adapterID
            )
            return RelayDiagnosticResult(
                success: true,
                fetchHealth: snapshot.fetchHealth,
                resolvedAdapterID: relayMetadata.resolvedAdapterID,
                resolvedAuthSource: relayMetadata.authSource,
                message: host.text(.connectionSuccess),
                snapshotPreview: RelayDiagnosticSnapshotPreview(
                    remaining: snapshot.remaining,
                    used: snapshot.used,
                    limit: snapshot.limit,
                    unit: snapshot.unit
                )
            )
        } catch {
            host.providerRefreshModel.mutateProviderState { state in
                state.errors[descriptor.id] = error.localizedDescription
            }
            let health = AppProviderRefreshCoordinator.classifyFetchHealth(error)
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: health,
                resolvedAdapterID: descriptor.relayManifest?.id ?? descriptor.relayConfig?.adapterID ?? "generic-newapi",
                resolvedAuthSource: nil,
                message: "\(host.text(.connectionFailed)): \(error.localizedDescription)",
                snapshotPreview: nil
            )
        }
    }

    // MARK: - Official provider settings

    func updateOfficialProviderSettings(
        providerID: String,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil
    ) {
        let host = requireHost()
        let outcome = officialProviderSettingsCoordinator.updateOfficialProviderSettings(
            providerID: providerID,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: traeValueDisplayMode,
            providers: &host.config.providers
        )
        guard outcome != .none else { return }
        if outcome.shouldPersistAndRestart {
            persistAndRestart()
        }
        if outcome.shouldNotifyDisplayConfigChange {
            host.notifyStatusBarDisplayConfigChanged()
        }
    }

    func saveOfficialDraft(_ draft: OfficialSettingsDraft) {
        updateOfficialProviderSettings(
            providerID: draft.providerID,
            sourceMode: draft.sourceMode,
            webMode: draft.webMode,
            quotaDisplayMode: draft.quotaDisplayMode,
            traeValueDisplayMode: draft.traeValueDisplayMode
        )
    }

    @discardableResult
    func saveOfficialCredentialAndSettings(
        providerID: String,
        credentialInput: String?,
        manualCookieInput: String?,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil
    ) -> Bool {
        let host = requireHost()
        var savedCredential = false
        if let provider = host.config.providers.first(where: { $0.id == providerID }),
           let credentialInput {
            savedCredential = saveToken(credentialInput, for: provider) || savedCredential
        }
        if let manualCookieInput {
            savedCredential = saveOfficialManualCookie(manualCookieInput, providerID: providerID) || savedCredential
        }
        updateOfficialProviderSettings(
            providerID: providerID,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: traeValueDisplayMode
        )
        return savedCredential
    }

    // MARK: - App-level config mutation

    func setLanguage(_ language: AppLanguage) {
        let host = requireHost()
        guard let outcome = configurationMutationCoordinator.setLanguage(
            language,
            config: &host.config,
            repository: host.configurationRepository,
            showFeedback: true,
            successText: host.localizedText("已保存", "Saved"),
            failureText: host.localizedText("保存失败", "Save Failed")
        ) else { return }
        applyConfigurationPersistenceOutcome(outcome)
    }

    func setResourceMode(_ resourceMode: ResourceMode) {
        let host = requireHost()
        guard let outcome = configurationMutationCoordinator.setResourceMode(
            resourceMode,
            config: &host.config,
            repository: host.configurationRepository,
            showFeedback: true,
            successText: host.localizedText("已保存", "Saved"),
            failureText: host.localizedText("保存失败", "Save Failed")
        ) else { return }
        if applyConfigurationPersistenceOutcome(outcome) {
            host.providerRefreshModel.remakeRefreshScheduler()
            host.restartPolling()
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        let host = requireHost()
        guard let outcome = configurationMutationCoordinator.setLaunchAtLoginEnabled(
            enabled,
            config: &host.config,
            setLaunchAtLogin: { try host.launchAtLoginService.setEnabled($0) },
            repository: host.configurationRepository,
            showFeedback: true,
            successText: host.localizedText("已保存", "Saved"),
            failureText: host.localizedText("保存失败", "Save Failed")
        ) else { return }
        if let persistence = outcome.persistence {
            _ = applyConfigurationPersistenceOutcome(persistence)
        }
        if let errorMessage = outcome.errorMessage {
            host.providerRefreshModel.mutateProviderState { state in
                state.errors["launch-at-login"] = errorMessage
            }
        }
    }

    func setGlobalRefreshIntervalSeconds(_ seconds: Int) {
        let host = requireHost()
        let supported = [15, 30, 60, 300]
        let normalized = supported.contains(seconds) ? seconds : 60
        guard host.config.providers.contains(where: { $0.pollIntervalSec != normalized }) else { return }

        for index in host.config.providers.indices {
            host.config.providers[index].pollIntervalSec = normalized
        }

        if persistConfiguration(showFeedback: true) {
            host.restartPolling()
        }
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
        case .amp:
            return "Amp"
        case .cursor:
            return "Cursor"
        case .jetbrains:
            return "JetBrains"
        case .kiro:
            return "Kiro"
        case .windsurf:
            return "Windsurf"
        case .kimi:
            return descriptor.family == .official ? "Kimi Coding" : "Kimi"
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
        case .grok:
            return "Grok"
        case .relay, .open, .dragon:
            return descriptor.name
        }
    }

    // MARK: - Private orchestration

    private func applyCredentialMutationOutcome(_ outcome: AppCredentialMutationOutcome) {
        guard outcome != .none else { return }
        let host = requireHost()
        if outcome.shouldBumpLookupVersion {
            host.credentialLookupVersion &+= 1
        }
    }

    private func persistAndRestart() {
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

    private func applyGenericProviderSettingsMutation(_ outcome: AppProviderSettingsMutationOutcome) {
        guard outcome != .none else { return }
        let host = requireHost()
        if outcome.shouldPersistAndRestart {
            persistAndRestart()
        }
        if outcome.shouldNotifyDisplayConfigChange {
            host.notifyStatusBarDisplayConfigChanged()
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

    private func persistThirdPartyBalanceBaselines() {
        let host = requireHost()
        host.thirdPartyBalanceBaselineStore.save(host.thirdPartyBalanceBaselineTracker.snapshotEntries())
    }

    private func normalizedCredential(_ token: String, kind: AuthKind) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .bearer:
            return TraeProvider.normalizeToken(trimmed)
        case .none, .localCodex:
            return trimmed
        }
    }

    func requireHost() -> AppViewModel {
        guard let host else {
            preconditionFailure("AppConfigurationModel.bind must be called before use")
        }
        return host
    }
}
