import Foundation
import OhMyUsageApplication
import OhMyUsageDomain

@MainActor
extension AppViewModel {
    func setEnabled(_ enabled: Bool, providerID: String) {
        let outcome = providerListMutationCoordinator.setEnabled(
            enabled,
            providerID: providerID,
            config: &config
        )
        applyProviderListMutation(outcome)
    }

    func reorderEnabledProviders(
        family: ProviderFamily,
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        let outcome = providerListMutationCoordinator.reorderEnabledProviders(
            family: family,
            fromOffsets: fromOffsets,
            toOffset: toOffset,
            config: &config
        )
        applyProviderListMutation(outcome)
    }

    func setLowThreshold(_ value: Double, providerID: String) {
        commitProviderThreshold(value, providerID: providerID)
    }

    func commitProviderThreshold(_ value: Double, providerID: String) {
        let outcome = providerListMutationCoordinator.commitThreshold(
            value,
            providerID: providerID,
            config: &config
        )
        applyProviderListMutation(outcome)
    }

    func hasToken(for descriptor: ProviderDescriptor) -> Bool {
        credentialLookupCoordinator.credentialExists(
            for: descriptor,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func savedTokenLength(for descriptor: ProviderDescriptor) -> Int? {
        credentialLookupCoordinator.savedCredentialLength(
            for: descriptor,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func hasToken(auth: AuthConfig) -> Bool {
        credentialLookupCoordinator.credentialExists(
            auth: auth,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func savedTokenLength(auth: AuthConfig) -> Int? {
        credentialLookupCoordinator.savedCredentialLength(
            auth: auth,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func saveToken(_ token: String, for descriptor: ProviderDescriptor) -> Bool {
        let outcome = providerCredentialCoordinator.saveToken(
            token,
            descriptor: descriptor,
            normalize: { token, kind in
                self.normalizedCredential(token, kind: kind)
            },
            saveCredential: { value, service, account in
                credentialAccessService.saveCredential(value, service: service, account: account)
            }
        )
        applyCredentialMutationOutcome(outcome)
        return outcome.didPersistCredential
    }

    @discardableResult
    func saveTokenAndRestart(_ token: String, for descriptor: ProviderDescriptor) -> Bool {
        let ok = saveToken(token, for: descriptor)
        if ok {
            restartPolling()
        }
        return ok
    }

    func saveToken(_ token: String, auth: AuthConfig) -> Bool {
        let outcome = providerCredentialCoordinator.saveToken(
            token,
            auth: auth,
            normalize: { token, kind in
                self.normalizedCredential(token, kind: kind)
            },
            saveCredential: { value, service, account in
                credentialAccessService.saveCredential(value, service: service, account: account)
            }
        )
        applyCredentialMutationOutcome(outcome)
        return outcome.didPersistCredential
    }

    @discardableResult
    func saveTokenAndRestart(_ token: String, auth: AuthConfig) -> Bool {
        let ok = saveToken(token, auth: auth)
        if ok {
            restartPolling()
        }
        return ok
    }

    func hasOfficialManualCookie(for provider: ProviderDescriptor) -> Bool {
        credentialLookupCoordinator.manualCookieExists(
            for: provider,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func savedOfficialManualCookieLength(for provider: ProviderDescriptor) -> Int? {
        credentialLookupCoordinator.savedManualCookieLength(
            for: provider,
            secureStorageReady: secureStorageReady,
            lookupVersion: credentialLookupVersion,
            credentialAccessService: credentialAccessService
        ) { [weak self] in
            self?.credentialLookupVersion &+= 1
        }
    }

    func saveOfficialManualCookie(_ value: String, providerID: String) -> Bool {
        let outcome = providerCredentialCoordinator.saveOfficialManualCookie(
            value,
            providerID: providerID,
            providers: config.providers,
            saveCredential: { value, service, account in
                credentialAccessService.saveCredential(value, service: service, account: account)
            }
        )
        applyCredentialMutationOutcome(outcome)
        return outcome.didPersistCredential
    }

    @discardableResult
    func saveOfficialManualCookieAndRestart(_ value: String, providerID: String) -> Bool {
        let ok = saveOfficialManualCookie(value, providerID: providerID)
        if ok {
            restartPolling()
        }
        return ok
    }

    func invalidateCredentialLookupCache() {
        applyCredentialMutationOutcome(
            providerCredentialCoordinator.invalidateLookupCache {
                credentialAccessService.invalidateLookupCache()
            }
        )
    }

    @discardableResult
    func addRelaySiteDraft(
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        userID: String,
        credentialInput: String? = nil,
        balanceCredentialMode: RelayCredentialMode = .browserPreferred
    ) -> ProviderDescriptor? {
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
            providers: config.providers + [baseProvider]
        ) ?? baseProvider

        config.providers.append(provider)
        if config.statusBarProviderID == nil {
            config.statusBarProviderID = provider.id
        }

        if let credentialInput {
            let trimmedCredential = credentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCredential.isEmpty, let balanceAuth = provider.relayConfig?.balanceAuth {
                _ = saveToken(trimmedCredential, auth: balanceAuth)
            }
        }

        persistAndRestart()
        notifyStatusBarDisplayConfigChanged()
        refreshDisplayedStatusBarProviders()
        return provider
    }

    func addOpenRelay(name: String, baseURL: String, preferredAdapterID: String? = nil) {
        let provider = ProviderDescriptor.makeOpenRelay(
            name: name,
            baseURL: baseURL,
            preferredAdapterID: preferredAdapterID
        )
        config.providers.append(provider)
        if config.statusBarProviderID == nil {
            config.statusBarProviderID = provider.id
        }
        persistAndRestart()
        notifyStatusBarDisplayConfigChanged()
        refreshDisplayedStatusBarProviders()
    }

    func removeProvider(providerID: String) {
        config.providers.removeAll { $0.id == providerID }
        if config.statusBarProviderID == providerID {
            config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: config.providers)
        }
        thirdPartyBalanceBaselineTracker.remove(providerID: providerID)
        persistThirdPartyBalanceBaselines()
        snapshots.removeValue(forKey: providerID)
        errors.removeValue(forKey: providerID)
        consecutiveFailures.removeValue(forKey: providerID)
        activeAlerts.remove("low:\(providerID)")
        activeAlerts.remove("fail:\(providerID)")
        activeAlerts.remove("auth:\(providerID)")
        persistAndRestart()
        notifyStatusBarDisplayConfigChanged()
        refreshDisplayedStatusBarProviders()
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
        let existingRelayConfig = config.providers.first(where: { $0.id == providerID })?.relayConfig
        let resolvedQuotaDisplayMode = config.providers.first(where: { $0.id == providerID })?.relayConfig?.quotaDisplayMode
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
            providers: &config.providers,
            previewBuilder: relayDescriptorPreviewBuilder
        )
        applyGenericProviderSettingsMutation(outcome)
    }

    func saveRelayDraft(_ draft: RelaySettingsDraft) {
        let outcome = relayProviderSettingsCoordinator.updateOpenProviderSettings(
            draft: draft,
            providers: &config.providers,
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
        let existingRelayConfig = config.providers.first(where: { $0.id == providerID })?.relayConfig
        let resolvedQuotaDisplayMode = config.providers.first(where: { $0.id == providerID })?.relayConfig?.quotaDisplayMode
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
            providers: config.providers
        )
    }

    func relayDescriptorForPreview(draft: RelaySettingsDraft) -> ProviderDescriptor? {
        relayDescriptorPreviewBuilder.build(draft: draft, providers: config.providers)
    }

    func testRelayDraft(_ draft: RelaySettingsDraft) async -> RelayDiagnosticResult {
        guard let descriptor = relayDescriptorForPreview(draft: draft) else {
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: draft.preferredAdapterID,
                resolvedAuthSource: nil,
                message: text(.error),
                snapshotPreview: nil
            )
        }
        return await testRelayConnection(descriptor: descriptor)
    }

    func importRelayDraftFromBrowser(_ draft: RelaySettingsDraft) async -> RelayDiagnosticResult {
        var importDraft = draft
        importDraft.balanceCredentialMode = .browserPreferred
        guard let descriptor = relayDescriptorForPreview(draft: importDraft) else {
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: draft.preferredAdapterID,
                resolvedAuthSource: nil,
                message: text(.error),
                snapshotPreview: nil
            )
        }
        return await testRelayConnection(descriptor: descriptor)
    }

    func updateThirdPartyQuotaDisplayMode(
        providerID: String,
        quotaDisplayMode: OfficialQuotaDisplayMode
    ) {
        let outcome = relayProviderSettingsCoordinator.updateThirdPartyQuotaDisplayMode(
            providerID: providerID,
            quotaDisplayMode: quotaDisplayMode,
            providers: &config.providers
        )
        applyGenericProviderSettingsMutation(outcome)
    }

    func relayAdapterName(for provider: ProviderDescriptor) -> String? {
        provider.relayManifest?.displayName
    }

    func relayAuthSource(for providerID: String) -> String? {
        RelaySnapshotDisplayMetadata(snapshot: snapshots[providerID]).authSource
    }

    func relayFetchHealth(for providerID: String) -> FetchHealth? {
        snapshots[providerID]?.fetchHealth
    }

    func relayValueFreshness(for providerID: String) -> ValueFreshness? {
        snapshots[providerID]?.valueFreshness
    }

    func testRelayConnection(providerID: String) async -> RelayDiagnosticResult {
        guard let descriptor = descriptor(for: providerID), descriptor.isRelay else {
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: "unknown",
                resolvedAuthSource: nil,
                message: text(.error),
                snapshotPreview: nil
            )
        }

        return await testRelayConnection(descriptor: descriptor)
    }

    func testRelayConnection(descriptor: ProviderDescriptor) async -> RelayDiagnosticResult {
        let provider = providerFactory.makeProvider(for: descriptor)
        do {
            let snapshot = try await provider.fetch(forceRefresh: true)
            snapshots[descriptor.id] = boundedSnapshot(snapshot)
            errors.removeValue(forKey: descriptor.id)
            lastUpdatedAt = Date()
            notifyStatusBarDisplayConfigChanged()
            let relayMetadata = RelaySnapshotDisplayMetadata(
                snapshot: snapshot,
                fallbackAdapterID: descriptor.relayManifest?.id ?? descriptor.relayConfig?.adapterID
            )
            return RelayDiagnosticResult(
                success: true,
                fetchHealth: snapshot.fetchHealth,
                resolvedAdapterID: relayMetadata.resolvedAdapterID,
                resolvedAuthSource: relayMetadata.authSource,
                message: text(.connectionSuccess),
                snapshotPreview: RelayDiagnosticSnapshotPreview(
                    remaining: snapshot.remaining,
                    used: snapshot.used,
                    limit: snapshot.limit,
                    unit: snapshot.unit
                )
            )
        } catch {
            errors[descriptor.id] = error.localizedDescription
            let health = classifyFetchHealth(error)
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: health,
                resolvedAdapterID: descriptor.relayManifest?.id ?? descriptor.relayConfig?.adapterID ?? "generic-newapi",
                resolvedAuthSource: nil,
                message: "\(text(.connectionFailed)): \(error.localizedDescription)",
                snapshotPreview: nil
            )
        }
    }

    func updateOfficialProviderSettings(
        providerID: String,
        sourceMode: OfficialSourceMode,
        webMode: OfficialWebMode,
        quotaDisplayMode: OfficialQuotaDisplayMode? = nil,
        traeValueDisplayMode: OfficialTraeValueDisplayMode? = nil
    ) {
        let outcome = officialProviderSettingsCoordinator.updateOfficialProviderSettings(
            providerID: providerID,
            sourceMode: sourceMode,
            webMode: webMode,
            quotaDisplayMode: quotaDisplayMode,
            traeValueDisplayMode: traeValueDisplayMode,
            providers: &config.providers
        )
        guard outcome != .none else { return }
        if outcome.shouldPersistAndRestart {
            persistAndRestart()
        }
        if outcome.shouldNotifyDisplayConfigChange {
            notifyStatusBarDisplayConfigChanged()
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
        var savedCredential = false
        if let provider = config.providers.first(where: { $0.id == providerID }),
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

    @discardableResult
    func persistConfiguration(
        showFeedback: Bool = false,
        successText: String? = nil
    ) -> Bool {
        applyConfigurationPersistenceOutcome(
            configurationMutationCoordinator.persistConfiguration(
                config,
                repository: configurationRepository,
                showFeedback: showFeedback,
                successText: successText ?? localizedText("已保存", "Saved"),
                failureText: localizedText("保存失败", "Save Failed")
            )
        )
    }

    @discardableResult
    func resetConfiguration(showFeedback: Bool = false) -> Bool {
        applyConfigurationPersistenceOutcome(
            configurationMutationCoordinator.resetConfiguration(
                repository: configurationRepository,
                showFeedback: showFeedback,
                successText: localizedText("已重置", "Reset Complete"),
                failureText: localizedText("重置失败", "Reset Failed")
            )
        )
    }

    @discardableResult
    func applyConfigurationPersistenceOutcome(
        _ outcome: AppConfigurationPersistenceOutcome
    ) -> Bool {
        settingsPersistenceFeedbackCoordinator.apply(outcome) { [weak self] state, errorMessage in
            self?.settingsPersistenceStatus = state
            self?.settingsPersistenceErrorMessage = errorMessage
        }
    }

    func pruneThirdPartyBalanceBaselines() {
        let previousEntries = thirdPartyBalanceBaselineTracker.snapshotEntries()
        let validProviderIDs = Set(
            config.providers
                .filter { $0.family == .thirdParty }
                .map(\.id)
        )
        thirdPartyBalanceBaselineTracker.prune(
            keepingProviderIDs: validProviderIDs,
            maxEntries: RuntimeDiagnosticsLimits.thirdPartyBalanceBaselineCacheMaxEntries
        )
        persistThirdPartyBalanceBaselinesIfChanged(previousEntries: previousEntries)
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
        case .relay, .open, .dragon:
            return descriptor.name
        }
    }

    func descriptor(for id: String) -> ProviderDescriptor? {
        config.providers.first(where: { $0.id == id })
    }
}

private extension AppViewModel {
    func applyCredentialMutationOutcome(_ outcome: AppCredentialMutationOutcome) {
        guard outcome != .none else { return }
        if outcome.shouldBumpLookupVersion {
            credentialLookupVersion &+= 1
        }
    }

    func persistAndRestart() {
        normalizeStatusBarSelections()
        pruneThirdPartyBalanceBaselines()
        _ = persistConfiguration(showFeedback: true)
        restartPolling()
        syncClaudeProfilesCurrentState()
        officialProfileLifecycleCoordinator.scheduleClaudePrefetchIfNeeded(
            descriptor: claudeOfficialProviderDescriptor(),
            profiles: claudeDisplayableProfiles(),
            slots: claudeSlots,
            runtime: claudeOfficialProfileRefreshRuntime
        ) { [weak self] profile, descriptor in
            guard let self else { return .skipped }
            return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
        }
    }

    func applyProviderListMutation(_ outcome: AppProviderListMutationOutcome) {
        guard outcome != .none else { return }
        if !outcome.removedThirdPartyBaselineProviderIDs.isEmpty {
            for providerID in outcome.removedThirdPartyBaselineProviderIDs {
                thirdPartyBalanceBaselineTracker.remove(providerID: providerID)
            }
            persistThirdPartyBalanceBaselines()
        }
        if outcome.shouldPersistAndRestart {
            persistAndRestart()
        }
        if outcome.shouldNotifyDisplayConfigChange {
            notifyStatusBarDisplayConfigChanged()
        }
        if outcome.shouldRefreshDisplayedProviders {
            refreshDisplayedStatusBarProviders()
        }
    }

    func applyGenericProviderSettingsMutation(_ outcome: AppProviderSettingsMutationOutcome) {
        guard outcome != .none else { return }
        if outcome.shouldPersistAndRestart {
            persistAndRestart()
        }
        if outcome.shouldNotifyDisplayConfigChange {
            notifyStatusBarDisplayConfigChanged()
        }
    }

    func persistThirdPartyBalanceBaselinesIfChanged(
        previousEntries: [String: ThirdPartyBalanceBaselineTracker.Entry]
    ) {
        let latestEntries = thirdPartyBalanceBaselineTracker.snapshotEntries()
        guard latestEntries != previousEntries else { return }
        thirdPartyBalanceBaselineStore.save(latestEntries)
    }

    func persistThirdPartyBalanceBaselines() {
        thirdPartyBalanceBaselineStore.save(thirdPartyBalanceBaselineTracker.snapshotEntries())
    }

    func normalizedCredential(_ token: String, kind: AuthKind) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .bearer:
            return TraeProvider.normalizeToken(trimmed)
        case .none, .localCodex:
            return trimmed
        }
    }

    func classifyFetchHealth(_ error: Error) -> FetchHealth {
        AppProviderRefreshCoordinator.classifyFetchHealth(error)
    }

    func normalizeBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return "https://open.ailinyu.de"
        }
        if !value.contains("://") {
            value = "https://" + value
        }
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    func nonEmptyOrDefault(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
