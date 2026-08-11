import Foundation
import OhMyUsageDomain

@MainActor
extension AppViewModel {
    func codexSlotViewModels() -> [CodexSlotViewModel] {
        codexSlotViewModels(refreshFromStore: true, triggerPrefetch: true)
    }

    func codexSlotViewModelsForSettings() -> [CodexSlotViewModel] {
        codexSlotViewModels(refreshFromStore: false, triggerPrefetch: false)
    }

    func codexProfilesForSettings() -> [CodexAccountProfile] {
        codexProfiles.sorted { $0.slotID < $1.slotID }
    }

    func nextCodexProfileSlotID() -> CodexSlotID {
        codexProfileStore.nextAvailableSlotID()
    }

    func codexSettingsTitle(for slotID: CodexSlotID) -> String {
        "Codex \(slotID.rawValue)"
    }

    func oauthImportState(for providerType: ProviderType) -> OAuthImportState? {
        switch providerType {
        case .codex:
            return codexOAuthImportState
        case .claude:
            return claudeOAuthImportState
        default:
            return nil
        }
    }

    func claudeOAuthImportEnabled() -> Bool {
        true
    }

    func setClaudeOAuthImportEnabled(_ enabled: Bool) {
        _ = enabled
    }

    func startOAuthImport(providerType: ProviderType, slotID: CodexSlotID) {
        switch providerType {
        case .codex:
            if let task = officialAccountImportCoordinator.startCodexImport(
                slotID: slotID,
                currentTask: codexOAuthImportTask,
                currentState: { self.codexOAuthImportState },
                importAccount: { [oauthImportOrchestrator] provider, slotID, stateHandler in
                    await oauthImportOrchestrator.importAccount(
                        provider: provider,
                        slotID: slotID,
                        stateHandler: stateHandler
                    )
                },
                matchingProfile: { rawCredentialJSON in
                    self.codexProfileStore.matchingProfile(authJSON: rawCredentialJSON)
                },
                saveImportedProfile: { imported, originalSlotID, existing in
                    let resolvedSlotID = existing?.slotID ?? originalSlotID
                    let resolvedDisplayName = existing?.displayName ?? "Codex \(resolvedSlotID.rawValue)"
                    let detail = self.saveCodexProfile(
                        slotID: resolvedSlotID,
                        displayName: resolvedDisplayName,
                        note: existing?.note,
                        authJSON: imported.rawCredentialJSON
                    )
                    return OAuthImportSaveOutcome(slotID: resolvedSlotID, detail: detail)
                },
                setState: { self.codexOAuthImportState = $0 },
                clearTask: { self.codexOAuthImportTask = nil }
            ) {
                codexOAuthImportTask = task
            }
        case .claude:
            if let task = officialAccountImportCoordinator.startClaudeImport(
                slotID: slotID,
                currentTask: claudeOAuthImportTask,
                currentState: { self.claudeOAuthImportState },
                importAccount: { [oauthImportOrchestrator] provider, slotID, stateHandler in
                    await oauthImportOrchestrator.importAccount(
                        provider: provider,
                        slotID: slotID,
                        stateHandler: stateHandler
                    )
                },
                matchingProfile: { rawCredentialJSON in
                    self.claudeProfileStore.matchingProfile(credentialsJSON: rawCredentialJSON)
                },
                saveImportedProfile: { imported, originalSlotID, existing in
                    let resolvedSlotID = existing?.slotID ?? originalSlotID
                    let resolvedDisplayName = existing?.displayName ?? "Claude \(resolvedSlotID.rawValue)"
                    let detail = self.saveClaudeProfile(
                        slotID: resolvedSlotID,
                        displayName: resolvedDisplayName,
                        note: existing?.note,
                        source: .manualCredentials,
                        configDir: existing?.configDir,
                        credentialsJSON: imported.rawCredentialJSON
                    )
                    return OAuthImportSaveOutcome(slotID: resolvedSlotID, detail: detail)
                },
                setState: { self.claudeOAuthImportState = $0 },
                clearTask: { self.claudeOAuthImportTask = nil }
            ) {
                claudeOAuthImportTask = task
            }
        default:
            return
        }
    }

