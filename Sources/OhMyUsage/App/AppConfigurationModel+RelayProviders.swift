// Relay / 开放站点的配置事务：站点草稿的新建与真链路测试、Provider 删除、
// 草稿保存/预览、连接诊断与 relay 展示元数据查询。

import OhMyUsageProviders
import Foundation
import OhMyUsageApplication
import OhMyUsageDomain

@MainActor
extension AppConfigurationModel {
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
        guard let provider = buildRelaySiteDescriptor(
            name: name,
            baseURL: baseURL,
            preferredAdapterID: preferredAdapterID,
            userID: userID,
            balanceCredentialMode: balanceCredentialMode,
            existingProviders: host.config.providers
        ) else { return nil }

        host.config.providers.append(provider)
        if host.config.statusBarProviderID == nil {
            host.config.statusBarProviderID = provider.id
        }

        stageRelayCredentialIfNeeded(credentialInput, descriptor: provider)

        persistAndRestart()
        host.notifyStatusBarDisplayConfigChanged()
        host.refreshDisplayedStatusBarProviders()
        return provider
    }

    /// 新站点草稿面板的真链路测试：用草稿输入构建临时 descriptor，把凭证预写入
    /// 与正式保存一致的 keychain 槽位（relay 的 keychain account 由站点 host 派生，
    /// 与后续 addRelaySiteDraft 写入同一个键），再走真实 fetch。
    /// 临时 descriptor 不进入 providers 列表，测试后清理其运行时快照。
    func testNewRelaySiteDraft(
        name: String,
        baseURL: String,
        preferredAdapterID: String? = nil,
        userID: String,
        credentialInput: String? = nil
    ) async -> RelayDiagnosticResult {
        let host = requireHost()
        guard let descriptor = buildRelaySiteDescriptor(
            name: name,
            baseURL: baseURL,
            preferredAdapterID: preferredAdapterID,
            userID: userID,
            balanceCredentialMode: .browserPreferred,
            existingProviders: host.config.providers
        ) else {
            return RelayDiagnosticResult(
                success: false,
                fetchHealth: .endpointMisconfigured,
                resolvedAdapterID: preferredAdapterID ?? "generic-newapi",
                resolvedAuthSource: nil,
                message: host.text(.error),
                snapshotPreview: nil
            )
        }

        stageRelayCredentialIfNeeded(credentialInput, descriptor: descriptor)

        let result = await testRelayConnection(descriptor: descriptor)
        host.providerRefreshModel.mutateProviderState { state in
            state.snapshots.removeValue(forKey: descriptor.id)
            state.errors.removeValue(forKey: descriptor.id)
        }
        return result
    }

    private func buildRelaySiteDescriptor(
        name: String,
        baseURL: String,
        preferredAdapterID: String?,
        userID: String,
        balanceCredentialMode: RelayCredentialMode,
        existingProviders: [ProviderDescriptor]
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

        return relayDescriptorPreviewBuilder.build(
            draft: draft,
            providers: existingProviders + [baseProvider]
        ) ?? baseProvider
    }

    private func stageRelayCredentialIfNeeded(_ credentialInput: String?, descriptor: ProviderDescriptor) {
        guard let credentialInput else { return }
        let trimmedCredential = credentialInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCredential.isEmpty, let balanceAuth = descriptor.relayConfig?.balanceAuth else { return }
        saveCredential(trimmedCredential, field: .authToken(balanceAuth), restartPolicy: .none)
    }

    func removeProvider(providerID: String) {
        let host = requireHost()
        host.providerRefreshModel.invalidateRefreshes(providerID: providerID)
        host.removeLocalUsageHistoryEntries(providerID: providerID)
        host.removeUsageAnalyticsEntries(providerID: providerID)
        OfficialProviderFetchRuntime.invalidateCaches()
        host.persistedSnapshotCache?.remove(providerID: providerID)
        host.config.providers.removeAll { $0.id == providerID }
        if host.config.statusBarProviderID == providerID {
            host.config.statusBarProviderID = AppConfig.defaultStatusBarProviderID(from: host.config.providers)
        }
        host.providerRefreshModel.mutateProviderState { state in
            state.thirdPartyBalanceBaselineTracker.remove(providerID: providerID)
            state.snapshots.removeValue(forKey: providerID)
            state.errors.removeValue(forKey: providerID)
            state.consecutiveFailures.removeValue(forKey: providerID)
            state.retryNotBefore.removeValue(forKey: providerID)
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

    // MARK: - Private orchestration

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
}