    func cancelOAuthImport(providerType: ProviderType) {
        switch providerType {
        case .codex:
            Task { await oauthImportOrchestrator.cancelImport(provider: .codex) }
        case .claude:
            Task { await oauthImportOrchestrator.cancelImport(provider: .claude) }
        default:
            break
        }
    }

    func saveCodexProfile(slotID: CodexSlotID, displayName: String, note: String?, authJSON: String) -> String {
        do {
            _ = try codexProfileStore.saveProfile(
                slotID: slotID,
                displayName: displayName,
                note: note,
                authJSON: authJSON,
                currentFingerprint: codexDesktopAuthService.currentCredentialFingerprint()
            )
            syncCodexProfilesCurrentState()
            activateOfficialProviderAfterProfileSave(type: .codex)
            return text(.codexProfileImported)
        } catch {
            return "\(text(.codexProfileImportFailed)): \(error.localizedDescription)"
        }
    }

    func removeCodexProfile(slotID: CodexSlotID) {
        syncCodexProfilesCurrentState()
        codexProfiles = codexProfileStore.removeProfile(slotID: slotID)
        codexSlots = codexSlotStore.remove(slotID: slotID)
        codexOfficialProfileRefreshRuntime.remove(slotID: slotID)
        setCodexSwitchFeedback(nil, for: slotID)
    }

    func claudeSlotViewModels() -> [ClaudeSlotViewModel] {
        claudeSlotViewModels(refreshFromStore: true, triggerPrefetch: true)
    }

    func claudeSlotViewModelsForSettings() -> [ClaudeSlotViewModel] {
        claudeSlotViewModels(refreshFromStore: false, triggerPrefetch: false)
    }

    func claudeProfilesForSettings() -> [ClaudeAccountProfile] {
        claudeDisplayableProfiles()
    }

    func refreshSettingsProfileState() {
        syncCodexProfilesCurrentState()
        syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
    }

    func nextClaudeProfileSlotID() -> CodexSlotID {
        claudeProfileStore.nextAvailableSlotID()
    }

    func claudeSettingsTitle(for slotID: CodexSlotID) -> String {
        "Claude \(slotID.rawValue)"
    }

    func saveClaudeProfile(
        slotID: CodexSlotID,
        displayName: String,
        note: String?,
        source: ClaudeProfileSource,
        configDir: String?,
        credentialsJSON: String?
    ) -> String {
        do {
            if try claudeProfileStore.updateProfileMetadataIfCredentialInputsUnchanged(
                slotID: slotID,
                displayName: displayName,
                note: note,
                source: source,
                configDir: configDir,
                credentialsJSON: credentialsJSON
            ) != nil {
                syncClaudeProfilesCurrentState()
                return localizedText("Claude 账号备注已更新", "Claude profile note updated")
            }

            _ = try claudeProfileStore.saveProfile(
                slotID: slotID,
                displayName: displayName,
                note: note,
                source: source,
                configDir: configDir,
                credentialsJSON: credentialsJSON,
                currentFingerprint: claudeDesktopAuthService.currentCredentialFingerprint()
            )
            syncClaudeProfilesCurrentState()
            return localizedText("Claude 账号档案已导入", "Claude profile imported")
        } catch {
            return "\(localizedText("导入失败", "Import failed")): \(error.localizedDescription)"
        }
    }

    func removeClaudeProfile(slotID: CodexSlotID) {
        let previousConfiguredDisplaySlotID = config.claudeStatusBarDisplaySlotID
        let previousResolvedDisplaySlotID = resolvedClaudeStatusBarDisplaySlotID()
        syncClaudeProfilesCurrentState()
        claudeProfiles = claudeProfileStore.removeProfile(slotID: slotID)
        claudeSlots = claudeSlotStore.remove(slotID: slotID)
        claudeOfficialProfileRefreshRuntime.remove(slotID: slotID)
        setClaudeSwitchFeedback(nil, for: slotID)
        normalizeStatusBarSelections()
        if config.claudeStatusBarDisplaySlotID != previousConfiguredDisplaySlotID {
            _ = persistConfiguration(showFeedback: false)
        }
        let resolvedDisplaySlotID = resolvedClaudeStatusBarDisplaySlotID()
        if resolvedDisplaySlotID != previousResolvedDisplaySlotID {
            triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: resolvedDisplaySlotID)
            notifyStatusBarDisplayConfigChanged()
        }
    }

    func switchCodexProfile(slotID: CodexSlotID) async {
        syncCodexProfilesCurrentState()
        await officialAccountSwitchCoordinator.switchCodexProfile(
            slotID: slotID,
            transactionCoordinator: codexSwitchCoordinator,
            prepare: { [self] in
                guard let profile = self.codexProfiles.first(where: { $0.slotID == slotID }) else {
                    throw AccountSwitchTransactionUserMessageError(message: self.text(.codexProfileMissing))
                }
                return profile
            },
            apply: { [self] profile in
                let refreshedProfile = try await self.refreshCodexProfileAuthBeforeDesktopApply(profile)
                try self.codexDesktopAuthService.applyProfile(refreshedProfile)
            },
            restart: { [self] _ in
                await self.codexDesktopAppService.restartIfRunning()
            },
            verify: { [self] _ in
                self.syncCodexProfilesCurrentState()
                guard let descriptor = self.config.providers.first(where: { $0.type == .codex && $0.family == .official }) else {
                    return .none
                }
                let provider = self.providerFactory.makeProvider(for: descriptor)
                let fetched = try await provider.fetch(forceRefresh: true)
                if let currentAuthJSON = self.codexDesktopAuthService.currentAuthJSON() {
                    _ = self.codexProfileStore.updateStoredAuthJSON(
                        slotID: slotID,
                        authJSON: currentAuthJSON
                    )
                    self.syncCodexProfilesCurrentState()
                }
                let snapshot = self.markCodexSnapshotActive(fetched, preferredSlotID: slotID)
                return OfficialAccountSwitchVerificationResult(
                    descriptor: descriptor,
                    snapshot: snapshot
                )
            },
            commitVerifiedState: { [self] descriptor, snapshot in
                self.codexSlots = self.codexSlotStore.upsertActive(snapshot: snapshot)
                self.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                self.errors.removeValue(forKey: descriptor.id)
                self.consecutiveFailures[descriptor.id] = 0
                self.lastUpdatedAt = Date()
                self.notifyStatusBarDisplayConfigChanged()
            },
            successMessage: { restartResult in
                self.codexSwitchMessage(
                    for: restartResult,
                    successKey: .codexSwitchSuccess
                )
            },
            setFeedback: { feedback, slotID in
                self.setCodexSwitchFeedback(feedback, for: slotID)
            },
            recordVerifyError: { descriptor, message in
                self.errors[descriptor.id] = message
            },
            notify: { message in
                self.notifications.notify(
                    title: "Codex",
                    body: message,
                    identifier: "codex-switch-\(slotID.rawValue.lowercased())"
                )
            },
            applyFailureMessage: { error in
                "\(self.text(.codexSwitchFailed)): \(error.localizedDescription)"
            },
            verifyFailureMessage: { error in
                "\(self.text(.codexSwitchNeedsVerification)): \(error.localizedDescription)"
            }
        )
    }

    private func refreshCodexProfileAuthBeforeDesktopApply(
        _ profile: CodexAccountProfile
    ) async throws -> CodexAccountProfile {
        guard let descriptor = config.providers.first(where: { $0.type == .codex && $0.family == .official }) else {
            return profile
        }

        do {
            let result = try await codexProfileSnapshotService.fetchSnapshot(
                profile: profile,
                descriptor: descriptor
            )
            guard let refreshedAuthJSON = result.refreshedAuthJSON,
                  !refreshedAuthJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let updated = codexProfileStore.updateStoredAuthJSON(
                    slotID: profile.slotID,
                    authJSON: refreshedAuthJSON
                  ) else {
                return profile
            }
            syncCodexProfilesCurrentState()
            return updated
        } catch {
            return profile
        }
    }

    func switchClaudeProfile(slotID: CodexSlotID) async {
        syncClaudeProfilesCurrentState()
        await officialAccountSwitchCoordinator.switchClaudeProfile(
            slotID: slotID,
            transactionCoordinator: claudeSwitchCoordinator,
            prepare: { [self] in
                guard let profile = self.claudeProfiles.first(where: { $0.slotID == slotID }) else {
                    throw AccountSwitchTransactionUserMessageError(
                        message: self.localizedText("该槽位还没有导入可切换的 Claude 账号", "No imported Claude profile is available for this slot")
                    )
                }
                return profile
            },
            apply: { [self] profile in
                let credentialsJSON = try self.claudeProfileStore.resolvedCredentialsJSON(for: profile)
                try self.claudeDesktopAuthService.applyCredentialsJSON(credentialsJSON)
            },
            restart: { _ in () },
            verify: { [self] _ in
                self.syncClaudeProfilesCurrentState()
                guard let descriptor = self.config.providers.first(where: { $0.type == .claude && $0.family == .official }) else {
                    return .none
                }
                let provider = self.providerFactory.makeProvider(for: descriptor)
                let fetched = try await provider.fetch(forceRefresh: true)
                let snapshot = self.markClaudeSnapshotActive(fetched, preferredSlotID: slotID)
                return OfficialAccountSwitchVerificationResult(
                    descriptor: descriptor,
                    snapshot: snapshot
                )
            },
            commitVerifiedState: { [self] descriptor, snapshot in
                self.claudeSlots = self.claudeSlotStore.upsertActive(snapshot: snapshot)
                self.snapshots[descriptor.id] = self.boundedSnapshot(snapshot)
                self.errors.removeValue(forKey: descriptor.id)
                self.consecutiveFailures[descriptor.id] = 0
                self.lastUpdatedAt = Date()
                self.notifyStatusBarDisplayConfigChanged()
            },
            verifiedSuccessMessage: self.localizedText("已切换 Claude 账号", "Claude account switched"),
            localSuccessMessage: self.localizedText("已写入本机 Claude 登录", "Local Claude credentials updated"),
            setFeedback: { feedback, slotID in
                self.setClaudeSwitchFeedback(feedback, for: slotID)
            },
            recordVerifyError: { descriptor, message in
                self.errors[descriptor.id] = message
            },
            notify: { message in
                self.notifications.notify(
                    title: "Claude",
                    body: message,
                    identifier: "claude-switch-\(slotID.rawValue.lowercased())"
                )
            },
            applyFailureMessage: { error in
                "\(self.localizedText("切换失败", "Switch failed")): \(error.localizedDescription)"
            },
            verifyFailureMessage: { error in
                "\(self.localizedText("已切换到该账号，但需要重新验证", "Switched to this account, but re-verification is required")): \(error.localizedDescription)"
            }
        )
    }

    func boundedSnapshot(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        var copy = snapshot
        copy.note = RuntimeBoundedState.boundedSnapshotNote(copy.note)
        return copy
    }

    func markCodexSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true
    ) -> UsageSnapshot {
        AppOfficialProfileStateCoordinator.markCodexSnapshotActive(
            snapshot,
            preferredSlotID: preferredSlotID,
            isActive: isActive,
            profiles: codexProfiles
        )
    }

    func syncCodexProfilesCurrentState() {
        let result = officialProfileSyncCoordinator.syncCodexProfiles(
            profileStore: codexProfileStore,
            desktopAuthService: codexDesktopAuthService
        )
        if result.profiles != codexProfiles {
            codexProfiles = result.profiles
        }
        codexOfficialProfileRefreshRuntime.pruneRetryState(keeping: result.visibleSlotIDs)
    }

    func refreshOfficialInactiveProfileCardInBackgroundIfNeeded(for descriptor: ProviderDescriptor) async {
        await officialProfileLifecycleCoordinator.refreshInactiveProfilesInBackgroundIfNeeded(
            descriptor: descriptor,
            codexSlots: codexSlots,
            claudeSlots: claudeSlots,
            codexRuntime: codexOfficialProfileRefreshRuntime,
            claudeRuntime: claudeOfficialProfileRefreshRuntime,
            syncCodexProfiles: {
                self.syncCodexProfilesCurrentState()
                return self.codexProfiles
            },
            syncClaudeProfiles: {
                self.syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
                return self.claudeProfiles
            },
            refreshCodexProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshCodexProfileSnapshotSlot(profile, descriptor: descriptor)
            },
            refreshClaudeProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        )
    }

    func refreshOfficialProfileCardsAfterManualRefresh(for descriptor: ProviderDescriptor) async {
        await officialProfileLifecycleCoordinator.refreshProfilesAfterManualRefresh(
            descriptor: descriptor,
            codexSlots: codexSlots,
            claudeSlots: claudeSlots,
            codexRuntime: codexOfficialProfileRefreshRuntime,
            claudeRuntime: claudeOfficialProfileRefreshRuntime,
            syncCodexProfiles: {
                self.syncCodexProfilesCurrentState()
                return self.codexProfiles
            },
            syncClaudeProfiles: {
                self.syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
                return self.claudeDisplayableProfiles()
            },
            refreshCodexProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshCodexProfileSnapshotSlot(
                    profile,
                    descriptor: descriptor,
                    allowSessionWindowStabilization: false
                )
            },
            refreshClaudeProfile: { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        )
    }

    func refreshCodexProfileSnapshotSlot(
        _ profile: CodexAccountProfile,
        descriptor: ProviderDescriptor,
        allowSessionWindowStabilization: Bool = true
    ) async -> OfficialProfileRefreshExecutionResult {
        await officialProfileRefreshCoordinator.refreshCodexProfileSlot(
            profile: profile,
            descriptor: descriptor,
            runtime: codexOfficialProfileRefreshRuntime,
            allowSessionWindowStabilization: allowSessionWindowStabilization,
            fetchSnapshot: { profile, descriptor in
                try await self.codexProfileSnapshotService.fetchSnapshot(
                    profile: profile,
                    descriptor: descriptor
                )
            },
            persistRefreshedAuthJSON: { slotID, refreshedAuthJSON in
                _ = self.codexProfileStore.updateStoredAuthJSON(
                    slotID: slotID,
                    authJSON: refreshedAuthJSON
                )
            },
            syncProfiles: {
                self.syncCodexProfilesCurrentState()
            },
            transformSnapshot: { snapshot, slotID in
                self.boundedSnapshot(
                    self.markCodexSnapshotActive(
                        snapshot,
                        preferredSlotID: slotID,
                        isActive: false
                    )
                )
            },
            commitInactiveSnapshot: { snapshot, slotID, allowSessionWindowStabilization in
                self.codexSlots = self.codexSlotStore.upsertInactive(
                    snapshot: snapshot,
                    preferredSlotID: slotID,
                    allowSessionWindowStabilization: allowSessionWindowStabilization
                )
            }
        )
    }

    var hasPersistedOfficialMonitoringState: Bool {
        AppOfficialProfileStateCoordinator.hasPersistedOfficialMonitoringState(
            codexProfiles: codexProfiles,
            codexSlots: codexSlots,
            claudeProfiles: claudeProfiles,
            claudeSlots: claudeSlots
        )
    }

    func restorePersistedOfficialProvidersIfNeeded() {
        if AppOfficialProfileStateCoordinator.restorePersistedOfficialProvidersIfNeeded(
            config: &config,
            codexProfiles: codexProfiles,
            codexSlots: codexSlots,
            claudeProfiles: claudeProfiles,
            claudeSlots: claudeSlots
        ) {
            normalizeStatusBarSelections()
        }
    }

    func claudeStatusBarDisplaySnapshot() -> UsageSnapshot? {
        let descriptor = claudeOfficialProviderDescriptor()
        return officialProfileDisplayCoordinator.claudeStatusBarDisplaySnapshot(
            resolvedSlotID: resolvedClaudeStatusBarDisplaySlotID(),
            slotViewModels: claudeSlotViewModels(refreshFromStore: true, triggerPrefetch: false),
            providerSnapshot: descriptor.flatMap { snapshots[$0.id] }
        )
    }

    func claudeOfficialProviderDescriptor() -> ProviderDescriptor? {
        config.providers.first(where: { $0.type == .claude && $0.family == .official })
    }

    func claudeDisplayableProfiles() -> [ClaudeAccountProfile] {
        AppOfficialProfileStateCoordinator.displayableClaudeProfiles(claudeProfiles)
    }

    func resolvedClaudeStatusBarDisplaySlotID() -> CodexSlotID? {
        AppOfficialProfileStateCoordinator.resolveClaudeStatusBarDisplaySlotID(
            configuredSlotID: config.claudeStatusBarDisplaySlotID,
            profiles: claudeProfiles,
            slots: claudeSlots
        )
    }

    func triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: CodexSlotID?) {
        let action = officialProfileDisplayCoordinator.claudeStatusBarDisplayPrefetchAction(
            slotID: slotID,
            descriptor: claudeOfficialProviderDescriptor(),
            profiles: claudeProfiles
        )
        switch action {
        case .none:
            return
        case .notifyOnly:
            notifyStatusBarDisplayConfigChanged()
            return
        case .refresh(let slotID):
            guard let descriptor = claudeOfficialProviderDescriptor(),
                  let profile = claudeProfiles.first(where: { $0.slotID == slotID }) else {
                return
            }
            Task { [weak self] in
                guard let self else { return }
                _ = await self.refreshClaudeProfileSnapshotSlot(profile, descriptor: descriptor)
                self.notifyStatusBarDisplayConfigChanged()
            }
        }
    }

    func markClaudeSnapshotActive(
        _ snapshot: UsageSnapshot,
        preferredSlotID: CodexSlotID? = nil,
        isActive: Bool = true
    ) -> UsageSnapshot {
        AppOfficialProfileStateCoordinator.markClaudeSnapshotActive(
            snapshot,
            preferredSlotID: preferredSlotID,
            isActive: isActive,
            profiles: claudeProfiles
        )
    }

    func bootstrapClaudeProfileState() {
        let bootstrapResult = officialProfileSyncCoordinator.bootstrapClaudeProfilesIfNeeded(
            currentProfiles: claudeProfiles,
            didRunAutoCaptureCompaction: didRunClaudeAutoCaptureCompaction,
            profileStore: claudeProfileStore,
            desktopAuthService: claudeDesktopAuthService
        )
        didRunClaudeAutoCaptureCompaction = bootstrapResult.didRunAutoCaptureCompaction
        if bootstrapResult.profiles != claudeProfiles {
            claudeProfiles = bootstrapResult.profiles
        }
        if !bootstrapResult.removedSlotIDs.isEmpty {
            removeClaudeSlotState(slotIDs: bootstrapResult.removedSlotIDs)
        }
        syncClaudeProfilesCurrentState(triggerPrefetchOnChange: true)
    }

    func syncClaudeProfilesCurrentState(triggerPrefetchOnChange: Bool = true) {
        let previousConfiguredDisplaySlotID = config.claudeStatusBarDisplaySlotID
        let previousResolvedDisplaySlotID = resolvedClaudeStatusBarDisplaySlotID()
        let syncResult = officialProfileSyncCoordinator.syncClaudeProfiles(
            currentProfiles: claudeProfiles,
            slots: claudeSlots,
            configuredDisplaySlotID: config.claudeStatusBarDisplaySlotID,
            profileStore: claudeProfileStore,
            desktopAuthService: claudeDesktopAuthService
        )
        if syncResult.profiles != claudeProfiles {
            claudeProfiles = syncResult.profiles
        }

        claudeOfficialProfileRefreshRuntime.pruneVisibleSlots(keeping: syncResult.visibleSlotIDs)
        config.claudeStatusBarDisplaySlotID = syncResult.syncEvaluation.normalizedConfiguredDisplaySlotID

        if config.claudeStatusBarDisplaySlotID != previousConfiguredDisplaySlotID {
            _ = persistConfiguration(showFeedback: false)
        }

        if triggerPrefetchOnChange,
           syncResult.syncEvaluation.didProfileIdentityChange {
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
        let resolvedDisplaySlotID = syncResult.syncEvaluation.resolvedDisplaySlotID
        if resolvedDisplaySlotID != previousResolvedDisplaySlotID {
            triggerClaudeStatusBarDisplayPrefetchIfNeeded(slotID: resolvedDisplaySlotID)
            notifyStatusBarDisplayConfigChanged()
        }
    }

    func refreshClaudeProfileSnapshotSlot(
        _ profile: ClaudeAccountProfile,
        descriptor: ProviderDescriptor
    ) async -> OfficialProfileRefreshExecutionResult {
        await officialProfileRefreshCoordinator.refreshClaudeProfileSlot(
            profile: profile,
            descriptor: descriptor,
            runtime: claudeOfficialProfileRefreshRuntime,
            shouldRefreshProfile: { AppOfficialProfileStateCoordinator.canDisplayClaudeMonitoringProfile($0) },
            fetchSnapshot: { profile, descriptor in
                try await self.claudeProfileSnapshotService.fetchSnapshot(
                    profile: profile,
                    descriptor: descriptor
                )
            },
            persistRefreshedCredentialsJSON: { slotID, refreshedCredentialsJSON in
                _ = self.claudeProfileStore.updateStoredCredentials(
                    slotID: slotID,
                    credentialsJSON: refreshedCredentialsJSON
                )
            },
            syncProfiles: {
                self.syncClaudeProfilesCurrentState(triggerPrefetchOnChange: false)
            },
            transformSnapshot: { snapshot, slotID in
                self.boundedSnapshot(
                    self.markClaudeSnapshotActive(
                        snapshot,
                        preferredSlotID: slotID,
                        isActive: false
                    )
                )
            },
            commitInactiveSnapshot: { snapshot, slotID in
                self.claudeSlots = self.claudeSlotStore.upsertInactive(
                    snapshot: snapshot,
                    preferredSlotID: slotID
                )
                if self.resolvedClaudeStatusBarDisplaySlotID() == slotID {
                    self.notifyStatusBarDisplayConfigChanged()
                }
            }
        )
    }

    private func codexSlotViewModels(
        refreshFromStore: Bool,
        triggerPrefetch: Bool
    ) -> [CodexSlotViewModel] {
        if refreshFromStore {
            let latestCodexSlots = codexSlotStore.visibleSlots()
            if latestCodexSlots != codexSlots {
                codexSlots = latestCodexSlots
            }
        }
        if triggerPrefetch {
            officialProfileLifecycleCoordinator.scheduleCodexPrefetchIfNeeded(
                descriptor: config.providers.first(where: { $0.type == .codex && $0.family == .official }),
                profiles: codexProfiles,
                slots: codexSlots,
                runtime: codexOfficialProfileRefreshRuntime
            ) { [weak self] profile, descriptor in
                guard let self else { return .skipped }
                return await self.refreshCodexProfileSnapshotSlot(profile, descriptor: descriptor)
            }
        }
        return AppOfficialProfileMenuPresenter.codexSlotViewModels(
            profiles: codexProfiles,
            slots: codexSlots,
            feedbackBySlotID: codexSwitchFeedback,
            isSwitching: { self.codexSwitchCoordinator.isRunning(slotID: $0) },
            titleForSlotID: { self.codexMenuTitle(for: $0) }
        )
    }

    private func claudeSlotViewModels(
        refreshFromStore: Bool,
        triggerPrefetch: Bool
    ) -> [ClaudeSlotViewModel] {
        if refreshFromStore {
            let latestClaudeSlots = claudeSlotStore.visibleSlots()
            if latestClaudeSlots != claudeSlots {
                claudeSlots = latestClaudeSlots
            }
        }
        if triggerPrefetch {
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
        return AppOfficialProfileMenuPresenter.claudeSlotViewModels(
            profiles: claudeProfiles,
            slots: claudeSlots,
            feedbackBySlotID: claudeSwitchFeedback,
            isSwitching: { self.claudeSwitchCoordinator.isRunning(slotID: $0) },
            titleForSlotID: { self.claudeMenuTitle(for: $0) }
        )
    }

    private func codexMenuTitle(for slotID: CodexSlotID) -> String {
        "Codex \(slotID.rawValue)"
    }

    private func setCodexSwitchFeedback(_ feedback: CodexSwitchFeedback?, for slotID: CodexSlotID) {
        codexFeedbackCoordinator.set(
            feedback,
            for: slotID,
            currentValue: { [weak self] in self?.codexSwitchFeedback[$0] },
            setValue: { [weak self] slotID, feedback in
                if let feedback {
                    self?.codexSwitchFeedback[slotID] = feedback
                } else {
                    self?.codexSwitchFeedback.removeValue(forKey: slotID)
                }
            }
        )
    }

    private func activateOfficialProviderAfterProfileSave(type: ProviderType) {
        let before = config
        if let index = config.providers.firstIndex(where: { $0.type == type && $0.family == .official }),
           !config.providers[index].enabled {
            config.providers[index].enabled = true
        }
        normalizeStatusBarSelections()
        if config != before {
            _ = persistConfiguration(showFeedback: true)
            restartPolling()
            refreshDisplayedStatusBarProviders()
        }
        notifyStatusBarDisplayConfigChanged()
    }

    private func codexSwitchMessage(
        for restartResult: CodexDesktopAppRestartResult,
        successKey: L10nKey
    ) -> String {
        if restartResult.requiresManualRelaunch {
            return text(.codexSwitchDesktopRestartIncomplete)
        }
        return text(successKey)
    }

    private func normalizedClaudeStatusBarDisplaySlotID(_ slotID: CodexSlotID?) -> CodexSlotID? {
        AppOfficialProfileStateCoordinator.normalizedClaudeStatusBarDisplaySlotID(
            slotID,
            profiles: claudeProfiles
        )
    }

    private func claudeMenuTitle(for slotID: CodexSlotID) -> String {
        "Claude \(slotID.rawValue)"
    }

    private func removeClaudeSlotState(slotIDs: [CodexSlotID]) {
        guard !slotIDs.isEmpty else { return }
        let uniqueSlotIDs = Array(Set(slotIDs)).sorted()
        for slotID in uniqueSlotIDs {
            claudeSlots = claudeSlotStore.remove(slotID: slotID)
            claudeOfficialProfileRefreshRuntime.remove(slotID: slotID)
            claudeSwitchFeedback.removeValue(forKey: slotID)
        }
    }

    private func setClaudeSwitchFeedback(_ feedback: ClaudeSwitchFeedback?, for slotID: CodexSlotID) {
        claudeFeedbackCoordinator.set(
            feedback,
            for: slotID,
            currentValue: { [weak self] in self?.claudeSwitchFeedback[$0] },
            setValue: { [weak self] slotID, feedback in
                if let feedback {
                    self?.claudeSwitchFeedback[slotID] = feedback
                } else {
                    self?.claudeSwitchFeedback.removeValue(forKey: slotID)
                }
            }
        )
    }
}
